// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC Open Platform (ACOP) Version 1.0.0.260614-r1

package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net"
	"net/http"
	"net/smtp"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	_ "github.com/go-sql-driver/mysql"
	"golang.org/x/crypto/bcrypt"
)

const acopVersion = "1.0.0.260614-r1"

type Config struct {
	DBHost        string
	DBUser        string
	DBPass        string
	DBName        string
	HTTPAddr      string
	SessionSecret string
	AdminUID      int64
	CsacEndpoint  string // CsAC 主后端接口，用于验证主客户端调试模式
	BotEndpoint   string // ServerBot端点，用于通知脚本重载
	BotSecret     string // ServerBot内部通信密钥
	UploadDir     string // 与主后端共享的公开上传目录
	LibDir        string // AJL库文件输出目录（默认 ../ServerBot/lib 相对于acop可执行文件）
	// SMTP 邮件配置
	SMTPHost    string
	SMTPPort    string
	SMTPUser    string
	SMTPPass    string
	SMTPFrom    string
	SMTPEnabled bool
}

// codeEntry 验证码条目
type codeEntry struct {
	code      string
	expiresAt time.Time
	used      bool
}

// CodeStore 验证码存储
type CodeStore struct {
	mu    sync.RWMutex
	codes map[string]*codeEntry // key: email
}

func NewCodeStore() *CodeStore {
	cs := &CodeStore{codes: make(map[string]*codeEntry)}
	go cs.cleanupLoop()
	return cs
}

func (cs *CodeStore) Set(email, code string, ttl time.Duration) {
	cs.mu.Lock()
	defer cs.mu.Unlock()
	cs.codes[strings.ToLower(email)] = &codeEntry{code: code, expiresAt: time.Now().Add(ttl), used: false}
}

func (cs *CodeStore) Verify(email, code string) bool {
	cs.mu.Lock()
	defer cs.mu.Unlock()
	key := strings.ToLower(email)
	entry, ok := cs.codes[key]
	if !ok || entry.used || time.Now().After(entry.expiresAt) {
		return false
	}
	if entry.code != code {
		return false
	}
	entry.used = true
	return true
}

func (cs *CodeStore) cleanupLoop() {
	ticker := time.NewTicker(5 * time.Minute)
	for range ticker.C {
		cs.mu.Lock()
		now := time.Now()
		for k, v := range cs.codes {
			if now.After(v.expiresAt) {
				delete(cs.codes, k)
			}
		}
		cs.mu.Unlock()
	}
}

type ACOP struct {
	db        *sql.DB
	config    Config
	codeStore *CodeStore
	routes    map[string]func(*ACOPCtx)
}

type ACOPCtx struct {
	app    *ACOP
	w      http.ResponseWriter
	r      *http.Request
	params map[string]any
	devID  int64 // 登录后的开发者ID
}

func main() {
	cfg := loadConfig()
	app, err := NewACOP(cfg)
	if err != nil {
		log.Fatalf("ACOP startup failed: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", app.ServeHTTP)

	server := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}
	log.Printf("CsAC Open Platform v%s listening on %s", acopVersion, cfg.HTTPAddr)
	// 输出lib输出目录信息，方便调试
	libDir := cfg.LibDir
	if libDir == "" {
		exePath, _ := os.Executable()
		libDir = filepath.Join(filepath.Dir(exePath), "..", "ServerBot", "lib")
	}
	log.Printf("ACOP: AJL库输出目录: %s (设置ACOP_LIB_DIR环境变量可自定义)", libDir)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("ACOP stopped: %v", err)
	}
}

func NewACOP(cfg Config) (*ACOP, error) {
	dsn := fmt.Sprintf("%s:%s@tcp(%s)/%s?charset=utf8mb4&parseTime=false&loc=UTC", cfg.DBUser, cfg.DBPass, cfg.DBHost, cfg.DBName)
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(40)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(5 * time.Minute)
	if err := db.Ping(); err != nil {
		return nil, err
	}

	app := &ACOP{
		db:        db,
		config:    cfg,
		codeStore: NewCodeStore(),
	}
	app.routes = app.buildRoutes()
	app.ensureSchema()
	app.ensureSchemaMigrations()
	return app, nil
}

