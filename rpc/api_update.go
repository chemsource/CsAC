// Copyright (c) Chemsource Studio. All rights reserved.
// Backend Version 2.2.0.260615-r2

package main

import (
	"archive/zip"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	csacCurrentVersion = "2.2.0.260615-r2"
	githubRepo         = "Leonmmcoset/csac-terminal"
	githubReleasesURL  = "https://api.github.com/repos/" + githubRepo + "/releases/latest"
)

// UpdateInfo 表示一个可用的更新
type UpdateInfo struct {
	Version      string            `json:"version"`
	Current      string            `json:"current"`
	ReleaseName  string            `json:"release_name"`
	ReleaseNotes string            `json:"release_notes"`
	PublishedAt  string            `json:"published_at"`
	Assets       map[string]string `json:"assets"` // platform -> download_url
	HasUpdate    bool              `json:"has_update"`
}

// updateState 管理自动更新的状态
type updateState struct {
	mu               sync.Mutex
	lastCheck        time.Time
	cachedInfo       *UpdateInfo
	checking         bool
	downloading      bool
	installedVersion string // 已安装的web版本号，避免重复解压
}

var globalUpdateState = &updateState{}

// apiUpdateCheck 前端检查是否有可用更新
func apiUpdateCheck(c *Ctx) {
	info, err := checkForUpdate()
	if err != nil {
		c.JSON(http.StatusOK, map[string]any{
			"success":         true,
			"auto_update":     c.app.config.AutoUpdate,
			"has_update":      false,
			"current_version": csacCurrentVersion,
			"message":         "检查更新失败: " + err.Error(),
		})
		return
	}
	c.JSON(http.StatusOK, map[string]any{
		"success":         true,
		"auto_update":     c.app.config.AutoUpdate,
		"has_update":      info.HasUpdate,
		"current_version": csacCurrentVersion,
		"latest_version":  info.Version,
		"release_name":    info.ReleaseName,
		"release_notes":   info.ReleaseNotes,
		"published_at":    info.PublishedAt,
		"assets":          info.Assets,
	})
}

// apiUpdateDownload 前端请求下载指定平台的更新包
func apiUpdateDownload(c *Ctx) {
	if !c.app.config.AutoUpdate {
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "自动更新未启用"})
		return
	}
	platform, _ := c.input["platform"].(string)
	if platform == "" {
		c.JSON(http.StatusBadRequest, map[string]any{"success": false, "message": "缺少 platform 参数"})
		return
	}
	info, err := checkForUpdate()
	if err != nil || !info.HasUpdate {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "没有可用更新"})
		return
	}
	url, ok := info.Assets[platform]
	if !ok || url == "" {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "找不到该平台的更新包"})
		return
	}
	// 下载到 update 目录
	updateDir := c.app.config.UpdateDir
	if err := os.MkdirAll(updateDir, 0755); err != nil {
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "创建更新目录失败"})
		return
	}
	filename := filepath.Base(url)
	destPath := filepath.Join(updateDir, filename)
	if _, err := os.Stat(destPath); err == nil {
		// 已下载过
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "更新包已存在", "path": destPath})
		return
	}
	if err := downloadFile(url, destPath); err != nil {
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "下载失败: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "下载完成", "path": destPath})
}

// checkForUpdate 检查GitHub是否有新版本（带缓存，5分钟内不重复请求）
func checkForUpdate() (*UpdateInfo, error) {
	globalUpdateState.mu.Lock()
	if globalUpdateState.cachedInfo != nil && time.Since(globalUpdateState.lastCheck) < 5*time.Minute {
		info := globalUpdateState.cachedInfo
		globalUpdateState.mu.Unlock()
		return info, nil
	}
	if globalUpdateState.checking {
		globalUpdateState.mu.Unlock()
		// 另一个goroutine正在检查，返回缓存或空结果
		if globalUpdateState.cachedInfo != nil {
			return globalUpdateState.cachedInfo, nil
		}
		return &UpdateInfo{Current: csacCurrentVersion, HasUpdate: false}, nil
	}
	globalUpdateState.checking = true
	globalUpdateState.mu.Unlock()

	info, err := fetchLatestRelease()
	if err != nil {
		globalUpdateState.mu.Lock()
		globalUpdateState.checking = false
		globalUpdateState.mu.Unlock()
		return nil, err
	}

	globalUpdateState.mu.Lock()
	globalUpdateState.cachedInfo = info
	globalUpdateState.lastCheck = time.Now()
	globalUpdateState.checking = false
	globalUpdateState.mu.Unlock()
	return info, nil
}

