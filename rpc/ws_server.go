package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

type wsIdentity struct {
	Token     string
	UID       int64
	ExpiresAt int64
}

type wsOutgoing struct {
	Payload   []byte
	CloseCode int
}

type wsPeer struct {
	service    *realtimeService
	connection *websocket.Conn
	request    *http.Request
	ctx        context.Context
	cancel     context.CancelFunc
	outgoing   chan wsOutgoing
	done       chan struct{}
	started    time.Time
	mu         sync.Mutex
	account    wsIdentity
	closed     bool
	pending    int64
	cursor     int64
	acked      int64
	typing     map[string]time.Time
	window     time.Time
	requests   int
}

func (p *wsPeer) identity() wsIdentity {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.account
}

func (p *wsPeer) allowRequest() bool {
	if time.Since(p.window) >= time.Minute {
		p.window, p.requests = time.Now(), 0
	}
	p.requests++
	limit := 1200
	if p.identity().UID == 0 {
		limit = 10
	}
	return p.requests <= limit
}

func (p *wsPeer) setIdentity(identity wsIdentity) {
	wasConnected := identity.UID > 0 && p.service.connected(identity.UID)
	p.mu.Lock()
	previous := p.account
	p.account = identity
	p.mu.Unlock()
	if previous.UID > 0 && previous.UID != identity.UID && !p.service.connected(previous.UID) {
		p.service.presenceChanged(previous.UID, false)
	}
	if identity.UID > 0 && !wasConnected {
		p.service.presenceChanged(identity.UID, true)
	}
}

func (p *wsPeer) send(value any) bool { return p.sendThenClose(value, 0) }

func (p *wsPeer) sendThenClose(value any, closeCode int) bool {
	payload, err := json.Marshal(value)
	if err != nil || len(payload) > wsMaxFrameBytes {
		p.close(websocket.CloseMessageTooBig, "Response exceeds limit; use smaller pages")
		return false
	}
	p.mu.Lock()
	if p.closed {
		p.mu.Unlock()
		return false
	}
	if p.pending+int64(len(payload)) > 2*wsMaxFrameBytes {
		p.mu.Unlock()
		p.close(websocket.CloseTryAgainLater, "Slow consumer; reconnect and resume")
		return false
	}
	total := p.service.pendingBytes.Add(int64(len(payload)))
	if total > 32<<20 {
		p.service.pendingBytes.Add(-int64(len(payload)))
		p.mu.Unlock()
		p.close(websocket.CloseTryAgainLater, "Server busy; reconnect and resume")
		return false
	}
	select {
	case p.outgoing <- wsOutgoing{Payload: payload, CloseCode: closeCode}:
		p.pending += int64(len(payload))
		p.mu.Unlock()
		return true
	default:
		p.service.pendingBytes.Add(-int64(len(payload)))
		p.mu.Unlock()
		p.close(websocket.CloseTryAgainLater, "Slow consumer; reconnect and resume")
		return false
	}
}

func (p *wsPeer) sendEvent(event realtimeEvent) {
	p.mu.Lock()
	if event.Seq <= p.cursor {
		p.mu.Unlock()
		return
	}
	p.cursor = event.Seq
	p.mu.Unlock()
	if event.Type == "session.revoked" {
		var data struct {
			SessionHash string `json:"session_hash"`
		}
		if json.Unmarshal(event.Payload, &data) == nil && data.SessionHash == sessionFingerprint(p.identity().Token) {
			p.close(4401, "Session revoked")
		}
		return
	}
	p.send(eventNotification(event))
}

func (p *wsPeer) release(message wsOutgoing) {
	p.mu.Lock()
	p.pending -= int64(len(message.Payload))
	p.mu.Unlock()
	p.service.pendingBytes.Add(-int64(len(message.Payload)))
}

func (p *wsPeer) close(code int, reason string) {
	p.mu.Lock()
	if p.closed {
		p.mu.Unlock()
		return
	}
	p.closed = true
	close(p.done)
	p.cancel()
	p.mu.Unlock()
	_ = p.connection.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(code, reason), time.Now().Add(time.Second))
	_ = p.connection.Close()
	p.service.remove(p)
}

