package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"
)

func (a *App) executeWSAction(peer *wsPeer, request wsRequest) wsOutcome {
	switch request.Method {
	case "events.resume":
		return a.resumeWSEvents(peer, request.Params)
	case "events.ack":
		sequence, err := strconv.ParseInt(toString(request.Params["seq"]), 10, 64)
		latest, _, boundsErr := a.realtimeBounds(peer.ctx)
		if boundsErr != nil {
			return wsOutcome{Error: &wsError{Code: -32603, Message: "Event storage unavailable"}}
		}
		if err != nil || sequence < 0 || sequence > latest {
			return wsOutcome{Error: &wsError{Code: -32602, Message: "Invalid acknowledged cursor"}}
		}
		peer.mu.Lock()
		defer peer.mu.Unlock()
		if sequence > peer.acked {
			peer.acked = sequence
		}
		return wsOutcome{Result: map[string]any{"acked": strconv.FormatInt(peer.acked, 10)}}
	case "requests.status":
		key := toString(request.Params["idempotency_key"])
		if !wsRequestKey.MatchString(key) {
			return wsOutcome{Error: &wsError{Code: -32602, Message: "Invalid idempotency_key"}}
		}
		var encoded sql.NullString
		err := a.db.QueryRowContext(peer.ctx, "SELECT result_json FROM csac_ws_requests WHERE uid = ? AND request_key = ?", peer.identity().UID, key).Scan(&encoded)
		if err == sql.ErrNoRows {
			return wsOutcome{Result: map[string]any{"state": "unknown"}}
		}
		if err != nil {
			return wsOutcome{Error: &wsError{Code: -32603, Message: "Request status unavailable"}}
		}
		if !encoded.Valid {
			return wsOutcome{Result: map[string]any{"state": "pending_or_interrupted"}}
		}
		return wsOutcome{Result: map[string]any{"state": "complete", "outcome": json.RawMessage(encoded.String)}}
	case "presence.get":
		return a.getWSPresence(peer, request.Params)
	case "typing.set":
		return a.setWSTyping(peer, request.Params)
	default:
		return wsOutcome{Error: &wsError{Code: -32601, Message: "Unknown method"}}
	}
}

func (a *App) resumeWSEvents(peer *wsPeer, params map[string]any) wsOutcome {
	after, err := strconv.ParseInt(toString(params["after"]), 10, 64)
	if err != nil || after < 0 {
		return wsOutcome{Error: &wsError{Code: -32602, Message: "after must be a nonnegative cursor string"}}
	}
	latest, retainedAfter, err := a.realtimeBounds(peer.ctx)
	if err != nil {
		return wsOutcome{Error: &wsError{Code: -32603, Message: "Event storage unavailable"}}
	}
	if after < retainedAfter || after > latest {
		return wsOutcome{Error: &wsError{Code: -32009, Message: "A full state synchronization is required", Data: map[string]any{
			"reset_required": true, "cursor": strconv.FormatInt(latest, 10), "retained_after": strconv.FormatInt(retainedAfter, 10),
		}}}
	}
	limit := limitBetween(toInt64Default(params["limit"], 200), 1, 500)
	events, err := a.readRealtimeEvents(peer.ctx, after, 5000)
	if err != nil {
		return wsOutcome{Error: &wsError{Code: -32603, Message: "Event storage unavailable"}}
	}
	uid := peer.identity().UID
	result := make([]any, 0, limit)
	next := after
	audiences := map[string]map[int64]bool{}
	for _, event := range events {
		if event.Seq > latest {
			break
		}
		next = event.Seq
		if event.Type == "session.revoked" {
			continue
		}
		key := eventAudienceKey(event)
		uids, exists := audiences[key]
		if !exists {
			uids, err = a.eventAudience(peer.ctx, event)
			if err != nil {
				return wsOutcome{Error: &wsError{Code: -32603, Message: "Event authorization unavailable"}}
			}
			audiences[key] = uids
		}
		if uids[uid] {
			result = append(result, eventNotification(event)["params"])
			if int64(len(result)) >= limit {
				break
			}
		}
	}
	return wsOutcome{Result: map[string]any{
		"events": result, "next_cursor": strconv.FormatInt(next, 10),
		"has_more": next < latest, "latest": strconv.FormatInt(latest, 10),
		"retained_after": strconv.FormatInt(retainedAfter, 10),
	}}
}

