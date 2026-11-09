package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

func (app *ACOP) signAdminSession(uid, issuedAt int64) string {
	mac := hmac.New(sha256.New, []byte(app.config.SessionSecret))
	fmt.Fprintf(mac, "admin:%d:%d", uid, issuedAt)
	return hex.EncodeToString(mac.Sum(nil))
}

func (app *ACOP) hasAdminSession(r *http.Request) bool {
	if app.config.SessionSecret == "" || app.config.AdminUID <= 0 {
		return false
	}
	cookie, err := r.Cookie("acop_admin")
	if err != nil {
		return false
	}
	parts := strings.Split(cookie.Value, ":")
	if len(parts) != 3 {
		return false
	}
	uid, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil || uid != app.config.AdminUID {
		return false
	}
	issuedAt, err := strconv.ParseInt(parts[1], 10, 64)
	now := time.Now().Unix()
	if err != nil || issuedAt <= 0 || issuedAt > now || now-issuedAt >= sessionExpiry {
		return false
	}
	return hmac.Equal([]byte(parts[2]), []byte(app.signAdminSession(uid, issuedAt)))
}

func (ctx *ACOPCtx) setAdminSession(uid int64) {
	now := time.Now().Unix()
	http.SetCookie(ctx.w, &http.Cookie{
		Name:     "acop_admin",
		Value:    fmt.Sprintf("%d:%d:%s", uid, now, ctx.app.signAdminSession(uid, now)),
		Path:     "/",
		MaxAge:   sessionExpiry,
		HttpOnly: true,
		Secure:   ctx.r.TLS != nil || strings.EqualFold(ctx.r.Header.Get("X-Forwarded-Proto"), "https"),
		SameSite: http.SameSiteLaxMode,
	})
}
