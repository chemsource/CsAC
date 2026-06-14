// Copyright (c) Chemsource Studio. All rights reserved.
// Contact: swcsstudio@126.com

package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

const (
	defaultAdminUID               int64 = 1
	defaultCacheSalt                    = "123456"
	defaultSessionLifetimeSeconds       = 2592000
	defaultLongPollMaxSeconds           = 15
	defaultLongPollSleepMillis          = 350
	defaultMaxImageBytes          int64 = 5242880
	defaultMaxVoiceBytes          int64 = 10485760
	defaultAvatar                       = "default.png"
	registerEmailCodeTTL                = 600
	registerEmailResendSeconds          = 60
	registerEmailMaxAttempts            = 5
	registerEmailMaxSendsPerHour        = 5
)

type Config struct {
	HTTPAddr                             string
	DBHost                               string
	DBUser                               string
	DBPass                               string
	DBName                               string
	AdminUID                             int64
	CacheSalt                            string
	SessionLifetimeSeconds               int64
	LongPollMaxSeconds                   int
	LongPollSleepMillis                  int
	MaxImageBytes                        int64
	MaxVoiceBytes                        int64
	DefaultAvatar                        string
	RequireRegisterEmailVerification     bool
	RequireExistingUserEmailVerification bool
	UploadDir                            string
	PrivateUploadDir                     string
	SessionCookieName                    string
}

type HandlerFunc func(*Ctx)

type App struct {
	db            *sql.DB
	config        Config
	routes        map[string]HandlerFunc
	columnCache   map[string]map[string]bool
	columnCacheMu chan struct{}
}

func main() {
	app, err := NewApp(loadConfig())
	if err != nil {
		log.Fatalf("startup failed: %v", err)
	}

	server := &http.Server{
		Addr:              app.config.HTTPAddr,
		Handler:           app,
		ReadHeaderTimeout: 10 * time.Second,
	}
	log.Printf("CsAC Go backend listening on %s", app.config.HTTPAddr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("server stopped: %v", err)
	}
}

func NewApp(cfg Config) (*App, error) {
	dsn := fmt.Sprintf("%s:%s@tcp(%s)/%s?charset=utf8mb4&parseTime=false&loc=UTC", cfg.DBUser, cfg.DBPass, cfg.DBHost, cfg.DBName)
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(80)
	db.SetMaxIdleConns(20)
	db.SetConnMaxLifetime(5 * time.Minute)
	if err := db.Ping(); err != nil {
		return nil, err
	}

	app := &App{
		db:            db,
		config:        cfg,
		columnCache:   map[string]map[string]bool{},
		columnCacheMu: make(chan struct{}, 1),
	}
	app.columnCacheMu <- struct{}{}
	app.routes = app.buildRoutes()
	app.ensureSchema()
	return app, nil
}

