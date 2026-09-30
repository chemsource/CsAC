// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC eMApps - Lightweight Mini-App Container Server
// Version 1.0.0

package main

import (
	"database/sql"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

const (
	emappsVersion     = "1.0.0"
	defaultHTTPAddr   = ":8090"
	defaultPkgDir     = "./emapps_packages"
	defaultMaxPkgSize = 2 * 1024 * 1024 // 2MB
)

// Config 小程序服务配置
type Config struct {
	HTTPAddr   string
	DBHost     string
	DBUser     string
	DBPass     string
	DBName     string
	PkgDir     string // 包文件存储目录
	MaxPkgSize int64  // 最大包大小
	BotSecret  string
}

func loadConfig() Config {
	cfg := Config{
		HTTPAddr:   getenv("EMAPPS_HTTP_ADDR", defaultHTTPAddr),
		DBHost:     getenv("EMAPPS_DB_HOST", "localhost"),
		DBUser:     getenv("EMAPPS_DB_USER", "root"),
		DBPass:     getenv("EMAPPS_DB_PASS", ""),
		DBName:     getenv("EMAPPS_DB_NAME", "csac"),
		PkgDir:     getenv("EMAPPS_PKG_DIR", defaultPkgDir),
		MaxPkgSize: int64(getenvInt("EMAPPS_MAX_PKG_SIZE", int(defaultMaxPkgSize))),
		BotSecret:  os.Getenv("CSAC_BOT_SECRET"),
	}
	return cfg
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getenvInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	var n int
	for _, c := range v {
		if c >= '0' && c <= '9' {
			n = n*10 + int(c-'0')
		}
	}
	if n == 0 {
		return fallback
	}
	return n
}

func main() {
	cfg := loadConfig()

	// 连接数据库
	dsn := cfg.DBUser + ":" + cfg.DBPass + "@tcp(" + cfg.DBHost + ")/" + cfg.DBName + "?charset=utf8mb4&parseTime=true&loc=Local"
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		log.Fatalf("eMApps: 数据库连接失败: %v", err)
	}
	db.SetMaxOpenConns(5)
	db.SetMaxIdleConns(2)
	db.SetConnMaxLifetime(5 * time.Minute)
	if err := db.Ping(); err != nil {
		log.Fatalf("eMApps: 数据库 Ping 失败: %v", err)
	}
	log.Println("eMApps: 数据库已连接")

	// 创建服务实例
	svc := &eMAppsService{
		cfg: cfg,
		db:  db,
		sig: newSigner(),
	}

	// 初始化签名密钥
	if err := svc.sig.init(); err != nil {
		log.Fatalf("eMApps: 签名密钥初始化失败: %v", err)
	}

	// 确保数据表和目录就绪
	svc.ensureSchema()

	// 路由注册
	mux := http.NewServeMux()
	// 小程序包管理
	mux.HandleFunc("/emapps/api/pkg/", svc.handlePkgAPI)
	// 包文件下载（CDN）
	mux.HandleFunc("/emapps/dl/", svc.handleDownload)
	// 公开目录（无需认证，供客户端浏览）
	mux.HandleFunc("/emapps/public/catalog", svc.handlePublicCatalog)
	// 公钥（无需认证，供客户端验签）
	mux.HandleFunc("/emapps/public/key", svc.handlePublicKey)
	// 小程序详情（无需认证，供客户端打开前获取签名哈希）
	mux.HandleFunc("/emapps/public/info", svc.handlePublicInfo)
	// ACOP审核通过回调（内部接口，X-Bot-Secret鉴权）
	mux.HandleFunc("/emapps/internal/approve", svc.handleInternalApprove)
	// 健康检查
	mux.HandleFunc("/healthz", svc.handleHealth)

	// CORS 跨域配置
	corsOrigin := os.Getenv("EMAPPS_CORS_ORIGIN")
	if corsOrigin == "" {
		corsOrigin = "*"
	}
	log.Printf("eMApps: CORS 允许来源: %s", corsOrigin)

	server := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           corsMiddleware(mux, corsOrigin),
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	log.Printf("eMApps v%s 启动, 监听 %s", emappsVersion, cfg.HTTPAddr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("eMApps 退出: %v", err)
	}
}
