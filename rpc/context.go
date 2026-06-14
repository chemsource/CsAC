// Copyright (c) Chemsource Studio. All rights reserved.
// Contact: swcsstudio@126.com

package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var callbackCleaner = regexp.MustCompile(`[^A-Za-z0-9_.$]`)

type Session struct {
	SID       string
	UID       int64
	Nickname  string
	Platform  string
	SX        bool
	SE        int64
	LastTouch int64
	ExpiresAt int64
	dirty     bool
	destroy   bool
}

type Ctx struct {
	app       *App
	w         http.ResponseWriter
	r         *http.Request
	input     map[string]any
	parsed    bool
	session   *Session
	responded bool
}

func NewCtx(app *App, w http.ResponseWriter, r *http.Request) *Ctx {
	ctx := &Ctx{app: app, w: w, r: r, session: &Session{}}
	ctx.loadSession()
	return ctx
}

func (c *Ctx) ResolveRoute() string {
	route := c.InputString("route")
	path := strings.TrimSpace(c.r.URL.Path)
	if route == "" {
		for _, marker := range []string{"/rpc/UniCsAC.php/", "/UniCsAC.php/"} {
			if idx := strings.Index(path, marker); idx >= 0 {
				route = path[idx+len(marker):]
				break
			}
		}
	}
	if route == "" {
		trimmed := strings.Trim(path, "/")
		if trimmed != "" && trimmed != "UniCsAC.php" && trimmed != "rpc/UniCsAC.php" {
			route = trimmed
		}
	}
	route = strings.TrimSpace(route)
	if route == "" {
		return ""
	}
	route = strings.TrimLeft(strings.ReplaceAll(route, `\\`, "/"), "/")
	if idx := strings.IndexAny(route, "?#"); idx >= 0 {
		route = route[:idx]
	}
	if strings.HasSuffix(route, ".php") {
		route = strings.TrimSuffix(route, ".php")
	}
	return strings.Trim(route, "/")
}

func (c *Ctx) Input() map[string]any {
	if c.parsed {
		return c.input
	}
	c.parsed = true
	data := map[string]any{}
	mergeValues(data, c.r.URL.Query())

	contentType := c.r.Header.Get("Content-Type")
	if strings.Contains(contentType, "multipart/form-data") {
		_ = c.r.ParseMultipartForm(64 << 20)
		if c.r.MultipartForm != nil {
			mergeValues(data, c.r.MultipartForm.Value)
		}
	} else if strings.Contains(contentType, "application/x-www-form-urlencoded") {
		_ = c.r.ParseForm()
		mergeValues(data, c.r.PostForm)
	}

	if strings.Contains(contentType, "application/json") {
		defer c.r.Body.Close()
		var jsonData map[string]any
		if err := json.NewDecoder(c.r.Body).Decode(&jsonData); err == nil {
			for k, v := range jsonData {
				data[k] = v
			}
		}
	}

	c.input = data
	return data
}

func mergeValues(dst map[string]any, values map[string][]string) {
	for key, list := range values {
		if len(list) == 0 {
			dst[key] = ""
			continue
		}
		dst[key] = list[len(list)-1]
	}
}

func (c *Ctx) InputValue(key string, fallback any) any {
	if value, ok := c.Input()[key]; ok {
		return value
	}
	return fallback
}

func (c *Ctx) HasInput(key string) bool {
	_, ok := c.Input()[key]
	return ok
}

func (c *Ctx) InputString(key string, fallback ...string) string {
	def := ""
	if len(fallback) > 0 {
		def = fallback[0]
	}
	value := c.InputValue(key, def)
	switch v := value.(type) {
	case nil:
		return def
	case string:
		return strings.TrimSpace(v)
	case []string, []any, map[string]any:
		return def
	case json.Number:
		return strings.TrimSpace(v.String())
	default:
		return strings.TrimSpace(toString(v))
	}
}

func (c *Ctx) InputInt(key string, fallback ...int64) int64 {
	def := int64(0)
	if len(fallback) > 0 {
		def = fallback[0]
	}
	value := c.InputValue(key, def)
	return toInt64Default(value, def)
}

func (c *Ctx) InputBool(key string, fallback ...bool) bool {
	def := false
	if len(fallback) > 0 {
		def = fallback[0]
	}
	value := c.InputValue(key, boolToString(def))
	if b, ok := value.(bool); ok {
		return b
	}
	switch strings.ToLower(strings.TrimSpace(toString(value))) {
	case "1", "true", "on", "yes":
		return true
	}
	return false
}

func (c *Ctx) RequireMethod(method string) bool {
	if !strings.EqualFold(c.r.Method, method) {
		c.JSON(http.StatusMethodNotAllowed, map[string]any{"success": false, "message": "无效的请求方法"})
		return false
	}
	return true
}

func (c *Ctx) JSON(status int, data map[string]any) {
	if c.responded {
		return
	}
	if err := c.saveSession(); err != nil {
		log.Printf("save session failed: %v", err)
	}
	callback := callbackCleaner.ReplaceAllString(c.r.URL.Query().Get("callback"), "")
	payload, err := json.Marshal(data)
	if err != nil {
		status = http.StatusInternalServerError
		payload = []byte(`{"success":false,"message":"服务器内部错误"}`)
	}
	if callback != "" {
		c.w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
		c.w.WriteHeader(status)
		_, _ = c.w.Write([]byte(callback + "(" + string(payload) + ");"))
	} else {
		c.w.Header().Set("Content-Type", "application/json; charset=utf-8")
		c.w.WriteHeader(status)
		_, _ = c.w.Write(payload)
	}
	c.responded = true
}

