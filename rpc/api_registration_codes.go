package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const (
	maxRegistrationCodeUses = 1<<31 - 1
	maxRegistrationExpiry   = 253402300799 // 9999-12-31T23:59:59Z
	registrationPageDefault = 30
	registrationPageMax     = 100
)

func requireRegistrationAdmin(c *Ctx, method string) bool {
	c.jsonOnly = true
	for key := range c.w.Header() {
		if strings.HasPrefix(key, "Access-Control-") {
			c.w.Header().Del(key)
		}
	}
	c.w.Header().Set("X-Content-Type-Options", "nosniff")
	// The legacy RPC reflects CORS origins and supports JSONP. Never expose
	// these privileged endpoints (including reads) across browser origins.
	scheme := "http"
	if requestIsSecure(c.r) {
		scheme = "https"
	}
	origin, site := c.r.Header.Get("Origin"), c.r.Header.Get("Sec-Fetch-Site")
	if (origin != "" && !strings.EqualFold(origin, scheme+"://"+c.r.Host)) || site == "cross-site" || site == "same-site" {
		registrationAdminError(c, http.StatusForbidden, "注册码管理仅允许同源请求")
		return false
	}
	if !c.RequireMethod(method) {
		return false
	}
	if c.session == nil || c.session.SID == "" || c.session.UID <= 0 {
		registrationAdminError(c, http.StatusUnauthorized, "请先登录管理员账号")
		return false
	}
	if c.session.UID != c.app.config.AdminUID {
		registrationAdminError(c, http.StatusForbidden, "仅站点管理员可以管理注册码")
		return false
	}
	var uid int64
	err := c.app.db.QueryRowContext(c.r.Context(), `SELECT s.uid FROM csac_sessions s JOIN chat_user u ON u.id = s.uid
		WHERE s.sid = ? AND s.uid = ? AND s.expires_at > UNIX_TIMESTAMP() AND u.status = 1
		AND COALESCE(u.is_bot, 0) = 0 AND COALESCE(u.ban_until, 0) <= UNIX_TIMESTAMP()`, c.session.SID, c.app.config.AdminUID).Scan(&uid)
	if errors.Is(err, sql.ErrNoRows) {
		registrationAdminError(c, http.StatusForbidden, "管理员账号或会话不可用")
		return false
	}
	if err != nil {
		registrationAdminError(c, http.StatusServiceUnavailable, "暂时无法验证管理员会话")
		return false
	}
	return true
}

func registrationAdminError(c *Ctx, status int, message string) {
	c.JSON(status, map[string]any{"success": false, "message": message})
}

func apiRegistrationCodeCreate(c *Ctx) {
	if !requireRegistrationAdmin(c, http.MethodPost) || !requireRegistrationAdminJSON(c) {
		return
	}
	maxUses, ok := registrationPositiveInt(c.jsonInput["max_uses"])
	if !ok || maxUses > maxRegistrationCodeUses {
		registrationAdminError(c, http.StatusBadRequest, "max_uses 必须为 1 至 2147483647 的整数")
		return
	}
	var neverExpires bool
	if raw, supplied := c.jsonInput["never_expires"]; supplied {
		neverExpires, ok = raw.(bool)
		if !ok {
			registrationAdminError(c, http.StatusBadRequest, "never_expires 必须为布尔值")
			return
		}
	}
	var expiry *int64
	if neverExpires {
		if c.jsonInput["expires_at"] != nil {
			registrationAdminError(c, http.StatusBadRequest, "永久有效与到期时间不能同时设置")
			return
		}
	} else {
		value, ok := registrationPositiveInt(c.jsonInput["expires_at"])
		if !ok || value <= time.Now().Unix() || value > maxRegistrationExpiry {
			registrationAdminError(c, http.StatusBadRequest, "请设置未来的到期时间（Unix 秒），或显式选择永久有效")
			return
		}
		expiry = &value
	}
	store := c.app.registrationCodes
	if store.cipher == nil {
		registrationAdminError(c, http.StatusServiceUnavailable, "尚未配置注册码加密密钥")
		return
	}
	code, err := store.create(c.r.Context(), c.session.UID, maxUses, expiry)
	if err != nil {
		registrationAdminError(c, http.StatusInternalServerError, "生成注册码失败")
		return
	}
	c.JSON(http.StatusCreated, map[string]any{"success": true, "data": code})
}