func (app *ACOP) buildRoutes() map[string]func(*ACOPCtx) {
	return map[string]func(*ACOPCtx){
		// 开发者认证
		"dev/register":      app.apiDevRegister,
		"dev/login":         app.apiDevLogin,
		"dev/logout":        app.apiDevLogout,
		"dev/get_info":      app.apiDevGetInfo,
		"dev/send_code":     app.apiDevSendCode,
		"dev/login_by_code": app.apiDevLoginByCode,
		// Bot管理
		"bot/create":        app.apiBotCreate,
		"bot/list":          app.apiBotList,
		"bot/get_info":      app.apiBotGetInfo,
		"bot/update":        app.apiBotUpdate,
		"bot/upload_avatar": app.apiBotUploadAvatar,
		"bot/reset_token":   app.apiBotResetToken,
		"bot/delete":        app.apiBotDelete,
		// 脚本管理
		"script/create":      app.apiScriptCreate,
		"script/list":        app.apiScriptList,
		"script/get":         app.apiScriptGet,
		"script/update":      app.apiScriptUpdate,
		"script/delete":      app.apiScriptDelete,
		"script/toggle":      app.apiScriptToggle,
		"script/test":        app.apiScriptTest,
		"script/upload_acr":  app.apiScriptUploadAcr,
		"script/upload_acrg": app.apiScriptUploadAcrg,
		// 日志
		"log/list": app.apiLogList,
		// 权限申请
		"perm/request": app.apiPermRequest,
		"perm/list":    app.apiPermList,
		// 管理员
		"admin/perm/handle":  app.apiAdminPermHandle,
		"admin/perm/pending": app.apiAdminPermPending,
		"admin/bot/list":     app.apiAdminBotList,
		"admin/login":        app.apiAdminLogin,
		"admin/logout":       app.apiAdminLogout,
		"admin/check":        app.apiAdminCheck,
		// v2.2.1: JSLibs库管理
		"lib/upload":                app.apiLibUpload,
		"lib/my_libs":               app.apiLibMyLibs,
		"lib/list":                  app.apiLibList,
		"admin/lib/pending":         app.apiAdminLibPending,
		"admin/lib/review":          app.apiAdminLibReview,
		"admin/lib/set_upload_perm": app.apiAdminLibSetUploadPerm,
		// 管理员: ACR脚本审核
		"admin/acr/pending": app.apiAdminAcrPending,
		"admin/acr/review":  app.apiAdminAcrReview,
		"admin/acr/read":    app.apiAdminAcrRead,
		// EMA小程序上传与审核
		"script/upload_ema": app.apiScriptUploadEma,
		"admin/ema/pending": app.apiAdminEmaPending,
		"admin/ema/read":    app.apiAdminEmaRead,
		"admin/ema/review":  app.apiAdminEmaReview,
		// 诊断
		"diag/test-save": app.apiDiagTestSave,
	}
}

func (app *ACOP) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// CORS
	if origin := r.Header.Get("Origin"); origin != "" {
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		w.Header().Set("Vary", "Origin")
	}
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With, Accept, X-CsAC-Debug-Cookie")
	w.Header().Set("Cache-Control", "no-store")

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}

	ctx := &ACOPCtx{app: app, w: w, r: r}
	ctx.parseParams()
	ctx.loadSession()

	route := ctx.param("route")
	if route == "" {
		path := strings.Trim(r.URL.Path, "/")
		if path != "" {
			route = path
		}
	}
	if route == "" {
		ctx.JSON(http.StatusBadRequest, map[string]any{"success": false, "message": "缺少route参数"})
		return
	}
	handler := app.routes[route]
	if handler == nil {
		ctx.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "未知的route: " + route})
		return
	}
	handler(ctx)
}

// ===== 参数解析 =====

func (ctx *ACOPCtx) parseParams() {
	params := map[string]any{}
	for k, v := range ctx.r.URL.Query() {
		if len(v) > 0 {
			params[k] = v[len(v)-1]
		}
	}
	contentType := ctx.r.Header.Get("Content-Type")
	if strings.Contains(contentType, "application/json") {
		var jsonData map[string]any
		if err := json.NewDecoder(ctx.r.Body).Decode(&jsonData); err == nil {
			for k, v := range jsonData {
				params[k] = v
			}
		}
	} else if strings.Contains(contentType, "multipart/form-data") {
		ctx.r.ParseMultipartForm(6 << 20)
		for k, v := range ctx.r.PostForm {
			if len(v) > 0 {
				params[k] = v[len(v)-1]
			}
		}
	} else if strings.Contains(contentType, "application/x-www-form-urlencoded") {
		ctx.r.ParseForm()
		for k, v := range ctx.r.PostForm {
			if len(v) > 0 {
				params[k] = v[len(v)-1]
			}
		}
	}
	ctx.params = params
}

func (ctx *ACOPCtx) param(key string) string {
	v, ok := ctx.params[key]
	if !ok {
		return ""
	}
	return strings.TrimSpace(fmt.Sprint(v))
}

func (ctx *ACOPCtx) paramInt(key string) int64 {
	s := ctx.param(key)
	if s == "" {
		return 0
	}
	n, _ := strconv.ParseInt(s, 10, 64)
	return n
}

func (ctx *ACOPCtx) JSON(status int, data map[string]any) {
	if ctx.w == nil {
		return
	}
	payload, _ := json.Marshal(data)
	ctx.w.Header().Set("Content-Type", "application/json; charset=utf-8")
	ctx.w.WriteHeader(status)
	_, _ = ctx.w.Write(payload)
}

