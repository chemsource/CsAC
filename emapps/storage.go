// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC eMApps - Package storage & DB schema

package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// eMAppPackage 数据库记录模型
type eMAppPackage struct {
	ID          int64  `json:"id"`
	AppID       string `json:"app_id"`       // 小程序唯一标识
	Name        string `json:"name"`         // 显示名称
	Version     int64  `json:"version"`      // 版本号（递增整数）
	Desc        string `json:"desc"`         // 描述
	DevID       int64  `json:"dev_id"`       // 开发者ID
	PackageSize int64  `json:"package_size"` // 包大小（字节）
	FileHash    string `json:"file_hash"`    // SHA-256 hex
	Signature   string `json:"signature"`    // RSA base64 签名
	EntryPage   string `json:"entry_page"`   // 入口页面（默认 index.html）
	CreatedAt   int64  `json:"created_at"`
}

// eMAppsService 主服务
type eMAppsService struct {
	cfg Config
	db  *sql.DB
	sig *signer
}

// ensureSchema 确保数据库表和目录
func (svc *eMAppsService) ensureSchema() {
	// 小程序包表
	if _, err := svc.db.Exec(`CREATE TABLE IF NOT EXISTS emapps_packages (
		id INT NOT NULL AUTO_INCREMENT,
		app_id VARCHAR(64) NOT NULL COMMENT '小程序唯一标识',
		name VARCHAR(100) NOT NULL COMMENT '显示名称',
		version INT NOT NULL DEFAULT 1 COMMENT '版本号',
		dev_id INT NOT NULL COMMENT '开发者ID',
		package_size INT NOT NULL DEFAULT 0 COMMENT '包大小(字节)',
		file_hash VARCHAR(64) NOT NULL DEFAULT '' COMMENT 'SHA-256',
		signature TEXT NOT NULL COMMENT 'RSA签名',
		entry_page VARCHAR(100) NOT NULL DEFAULT 'index.html' COMMENT '入口页面',
		` + "`desc`" + ` VARCHAR(500) NOT NULL DEFAULT '' COMMENT '描述',
		created_at INT NOT NULL,
		PRIMARY KEY (id),
		UNIQUE KEY uk_app_version (app_id, version),
		INDEX idx_app_id (app_id),
		INDEX idx_dev_id (dev_id)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`); err != nil {
		log.Printf("eMApps: 建表失败: %v", err)
	}
	// 迁移：source_id字段（ACOP审核来源ID）
	svc.db.Exec("ALTER TABLE emapps_packages ADD COLUMN IF NOT EXISTS source_id VARCHAR(64) NOT NULL DEFAULT '' AFTER signature")

	// 确保包存储目录
	if err := os.MkdirAll(svc.cfg.PkgDir, 0755); err != nil {
		log.Printf("eMApps: 创建包目录失败: %v", err)
	}
}

