package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"
)

type wsOutcome struct {
	Result    any      `json:"result,omitempty"`
	Error     *wsError `json:"error,omitempty"`
	CloseCode int      `json:"-"`
}

type wsHTTPResponse struct {
	header   http.Header
	body     bytes.Buffer
	status   int
	overflow bool
}

func (w *wsHTTPResponse) Header() http.Header { return w.header }

func (w *wsHTTPResponse) WriteHeader(status int) {
	if w.status == 0 {
		w.status = status
	}
}

func (w *wsHTTPResponse) Write(data []byte) (int, error) {
	if w.body.Len()+len(data) > wsMaxFrameBytes-4096 {
		w.overflow = true
		return 0, fmt.Errorf("RPC response exceeds frame limit")
	}
	w.WriteHeader(http.StatusOK)
	return w.body.Write(data)
}

func (a *App) handleWSMessage(peer *wsPeer, raw []byte) (any, int) {
	requests := []json.RawMessage{raw}
	batch := len(bytes.TrimSpace(raw)) > 0 && bytes.TrimSpace(raw)[0] == '['
	if batch {
		if json.Unmarshal(raw, &requests) != nil || len(requests) == 0 || len(requests) > 16 {
			return wsResponse{JSONRPC: "2.0", ID: json.RawMessage("null"), Error: &wsError{Code: -32600, Message: "Batch size must be between 1 and 16"}}, 0
		}
	}
	responses := make([]wsResponse, 0, len(requests))
	closeCode := 0
	responseBytes := 0
	for _, rawRequest := range requests {
		if !peer.allowRequest() {
			responses = append(responses, wsResponse{JSONRPC: "2.0", ID: json.RawMessage("null"), Error: &wsError{Code: -32014, Message: "Request rate exceeded"}})
			closeCode = 4429
			break
		}
		request, failure := parseWSRequest(rawRequest)
		if failure != nil {
			identifier := request.ID
			if len(identifier) == 0 {
				identifier = json.RawMessage("null")
			}
			responses = append(responses, wsResponse{JSONRPC: "2.0", ID: identifier, Error: failure})
			continue
		}
		outcome := wsOutcome{}
		if closeCode != 0 || responseBytes > wsMaxFrameBytes/2 {
			outcome.Error = &wsError{Code: -32012, Message: "Submit the remaining requests separately"}
		} else {
			outcome = a.executeWSRequest(peer, request)
			if outcome.CloseCode != 0 {
				closeCode = outcome.CloseCode
			}
		}
		if len(request.ID) == 0 {
			continue
		}
		response := wsResponse{JSONRPC: "2.0", ID: request.ID, Result: outcome.Result, Error: outcome.Error}
		encoded, err := json.Marshal(response)
		// Reserve enough space for errors for the remaining batch members. A
		// completed mutation is still recorded under its idempotency key.
		if err != nil || (batch && responseBytes+len(encoded) > wsMaxFrameBytes-8192) {
			response = wsResponse{JSONRPC: "2.0", ID: request.ID, Error: &wsError{
				Code: -32013, Message: "Response exceeds batch limit; request a smaller page or check request status",
			}}
			encoded, _ = json.Marshal(response)
		}
		responseBytes += len(encoded) + 1
		responses = append(responses, response)
	}
	if len(responses) == 0 {
		return nil, closeCode
	}
	if batch {
		return responses, closeCode
	}
	return responses[0], closeCode
}