func loadConfig() Config {
	wd, _ := os.Getwd()
	workspaceRoot := filepath.Dir(wd)
	if v := os.Getenv("CSAC_WORKSPACE_ROOT"); v != "" {
		workspaceRoot = v
	}

	return Config{
		HTTPAddr:                             getenv("CSAC_HTTP_ADDR", ":8080"),
		DBHost:                               getenv("CSAC_DB_HOST", "localhost"),
		DBUser:                               getenv("CSAC_DB_USER", "admin"),
		DBPass:                               getenv("CSAC_DB_PASS", "123456"),
		DBName:                               getenv("CSAC_DB_NAME", "csac"),
		AdminUID:                             getenvInt64("CSAC_ADMIN_UID", defaultAdminUID),
		CacheSalt:                            getenv("CSAC_CACHE_SALT", defaultCacheSalt),
		SessionLifetimeSeconds:               getenvInt64("CSAC_SESSION_LIFETIME_SECONDS", defaultSessionLifetimeSeconds),
		LongPollMaxSeconds:                   int(getenvInt64("CSAC_LONG_POLL_MAX_SECONDS", defaultLongPollMaxSeconds)),
		LongPollSleepMillis:                  int(getenvInt64("CSAC_LONG_POLL_SLEEP_MILLIS", defaultLongPollSleepMillis)),
		MaxImageBytes:                        getenvInt64("CSAC_MAX_IMAGE_BYTES", defaultMaxImageBytes),
		MaxVoiceBytes:                        getenvInt64("CSAC_MAX_VOICE_BYTES", defaultMaxVoiceBytes),
		DefaultAvatar:                        getenv("CSAC_DEFAULT_AVATAR", defaultAvatar),
		RequireRegisterEmailVerification:     getenvBool("CSAC_REQUIRE_REGISTER_EMAIL_VERIFICATION", true),
		RequireExistingUserEmailVerification: getenvBool("CSAC_REQUIRE_EXISTING_USER_EMAIL_VERIFICATION", true),
		UploadDir:                            filepath.Clean(getenv("CSAC_UPLOAD_DIR", filepath.Join(workspaceRoot, "upload"))) + string(os.PathSeparator),
		PrivateUploadDir:                     filepath.Clean(getenv("CSAC_PRIVATE_UPLOAD_DIR", filepath.Join(workspaceRoot, "uploads", "chat"))) + string(os.PathSeparator),
		SessionCookieName:                    getenv("CSAC_SESSION_COOKIE_NAME", "PHPSESSID"),
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
		parsed, err := strconv.ParseInt(v, 10, 64)
		if err == nil {
			return parsed
		}
	}
	return fallback
}

func getenvBool(key string, fallback bool) bool {
	if v := os.Getenv(key); v != "" {
		switch strings.ToLower(strings.TrimSpace(v)) {
		case "1", "true", "yes", "on":
			return true
		case "0", "false", "no", "off":
			return false
		}
	}
	return fallback
}

func (a *App) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	a.sendCORSHeaders(w, r)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}

	if isWebSocketRequest(r) && (r.URL.Path == "/ws" || r.URL.Path == "/websocket.php") {
		a.handleWebSocket(w, r)
		return
	}
	if r.URL.Path == "/websocket.php" {
		writeJSONRaw(w, http.StatusUpgradeRequired, map[string]any{
			"success": false,
			"message": "Experimental WebSocket is served by the Go backend. Use WebSocket upgrade on /ws or /websocket.php.",
		})
		return
	}
	if r.URL.Path == "/healthz" {
		writeJSONRaw(w, http.StatusOK, map[string]any{"success": true, "message": "ok"})
		return
	}

	ctx := NewCtx(a, w, r)
	defer func() {
		if rec := recover(); rec != nil {
			log.Printf("panic handling %s: %v", r.URL.String(), rec)
			if !ctx.responded {
				ctx.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "服务器内部错误"})
			}
		}
	}()

	route := ctx.ResolveRoute()
	if route == "" {
		ctx.JSON(http.StatusBadRequest, map[string]any{"success": false, "message": "缺少 route 参数"})
		return
	}
	handler := a.routes[route]
	if handler == nil {
		ctx.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "无效的 route: " + route})
		return
	}
	handler(ctx)
}

func (a *App) sendCORSHeaders(w http.ResponseWriter, r *http.Request) {
	if origin := r.Header.Get("Origin"); origin != "" {
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		w.Header().Set("Vary", "Origin")
	}
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
	allowHeaders := r.Header.Get("Access-Control-Request-Headers")
	if allowHeaders == "" {
		allowHeaders = "Content-Type, Authorization, X-Requested-With, Accept"
	}
	w.Header().Set("Access-Control-Allow-Headers", allowHeaders)
	w.Header().Set("Cache-Control", "no-store")
}

