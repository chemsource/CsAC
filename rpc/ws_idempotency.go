package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"regexp"
)

var wsRequestKey = regexp.MustCompile(`^[A-Za-z0-9_.:-]{8,128}$`)

func (a *App) executeIdempotentWS(peer *wsPeer, request wsRequest, execute func() wsOutcome) wsOutcome {
	if !wsRequestKey.MatchString(request.IdempotencyKey) {
		return wsOutcome{Error: &wsError{Code: -32602, Message: "A mutation requires an 8–128 character idempotency_key"}}
	}
	payload, _ := json.Marshal(map[string]any{"method": request.Method, "params": request.Params})
	mac := hmac.New(sha256.New, []byte(a.config.CacheSalt))
	mac.Write(payload)
	fingerprint := hex.EncodeToString(mac.Sum(nil))
	uid := peer.identity().UID
	result, err := a.db.ExecContext(peer.ctx, `INSERT IGNORE INTO csac_ws_requests
        (uid, request_key, fingerprint, created_at) VALUES (?, ?, ?, UNIX_TIMESTAMP())`, uid, request.IdempotencyKey, fingerprint)
	if err != nil {
		return wsOutcome{Error: &wsError{Code: -32603, Message: "Request retry storage unavailable"}}
	}
	inserted, err := result.RowsAffected()
	if err != nil {
		return wsOutcome{Error: &wsError{Code: -32603, Message: "Request retry storage unavailable"}}
	}
	if inserted == 0 {
		var existingFingerprint string
		var completed []byte
		if a.db.QueryRowContext(peer.ctx, "SELECT fingerprint, result_json FROM csac_ws_requests WHERE uid = ? AND request_key = ?", uid, request.IdempotencyKey).Scan(&existingFingerprint, &completed) != nil {
			return wsOutcome{Error: &wsError{Code: -32603, Message: "Request retry storage unavailable"}}
		}
		if existingFingerprint != fingerprint {
			return wsOutcome{Error: &wsError{Code: -32010, Message: "Idempotency key already belongs to different arguments"}}
		}
		if len(completed) == 0 {
			return wsOutcome{Error: &wsError{Code: -32011, Message: "Request is running or was interrupted; query its status and synchronize before retrying"}}
		}
		var cached wsOutcome
		decoder := json.NewDecoder(bytes.NewReader(completed))
		decoder.UseNumber()
		if decoder.Decode(&cached) != nil {
			return wsOutcome{Error: &wsError{Code: -32603, Message: "Stored request result unavailable"}}
		}
		return cached
	}
	outcome := execute()
	encoded, err := json.Marshal(outcome)
	if err != nil {
		return wsOutcome{Error: &wsError{Code: -32603, Message: "Request result unavailable; synchronize before retrying"}}
	}
	// Persist with a fresh context even when the socket disconnected after the
	// business write. An unresolved reservation is never executed a second time.
	_, err = a.exec("UPDATE csac_ws_requests SET result_json = ? WHERE uid = ? AND request_key = ?", string(encoded), uid, request.IdempotencyKey)
	if err != nil {
		return wsOutcome{Error: &wsError{Code: -32011, Message: "Request result could not be persisted; synchronize before retrying"}}
	}
	return outcome
}