func (p *wsPeer) writeLoop() {
	ticker := time.NewTicker(20 * time.Second)
	defer ticker.Stop()
	defer func() {
		p.close(websocket.CloseNormalClosure, "Connection closed")
		for {
			select {
			case message := <-p.outgoing:
				p.release(message)
			default:
				return
			}
		}
	}()
	for {
		select {
		case <-p.done:
			return
		case message := <-p.outgoing:
			p.release(message)
			_ = p.connection.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if p.connection.WriteMessage(websocket.TextMessage, message.Payload) != nil {
				return
			}
			if message.CloseCode != 0 {
				p.close(message.CloseCode, "Session closed")
				return
			}
		case <-ticker.C:
			if p.identity().UID == 0 && time.Since(p.started) > 30*time.Second {
				p.close(4401, "Authentication timeout")
				return
			}
			if p.connection.WriteControl(websocket.PingMessage, nil, time.Now().Add(10*time.Second)) != nil {
				return
			}
		}
	}
}

func (a *App) loadWSIdentity(ctx context.Context, token string) (wsIdentity, error) {
	identity := wsIdentity{Token: token}
	if !validSessionID(token) {
		return wsIdentity{}, sql.ErrNoRows
	}
	err := a.db.QueryRowContext(ctx, `SELECT s.uid, s.expires_at FROM csac_sessions s JOIN chat_user u ON u.id = s.uid
        WHERE s.sid = ? AND s.expires_at > UNIX_TIMESTAMP() AND u.status = 1
        AND COALESCE(u.ban_until, 0) <= UNIX_TIMESTAMP()`, token).Scan(&identity.UID, &identity.ExpiresAt)
	return identity, err
}

func (a *App) handleWebSocketV2(w http.ResponseWriter, request *http.Request) {
	if !websocket.IsWebSocketUpgrade(request) {
		writeJSONRaw(w, http.StatusUpgradeRequired, map[string]any{"success": false, "message": "WebSocket upgrade required"})
		return
	}
	upgrader := websocket.Upgrader{
		ReadBufferSize: 4096, WriteBufferSize: 4096,
		Subprotocols: []string{"csac.v2"},
		CheckOrigin:  func(r *http.Request) bool { return wsAllowedOrigin(r.Header.Get("Origin"), a.config.WSOrigins) },
	}
	identity := wsIdentity{}
	token := requestSessionID(request, a.config.SessionCookieName)
	if request.Header.Get("Authorization") != "" && token == "" {
		wsHTTPError(w, http.StatusUnauthorized)
		return
	}
	if token != "" {
		var err error
		identity, err = a.loadWSIdentity(request.Context(), token)
		if err != nil {
			wsHTTPError(w, http.StatusUnauthorized)
			return
		}
	}
	latest, retainedAfter, err := a.realtimeBounds(request.Context())
	if err != nil {
		wsHTTPError(w, http.StatusServiceUnavailable)
		return
	}
	connection, err := upgrader.Upgrade(w, request, nil)
	if err != nil {
		return
	}
	ctx, cancel := context.WithCancel(a.realtime.ctx)
	peer := &wsPeer{
		service: a.realtime, connection: connection, request: request,
		ctx: ctx, cancel: cancel, outgoing: make(chan wsOutgoing, 32), done: make(chan struct{}),
		started: time.Now(), account: identity, cursor: latest, typing: map[string]time.Time{},
	}
	if !a.realtime.add(peer) {
		cancel()
		_ = connection.Close()
		return
	}
	defer peer.close(websocket.CloseNormalClosure, "Connection closed")
	connection.SetReadLimit(wsMaxFrameBytes)
	_ = connection.SetReadDeadline(time.Now().Add(90 * time.Second))
	connection.SetPongHandler(func(string) error { return connection.SetReadDeadline(time.Now().Add(90 * time.Second)) })
	go peer.writeLoop()
	peer.send(map[string]any{
		"jsonrpc": "2.0", "method": "session.ready",
		"params": map[string]any{
			"protocol": 2, "authenticated": identity.UID > 0, "uid": identity.UID,
			"cursor": strconv.FormatInt(latest, 10), "retained_after": strconv.FormatInt(retainedAfter, 10),
			"heartbeat_seconds": 20, "max_message_bytes": wsMaxFrameBytes, "max_batch": 16,
			"retention_days": a.config.WSRetentionDays,
		},
	})
	if identity.UID > 0 {
		a.realtime.presenceChanged(identity.UID, true)
	}
	for {
		messageType, raw, err := connection.ReadMessage()
		if err != nil {
			return
		}
		if messageType != websocket.TextMessage {
			peer.close(websocket.CloseUnsupportedData, "JSON text frames required")
			return
		}
		response, closeCode := a.handleWSMessage(peer, raw)
		if response != nil && !peer.sendThenClose(response, closeCode) {
			return
		}
		if closeCode != 0 {
			<-peer.done
			return
		}
	}
}