func (a *App) buildRoutes() map[string]HandlerFunc {
	return map[string]HandlerFunc{
		"auth/login":                  apiAuthLogin,
		"auth/send_register_code":     apiAuthSendRegisterCode,
		"auth/send_email_bind_code":   apiAuthSendEmailBindCode,
		"auth/verify_email_bind_code": apiAuthVerifyEmailBindCode,
		"auth/register":               apiAuthRegister,
		"auth/logout":                 apiAuthLogout,
		"user/get_info":               apiUserGetInfo,
		"user/update_profile":         apiUserUpdateProfile,
		"user/upgrade_password":       apiUserUpgradePassword,
		"user/delete_account":         apiUserDeleteAccount,
		"user/get_friends":            apiUserGetFriends,
		"user/get_groups":             apiUserGetGroups,
		"user/get_notifications":      apiUserGetNotifications,
		"user/get_notice_list":        apiUserGetNoticeList,
		"user/mark_notice_read":       apiUserMarkNoticeRead,
		"user/get_created_groups":     apiUserGetCreatedGroups,
		"friend/send_request":         apiFriendSendRequest,
		"friend/handle_request":       apiFriendHandleRequest,
		"friend/delete_friend":        apiFriendDeleteFriend,
		"friend/block_friend":         apiFriendBlockFriend,
		"friend/recover_friend":       apiFriendRecoverFriend,
		"friend/update_remark":        apiFriendUpdateRemark,
		"friend/get_common_groups":    apiFriendGetCommonGroups,
		"friend/get_deleted_notices":  apiFriendGetDeletedNotices,
		"friend/get_friend_requests":  apiFriendGetFriendRequests,
		"message/send_group_msg":      apiMessageSendGroupMsg,
		"message/send_private_msg":    apiMessageSendPrivateMsg,
		"message/send_voice_msg":      apiMessageSendVoiceMsg,
		"message/send_emoji_msg":      apiMessageSendEmojiMsg,
		"emoji/get_list":              apiEmojiGetList,
		"message/send_pat_msg":        apiMessageSendPatMsg,
		"message/pat":                 apiMessageSendPatMsg,
		"message/get_group_msg":       apiMessageGetGroupMsg,
		"message/get_private_msg":     apiMessageGetPrivateMsg,
		"message/recall_msg":          apiMessageRecallMsg,
		"message/mark_read":           apiMessageMarkRead,
		"message/get_mentions":        apiMessageGetMentions,
		"message/poll_updates":        apiMessagePollUpdates,
		"group/create":                apiGroupCreate,
		"group/get_members":           apiGroupGetMembers,
		"group/get_applications":      apiGroupGetApplications,
		"group/apply_join":            apiGroupApplyJoin,
		"group/handle_apply":          apiGroupHandleApply,
		"group/invite_member":         apiGroupInviteMember,
		"group/kick_member":           apiGroupKickMember,
		"group/mute_member":           apiGroupMuteMember,
		"group/set_admin":             apiGroupSetAdmin,
		"group/set_member_title":      apiGroupSetMemberTitle,
		"group/edit_info":             apiGroupEditInfo,
		"group/update_settings":       apiGroupUpdateSettings,
		"group/leave":                 apiGroupLeave,
		"group/disband":               apiGroupDisband,
		"group/transfer":              apiGroupTransfer,
		"group/reset_invite_code":     apiGroupResetInviteCode,
		"group/get_group_view_info":   apiGroupGetGroupViewInfo,
		"group/get_public_list":       apiGroupGetPublicList,
		"group/get_group_msg":         apiMessageGetGroupMsg,
		"essence/set_essence":         apiEssenceSet,
		"essence/get_essence":         apiEssenceGet,
		"essence/get_essence_stats":   apiEssenceStats,
		"report/submit_report":        apiReportSubmit,
		"admin/generate_token":        apiAdminGenerateToken,
		"admin/admin_ban":             apiAdminBan,
		"utils/upload_image":          apiUtilsUploadImage,
		"utils/upload_voice":          apiUtilsUploadVoice,
		"bug_report":                  apiBugReport,
		"test":                        apiTest,
		"utils/session_extend":        apiUtilsSessionExtend,
		"utils/session_reset":         apiUtilsSessionReset,
		"utils/session_info":          apiUtilsSessionInfo,
	}
}
