// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC eMApps - HTTP API handlers

package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// handleHealth 健康检查
func (svc *eMAppsService) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"success":true,"service":"emapps","version":"` + emappsVersion + `"}`))
}

// handlePkgAPI 统一包管理入口
// 路由格式: /emapps/api/pkg/{action}
func (svc *eMAppsService) handlePkgAPI(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// 仅允许 POST
	if r.Method != http.MethodPost {
		writeJSONResp(w, http.StatusMethodNotAllowed, errResp("仅支持 POST"))
		return
	}

	// 鉴权：X-Dev-Token（由 ACOP 签发，携带 dev_id）
	devID, ok := svc.authenticate(r)
	if !ok {
		writeJSONResp(w, http.StatusForbidden, errResp("认证失败"))
		return
	}

	// 路由提取: /emapps/api/pkg/{action}
	path := strings.TrimPrefix(r.URL.Path, "/emapps/api/pkg/")
	path = strings.TrimSuffix(path, "/")
	parts := strings.SplitN(path, "/", 2)
	action := parts[0]

	switch action {
	case "upload":
		svc.apiPkgUpload(w, r, devID)
	case "info":
		svc.apiPkgInfo(w, r, devID)
	case "list":
		svc.apiPkgList(w, r, devID)
	case "pubkey":
		svc.apiPubKey(w, r)
	default:
		writeJSONResp(w, http.StatusNotFound, errResp("未知操作: "+action))
	}
}

// handleDownload 包文件下载
// GET /emapps/dl/{appId}
// 客户端验证: 先调 /emapps/api/pkg/info 取哈希+签名，再下载验签
func (svc *eMAppsService) handleDownload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		writeJSONResp(w, http.StatusMethodNotAllowed, errResp("仅支持 GET"))
		return
	}

	// /emapps/dl/{appId}
	appID := strings.TrimPrefix(r.URL.Path, "/emapps/dl/")
	appID = strings.TrimSuffix(appID, "/")
	if appID == "" {
		writeJSONResp(w, http.StatusBadRequest, errResp("缺少 app_id"))
		return
	}

	pkg, err := svc.GetLatest(appID)
	if err != nil || pkg == nil {
		writeJSONResp(w, http.StatusNotFound, errResp("包不存在"))
		return
	}

	data, err := svc.ReadPkg(pkg.AppID, pkg.Version)
	if err != nil {
		writeJSONResp(w, http.StatusNotFound, errResp("包文件读取失败"))
		return
	}

	w.Header().Set("Content-Type", "application/zip")
	w.Header().Set("Content-Length", strconv.Itoa(len(data)))
	w.Header().Set("X-Package-Version", strconv.FormatInt(pkg.Version, 10))
	w.Header().Set("X-Package-Hash", pkg.FileHash)
	w.Header().Set("X-Package-Signature", pkg.Signature)
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s_v%d.zip"`, sanitizeAppID(appID), pkg.Version))
	w.WriteHeader(http.StatusOK)
	w.Write(data)

	log.Printf("eMApps: 下发包 %s v%d (%d bytes)", appID, pkg.Version, len(data))
}

// apiPkgUpload 上传小程序包
// POST /emapps/api/pkg/upload
// Body (multipart): dev_token, app_id, name, desc, pkg_file (ZIP)
func (svc *eMAppsService) apiPkgUpload(w http.ResponseWriter, r *http.Request, devID int64) {
	// 解析 multipart form (max 10MB in memory)
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		writeJSONResp(w, http.StatusBadRequest, errResp("请求体解析失败: "+err.Error()))
		return
	}

	appID := strings.TrimSpace(r.FormValue("app_id"))
	name := strings.TrimSpace(r.FormValue("name"))
	desc := strings.TrimSpace(r.FormValue("desc"))

	if appID == "" || name == "" {
		writeJSONResp(w, http.StatusBadRequest, errResp("app_id 和 name 不能为空"))
		return
	}
	if !isValidAppID(appID) {
		writeJSONResp(w, http.StatusBadRequest, errResp("app_id 格式无效（需以字母开头，仅允许字母数字下划线）"))
		return
	}

	// 读取包文件
	file, _, err := r.FormFile("pkg_file")
	if err != nil {
		writeJSONResp(w, http.StatusBadRequest, errResp("缺少 pkg_file"))
		return
	}
	defer file.Close()

	pkgData, err := io.ReadAll(io.LimitReader(file, svc.cfg.MaxPkgSize+1))
	if err != nil {
		writeJSONResp(w, http.StatusInternalServerError, errResp("读取文件失败"))
		return
	}

	pkg, err := svc.SavePkg(appID, name, desc, devID, pkgData)
	if err != nil {
		writeJSONResp(w, http.StatusBadRequest, errResp(err.Error()))
		return
	}

	writeJSONResp(w, http.StatusOK, map[string]any{
		"success": true,
		"message": "上传成功",
		"data": map[string]any{
			"id":           pkg.ID,
			"app_id":       pkg.AppID,
			"version":      pkg.Version,
			"package_size": pkg.PackageSize,
			"file_hash":    pkg.FileHash,
			"signature":    pkg.Signature,
		},
	})
}

