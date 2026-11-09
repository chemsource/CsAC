package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

type realtimeService struct {
	app          *App
	ctx          context.Context
	cancel       context.CancelFunc
	wake         chan struct{}
	stopped      chan struct{}
	mu           sync.Mutex
	peers        map[*wsPeer]struct{}
	pendingBytes atomic.Int64
}

func newRealtimeService(app *App) *realtimeService {
	ctx, cancel := context.WithCancel(context.Background())
	service := &realtimeService{
		app: app, ctx: ctx, cancel: cancel, wake: make(chan struct{}, 1),
		stopped: make(chan struct{}), peers: make(map[*wsPeer]struct{}),
	}
	go service.run()
	return service
}

func (r *realtimeService) close() {
	r.cancel()
	for _, peer := range r.snapshot() {
		peer.close(websocket.CloseServiceRestart, "Server restarting")
	}
	<-r.stopped
}

func (r *realtimeService) notify() {
	select {
	case r.wake <- struct{}{}:
	default:
	}
}

func (r *realtimeService) snapshot() []*wsPeer {
	r.mu.Lock()
	defer r.mu.Unlock()
	peers := make([]*wsPeer, 0, len(r.peers))
	for peer := range r.peers {
		peers = append(peers, peer)
	}
	return peers
}

func (r *realtimeService) add(peer *wsPeer) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.peers) >= r.app.config.WSMaxConnections || r.ctx.Err() != nil {
		return false
	}
	r.peers[peer] = struct{}{}
	return true
}

func (r *realtimeService) remove(peer *wsPeer) {
	r.mu.Lock()
	delete(r.peers, peer)
	r.mu.Unlock()
	identity := peer.identity()
	if identity.UID > 0 && !r.connected(identity.UID) {
		r.presenceChanged(identity.UID, false)
	}
}

func (r *realtimeService) connected(uid int64) bool {
	for _, peer := range r.snapshot() {
		if peer.identity().UID == uid {
			return true
		}
	}
	return false
}

func (r *realtimeService) run() {
	defer close(r.stopped)
	cursor, _, err := r.app.realtimeBounds(r.ctx)
	if err != nil {
		log.Print("realtime initial cursor unavailable")
	}
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	lastPrune := time.Time{}
	lastValidation := time.Time{}
	lastErrorLog := time.Time{}
	for {
		select {
		case <-r.ctx.Done():
			return
		case <-ticker.C:
		case <-r.wake:
		}
		ctx, cancel := context.WithTimeout(r.ctx, 5*time.Second)
		err := r.app.publishRealtimeEvents(ctx)
		if err == nil {
			var events []realtimeEvent
			events, err = r.app.readRealtimeEvents(ctx, cursor, 256)
			if err == nil && len(events) > 0 {
				err = r.deliver(ctx, events)
				if err == nil {
					cursor = events[len(events)-1].Seq
				}
			}
		}
		if time.Since(lastValidation) >= 5*time.Second {
			if validationErr := r.validatePeers(ctx); validationErr != nil {
				if err == nil {
					err = validationErr
				}
			} else {
				lastValidation = time.Now()
			}
		}
		if time.Since(lastPrune) >= time.Minute && err == nil {
			err = r.app.pruneRealtime(ctx)
			if err == nil {
				lastPrune = time.Now()
			}
		}
		cancel()
		if err != nil && r.ctx.Err() == nil && time.Since(lastErrorLog) >= time.Minute {
			log.Print("realtime database work failed, retrying")
			lastErrorLog = time.Now()
		}
	}
}