// ===== Session管理 =====

// sessionExpiry 会话有效期（7天）
const sessionExpiry = 86400 * 7

// signSession 对 devID:timestamp 做 HMAC-SHA256 签名
func (app *ACOP) signSession(devID int64, ts int64) string {
	mac := hmac.New(sha256.New, []byte(app.config.SessionSecret))
	mac.Write([]byte(fmt.Sprintf("%d:%d", devID, ts)))
	return hex.EncodeToString(mac.Sum(nil))
}

func (ctx *ACOPCtx) loadSession() {
	cookie, err := ctx.r.Cookie("acop_session")
	if err != nil || cookie.Value == "" {
		return
	}
	// token格式: devID:timestamp:hmac
	parts := strings.SplitN(cookie.Value, ":", 3)
	if len(parts) != 3 {
		return
	}
	devID, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil || devID <= 0 {
		return
	}
	ts, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return
	}
	// 校验过期
	if time.Now().Unix()-ts > sessionExpiry {
		return
	}
	// 校验 HMAC
	expected := ctx.app.signSession(devID, ts)
	if !hmac.Equal([]byte(parts[2]), []byte(expected)) {
		return
	}
	ctx.devID = devID
}

func (ctx *ACOPCtx) setSession(devID int64) {
	ts := time.Now().Unix()
	sig := ctx.app.signSession(devID, ts)
	token := fmt.Sprintf("%d:%d:%s", devID, ts, sig)
	http.SetCookie(ctx.w, &http.Cookie{
		Name:     "acop_session",
		Value:    token,
		Path:     "/",
		MaxAge:   sessionExpiry,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Secure:   ctx.r.TLS != nil,
	})
	ctx.devID = devID
}

func (ctx *ACOPCtx) clearSession() {
	http.SetCookie(ctx.w, &http.Cookie{
		Name:     "acop_session",
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		HttpOnly: true,
	})
	ctx.devID = 0
}

func (ctx *ACOPCtx) requireLogin() (int64, bool) {
	if ctx.devID <= 0 {
		ctx.JSON(http.StatusUnauthorized, map[string]any{"success": false, "message": "未登录"})
		return 0, false
	}
	// 检查开发者状态
	dev, err := ctx.app.fetchOne("SELECT id, status FROM open_dev_accounts WHERE id = ?", ctx.devID)
	if err != nil || dev == nil || intval(dev, "status") != 1 {
		ctx.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "账号已被封禁"})
		return 0, false
	}
	return ctx.devID, true
}

func (ctx *ACOPCtx) requireAdmin() bool {
	if cookie, err := ctx.r.Cookie("acop_admin"); err == nil && cookie.Value == fmt.Sprintf("admin_%d", ctx.app.config.AdminUID) {
		return true
	}
	if ctx.devID > 0 {
		dev, err := ctx.app.fetchOne("SELECT uid, status FROM open_dev_accounts WHERE id = ?", ctx.devID)
		if err == nil && dev != nil && intval(dev, "uid") == ctx.app.config.AdminUID && intval(dev, "status") == 1 {
			return true
		}
	}
	if ctx.app.verifyCsacDebugSession(ctx.r.Header.Get("X-CsAC-Debug-Cookie")) {
		return true
	}
	ctx.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "需要管理员权限"})
	return false
}

func (app *ACOP) verifyCsacDebugSession(cookie string) bool {
	cookie = strings.TrimSpace(cookie)
	if cookie == "" || strings.ContainsAny(cookie, "\r\n") {
		return false
	}
	endpoint := strings.TrimSpace(app.config.CsacEndpoint)
	if endpoint == "" {
		return false
	}
	req, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return false
	}
	q := req.URL.Query()
	q.Set("route", "utils/session_info")
	req.URL.RawQuery = q.Encode()
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Cookie", cookie)
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		log.Printf("ACOP: verify CsAC debug session failed: %v", err)
		return false
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return false
	}
	var data map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return false
	}
	return data["success"] == true && data["active"] == true
}

// ===== 数据库辅助 =====

var safeIdent = regexp.MustCompile(`^[A-Za-z0-9_]+$`)

func (app *ACOP) fetchOne(query string, args ...any) (map[string]any, error) {
	rows, err := app.fetchAll(query, args...)
	if err != nil || len(rows) == 0 {
		return nil, err
	}
	return rows[0], nil
}