// SavePkg 保存小程序包（ZIP），生成签名
func (svc *eMAppsService) SavePkg(appID, name, desc string, devID int64, pkgData []byte) (*eMAppPackage, error) {
	// 校验ZIP格式
	if err := validateZip(pkgData); err != nil {
		return nil, fmt.Errorf("包校验失败: %w", err)
	}

	// 大小检查
	if int64(len(pkgData)) > svc.cfg.MaxPkgSize {
		return nil, fmt.Errorf("包大小 %d 超过限制 %d", len(pkgData), svc.cfg.MaxPkgSize)
	}

	// 签名
	hashHex, sigB64, err := svc.sig.SignPkg(pkgData)
	if err != nil {
		return nil, fmt.Errorf("签名失败: %w", err)
	}

	// 查询当前最大版本号
	var maxVer int64
	svc.db.QueryRow("SELECT COALESCE(MAX(version), 0) FROM emapps_packages WHERE app_id = ?", appID).Scan(&maxVer)
	newVer := maxVer + 1

	// 写入磁盘: pkgDir/appID/appID_v{version}.zip
	pkgPath := svc.pkgFilePath(appID, newVer)
	if err := os.MkdirAll(filepath.Dir(pkgPath), 0755); err != nil {
		return nil, fmt.Errorf("创建目录失败: %w", err)
	}
	if err := os.WriteFile(pkgPath, pkgData, 0644); err != nil {
		return nil, fmt.Errorf("写包文件失败: %w", err)
	}

	now := time.Now().Unix()
	result, err := svc.db.Exec(
		`INSERT INTO emapps_packages (app_id, name, version, dev_id, package_size, file_hash, signature, entry_page, `+"`desc`"+`, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, 'index.html', ?, ?)`,
		appID, name, newVer, devID, len(pkgData), hashHex, sigB64, desc, now,
	)
	if err != nil {
		os.Remove(pkgPath) // 回滚磁盘
		return nil, fmt.Errorf("数据库写入失败: %w", err)
	}

	id, _ := result.LastInsertId()
	log.Printf("eMApps: 保存包 %s v%d (id=%d, %d bytes)", appID, newVer, id, len(pkgData))

	return &eMAppPackage{
		ID:          id,
		AppID:       appID,
		Name:        name,
		Version:     newVer,
		Desc:        desc,
		DevID:       devID,
		PackageSize: int64(len(pkgData)),
		FileHash:    hashHex,
		Signature:   sigB64,
		EntryPage:   "index.html",
		CreatedAt:   now,
	}, nil
}

// GetLatest 获取最新版本信息（不含包体——客户端先查版本再决定是否下载）
func (svc *eMAppsService) GetLatest(appID string) (*eMAppPackage, error) {
	row := svc.db.QueryRow(
		`SELECT id, app_id, name, version, package_size, file_hash, signature, entry_page
		 FROM emapps_packages WHERE app_id = ? ORDER BY version DESC LIMIT 1`, appID,
	)
	var pkg eMAppPackage
	err := row.Scan(&pkg.ID, &pkg.AppID, &pkg.Name, &pkg.Version, &pkg.PackageSize, &pkg.FileHash, &pkg.Signature, &pkg.EntryPage)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &pkg, nil
}

// ReadPkg 读取包文件内容
func (svc *eMAppsService) ReadPkg(appID string, version int64) ([]byte, error) {
	data, err := os.ReadFile(svc.pkgFilePath(appID, version))
	if err == nil {
		return data, nil
	}
	// 兼容 ACOP 审核回调写入的 .ema 文件
	emaPath := filepath.Join(svc.cfg.PkgDir, sanitizeAppID(appID), fmt.Sprintf("%s_v%d.ema", sanitizeAppID(appID), version))
	return os.ReadFile(emaPath)
}

// ReadPkgByID 根据数据库ID读取包文件
func (svc *eMAppsService) ReadPkgByID(id int64) ([]byte, *eMAppPackage, error) {
	row := svc.db.QueryRow(
		`SELECT id, app_id, name, version, package_size, file_hash, signature FROM emapps_packages WHERE id = ?`, id,
	)
	var pkg eMAppPackage
	if err := row.Scan(&pkg.ID, &pkg.AppID, &pkg.Name, &pkg.Version, &pkg.PackageSize, &pkg.FileHash, &pkg.Signature); err != nil {
		return nil, nil, fmt.Errorf("包记录不存在: %w", err)
	}
	data, err := os.ReadFile(svc.pkgFilePath(pkg.AppID, pkg.Version))
	if err != nil {
		return nil, nil, err
	}
	return data, &pkg, nil
}