// apiPkgInfo 查询小程​​序最新版本信息（不含包体）
// POST /emapps/api/pkg/info
// Body: { "app_id": "demo" }
func (svc *eMAppsService) apiPkgInfo(w http.ResponseWriter, r *http.Request, devID int64) {
	var req struct {
		AppID string `json:"app_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONResp(w, http.StatusBadRequest, errResp("参数解析失败"))
		return
	}

	pkg, err := svc.GetLatest(req.AppID)
	if err != nil {
		writeJSONResp(w, http.StatusInternalServerError, errResp("查询失败"))
		return
	}
	if pkg == nil {
		writeJSONResp(w, http.StatusNotFound, errResp("包不存在"))
		return
	}

	writeJSONResp(w, http.StatusOK, map[string]any{
		"success": true,
		"data": map[string]any{
			"app_id":       pkg.AppID,
			"name":         pkg.Name,
			"version":      pkg.Version,
			"package_size": pkg.PackageSize,
			"file_hash":    pkg.FileHash,
			"signature":    pkg.Signature,
			"entry_page":   pkg.EntryPage,
			"download_url": fmt.Sprintf("/emapps/dl/%s", pkg.AppID),
		},
	})
}

// handlePublicInfo 获取小程序详情（无需认证，供客户端下载前调用）
// POST /emapps/public/info
// Body: {"app_id": "xxx"}
func (svc *eMAppsService) handlePublicInfo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		AppID string `json:"app_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"success": false, "message": "参数解析失败"})
		return
	}
	pkg, err := svc.GetLatest(req.AppID)
	if err != nil || pkg == nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"success": false, "message": "包不存在"})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"success": true,
		"data": map[string]any{
			"app_id":       pkg.AppID,
			"name":         pkg.Name,
			"version":      pkg.Version,
			"package_size": pkg.PackageSize,
			"file_hash":    pkg.FileHash,
			"signature":    pkg.Signature,
			"entry_page":   pkg.EntryPage,
			"download_url": fmt.Sprintf("/emapps/dl/%s", pkg.AppID),
		},
	})
}

// apiPkgList 列出开发者的所有小程序包
// POST /emapps/api/pkg/list
func (svc *eMAppsService) apiPkgList(w http.ResponseWriter, r *http.Request, devID int64) {
	list, err := svc.ListByDev(devID)
	if err != nil {
		writeJSONResp(w, http.StatusInternalServerError, errResp("查询失败"))
		return
	}
	if list == nil {
		list = []*eMAppPackage{}
	}

	items := make([]map[string]any, 0, len(list))
	for _, p := range list {
		items = append(items, map[string]any{
			"id":           p.ID,
			"app_id":       p.AppID,
			"name":         p.Name,
			"version":      p.Version,
			"package_size": p.PackageSize,
			"file_hash":    p.FileHash,
			"download_url": fmt.Sprintf("/emapps/dl/%s", p.AppID),
		})
	}

	writeJSONResp(w, http.StatusOK, map[string]any{
		"success": true,
		"data":    items,
	})
}