func writeJSONRaw(w http.ResponseWriter, status int, data map[string]any) {
	payload, _ := json.Marshal(data)
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_, _ = w.Write(payload)
}

func (c *Ctx) loadSession() {
	cookie, err := c.r.Cookie(c.app.config.SessionCookieName)
	if err != nil || cookie.Value == "" || !validSessionID(cookie.Value) {
		return
	}
	row, err := c.app.fetchOne("SELECT sid, uid, nickname, platform, sx, se, last_touch, expires_at FROM csac_sessions WHERE sid = ? AND expires_at > ? LIMIT 1", cookie.Value, time.Now().Unix())
	if err != nil || row == nil {
		return
	}
	c.session = &Session{
		SID:       str(row, "sid"),
		UID:       intval(row, "uid"),
		Nickname:  str(row, "nickname"),
		Platform:  str(row, "platform"),
		SX:        intval(row, "sx") == 1,
		SE:        intval(row, "se"),
		LastTouch: intval(row, "last_touch"),
		ExpiresAt: intval(row, "expires_at"),
	}
}

func (c *Ctx) ensureSession() {
	if c.session == nil {
		c.session = &Session{}
	}
	if c.session.SID == "" {
		c.session.SID = randomSessionID()
		c.session.ExpiresAt = time.Now().Unix() + c.app.config.SessionLifetimeSeconds
		c.session.dirty = true
	}
}

func (c *Ctx) markSessionDirty() {
	c.ensureSession()
	c.session.dirty = true
}

func (c *Ctx) saveSession() error {
	if c.session == nil {
		return nil
	}
	if c.session.destroy {
		if c.session.SID != "" {
			_, _ = c.app.exec("DELETE FROM csac_sessions WHERE sid = ?", c.session.SID)
		}
		http.SetCookie(c.w, &http.Cookie{Name: c.app.config.SessionCookieName, Value: "", Path: "/", Expires: time.Now().Add(-time.Hour), MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteLaxMode})
		return nil
	}
	if !c.session.dirty {
		return nil
	}
	c.ensureSession()
	if c.session.ExpiresAt <= time.Now().Unix() {
		c.session.ExpiresAt = time.Now().Unix() + c.app.config.SessionLifetimeSeconds
	}
	_, err := c.app.exec(`INSERT INTO csac_sessions (sid, uid, nickname, platform, sx, se, last_touch, expires_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE uid = VALUES(uid), nickname = VALUES(nickname), platform = VALUES(platform), sx = VALUES(sx), se = VALUES(se), last_touch = VALUES(last_touch), expires_at = VALUES(expires_at), updated_at = VALUES(updated_at)`,
		c.session.SID, c.session.UID, c.session.Nickname, c.session.Platform, boolInt(c.session.SX), c.session.SE, c.session.LastTouch, c.session.ExpiresAt, time.Now().Unix())
	if err != nil {
		return err
	}
	http.SetCookie(c.w, &http.Cookie{Name: c.app.config.SessionCookieName, Value: c.session.SID, Path: "/", Expires: time.Unix(c.session.ExpiresAt, 0), MaxAge: int(c.app.config.SessionLifetimeSeconds), HttpOnly: true, SameSite: http.SameSiteLaxMode, Secure: requestIsSecure(c.r)})
	c.session.dirty = false
	return nil
}

func (c *Ctx) destroySession() {
	if c.session == nil {
		c.session = &Session{}
	}
	c.session.destroy = true
	c.session.dirty = true
}

func validSessionID(value string) bool {
	if len(value) < 16 || len(value) > 128 {
		return false
	}
	for _, ch := range value {
		if (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == ',' || ch == '-' {
			continue
		}
		return false
	}
	return true
}

func randomSessionID() string {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		panic(err)
	}
	return hex.EncodeToString(buf)
}

func requestIsSecure(r *http.Request) bool {
	return r.TLS != nil || strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https")
}

func boolToString(v bool) string {
	if v {
		return "1"
	}
	return "0"
}

func boolInt(v bool) int {
	if v {
		return 1
	}
	return 0
}

func toInt64Default(value any, fallback int64) int64 {
	switch v := value.(type) {
	case int:
		return int64(v)
	case int8:
		return int64(v)
	case int16:
		return int64(v)
	case int32:
		return int64(v)
	case int64:
		return v
	case uint:
		return int64(v)
	case uint8:
		return int64(v)
	case uint16:
		return int64(v)
	case uint32:
		return int64(v)
	case uint64:
		return int64(v)
	case float32:
		return int64(v)
	case float64:
		return int64(v)
	case json.Number:
		if i, err := v.Int64(); err == nil {
			return i
		}
	case []byte:
		return toInt64Default(string(v), fallback)
	case string:
		v = strings.TrimSpace(v)
		if v == "" {
			return fallback
		}
		if strings.Contains(v, ".") {
			f, err := strconv.ParseFloat(v, 64)
			if err == nil {
				return int64(f)
			}
		}
		parsed, err := strconv.ParseInt(v, 10, 64)
		if err == nil {
			return parsed
		}
	}
	return fallback
}

func toString(value any) string {
	switch v := value.(type) {
	case nil:
		return ""
	case string:
		return v
	case []byte:
		return string(v)
	case json.Number:
		return v.String()
	default:
		return strings.TrimSpace(fmt.Sprint(v))
	}
}