// ListByDev 按开发者列出所有小程序包
func (svc *eMAppsService) ListByDev(devID int64) ([]*eMAppPackage, error) {
	rows, err := svc.db.Query(
		`SELECT id, app_id, name, version, package_size, file_hash, created_at
		 FROM emapps_packages WHERE dev_id = ? ORDER BY created_at DESC`,
		devID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var list []*eMAppPackage
	for rows.Next() {
		var p eMAppPackage
		if err := rows.Scan(&p.ID, &p.AppID, &p.Name, &p.Version, &p.PackageSize, &p.FileHash, &p.CreatedAt); err != nil {
			continue
		}
		p.DevID = devID
		list = append(list, &p)
	}
	return list, nil
}

// ListPublicCatalog 公开目录：返回所有已发布小程序的列表（按 app_id 去重取最新版本）
// 支持可选搜索关键词（匹配 name 或 app_id）
func (svc *eMAppsService) ListPublicCatalog(keyword string) ([]*eMAppPackage, error) {
	baseSQL := `SELECT e.id, e.app_id, e.name, e.version, e.package_size, e.file_hash, e.signature, e.entry_page, e.desc, e.created_at
		FROM emapps_packages e
		INNER JOIN (
			SELECT app_id, MAX(version) AS max_ver FROM emapps_packages GROUP BY app_id
		) latest ON e.app_id = latest.app_id AND e.version = latest.max_ver`
	var rows *sql.Rows
	var err error
	if keyword != "" {
		rows, err = svc.db.Query(baseSQL+` WHERE e.name LIKE ? OR e.app_id LIKE ? OR e.desc LIKE ? ORDER BY e.created_at DESC`, "%"+keyword+"%", "%"+keyword+"%", "%"+keyword+"%")
	} else {
		rows, err = svc.db.Query(baseSQL + ` ORDER BY e.created_at DESC`)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var list []*eMAppPackage
	for rows.Next() {
		var p eMAppPackage
		if err := rows.Scan(&p.ID, &p.AppID, &p.Name, &p.Version, &p.PackageSize, &p.FileHash, &p.Signature, &p.EntryPage, &p.Desc, &p.CreatedAt); err != nil {
			continue
		}
		list = append(list, &p)
	}
	return list, nil
}

// pkgFilePath 包文件路径: pkgDir/appID_v{version}.zip
func (svc *eMAppsService) pkgFilePath(appID string, version int64) string {
	fname := fmt.Sprintf("%s_v%d.zip", sanitizeAppID(appID), version)
	return filepath.Join(svc.cfg.PkgDir, sanitizeAppID(appID), fname)
}

// GetPublicKey 返回签名公钥（JSON）
func (svc *eMAppsService) GetPublicKey() ([]byte, error) {
	return svc.sig.PublicKeyJSON()
}

// ---- 工具函数 ----

// validateZip 校验是否为有效 ZIP
func validateZip(data []byte) error {
	r, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return fmt.Errorf("无效的 ZIP 包: %w", err)
	}
	// 必须有页面文件
	hasHTML := false
	for _, f := range r.File {
		if strings.HasSuffix(strings.ToLower(f.Name), ".html") {
			hasHTML = true
			break
		}
	}
	if !hasHTML {
		return fmt.Errorf("包中缺少 HTML 页面文件")
	}
	return nil
}

// sanitizeAppID 清理 appID 用于文件路径
func sanitizeAppID(s string) string {
	result := strings.Builder{}
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
			result.WriteRune(r)
		}
	}
	if result.Len() == 0 {
		return "unknown"
	}
	return result.String()
}

// computeHash 计算 SHA-256
func computeHash(data []byte) string {
	h := sha256.Sum256(data)
	return fmt.Sprintf("%x", h)
}

// writeJSON 统一 JSON 响应
func writeJSON(w io.Writer, statusCode int, v any) {
	data, _ := json.Marshal(v)
	if rw, ok := w.(interface {
		Header() httpHeader
		WriteHeader(int)
	}); ok {
		rw.Header().Set("Content-Type", "application/json")
		rw.WriteHeader(statusCode)
	}
	w.Write(data)
}

type httpHeader interface {
	Set(string, string)
}