func (app *ACOP) fetchAll(query string, args ...any) ([]map[string]any, error) {
	rows, err := app.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cols, err := rows.Columns()
	if err != nil {
		return nil, err
	}
	result := make([]map[string]any, 0)
	for rows.Next() {
		values := make([]sql.NullString, len(cols))
		dest := make([]any, len(cols))
		for i := range values {
			dest[i] = &values[i]
		}
		if err := rows.Scan(dest...); err != nil {
			return nil, err
		}
		row := map[string]any{}
		for i, col := range cols {
			if values[i].Valid {
				row[col] = values[i].String
			} else {
				row[col] = nil
			}
		}
		result = append(result, row)
	}
	return result, rows.Err()
}

func (app *ACOP) exec(query string, args ...any) (int64, error) {
	res, err := app.db.Exec(query, args...)
	if err != nil {
		return 0, err
	}
	affected, _ := res.RowsAffected()
	return affected, nil
}

func (app *ACOP) insertRow(table string, data map[string]any) (int64, error) {
	if !safeIdent.MatchString(table) {
		return 0, fmt.Errorf("invalid table name")
	}
	filtered := app.filterExistingColumns(table, data)
	if len(filtered) == 0 {
		return 0, fmt.Errorf("no valid columns for insert: %s", table)
	}
	data = filtered
	names := sortedKeys(data)
	placeholders := make([]string, len(names))
	args := make([]any, len(names))
	for i, name := range names {
		if !safeIdent.MatchString(name) {
			return 0, fmt.Errorf("invalid column name: %s", name)
		}
		placeholders[i] = "?"
		args[i] = data[name]
	}
	query := fmt.Sprintf("INSERT INTO `%s` (`%s`) VALUES (%s)",
		table, strings.Join(names, "`, `"), strings.Join(placeholders, ", "))
	res, err := app.db.Exec(query, args...)
	if err != nil {
		return 0, err
	}
	id, _ := res.LastInsertId()
	return id, nil
}

func (app *ACOP) filterExistingColumns(table string, data map[string]any) map[string]any {
	columns := app.tableColumns(table)
	filtered := map[string]any{}
	for key, value := range data {
		if safeIdent.MatchString(key) && columns[key] {
			filtered[key] = value
		}
	}
	return filtered
}

func (app *ACOP) tableColumns(table string) map[string]bool {
	if !safeIdent.MatchString(table) {
		return map[string]bool{}
	}
	rows, err := app.fetchAll("SHOW COLUMNS FROM `" + table + "`")
	columns := map[string]bool{}
	if err != nil {
		return columns
	}
	for _, row := range rows {
		field := str(row, "Field")
		if field != "" {
			columns[field] = true
		}
	}
	return columns
}

func (app *ACOP) updateRow(table string, data map[string]any, where string, whereArgs ...any) (int64, error) {
	if !safeIdent.MatchString(table) {
		return 0, fmt.Errorf("invalid table name")
	}
	names := sortedKeys(data)
	sets := make([]string, 0, len(names))
	args := make([]any, 0, len(names)+len(whereArgs))
	for _, name := range names {
		if !safeIdent.MatchString(name) {
			continue
		}
		sets = append(sets, fmt.Sprintf("`%s` = ?", name))
		args = append(args, data[name])
	}
	args = append(args, whereArgs...)
	res, err := app.db.Exec(fmt.Sprintf("UPDATE `%s` SET %s WHERE %s", table, strings.Join(sets, ", "), where), args...)
	if err != nil {
		return 0, err
	}
	affected, _ := res.RowsAffected()
	return affected, nil
}

func sortedKeys(m map[string]any) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func str(row map[string]any, key string) string {
	if row == nil {
		return ""
	}
	v, ok := row[key]
	if !ok || v == nil {
		return ""
	}
	return strings.TrimSpace(fmt.Sprint(v))
}

func intval(row map[string]any, key string) int64 {
	if row == nil {
		return 0
	}
	v, ok := row[key]
	if !ok || v == nil {
		return 0
	}
	s := strings.TrimSpace(fmt.Sprint(v))
	if s == "" {
		return 0
	}
	n, _ := strconv.ParseInt(s, 10, 64)
	return n
}

// ===== 配置加载 =====

func loadConfig() Config {
	loadEnvFile()
	smtpEnabled := os.Getenv("ACOP_SMTP_HOST") != ""
	return Config{
		DBHost:        getenv("ACOP_DB_HOST", ""),
		DBUser:        getenv("ACOP_DB_USER", ""),
		DBPass:        getenv("ACOP_DB_PASS", ""),
		DBName:        getenv("ACOP_DB_NAME", ""),
		HTTPAddr:      getenv("ACOP_HTTP_ADDR", ":8082"),
		SessionSecret: getenv("ACOP_SECRET", "change-me-to-a-random-secret"),
		AdminUID:      getenvInt64("ACOP_ADMIN_UID", 1),
		CsacEndpoint:  getenv("ACOP_CSAC_ENDPOINT", "https://csac.chat/rpc/UniCsAC.php"),
		BotEndpoint:   getenvBotEndpoint(),
		BotSecret:     getenv("ACOP_BOT_SECRET", "change-me-to-a-random-secret"),
		UploadDir:     getenv("ACOP_UPLOAD_DIR", "upload"),
		LibDir:        getenv("ACOP_LIB_DIR", ""),
		SMTPHost:      getenv("ACOP_SMTP_HOST", ""),
		SMTPPort:      getenv("ACOP_SMTP_PORT", "465"),
		SMTPUser:      getenv("ACOP_SMTP_USER", ""),
		SMTPPass:      getenv("ACOP_SMTP_PASS", ""),
		SMTPFrom:      getenv("ACOP_SMTP_FROM", ""),
		SMTPEnabled:   smtpEnabled,
	}
}

