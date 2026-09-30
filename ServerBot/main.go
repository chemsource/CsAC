// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC ServerBot Framework Version 1.0.0.260614-r1

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
	"sync"
	"time"

	_ "github.com/go-sql-driver/mysql"
	"github.com/gorilla/websocket"
)

const (
	botFrameworkVersion = "1.0.0.260614-r1"
	defaultHTTPAddr     = ":8081"
	defaultWSPath       = "/bot/ws"
	defaultRateLimit    = 5
)

// Config Bot框架配置
type Config struct {
	DBHost         string
	DBUser         string
	DBPass         string
	DBName         string
	HTTPAddr       string
	WSPath         string
	BotSecret      string // 用于内部API鉴权
	RateLimit      int    // 每秒最大操作次数
	AllowTPartyLib bool   // 是否允许导入第三方库（默认关闭）
}

// BotConn 一个已连接的Bot客户端
type BotConn struct {
	BotID     int64
	UID       int64
	DevID     int64
	BotName   string
	CanNotify bool
	CanHTTP   bool
	Conn      *websocket.Conn
	Send      chan []byte
	mu        sync.Mutex
}

// BotFramework 框架主结构
type BotFramework struct {
	db     *sql.DB
	config Config
	// 在线Bot连接池: botID -> *BotConn
	bots   map[int64]*BotConn
	botsMu sync.RWMutex
	// WebSocket升级器
	upgrader websocket.Upgrader
	// 速率限制: botID -> 上次操作时间戳列表
	rateLimit   map[int64][]int64
	rateLimitMu sync.Mutex
	// 脚本管理器
	scriptMgr *ScriptManager
}