// apiPubKey 获取验签公钥（供客户端和 IDE 工具读取）
// POST /emapps/api/pkg/pubkey
func (svc *eMAppsService) apiPubKey(w http.ResponseWriter, r *http.Request) {
	pubJSON, err := svc.sig.PublicKeyJSON()
	if err != nil {
		writeJSONResp(w, http.StatusInternalServerError, errResp("获取公钥失败"))
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(pubJSON)
}

// authenticate 鉴权：从 X-Dev-Token 头提取 dev_id
// 实际部署时由 acop 通过内部 proxy 转发，这里做轻量校验
func (svc *eMAppsService) authenticate(r *http.Request) (int64, bool) {
	token := r.Header.Get("X-Dev-Token")
	if token == "" {
		return 0, false
	}
	// 格式: "dev:{dev_id}:{hmac}" —— ACOP 签发
	parts := strings.SplitN(token, ":", 3)
	if len(parts) != 3 || parts[0] != "dev" {
		return 0, false
	}
	devID, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil || devID <= 0 {
		return 0, false
	}
	// TODO: 通过 HMAC 验证 token 真实性
	return devID, true
}

// ---- CORS 中间件 ----

// corsMiddleware 为所有响应添加跨域头，并处理预检 OPTIONS 请求
// allowedOrigin 可通过环境变量 EMAPPS_CORS_ORIGIN 配置，默认 "*"
func corsMiddleware(inner http.Handler, allowedOrigin string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", allowedOrigin)
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Dev-Token, X-Bot-Secret")
		w.Header().Set("Access-Control-Max-Age", "86400")

		// 预检请求直接返回 204
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		inner.ServeHTTP(w, r)
	})
}

// ---- 工具函数 ----

func errResp(msg string) map[string]any {
	return map[string]any{"success": false, "message": msg}
}

func writeJSONResp(w http.ResponseWriter, statusCode int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(v)
}

func isValidAppID(s string) bool {
	if len(s) < 1 || len(s) > 64 {
		return false
	}
	if !((s[0] >= 'a' && s[0] <= 'z') || (s[0] >= 'A' && s[0] <= 'Z')) {
		return false
	}
	for _, c := range s {
		if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-') {
			return false
		}
	}
	return true
}

// handlePublicCatalog 公开小程序目录（无需认证）
// GET /emapps/public/catalog?kw=搜索词
func (svc *eMAppsService) handlePublicCatalog(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	kw := r.URL.Query().Get("kw")
	list, err := svc.ListPublicCatalog(kw)
	if err != nil {
		writeJSONResp(w, http.StatusInternalServerError, errResp("查询失败"))
		return
	}
	if list == nil {
		list = []*eMAppPackage{}
	}
	items := make([]map[string]any, 0, len(list))
	for _, p := range list {
		items = append(items, map[string]any{
			"app_id":       p.AppID,
			"name":         p.Name,
			"version":      p.Version,
			"desc":         p.Desc,
			"package_size": p.PackageSize,
			"entry_page":   p.EntryPage,
			"download_url": fmt.Sprintf("/emapps/dl/%s", p.AppID),
		})
	}
	json.NewEncoder(w).Encode(map[string]any{"success": true, "data": items})
}