func loadEnvFile() {
	exePath, _ := os.Executable()
	candidates := []string{
		filepath.Join(filepath.Dir(exePath), ".env"),
		".env",
	}
	var envPath string
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			envPath = p
			break
		}
	}
	if envPath == "" {
		return
	}
	data, err := os.ReadFile(envPath)
	if err != nil {
		return
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		idx := strings.Index(line, "=")
		if idx < 0 {
			continue
		}
		key := strings.TrimSpace(line[:idx])
		val := strings.TrimSpace(line[idx+1:])
		if strings.HasPrefix(val, `"`) && strings.HasSuffix(val, `"`) {
			val = val[1 : len(val)-1]
		}
		if os.Getenv(key) == "" {
			os.Setenv(key, val)
		}
	}
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getenvInt64(key string, fallback int64) int64 {
	if v := os.Getenv(key); v != "" {
		n, err := strconv.ParseInt(v, 10, 64)
		if err == nil {
			return n
		}
	}
	return fallback
}

// getenvBotEndpoint 读取 ServerBot 端点，优先 ACOP_BOTAPI_URL（文档名），回退 ACOP_BOT_ENDPOINT
func getenvBotEndpoint() string {
	if v := os.Getenv("ACOP_BOTAPI_URL"); v != "" {
		return v
	}
	return os.Getenv("ACOP_BOT_ENDPOINT")
}

// ===== Schema =====