// fetchLatestRelease 从GitHub API获取最新release
func fetchLatestRelease() (*UpdateInfo, error) {
	client := &http.Client{Timeout: 15 * time.Second}
	req, err := http.NewRequest("GET", githubReleasesURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "CsAC-Backend-Update-Checker")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("GitHub API returned HTTP %d", resp.StatusCode)
	}

	var release map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return nil, err
	}

	tagName, _ := release["tag_name"].(string)
	releaseName, _ := release["name"].(string)
	body, _ := release["body"].(string)
	publishedAt, _ := release["published_at"].(string)

	if tagName == "" {
		tagName = releaseName
	}

	latestVersion := normalizeVersion(tagName)
	currentVersion := normalizeVersion(csacCurrentVersion)
	hasUpdate := compareVersions(currentVersion, latestVersion) < 0

	// 解析assets
	assets := map[string]string{}
	if rawAssets, ok := release["assets"].([]any); ok {
		for _, a := range rawAssets {
			asset, ok := a.(map[string]any)
			if !ok {
				continue
			}
			name, _ := asset["name"].(string)
			url, _ := asset["browser_download_url"].(string)
			if name == "" || url == "" {
				continue
			}
			platform := assetNameToPlatform(name)
			if platform != "" {
				assets[platform] = url
			}
		}
	}

	return &UpdateInfo{
		Version:      latestVersion,
		Current:      csacCurrentVersion,
		ReleaseName:  releaseName,
		ReleaseNotes: body,
		PublishedAt:  publishedAt,
		Assets:       assets,
		HasUpdate:    hasUpdate,
	}, nil
}

// assetNameToPlatform 从文件名推断平台标识
func assetNameToPlatform(name string) string {
	n := strings.ToLower(name)
	if strings.Contains(n, "web") || strings.HasSuffix(n, ".zip") && strings.Contains(n, "web") {
		return "web"
	}
	if strings.Contains(n, "android") || strings.HasSuffix(n, ".apk") {
		return "android"
	}
	if strings.Contains(n, "windows") || strings.HasSuffix(n, ".exe") || strings.HasSuffix(n, ".msix") {
		return "windows"
	}
	if strings.Contains(n, "linux") && (strings.HasSuffix(n, ".deb") || strings.HasSuffix(n, ".appimage") || strings.Contains(n, "linux")) {
		return "linux"
	}
	if strings.Contains(n, "ios") || strings.HasSuffix(n, ".ipa") {
		return "ios"
	}
	if strings.Contains(n, "macos") || strings.Contains(n, "darwin") || strings.HasSuffix(n, ".dmg") {
		return "macos"
	}
	if strings.Contains(n, "rpc_server") || strings.Contains(n, "server") {
		if strings.Contains(n, "linux") {
			return "server-linux"
		}
		if strings.Contains(n, "windows") {
			return "server-windows"
		}
		if strings.Contains(n, "darwin") || strings.Contains(n, "macos") {
			return "server-macos"
		}
		return "server"
	}
	if strings.Contains(n, "serverbot") || strings.Contains(n, "bot") {
		if strings.Contains(n, "linux") {
			return "bot-linux"
		}
		return "bot"
	}
	if strings.Contains(n, "acop_server") || strings.Contains(n, "acop") {
		if strings.Contains(n, "linux") {
			return "acop-server-linux"
		}
		return "acop-server"
	}
	return ""
}

// normalizeVersion 将版本号规范化为可比较的格式
func normalizeVersion(v string) string {
	s := strings.TrimSpace(v)
	s = strings.TrimPrefix(s, "v")
	s = strings.TrimPrefix(s, "V")
	// 去掉 refs/tags/ 前缀
	if idx := strings.LastIndex(s, "/"); idx >= 0 {
		s = s[idx+1:]
	}
	return s
}

// compareVersions 比较两个版本号，返回 -1, 0, 1
// 支持格式: 2.2.0.260615-r2 → 将 -r2 作为预发布版本号参与比较
func compareVersions(a, b string) int {
	// 分离预发布标识 (如 -r2, -beta1)
	splitPre := func(v string) (string, string) {
		if idx := strings.Index(v, "-"); idx >= 0 {
			return v[:idx], v[idx+1:]
		}
		return v, ""
	}
	aMain, aPre := splitPre(a)
	bMain, bPre := splitPre(b)

	partsA := strings.Split(aMain, ".")
	partsB := strings.Split(bMain, ".")
	maxLen := len(partsA)
	if len(partsB) > maxLen {
		maxLen = len(partsB)
	}
	for i := 0; i < maxLen; i++ {
		sa, sb := "0", "0"
		if i < len(partsA) {
			sa = stripNonNumeric(partsA[i])
		}
		if i < len(partsB) {
			sb = stripNonNumeric(partsB[i])
		}
		na, nb := 0, 0
		fmt.Sscanf(sa, "%d", &na)
		fmt.Sscanf(sb, "%d", &nb)
		if na < nb {
			return -1
		}
		if na > nb {
			return 1
		}
	}
	// 主版本号相同，比较预发布标识
	// 有预发布标识的版本低于无预发布标识的版本 (2.2.0 > 2.2.0-r2)
	if aPre == "" && bPre != "" {
		return 1
	}
	if aPre != "" && bPre == "" {
		return -1
	}
	if aPre != "" && bPre != "" {
		var ia, ib int
		fmt.Sscanf(stripNonNumeric(aPre), "%d", &ia)
		fmt.Sscanf(stripNonNumeric(bPre), "%d", &ib)
		if ia < ib {
			return -1
		}
		if ia > ib {
			return 1
		}
	}
	return 0
}