// handlePublicKey 获取验签公钥（无需认证，供客户端下载）
// GET /emapps/public/key
func (svc *eMAppsService) handlePublicKey(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	pubJSON, err := svc.sig.PublicKeyJSON()
	if err != nil {
		http.Error(w, "获取公钥失败", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(pubJSON)
}

// handleInternalApprove ACOP审核通过后回调：签名保存EMA文件
// 鉴权：X-Bot-Secret 头
// Body: JSON { "file_name": "xxx.ema", "content": "ema JSON", "source_id": "acop_123" }
func (svc *eMAppsService) handleInternalApprove(w http.ResponseWriter, r *http.Request) {
	log.Printf("[DIAG] eMApps handleInternalApprove 收到请求 method=%s", r.Method)
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	// 鉴权
	gotSecret := r.Header.Get("X-Bot-Secret")
	log.Printf("[DIAG] eMApps handleInternalApprove 鉴权: wantLen=%d gotLen=%d", len(svc.cfg.BotSecret), len(gotSecret))
	if svc.cfg.BotSecret != "" && gotSecret != svc.cfg.BotSecret {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusForbidden)
		json.NewEncoder(w).Encode(map[string]any{"success": false, "message": "unauthorized"})
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 10<<20)) // 10MB limit
	log.Printf("[DIAG] eMApps handleInternalApprove 读取body: %d bytes err=%v", len(body), err)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"success": false, "message": "read body failed"})
		return
	}
	var req struct {
		FileName string `json:"file_name"`
		Content  string `json:"content"`
		SourceID string `json:"source_id"`
	}
	if err := json.Unmarshal(body, &req); err != nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"success": false, "message": "invalid json"})
		return
	}

	// 解析EMA内容获取appId
	var ema struct {
		AppID   string `json:"appId"`
		Version string `json:"version"`
		Name    string `json:"name"`
		Desc    string `json:"desc"`
	}
	emaErr := json.Unmarshal([]byte(req.Content), &ema)
	emaPreview := req.Content
	if len(emaPreview) > 200 {
		emaPreview = emaPreview[:200] + "..."
	}
	log.Printf("[DIAG] eMApps EMA解析: err=%v appId=%q name=%q version=%q preview=%s",
		emaErr, ema.AppID, ema.Name, ema.Version, emaPreview)
	if emaErr != nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"success": false, "message": "invalid EMA: parse error"})
		return
	}
	if ema.AppID == "" {
		// 兜底：从文件名推导 appId（去掉 .ema 后缀）
		ema.AppID = strings.TrimSuffix(req.FileName, ".ema")
		if ema.AppID == "" || ema.AppID == req.FileName {
			ema.AppID = "miniapp_" + req.SourceID
		}
		log.Printf("[DIAG] eMApps EMA appId为空，从文件名推导: %s", ema.AppID)
	}
	appID := ema.AppID
	if len(appID) == 0 || len(appID) > 64 {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"success": false, "message": "invalid appId"})
		return
	}
	if ema.Version == "" {
		ema.Version = "1.0.0"
	}
	if ema.Name == "" {
		ema.Name = appID
	}

	// version 表中是 INT 自增，此处用时间戳推导（保证唯一递增）
	// 获取当前最大版本 + 1
	var maxVer int64
	svc.db.QueryRow("SELECT COALESCE(MAX(version), 0) FROM emapps_packages WHERE app_id = ?", appID).Scan(&maxVer)
	newVersion := maxVer + 1

	// 计算哈希 + 签名
	contentBytes := []byte(req.Content)
	fileHash := computeHash(contentBytes)
	_, signature, err := svc.sig.SignPkg(contentBytes)
	if err != nil {
		log.Printf("eMApps: 签名失败: %v", err)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"success": false, "message": "sign failed"})
		return
	}

	// 保存文件: 使用与 SavePkg 一致的路径 pkgDir/sanitizeAppID/appID_v{version}.ema
	pkgPath := filepath.Join(svc.cfg.PkgDir, sanitizeAppID(appID), fmt.Sprintf("%s_v%d.ema", sanitizeAppID(appID), newVersion))
	log.Printf("[DIAG] eMApps approve 准备写入: %s (%d bytes)", pkgPath, len(contentBytes))
	if err := os.MkdirAll(filepath.Dir(pkgPath), 0755); err != nil {
		log.Printf("eMApps: 创建目录失败: %v", err)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"success": false, "message": "mkdir failed"})
		return
	}
	if err := os.WriteFile(pkgPath, contentBytes, 0644); err != nil {
		log.Printf("eMApps: 保存EMA文件失败: %v", err)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"success": false, "message": "write file failed"})
		return
	}

	// 数据库：写入完整记录
	now := time.Now().Unix()
	_, err = svc.db.Exec(
		"INSERT INTO emapps_packages (app_id, name, version, dev_id, package_size, file_hash, signature, entry_page, `desc`, source_id, created_at) VALUES (?, ?, ?, 0, ?, ?, ?, 'index.html', ?, ?, ?)",
		appID, ema.Name, newVersion, len(contentBytes), fileHash, signature, ema.Desc, req.SourceID, now,
	)
	if err != nil {
		log.Printf("eMApps: 写入数据库失败: %v", err)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"success": false, "message": "db insert failed"})
		return
	}

	log.Printf("eMApps: EMA %s v%d 签名完成 path=%s hash=%s", appID, newVersion, pkgPath, fileHash[:16])

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"success":   true,
		"app_id":    appID,
		"version":   ema.Version,
		"file_hash": fileHash,
		"signature": signature,
	})
}