func (a *App) executeWSRequest(peer *wsPeer, request wsRequest) wsOutcome {
	if request.Method == "rpc.discover" {
		return wsOutcome{Result: map[string]any{
			"protocol": 2, "methods": a.wsDiscover(), "http_uploads": true,
			"control_methods":      []string{"ping", "session.authenticate", "events.resume", "events.ack", "requests.status", "presence.get", "typing.set"},
			"event_retention_days": a.config.WSRetentionDays, "max_batch": 16, "max_message_bytes": wsMaxFrameBytes,
		}}
	}
	if request.Method == "ping" {
		return wsOutcome{Result: map[string]any{"server_time": time.Now().Unix()}}
	}
	if request.Method == "session.authenticate" {
		if peer.identity().UID > 0 {
			return wsOutcome{Error: &wsError{Code: -32001, Message: "This connection is already authenticated"}}
		}
		ctx, cancel := context.WithTimeout(peer.ctx, 10*time.Second)
		defer cancel()
		identity, err := a.loadWSIdentity(ctx, toString(request.Params["token"]))
		if err != nil {
			return wsOutcome{Error: &wsError{Code: -32001, Message: "Invalid or expired session"}}
		}
		latest, _, err := a.realtimeBounds(ctx)
		if err != nil {
			return wsOutcome{Error: &wsError{Code: -32603, Message: "Event service unavailable"}}
		}
		peer.setIdentity(identity)
		return wsOutcome{Result: map[string]any{"uid": identity.UID, "expires_at": identity.ExpiresAt, "cursor": strconv.FormatInt(latest, 10)}}
	}
	method, businessMethod := a.wsMethodCatalog()[request.Method]
	if !businessMethod && request.Method != "events.resume" && request.Method != "events.ack" && request.Method != "requests.status" && request.Method != "presence.get" && request.Method != "typing.set" {
		return wsOutcome{Error: &wsError{Code: -32601, Message: "Method unavailable over WebSocket", Data: map[string]any{"http_supported": a.routes[request.Method] != nil}}}
	}
	identity := peer.identity()
	if !method.Public {
		if identity.UID == 0 {
			return wsOutcome{Error: &wsError{Code: -32001, Message: "Authentication required"}}
		}
		if !a.validWSSession(peer.ctx, identity) {
			return wsOutcome{Error: &wsError{Code: -32001, Message: "Session expired or revoked"}, CloseCode: 4401}
		}
	}
	if !businessMethod {
		if !a.wsEventAccess(identity.UID) {
			return wsOutcome{Error: &wsError{Code: -32001, Message: "Email verification required", Data: map[string]any{"needs_email_verification": true}}}
		}
		return a.executeWSAction(peer, request)
	}
	if identity.UID > 0 && (strings.HasPrefix(request.Method, "auth/login") || request.Method == "auth/register") {
		return wsOutcome{Error: &wsError{Code: -32001, Message: "Open a new connection to sign in to another account"}}
	}
	passwordChange := request.Method == "user/update_profile" && toString(request.Params["action"]) == "password"
	if method.RetryKey && !passwordChange {
		if len(request.ID) == 0 {
			return wsOutcome{Error: &wsError{Code: -32600, Message: "Mutation requests require an identifier"}}
		}
		return a.executeIdempotentWS(peer, request, func() wsOutcome { return a.callWSHandler(peer, request) })
	}
	return a.callWSHandler(peer, request)
}

func (a *App) callWSHandler(peer *wsPeer, request wsRequest) (outcome wsOutcome) {
	defer func() {
		if recover() != nil {
			log.Printf("WebSocket operation failed: %s", request.Method)
			outcome = wsOutcome{Error: &wsError{Code: -32603, Message: "Operation interrupted; synchronize its state before retrying"}}
		}
		a.realtime.notify()
	}()
	ctx, cancel := context.WithTimeout(peer.ctx, 30*time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, "/ws/v2", nil)
	req.RemoteAddr = peer.request.RemoteAddr
	for _, name := range []string{"X-Real-IP", "CF-Connecting-IP", "X-Forwarded-For", "X-Forwarded-Proto", "User-Agent"} {
		req.Header.Set(name, peer.request.Header.Get(name))
	}
	previous := peer.identity()
	if previous.Token != "" {
		req.Header.Set("Authorization", "Bearer "+previous.Token)
	}
	w := &wsHTTPResponse{header: make(http.Header)}
	operation := NewCtx(a, w, req)
	operation.input, operation.parsed, operation.strictPermissions = request.Params, true, true
	a.routes[request.Method](operation)
	if w.overflow {
		return wsOutcome{Error: &wsError{Code: -32013, Message: "Response exceeds limit; request a smaller page"}}
	}
	var data map[string]any
	decoder := json.NewDecoder(bytes.NewReader(w.body.Bytes()))
	decoder.UseNumber()
	if !operation.responded || decoder.Decode(&data) != nil {
		return wsOutcome{Error: &wsError{Code: -32603, Message: "Operation did not return a JSON response"}}
	}
	if w.status >= 400 || data["success"] == false {
		code := -32000
		if w.status == http.StatusUnauthorized || w.status == http.StatusForbidden {
			code = -32001
		}
		return wsOutcome{Error: &wsError{Code: code, Message: strDefault(data, "message", "Operation failed"), Data: map[string]any{"http_status": w.status, "body": data}}}
	}
	result := map[string]any{"http_status": w.status, "data": data}
	if operation.session != nil && operation.session.UID > 0 && !operation.session.destroy && operation.session.SID != previous.Token {
		identity, err := a.loadWSIdentity(ctx, operation.session.SID)
		if err != nil {
			return wsOutcome{Error: &wsError{Code: -32001, Message: "Session unavailable"}}
		}
		peer.setIdentity(identity)
		latest, _, err := a.realtimeBounds(ctx)
		if err != nil {
			return wsOutcome{Error: &wsError{Code: -32603, Message: "Event service unavailable"}}
		}
		result["session"] = map[string]any{"token": identity.Token, "uid": identity.UID, "expires_at": identity.ExpiresAt, "cursor": strconv.FormatInt(latest, 10)}
	}
	if operation.session != nil && operation.session.destroy {
		peer.setIdentity(wsIdentity{})
		return wsOutcome{Result: result, CloseCode: 4401}
	}
	return wsOutcome{Result: result}
}