func (a *App) getWSPresence(peer *wsPeer, params map[string]any) wsOutcome {
	uids, supplied := params["user_ids"].([]any)
	if !supplied {
		uids = []any{peer.identity().UID}
	}
	if len(uids) > 100 {
		return wsOutcome{Error: &wsError{Code: -32602, Message: "At most 100 users may be queried"}}
	}
	result := make([]map[string]any, 0, len(uids))
	for _, raw := range uids {
		uid := toInt64Default(raw, 0)
		if uid <= 0 || !a.permittedPresence(peer.ctx, peer.identity().UID, uid) {
			continue
		}
		var lastActive int64
		if a.db.QueryRowContext(peer.ctx, "SELECT last_active FROM chat_user WHERE id = ?", uid).Scan(&lastActive) != nil {
			continue
		}
		result = append(result, map[string]any{"uid": uid, "connected": a.realtime.connected(uid), "last_active": lastActive})
	}
	return wsOutcome{Result: map[string]any{"users": result}}
}

func (a *App) setWSTyping(peer *wsPeer, params map[string]any) wsOutcome {
	uid := peer.identity().UID
	conversationType := strings.ToLower(toString(params["conversation_type"]))
	id := toInt64Default(params["conversation_id"], 0)
	active := true
	if raw, supplied := params["active"]; supplied {
		var valid bool
		active, valid = raw.(bool)
		if !valid {
			return wsOutcome{Error: &wsError{Code: -32602, Message: "active must be a boolean"}}
		}
	}
	if id <= 0 || (conversationType != "group" && conversationType != "private") {
		return wsOutcome{Error: &wsError{Code: -32602, Message: "Invalid conversation"}}
	}
	event := realtimeEvent{Audience: "pair", OwnerUID: uid, PeerUID: id}
	if conversationType == "group" {
		member, err := a.fetchOne(`SELECT m.uid FROM chat_group_user m JOIN chat_room r ON r.id = m.room_id
            WHERE m.room_id = ? AND m.uid = ? AND r.is_disband = 0 AND COALESCE(r.ban_until, 0) <= ?
            AND COALESCE(m.mute_until, 0) <= ?`, id, uid, time.Now().Unix(), time.Now().Unix())
		if err != nil || member == nil {
			return wsOutcome{Error: &wsError{Code: -32001, Message: "Conversation access denied"}}
		}
		event.Audience, event.RoomID = "group", id
	} else {
		relation := friendRelation(a, uid, id)
		if relation == nil || intval(relation, "status") != 1 {
			return wsOutcome{Error: &wsError{Code: -32001, Message: "Conversation access denied"}}
		}
	}
	key := fmt.Sprintf("%s:%d", conversationType, id)
	if active && time.Since(peer.typing[key]) < time.Second {
		return wsOutcome{Result: map[string]any{"throttled": true}}
	}
	if len(peer.typing) > 512 {
		clear(peer.typing)
	}
	peer.typing[key] = time.Now()
	uids, err := a.eventAudience(peer.ctx, event)
	if err != nil {
		return wsOutcome{Error: &wsError{Code: -32603, Message: "Conversation authorization unavailable"}}
	}
	data := map[string]any{"uid": uid, "conversation_type": conversationType, "conversation_id": id, "active": active, "expires_at": time.Now().Add(5 * time.Second).Unix()}
	a.realtime.transient(uids, "typing.changed", data, uid)
	return wsOutcome{Result: map[string]any{"expires_at": data["expires_at"]}}
}