func (app *ACOP) ensureSchema() {
	app.ensureTable("open_dev_accounts", `CREATE TABLE IF NOT EXISTS open_dev_accounts (
		id INT NOT NULL AUTO_INCREMENT,
		uid INT NOT NULL DEFAULT 0 COMMENT '关联chat_user.id',
		email VARCHAR(255) NOT NULL,
		pwd VARCHAR(255) NOT NULL,
		dev_name VARCHAR(50) NOT NULL COMMENT '开发者名称',
		api_key VARCHAR(128) NOT NULL COMMENT '开发者API Key',
		status TINYINT NOT NULL DEFAULT 1 COMMENT '1=正常 0=封禁',
		created_at INT NOT NULL,
		PRIMARY KEY (id),
		UNIQUE KEY uk_email (email),
		UNIQUE KEY uk_uid (uid),
		UNIQUE KEY uk_api_key (api_key)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	app.ensureTable("bot_accounts", `CREATE TABLE IF NOT EXISTS bot_accounts (
		id INT NOT NULL AUTO_INCREMENT,
		uid INT NOT NULL COMMENT '关联chat_user.id',
		dev_id INT NOT NULL COMMENT '关联开发者ID',
		bot_token VARCHAR(128) NOT NULL COMMENT 'Bot认证Token',
		bot_name VARCHAR(50) NOT NULL COMMENT 'Bot名称',
		bot_desc VARCHAR(500) DEFAULT '' COMMENT 'Bot描述',
		bot_avatar VARCHAR(255) DEFAULT '' COMMENT 'Bot头像',
		status TINYINT NOT NULL DEFAULT 1 COMMENT '1=正常 0=禁用',
		can_notify TINYINT NOT NULL DEFAULT 0 COMMENT '是否允许发送通知',
		can_http TINYINT NOT NULL DEFAULT 0 COMMENT '是否允许HTTP请求',
		online TINYINT NOT NULL DEFAULT 0 COMMENT '是否在线',
		last_online INT NOT NULL DEFAULT 0 COMMENT '最后在线时间戳',
		created_at INT NOT NULL,
		PRIMARY KEY (id),
		UNIQUE KEY uk_bot_token (bot_token),
		INDEX idx_dev_id (dev_id),
		INDEX idx_uid (uid)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	app.ensureTable("bot_scripts", `CREATE TABLE IF NOT EXISTS bot_scripts (
		id INT NOT NULL AUTO_INCREMENT,
		bot_id INT NOT NULL COMMENT '关联bot_accounts.id',
		script_name VARCHAR(100) NOT NULL COMMENT '脚本名称',
		script_content MEDIUMTEXT NOT NULL COMMENT '脚本内容',
		enabled TINYINT NOT NULL DEFAULT 1 COMMENT '1=启用 0=禁用',
		version INT NOT NULL DEFAULT 1 COMMENT '脚本版本号',
		created_at INT NOT NULL,
		updated_at INT NOT NULL,
		PRIMARY KEY (id),
		INDEX idx_bot_id (bot_id)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	app.ensureTable("bot_logs", `CREATE TABLE IF NOT EXISTS bot_logs (
		id INT NOT NULL AUTO_INCREMENT,
		bot_id INT NOT NULL,
		script_id INT NOT NULL DEFAULT 0,
		level ENUM('log','error','warn') NOT NULL DEFAULT 'log',
		content TEXT NOT NULL,
		created_at INT NOT NULL,
		PRIMARY KEY (id),
		INDEX idx_bot_created (bot_id, created_at),
		INDEX idx_bot_level (bot_id, level)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	app.ensureTable("bot_perm_requests", `CREATE TABLE IF NOT EXISTS bot_perm_requests (
		id INT NOT NULL AUTO_INCREMENT,
		bot_id INT NOT NULL,
		perm_type VARCHAR(50) NOT NULL COMMENT '权限类型：notify, http等',
		reason TEXT NOT NULL COMMENT '申请理由',
		status TINYINT NOT NULL DEFAULT 0 COMMENT '0=待审 1=通过 2=拒绝',
		admin_reply TEXT COMMENT '管理员回复',
		created_at INT NOT NULL,
		handled_at INT NOT NULL DEFAULT 0,
		PRIMARY KEY (id),
		INDEX idx_bot_id (bot_id),
		INDEX idx_status (status)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	app.ensureTable("acr_uploads", `CREATE TABLE IF NOT EXISTS acr_uploads (
		id INT NOT NULL AUTO_INCREMENT,
		dev_id INT NOT NULL COMMENT '上传者open_dev_accounts.id',
		file_name VARCHAR(255) NOT NULL COMMENT 'ACR文件名',
		file_type VARCHAR(10) NOT NULL DEFAULT 'acr' COMMENT 'acr 或 acrg',
		content MEDIUMTEXT NOT NULL COMMENT 'ACR文件内容',
		status TINYINT NOT NULL DEFAULT 0 COMMENT '0=待审 1=通过 2=拒绝',
		admin_note TEXT COMMENT '管理员备注',
		created_at INT NOT NULL,
		reviewed_at INT NOT NULL DEFAULT 0,
		PRIMARY KEY (id),
		INDEX idx_dev_id (dev_id),
		INDEX idx_status (status)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	// v2.2.1: EMA小程序上传审核表
	app.ensureTable("ema_uploads", `CREATE TABLE IF NOT EXISTS ema_uploads (
		id INT NOT NULL AUTO_INCREMENT,
		dev_id INT NOT NULL COMMENT '上传者open_dev_accounts.id',
		file_name VARCHAR(255) NOT NULL COMMENT 'EMA文件名',
		file_path VARCHAR(500) NOT NULL DEFAULT '' COMMENT '本地文件路径',
		file_size INT NOT NULL DEFAULT 0 COMMENT '文件大小(字节)',
		status TINYINT NOT NULL DEFAULT 0 COMMENT '0=待审 1=通过 2=拒绝',
		admin_note TEXT COMMENT '管理员备注',
		created_at INT NOT NULL,
		reviewed_at INT NOT NULL DEFAULT 0,
		PRIMARY KEY (id),
		INDEX idx_dev_id (dev_id),
		INDEX idx_status (status)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	// v2.2.1: AJL库审核表
	app.ensureTable("bot_libs", `CREATE TABLE IF NOT EXISTS bot_libs (
		id INT NOT NULL AUTO_INCREMENT,
		name VARCHAR(100) NOT NULL COMMENT '库名',
		version VARCHAR(50) NOT NULL DEFAULT '1.0.0' COMMENT '版本号',
		content MEDIUMTEXT NOT NULL COMMENT 'JavaScript代码',
		signature VARCHAR(256) NOT NULL DEFAULT '' COMMENT '签名',
		author VARCHAR(100) NOT NULL DEFAULT '' COMMENT '作者',
		`+"`desc`"+` VARCHAR(500) NOT NULL DEFAULT '' COMMENT '描述',
		dev_id INT NOT NULL COMMENT '上传者开发者ID',
		status TINYINT NOT NULL DEFAULT 0 COMMENT '0=待审核 1=已通过 2=已拒绝',
		admin_note TEXT COMMENT '管理员备注',
		created_at INT NOT NULL,
		reviewed_at INT NOT NULL DEFAULT 0,
		PRIMARY KEY (id),
		INDEX idx_dev_id (dev_id),
		INDEX idx_status (status),
		UNIQUE KEY uk_name_version (name, version)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	// 系统通知表（管理员通知、审核结果通知）
	app.ensureTable("chat_user_notice", `CREATE TABLE IF NOT EXISTS chat_user_notice (
		id INT NOT NULL AUTO_INCREMENT,
		uid INT NOT NULL DEFAULT 0 COMMENT '接收者chat_user.id',
		title VARCHAR(255) NOT NULL COMMENT '通知标题',
		content TEXT NOT NULL COMMENT '通知内容',
		link VARCHAR(500) NOT NULL DEFAULT '' COMMENT '链接',
		is_read TINYINT NOT NULL DEFAULT 0 COMMENT '0=未读 1=已读',
		add_time VARCHAR(20) NOT NULL DEFAULT '' COMMENT '添加时间',
		PRIMARY KEY (id),
		INDEX idx_uid_isread (uid, is_read)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)
}

func (app *ACOP) ensureTable(table, ddl string) {
	if _, err := app.db.Exec(ddl); err != nil {
		log.Printf("ACOP: ensure table %s failed: %v", table, err)
	}
}

// ensureColumnAlter 为已有表添加缺失的列
func (app *ACOP) ensureSchemaMigrations() {
	migrations := []struct {
		table string
		col   string
		def   string
	}{
		{"open_dev_accounts", "uid", "INT NOT NULL DEFAULT 0 COMMENT '关联chat_user.id'"},
		{"open_dev_accounts", "allow_ajl_upload", "TINYINT NOT NULL DEFAULT 0 COMMENT '是否允许上传AJL库：0=不允许 1=允许'"},
		{"bot_accounts", "bot_avatar", "VARCHAR(255) DEFAULT '' COMMENT 'Bot头像'"},
		{"bot_accounts", "can_notify", "TINYINT NOT NULL DEFAULT 0 COMMENT '是否允许发送通知'"},
		{"bot_accounts", "can_http", "TINYINT NOT NULL DEFAULT 0 COMMENT '是否允许HTTP请求'"},
		{"bot_accounts", "online", "TINYINT NOT NULL DEFAULT 0 COMMENT '是否在线'"},
		{"bot_accounts", "last_online", "INT NOT NULL DEFAULT 0 COMMENT '最后在线时间戳'"},
		{"chat_user", "email", "VARCHAR(255) NULL DEFAULT NULL"},
		{"chat_user", "add_time", "INT NOT NULL DEFAULT 0"},
		{"chat_user", "avatar", "VARCHAR(255) NOT NULL DEFAULT 'default.png'"},
		{"chat_user", "is_first_login", "TINYINT(1) NOT NULL DEFAULT 0"},
		{"chat_user", "platform", "VARCHAR(100) NOT NULL DEFAULT 'bot'"},
		{"chat_user", "allow_auto_join", "TINYINT(1) NOT NULL DEFAULT 1"},
		{"chat_user", "pat_action", "VARCHAR(32) NOT NULL DEFAULT '拍了拍'"},
		{"chat_user", "hide_conv", "TEXT NOT NULL DEFAULT ''"},
		{"chat_user", "last_active", "INT NOT NULL DEFAULT 0"},
		{"chat_user", "status", "TINYINT(1) NOT NULL DEFAULT 1 COMMENT '1=正常 2=注销冷静期 3=已注销删除'"},
		{"chat_user", "delete_time", "INT NOT NULL DEFAULT 0 COMMENT '注销时间戳'"},
		{"chat_user", "restore_token", "VARCHAR(128) NOT NULL DEFAULT '' COMMENT '找回账号token'"},
		{"chat_user", "restore_token_expires", "INT NOT NULL DEFAULT 0 COMMENT '找回token过期时间戳'"},
		{"chat_user", "ban_until", "INT NOT NULL DEFAULT 0"},
		{"chat_user", "ban_reason", "VARCHAR(255) NOT NULL DEFAULT ''"},
		{"chat_user", "is_bot", "TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否为Bot账号：0=普通用户 1=Bot'"},
		{"acr_uploads", "desc", "TEXT COMMENT 'ACR/ACRG库描述'"},
		{"ema_uploads", "desc", "TEXT COMMENT 'EMA小程序描述'"},
	}
	for _, m := range migrations {
		colExists, _ := app.fetchOne(
			"SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?",
			m.table, m.col,
		)
		if colExists == nil {
			alterSQL := fmt.Sprintf("ALTER TABLE `%s` ADD COLUMN `%s` %s", m.table, m.col, m.def)
			if _, err := app.db.Exec(alterSQL); err != nil {
				log.Printf("ACOP: migration add column %s.%s failed: %v", m.table, m.col, err)
			} else {
				log.Printf("ACOP: migration added column %s.%s", m.table, m.col)
			}
		}
	}
	// 添加唯一索引（如果不存在）
	idxExists, _ := app.fetchOne(
		"SELECT INDEX_NAME FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'open_dev_accounts' AND INDEX_NAME = 'uk_uid'",
	)
	if idxExists == nil {
		if _, err := app.db.Exec("ALTER TABLE `open_dev_accounts` ADD UNIQUE KEY `uk_uid` (`uid`)"); err != nil {
			log.Printf("ACOP: migration add uk_uid failed (non-fatal): %v", err)
		}
	}
}

// ===== 密码处理 =====

func hashPasswordBcrypt(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(bytes), err
}

func checkPasswordBcrypt(password, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}

// hashCsacPassword CsAC主服务器的密码哈希方式: sha256(password + username)
func hashCsacPassword(password, username string) string {
	sum := sha256.Sum256([]byte(password + username))
	return hex.EncodeToString(sum[:])
}

// verifyCsacAccount 验证CsAC主服务器账号，返回 (uid, error)
func (app *ACOP) verifyCsacAccount(username, password string) (int64, error) {
	user, err := app.fetchOne("SELECT id, pwd, ban_until FROM chat_user WHERE username = ?", username)
	if err != nil || user == nil {
		return 0, fmt.Errorf("账号不存在")
	}
	// 检查封禁
	banUntil := intval(user, "ban_until")
	if banUntil > 0 && banUntil > time.Now().Unix() {
		return 0, fmt.Errorf("账号已被封禁")
	}
	// 验证密码
	storedPwd := str(user, "pwd")
	expectedPwd := hashCsacPassword(password, username)
	if storedPwd != expectedPwd {
		return 0, fmt.Errorf("密码错误")
	}
	return intval(user, "id"), nil
}

// ===== Token生成 =====

func generateToken(length int) string {
	buf := make([]byte, length)
	_, _ = rand.Read(buf)
	return fmt.Sprintf("%x", buf)[:length]
}

func generateCode(digits int) string {
	code := ""
	for i := 0; i < digits; i++ {
		n, _ := rand.Int(rand.Reader, big.NewInt(10))
		code += fmt.Sprintf("%d", n)
	}
	return code
}

func (app *ACOP) sendEmail(to, subject, body string) error {
	if !app.config.SMTPEnabled {
		return fmt.Errorf("邮件服务未配置")
	}
	from := app.config.SMTPFrom
	if from == "" {
		from = app.config.SMTPUser
	}
	addr := app.config.SMTPHost + ":" + app.config.SMTPPort

	msg := "From: " + from + "\r\n" +
		"To: " + to + "\r\n" +
		"Subject: " + subject + "\r\n" +
		"Content-Type: text/plain; charset=UTF-8\r\n" +
		"\r\n" + body

	auth := smtp.PlainAuth("", app.config.SMTPUser, app.config.SMTPPass, app.config.SMTPHost)

	// 支持 465(SSL) 和 587(TLS) 两种端口
	if app.config.SMTPPort == "465" {
		return app.sendMailSSL(addr, auth, from, to, []byte(msg))
	}
	return smtp.SendMail(addr, auth, from, []string{to}, []byte(msg))
}

func (app *ACOP) sendMailSSL(addr string, auth smtp.Auth, from, to string, msg []byte) error {
	conn, err := tlsDial(addr)
	if err != nil {
		return err
	}
	defer conn.Close()
	c, err := smtp.NewClient(conn, app.config.SMTPHost)
	if err != nil {
		return err
	}
	defer c.Close()
	if err := c.Auth(auth); err != nil {
		return err
	}
	if err := c.Mail(from); err != nil {
		return err
	}
	if err := c.Rcpt(to); err != nil {
		return err
	}
	w, err := c.Data()
	if err != nil {
		return err
	}
	if _, err := w.Write(msg); err != nil {
		return err
	}
	return w.Close()
}

func tlsDial(addr string) (*tls.Conn, error) {
	host, _, _ := net.SplitHostPort(addr)
	return tls.DialWithDialer(&net.Dialer{Timeout: 10 * time.Second}, "tcp", addr, &tls.Config{ServerName: host})
}

// ===== ServerBot脚本重载通知 =====

// notifyServerBotReload 通知ServerBot重载指定Bot的脚本
func (app *ACOP) notifyServerBotReload(botID int64) {
	if app.config.BotEndpoint == "" {
		return
	}
	go func() {
		url := app.config.BotEndpoint + "/bot/internal/reload_scripts"
		data, _ := json.Marshal(map[string]any{"bot_id": botID})
		req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(data))
		if err != nil {
			log.Printf("ACOP: 创建重载请求失败: %v", err)
			return
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Bot-Secret", app.config.BotSecret)
		client := &http.Client{Timeout: 5 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			log.Printf("ACOP: 通知ServerBot重载失败: %v", err)
			return
		}
		defer resp.Body.Close()
		log.Printf("ACOP: 已通知ServerBot重载Bot[%d]脚本", botID)
	}()
}