func main() {
	cfg := loadConfig()
	fw, err := NewBotFramework(cfg)
	if err != nil {
		log.Fatalf("ServerBot startup failed: %v", err)
	}

	mux := http.NewServeMux()
	// WebSocket端点：Bot连接
	mux.HandleFunc(cfg.WSPath, fw.handleBotWebSocket)
	// HTTP API端点：Bot操作
	mux.HandleFunc("/bot/api/", fw.handleBotAPI)
	// 内部事件推送端点（主服务器调用）
	mux.HandleFunc("/bot/internal/event", fw.handleInternalEvent)
	// 脚本管理端点
	mux.HandleFunc("/bot/internal/reload_scripts", fw.handleReloadScripts)
	mux.HandleFunc("/bot/internal/test_script", fw.handleTestScript)
	// v2.2.1: JSLibs库管理端点
	mux.HandleFunc("/bot/internal/lib/", fw.handleLibAPI)
	// 健康检查
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"success":true,"message":"ok"}`))
	})

	server := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}
	log.Printf("CsAC ServerBot Framework v%s listening on %s", botFrameworkVersion, cfg.HTTPAddr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("ServerBot stopped: %v", err)
	}
}

// NewBotFramework 创建框架实例
func NewBotFramework(cfg Config) (*BotFramework, error) {
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

	fw := &BotFramework{
		db:        db,
		config:    cfg,
		bots:      make(map[int64]*BotConn),
		rateLimit: make(map[int64][]int64),
		upgrader: websocket.Upgrader{
			ReadBufferSize:  4096,
			WriteBufferSize: 4096,
			CheckOrigin:     func(r *http.Request) bool { return true },
		},
	}

	fw.ensureSchema()
	// v2.2.1: 初始化 JSLibs 库管理器
	exePath, _ := os.Executable()
	libDir := filepath.Join(filepath.Dir(exePath), "lib")
	globalLibManager = NewLibManager(fw, libDir, cfg.BotSecret)
	// 初始化脚本管理器
	fw.scriptMgr = NewScriptManager(fw)
	log.Printf("ServerBot: schema ensured, %d bot accounts in database", fw.countBots())
	return fw, nil
}

// loadEnvFile 加载.env文件
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
		} else if strings.HasPrefix(val, "'") && strings.HasSuffix(val, "'") {
			val = val[1 : len(val)-1]
		}
		if os.Getenv(key) == "" {
			os.Setenv(key, val)
		}
	}
}

func loadConfig() Config {
	loadEnvFile()
	return Config{
		DBHost:         getenv("SB_DB_HOST", ""),
		DBUser:         getenv("SB_DB_USER", ""),
		DBPass:         getenv("SB_DB_PASS", ""),
		DBName:         getenv("SB_DB_NAME", ""),
		HTTPAddr:       getenv("SB_HTTP_ADDR", defaultHTTPAddr),
		WSPath:         getenv("SB_WS_PATH", defaultWSPath),
		BotSecret:      getenv("SB_SECRET", "change-me-to-a-random-secret"),
		RateLimit:      int(getenvInt64("SB_RATE_LIMIT_PER_SEC", defaultRateLimit)),
		AllowTPartyLib: getenvBool("SB_ALLOW_TPARTY_LIB", false),
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

// countBots 统计Bot数量
func (fw *BotFramework) countBots() int {
	var count int
	err := fw.db.QueryRow("SELECT COUNT(*) FROM bot_accounts").Scan(&count)
	if err != nil {
		return 0
	}
	return count
}

// RegisterBot 注册Bot到连接池
func (fw *BotFramework) RegisterBot(bot *BotConn) {
	fw.botsMu.Lock()
	defer fw.botsMu.Unlock()
	// 如果该Bot已有旧连接，关闭旧连接
	if old, ok := fw.bots[bot.BotID]; ok {
		close(old.Send)
		old.Conn.Close()
	}
	fw.bots[bot.BotID] = bot
	// 更新在线状态
	_, _ = fw.db.Exec("UPDATE bot_accounts SET online = 1, last_online = ? WHERE id = ?", time.Now().Unix(), bot.BotID)
	log.Printf("ServerBot: Bot [%s] (id=%d, uid=%d) connected", bot.BotName, bot.BotID, bot.UID)
}

// UnregisterBot 从连接池移除Bot
func (fw *BotFramework) UnregisterBot(botID int64) {
	fw.botsMu.Lock()
	defer fw.botsMu.Unlock()
	if bot, ok := fw.bots[botID]; ok {
		close(bot.Send)
		delete(fw.bots, botID)
		_, _ = fw.db.Exec("UPDATE bot_accounts SET online = 0, last_online = ? WHERE id = ?", time.Now().Unix(), botID)
		log.Printf("ServerBot: Bot [%s] (id=%d) disconnected", bot.BotName, botID)
	}
}

// GetBot 获取在线Bot
func (fw *BotFramework) GetBot(botID int64) *BotConn {
	fw.botsMu.RLock()
	defer fw.botsMu.RUnlock()
	return fw.bots[botID]
}

// GetBotByUID 通过聊天用户UID获取在线Bot
func (fw *BotFramework) GetBotByUID(uid int64) *BotConn {
	fw.botsMu.RLock()
	defer fw.botsMu.RUnlock()
	for _, bot := range fw.bots {
		if bot.UID == uid {
			return bot
		}
	}
	return nil
}

// GetAllOnlineBots 获取所有在线Bot
func (fw *BotFramework) GetAllOnlineBots() []*BotConn {
	fw.botsMu.RLock()
	defer fw.botsMu.RUnlock()
	result := make([]*BotConn, 0, len(fw.bots))
	for _, bot := range fw.bots {
		result = append(result, bot)
	}
	return result
}

// SendToBot 向Bot发送JSON消息
func (fw *BotFramework) SendToBot(botID int64, data map[string]any) error {
	bot := fw.GetBot(botID)
	if bot == nil {
		return fmt.Errorf("bot %d not online", botID)
	}
	return bot.SendJSON(data)
}

// SendToBotByUID 通过UID向Bot发送消息
func (fw *BotFramework) SendToBotByUID(uid int64, data map[string]any) error {
	bot := fw.GetBotByUID(uid)
	if bot == nil {
		return fmt.Errorf("bot with uid %d not online", uid)
	}
	return bot.SendJSON(data)
}

// SendJSON 向Bot连接发送JSON
func (bc *BotConn) SendJSON(data map[string]any) error {
	bc.mu.Lock()
	defer bc.mu.Unlock()
	return bc.Conn.WriteJSON(data)
}

// CheckRateLimit 检查速率限制
func (fw *BotFramework) CheckRateLimit(botID int64) bool {
	fw.rateLimitMu.Lock()
	defer fw.rateLimitMu.Unlock()
	now := time.Now().Unix()
	timestamps := fw.rateLimit[botID]
	// 清理1秒前的记录
	valid := make([]int64, 0, len(timestamps))
	for _, t := range timestamps {
		if now-t < 1 {
			valid = append(valid, t)
		}
	}
	if len(valid) >= fw.config.RateLimit {
		fw.rateLimit[botID] = valid
		return false
	}
	valid = append(valid, now)
	fw.rateLimit[botID] = valid
	return true
}
