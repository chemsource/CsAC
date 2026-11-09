package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"sort"
	"strings"
)

const wsMaxFrameBytes = 1 << 20

type wsRequest struct {
	JSONRPC        string          `json:"jsonrpc"`
	ID             json.RawMessage `json:"id"`
	Method         string          `json:"method"`
	Params         map[string]any  `json:"params"`
	IdempotencyKey string          `json:"idempotency_key,omitempty"`
}

type wsError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

func (e *wsError) Error() string { return e.Message }

type wsResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Result  any             `json:"result,omitempty"`
	Error   *wsError        `json:"error,omitempty"`
}

type wsMethod struct {
	Name     string `json:"name"`
	ReadOnly bool   `json:"read_only"`
	Public   bool   `json:"public"`
	RetryKey bool   `json:"idempotency_key"`
}

func parseWSRequest(raw []byte) (wsRequest, *wsError) {
	request := wsRequest{}
	if !json.Valid(raw) {
		return request, &wsError{Code: -32700, Message: "Invalid JSON request"}
	}
	var envelope struct {
		JSONRPC string          `json:"jsonrpc"`
		ID      json.RawMessage `json:"id"`
		Method  string          `json:"method"`
		Params  json.RawMessage `json:"params"`
		Key     string          `json:"idempotency_key"`
	}
	if bytes.TrimSpace(raw)[0] != '{' || json.Unmarshal(raw, &envelope) != nil {
		return request, &wsError{Code: -32600, Message: "Expected a JSON-RPC request object"}
	}
	request.JSONRPC, request.ID, request.Method = envelope.JSONRPC, envelope.ID, envelope.Method
	request.IdempotencyKey = envelope.Key
	if request.JSONRPC != "2.0" || request.Method == "" || len(request.Method) > 128 {
		return request, &wsError{Code: -32600, Message: "Invalid JSON-RPC request"}
	}
	if len(request.ID) > 128 || !validWSRequestID(request.ID) {
		request.ID = nil
		return request, &wsError{Code: -32600, Message: "Invalid request identifier"}
	}
	request.Params = map[string]any{}
	if len(envelope.Params) > 0 {
		if bytes.TrimSpace(envelope.Params)[0] != '{' {
			return request, &wsError{Code: -32602, Message: "Named parameters must be an object"}
		}
		decoder := json.NewDecoder(bytes.NewReader(envelope.Params))
		decoder.UseNumber()
		if decoder.Decode(&request.Params) != nil {
			return request, &wsError{Code: -32602, Message: "Invalid named parameters"}
		}
	}
	return request, nil
}

func validWSRequestID(raw json.RawMessage) bool {
	if len(raw) == 0 || bytes.Equal(raw, []byte("null")) {
		return true
	}
	var value any
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	if decoder.Decode(&value) != nil {
		return false
	}
	switch value.(type) {
	case string, json.Number:
		return true
	default:
		return false
	}
}

var wsHTTPRoutes = map[string]bool{
	"utils/upload_image": true, "utils/upload_voice": true,
	"message/send_voice_msg": true, "message/send_file_msg": true,
	"message/get_file": true, "group/file_upload": true,
	"update/download": true, "message/poll_updates": true,
	"utils/session_extend": true, "utils/session_reset": true, "utils/session_info": true,
	"test": true,
}

var wsReadOnlyRoutes = map[string]bool{
	"user/get_info": true, "user/get_friends": true, "user/get_groups": true,
	"user/get_notifications": true, "user/get_notice_list": true,
	"user/get_created_groups": true, "user/get_hide_conv_list": true,
	"friend/get_common_groups": true, "friend/get_deleted_notices": true,
	"friend/get_friend_requests": true, "emoji/get_list": true,
	"message/get_group_msg": true, "message/get_private_msg": true,
	"message/get_mentions": true, "group/get_members": true,
	"group/get_applications": true, "group/get_group_view_info": true,
	"group/get_public_list": true, "group/get_group_msg": true,
	"essence/get_essence": true, "essence/get_essence_stats": true,
	"space/get_list": true, "update/check": true, "group/file_list": true,
}

var wsPublicRoutes = map[string]bool{
	"auth/login": true, "auth/login_by_email": true, "auth/send_login_code": true,
	"auth/login_by_code": true, "auth/request_restore": true,
	"auth/restore_account": true, "auth/send_register_code": true, "auth/register": true,
	"update/check": true,
}

func (a *App) wsMethodCatalog() map[string]wsMethod {
	if a.wsMethods != nil {
		return a.wsMethods
	}
	catalog := make(map[string]wsMethod, len(a.routes))
	for name := range a.routes {
		if wsHTTPRoutes[name] || strings.HasPrefix(name, "admin/") {
			continue
		}
		readOnly := wsReadOnlyRoutes[name]
		catalog[name] = wsMethod{
			Name: name, ReadOnly: readOnly, Public: wsPublicRoutes[name],
			RetryKey: !readOnly && !strings.HasPrefix(name, "auth/") &&
				name != "user/upgrade_password" && name != "user/delete_account",
		}
	}
	return catalog
}

func (a *App) wsDiscover() []wsMethod {
	catalog := a.wsMethodCatalog()
	methods := make([]wsMethod, 0, len(catalog))
	for _, method := range catalog {
		methods = append(methods, method)
	}
	sort.Slice(methods, func(i, j int) bool { return methods[i].Name < methods[j].Name })
	return methods
}

func requestSessionID(request *http.Request, cookieName string) string {
	if authorization := request.Header.Get("Authorization"); authorization != "" {
		parts := strings.Fields(authorization)
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || !validSessionID(parts[1]) {
			return ""
		}
		return parts[1]
	}
	cookie, err := request.Cookie(cookieName)
	if err != nil || !validSessionID(cookie.Value) {
		return ""
	}
	return cookie.Value
}