func (r *realtimeService) validatePeers(ctx context.Context) error {
	peers := r.snapshot()
	identities := make(map[*wsPeer]wsIdentity, len(peers))
	tokens := make(map[string]bool, len(peers))
	for _, peer := range peers {
		identity := peer.identity()
		if identity.UID > 0 {
			identities[peer] = identity
			tokens[identity.Token] = true
		}
	}
	if len(tokens) == 0 {
		return nil
	}
	placeholders := make([]string, 0, len(tokens))
	arguments := make([]any, 0, len(tokens))
	for token := range tokens {
		placeholders = append(placeholders, "?")
		arguments = append(arguments, token)
	}
	rows, err := r.app.db.QueryContext(ctx, `SELECT s.sid, s.uid FROM csac_sessions s
        JOIN chat_user u ON u.id = s.uid WHERE s.expires_at > UNIX_TIMESTAMP()
        AND u.status = 1 AND COALESCE(u.ban_until, 0) <= UNIX_TIMESTAMP()
        AND s.sid IN (`+strings.Join(placeholders, ",")+`)`, arguments...)
	if err != nil {
		return err
	}
	valid := make(map[string]int64, len(tokens))
	for rows.Next() {
		var token string
		var uid int64
		if err := rows.Scan(&token, &uid); err != nil {
			rows.Close()
			return err
		}
		valid[token] = uid
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	active := map[int64]bool{}
	for peer, identity := range identities {
		if valid[identity.Token] != identity.UID {
			if peer.identity() == identity {
				peer.close(4401, "Session expired or revoked")
			}
		} else {
			active[identity.UID] = true
		}
	}
	if len(active) > 0 {
		placeholders = placeholders[:0]
		arguments = arguments[:0]
		for uid := range active {
			placeholders = append(placeholders, "?")
			arguments = append(arguments, uid)
		}
		_, _ = r.app.db.ExecContext(ctx, "UPDATE chat_user SET last_active = UNIX_TIMESTAMP() WHERE last_active < UNIX_TIMESTAMP() - 60 AND id IN ("+strings.Join(placeholders, ",")+")", arguments...)
	}
	return nil
}

func (a *App) validWSSession(ctx context.Context, identity wsIdentity) bool {
	var valid int
	err := a.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM csac_sessions s JOIN chat_user u ON u.id = s.uid
        WHERE s.sid = ? AND s.uid = ? AND s.expires_at > UNIX_TIMESTAMP()
        AND u.status = 1 AND COALESCE(u.ban_until, 0) <= UNIX_TIMESTAMP()`, identity.Token, identity.UID).Scan(&valid)
	return err == nil && valid == 1
}

func (a *App) eventAudience(ctx context.Context, event realtimeEvent) (map[int64]bool, error) {
	uids := map[int64]bool{}
	switch event.Audience {
	case "user":
		uids[event.OwnerUID] = true
	case "pair":
		if strings.HasPrefix(event.Type, "message.") {
			var allowed int
			err := a.db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM friend_relation WHERE status = 1
                AND ((uid1 = ? AND uid2 = ?) OR (uid1 = ? AND uid2 = ?)))`,
				event.OwnerUID, event.PeerUID, event.PeerUID, event.OwnerUID).Scan(&allowed)
			if err != nil || allowed == 0 {
				return uids, err
			}
		}
		uids[event.OwnerUID] = true
		uids[event.PeerUID] = true
	case "group", "group_admin":
		query := `SELECT m.uid FROM chat_group_user m JOIN chat_room r ON r.id = m.room_id
            WHERE m.room_id = ? AND r.is_disband = 0`
		arguments := []any{event.RoomID}
		if strings.HasPrefix(event.Type, "message.") {
			query += " AND COALESCE(r.ban_until, 0) <= UNIX_TIMESTAMP()"
		}
		if event.Audience == "group_admin" {
			query = `SELECT owner_uid AS uid FROM chat_room WHERE id = ? AND is_disband = 0
                UNION SELECT a.uid FROM chat_group_admin a JOIN chat_room r ON r.id = a.room_id
                WHERE a.room_id = ? AND r.is_disband = 0`
			arguments = append(arguments, event.RoomID)
		}
		rows, err := a.db.QueryContext(ctx, query, arguments...)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		for rows.Next() {
			var uid int64
			if err := rows.Scan(&uid); err != nil {
				return nil, err
			}
			uids[uid] = true
		}
		if err := rows.Err(); err != nil {
			return nil, err
		}
	case "contacts", "peers":
		uids[event.OwnerUID] = true
		rows, err := a.db.QueryContext(ctx, `SELECT CASE WHEN uid1 = ? THEN uid2 ELSE uid1 END
            FROM friend_relation WHERE status = 1 AND (uid1 = ? OR uid2 = ?)`, event.OwnerUID, event.OwnerUID, event.OwnerUID)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		for rows.Next() {
			var uid int64
			if err := rows.Scan(&uid); err != nil {
				return nil, err
			}
			uids[uid] = true
		}
		if err := rows.Err(); err != nil {
			return nil, err
		}
		if event.Audience == "peers" {
			members, err := a.db.QueryContext(ctx, `SELECT DISTINCT b.uid FROM chat_group_user a
                JOIN chat_group_user b ON b.room_id = a.room_id JOIN chat_room r ON r.id = a.room_id
                WHERE a.uid = ? AND r.is_disband = 0`, event.OwnerUID)
			if err != nil {
				return nil, err
			}
			defer members.Close()
			for members.Next() {
				var uid int64
				if err := members.Scan(&uid); err != nil {
					return nil, err
				}
				uids[uid] = true
			}
			if err := members.Err(); err != nil {
				return nil, err
			}
		}
	default:
		return nil, fmt.Errorf("unknown event audience")
	}
	delete(uids, 0)
	return uids, nil
}