func stripNonNumeric(s string) string {
	var b strings.Builder
	for _, c := range s {
		if c >= '0' && c <= '9' {
			b.WriteRune(c)
		} else {
			break
		}
	}
	result := b.String()
	if result == "" {
		return "0"
	}
	return result
}

// downloadFile 下载文件到指定路径（原子写入：先写临时文件再重命名）
func downloadFile(url, destPath string) error {
	client := &http.Client{Timeout: 10 * time.Minute}
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	// 先写入临时文件
	tmpPath := destPath + ".tmp"
	f, err := os.Create(tmpPath)
	if err != nil {
		return err
	}
	_, err = io.Copy(f, resp.Body)
	f.Close()
	if err != nil {
		os.Remove(tmpPath)
		return err
	}
	// 原子重命名
	if err := os.Rename(tmpPath, destPath); err != nil {
		os.Remove(tmpPath)
		return err
	}
	return nil
}

// autoUpdateWebPackage 自动检查并更新web前端包
func autoUpdateWebPackage(app *App) {
	if !app.config.AutoUpdate {
		return
	}
	info, err := checkForUpdate()
	if err != nil || !info.HasUpdate {
		return
	}
	webURL, ok := info.Assets["web"]
	if !ok || webURL == "" {
		return
	}

	globalUpdateState.mu.Lock()
	// 已安装过该版本，跳过
	if globalUpdateState.installedVersion == info.Version {
		globalUpdateState.mu.Unlock()
		return
	}
	if globalUpdateState.downloading {
		globalUpdateState.mu.Unlock()
		return
	}
	globalUpdateState.downloading = true
	globalUpdateState.mu.Unlock()

	defer func() {
		globalUpdateState.mu.Lock()
		globalUpdateState.downloading = false
		globalUpdateState.mu.Unlock()
	}()

	updateDir := app.config.UpdateDir
	if err := os.MkdirAll(updateDir, 0755); err != nil {
		log.Printf("[AutoUpdate] 创建更新目录失败: %v", err)
		return
	}

	// 下载所有平台的资源到update目录
	for platform, url := range info.Assets {
		filename := filepath.Base(url)
		destPath := filepath.Join(updateDir, filename)
		if _, err := os.Stat(destPath); err == nil {
			continue // 已下载
		}
		log.Printf("[AutoUpdate] 下载 %s (%s) ...", platform, filename)
		if err := downloadFile(url, destPath); err != nil {
			log.Printf("[AutoUpdate] 下载 %s 失败: %v", platform, err)
			continue
		}
		log.Printf("[AutoUpdate] 下载 %s 完成", platform)
	}

	// 自动解压web包到web目录
	webFilename := filepath.Base(webURL)
	webZipPath := filepath.Join(updateDir, webFilename)
	webDir := app.config.WebDir

	if err := unzipTo(webZipPath, webDir); err != nil {
		log.Printf("[AutoUpdate] 解压web包失败: %v", err)
		return
	}
	globalUpdateState.mu.Lock()
	globalUpdateState.installedVersion = info.Version
	globalUpdateState.mu.Unlock()
	log.Printf("[AutoUpdate] web前端已更新到 %s", info.Version)
}

// unzipTo 解压zip文件到指定目录
func unzipTo(src, dest string) error {
	r, err := zip.OpenReader(src)
	if err != nil {
		return err
	}
	defer r.Close()
	if err := os.MkdirAll(dest, 0755); err != nil {
		return err
	}
	for _, f := range r.File {
		fpath := filepath.Join(dest, f.Name)
		// 防止zip slip
		if !strings.HasPrefix(filepath.Clean(fpath), filepath.Clean(dest)+string(os.PathSeparator)) {
			return fmt.Errorf("非法路径: %s", f.Name)
		}
		if f.FileInfo().IsDir() {
			os.MkdirAll(fpath, 0755)
			continue
		}
		if err := os.MkdirAll(filepath.Dir(fpath), 0755); err != nil {
			return err
		}
		outFile, err := os.OpenFile(fpath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
		if err != nil {
			return err
		}
		rc, err := f.Open()
		if err != nil {
			outFile.Close()
			return err
		}
		_, err = io.Copy(outFile, rc)
		rc.Close()
		outFile.Close()
		if err != nil {
			return err
		}
	}
	return nil
}

// startAutoUpdateChecker 启动定时检查更新
func startAutoUpdateChecker(app *App) {
	if !app.config.AutoUpdate {
		return
	}
	// 启动时延迟30秒检查一次
	go func() {
		time.Sleep(30 * time.Second)
		autoUpdateWebPackage(app)
	}()
	// 每6小时检查一次
	go func() {
		ticker := time.NewTicker(6 * time.Hour)
		defer ticker.Stop()
		for range ticker.C {
			autoUpdateWebPackage(app)
		}
	}()
	log.Printf("[AutoUpdate] 自动更新已启用，每6小时检查一次")
}