func apiRegistrationCodeList(c *Ctx) {
	if !requireRegistrationAdmin(c, http.MethodGet) {
		return
	}
	beforeID, limit, ok := registrationAdminPage(c, "before_id")
	if !ok {
		return
	}
	codes, next, err := c.app.registrationCodes.list(c.r.Context(), beforeID, limit)
	if err != nil {
		registrationAdminError(c, http.StatusInternalServerError, "读取注册码列表失败")
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "data": map[string]any{"codes": codes, "next_before_id": next}})
}

func apiRegistrationCodeDetail(c *Ctx) {
	if !requireRegistrationAdmin(c, http.MethodGet) {
		return
	}
	id, ok := registrationPositiveInt(c.r.URL.Query().Get("id"))
	if !ok {
		registrationAdminError(c, http.StatusBadRequest, "无效的注册码 ID")
		return
	}
	beforeUID, limit, ok := registrationAdminPage(c, "before_uid")
	if !ok {
		return
	}
	store := c.app.registrationCodes
	if store.cipher == nil {
		registrationAdminError(c, http.StatusServiceUnavailable, "尚未配置注册码加密密钥")
		return
	}
	data, err := store.detail(c.r.Context(), id, beforeUID, limit)
	if errors.Is(err, sql.ErrNoRows) {
		registrationAdminError(c, http.StatusNotFound, "注册码不存在")
		return
	}
	if err != nil {
		registrationAdminError(c, http.StatusInternalServerError, "读取注册码详情失败，请检查服务配置")
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "data": data})
}

func apiRegistrationCodeRevoke(c *Ctx) {
	if !requireRegistrationAdmin(c, http.MethodPost) || !requireRegistrationAdminJSON(c) {
		return
	}
	id, ok := registrationPositiveInt(c.jsonInput["id"])
	if !ok {
		registrationAdminError(c, http.StatusBadRequest, "无效的注册码 ID")
		return
	}
	err := c.app.registrationCodes.revoke(c.r.Context(), id, c.session.UID)
	if errors.Is(err, sql.ErrNoRows) {
		registrationAdminError(c, http.StatusNotFound, "注册码不存在")
		return
	}
	if err != nil {
		registrationAdminError(c, http.StatusInternalServerError, "作废注册码失败")
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "注册码已作废"})
}

func requireRegistrationAdminJSON(c *Ctx) bool {
	if c.jsonInput == nil || c.inputErr != nil {
		registrationAdminError(c, http.StatusBadRequest, "请发送有效的 JSON 请求体")
		return false
	}
	return true
}

func registrationAdminPage(c *Ctx, cursor string) (int64, int, bool) {
	query := c.r.URL.Query()
	var before int64
	limit := int64(registrationPageDefault)
	if query.Has(cursor) {
		var ok bool
		if before, ok = registrationPositiveInt(query.Get(cursor)); !ok {
			registrationAdminError(c, http.StatusBadRequest, "无效的分页游标")
			return 0, 0, false
		}
	}
	if query.Has("limit") {
		var ok bool
		if limit, ok = registrationPositiveInt(query.Get("limit")); !ok || limit > registrationPageMax {
			registrationAdminError(c, http.StatusBadRequest, "limit 必须为 1 至 100 的整数")
			return 0, 0, false
		}
	}
	return before, int(limit), true
}

func registrationPositiveInt(raw any) (int64, bool) {
	var value int64
	var err error
	switch v := raw.(type) {
	case json.Number:
		value, err = v.Int64()
	case string:
		value, err = strconv.ParseInt(v, 10, 64)
	default:
		return 0, false
	}
	return value, err == nil && value > 0
}