func eventNotification(event realtimeEvent) map[string]any {
	return map[string]any{
		"jsonrpc": "2.0", "method": "event",
		"params": map[string]any{
			"seq": strconv.FormatInt(event.Seq, 10), "type": event.Type,
			"data": event.Payload, "server_time": event.CreatedAt,
		},
	}
}

func eventAudienceKey(event realtimeEvent) string {
	return fmt.Sprintf("%s:%s:%d:%d:%d", event.Type, event.Audience, event.OwnerUID, event.PeerUID, event.RoomID)
}

func (r *realtimeService) deliver(ctx context.Context, events []realtimeEvent) error {
	peers := r.snapshot()
	if len(peers) == 0 && r.app.config.BotEndpoint == "" {
		return nil
	}
	if err := r.validatePeers(ctx); err != nil {
		return err
	}
	audiences := map[string]map[int64]bool{}
	for _, event := range events {
		key := eventAudienceKey(event)
		uids, exists := audiences[key]
		if !exists {
			var err error
			uids, err = r.app.eventAudience(ctx, event)
			if err != nil {
				return err
			}
			audiences[key] = uids
		}
		if r.app.config.BotEndpoint != "" && event.Type != "session.revoked" {
			r.forwardBotState(event, uids)
		}
		for _, peer := range peers {
			identity := peer.identity()
			if identity.UID > 0 && uids[identity.UID] && r.app.wsEventAccess(identity.UID) {
				peer.sendEvent(event)
			}
		}
	}
	return nil
}

func (r *realtimeService) forwardBotState(event realtimeEvent, uids map[int64]bool) {
	if len(uids) == 0 {
		return
	}
	placeholders := make([]string, 0, len(uids))
	arguments := make([]any, 0, len(uids))
	for uid := range uids {
		placeholders = append(placeholders, "?")
		arguments = append(arguments, uid)
	}
	rows, err := r.app.fetchAll("SELECT uid FROM bot_accounts WHERE status = 1 AND uid IN ("+strings.Join(placeholders, ",")+")", arguments...)
	if err != nil || len(rows) == 0 {
		return
	}
	recipients := make([]int64, 0, len(rows))
	for _, row := range rows {
		recipients = append(recipients, intval(row, "uid"))
	}
	pushBotEvent("realtime_event", map[string]any{"recipient_uids": recipients, "event": eventNotification(event)["params"]})
}

func (r *realtimeService) presenceChanged(uid int64, connected bool) {
	ctx, cancel := context.WithTimeout(r.ctx, 3*time.Second)
	defer cancel()
	event := realtimeEvent{Audience: "peers", OwnerUID: uid}
	uids, err := r.app.eventAudience(ctx, event)
	if err != nil {
		return
	}
	r.transient(uids, "presence.changed", map[string]any{"uid": uid, "connected": connected}, 0)
}

func (r *realtimeService) transient(uids map[int64]bool, eventType string, data map[string]any, excludeUID int64) {
	message := map[string]any{
		"jsonrpc": "2.0", "method": "event",
		"params": map[string]any{"type": eventType, "transient": true, "data": data, "server_time": time.Now().Unix()},
	}
	for _, peer := range r.snapshot() {
		uid := peer.identity().UID
		if uid > 0 && uid != excludeUID && uids[uid] && r.app.wsEventAccess(uid) {
			peer.send(message)
		}
	}
}

func sessionFingerprint(token string) string {
	digest := sha256.Sum256([]byte(token))
	return hex.EncodeToString(digest[:])
}

func (a *App) wsEventAccess(uid int64) bool {
	return !a.config.RequireExistingUserEmailVerification || userEmailVerified(a, uid)
}

func (a *App) permittedPresence(ctx context.Context, uid, other int64) bool {
	if uid == other {
		return true
	}
	var allowed int
	err := a.db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM friend_relation
        WHERE status = 1 AND ((uid1 = ? AND uid2 = ?) OR (uid1 = ? AND uid2 = ?)))
        OR EXISTS(SELECT 1 FROM chat_group_user a JOIN chat_group_user b ON b.room_id = a.room_id
        JOIN chat_room r ON r.id = a.room_id WHERE a.uid = ? AND b.uid = ? AND r.is_disband = 0)`,
		uid, other, other, uid, uid, other).Scan(&allowed)
	return err == nil && allowed != 0
}

func wsAllowedOrigin(origin string, allowed string) bool {
	if origin == "" {
		return true
	}
	for _, candidate := range strings.Split(allowed, ",") {
		if strings.TrimSpace(candidate) == origin {
			return true
		}
	}
	return false
}
