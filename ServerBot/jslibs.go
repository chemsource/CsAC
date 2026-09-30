// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC ServerBot Framework v2.2.1
// JSLibs - AJL library loader, import resolver, and signature verification.

package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	neturl "net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

// AJLFile 表示一个 .ajl 库文件的格式
type AJLFile struct {
	Name      string `json:"name"`
	Version   string `json:"version"`
	Content   string `json:"content"`   // JavaScript 代码
	Signature string `json:"signature"` // HMAC-SHA256 签名
	Author    string `json:"author,omitempty"`
	Desc      string `json:"desc,omitempty"`
}

// LibManager 管理所有可用的 JSLibs 库
type LibManager struct {
	libs    map[string]*AJLFile // libName -> AJLFile
	libDir  string              // lib/ 目录路径
	signKey string              // 签名密钥
	mu      sync.RWMutex
	fw      *BotFramework
}

var globalLibManager *LibManager

// NewLibManager 创建库管理器
func NewLibManager(fw *BotFramework, libDir, signKey string) *LibManager {
	lm := &LibManager{
		libs:    make(map[string]*AJLFile),
		libDir:  libDir,
		signKey: signKey,
		fw:      fw,
	}
	lm.loadFromDisk()
	return lm
}

// loadFromDisk 从 lib/ 目录加载所有 .ajl 文件
func (lm *LibManager) loadFromDisk() {
	lm.mu.Lock()
	defer lm.mu.Unlock()

	lm.libs = make(map[string]*AJLFile)

	entries, err := os.ReadDir(lm.libDir)
	if err != nil {
		if os.IsNotExist(err) {
			log.Printf("[JSLibs] lib目录不存在: %s（将自动创建）", lm.libDir)
			os.MkdirAll(lm.libDir, 0755)
			return
		}
		log.Printf("[JSLibs] 读取lib目录失败: %v", err)
		return
	}

	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(strings.ToLower(entry.Name()), ".ajl") {
			continue
		}
		path := filepath.Join(lm.libDir, entry.Name())
		data, err := os.ReadFile(path)
		if err != nil {
			log.Printf("[JSLibs] 读取库文件失败 %s: %v", entry.Name(), err)
			continue
		}
		var ajl AJLFile
		if err := json.Unmarshal(data, &ajl); err != nil {
			log.Printf("[JSLibs] 解析库文件失败 %s: %v", entry.Name(), err)
			continue
		}
		if ajl.Name == "" || ajl.Content == "" {
			log.Printf("[JSLibs] 库文件 %s 缺少 name 或 content 字段", entry.Name())
			continue
		}
		// 签名校验
		if !verifyAJLSignature(&ajl, lm.signKey) {
			log.Printf("[JSLibs] 库文件 %s 签名校验失败，跳过加载", entry.Name())
			continue
		}
		lm.libs[strings.ToLower(ajl.Name)] = &ajl
		log.Printf("[JSLibs] 加载库: %s v%s", ajl.Name, ajl.Version)
	}
	log.Printf("[JSLibs] 共加载 %d 个库", len(lm.libs))
}

// Reload 重新从磁盘加载所有库
func (lm *LibManager) Reload() {
	lm.loadFromDisk()
}

// GetLib 获取指定名称的库
func (lm *LibManager) GetLib(name string) (*AJLFile, bool) {
	lm.mu.RLock()
	defer lm.mu.RUnlock()
	lib, ok := lm.libs[strings.ToLower(name)]
	return lib, ok
}

// ListLibs 列出所有可用库
func (lm *LibManager) ListLibs() []AJLFile {
	lm.mu.RLock()
	defer lm.mu.RUnlock()
	result := make([]AJLFile, 0, len(lm.libs))
	for _, lib := range lm.libs {
		result = append(result, *lib)
	}
	return result
}

// SaveLib 保存库到磁盘（用于上传/审核通过后）
func (lm *LibManager) SaveLib(ajl *AJLFile) error {
	if ajl.Name == "" || ajl.Content == "" {
		return fmt.Errorf("库名和内容不能为空")
	}
	// 生成签名
	ajl.Signature = generateAJLSignature(ajl, lm.signKey)

	data, err := json.MarshalIndent(ajl, "", "  ")
	if err != nil {
		return fmt.Errorf("序列化失败: %w", err)
	}

	// 确保lib目录存在
	if err := os.MkdirAll(lm.libDir, 0755); err != nil {
		return fmt.Errorf("创建lib目录失败: %w", err)
	}

	filename := strings.ToLower(ajl.Name) + ".ajl"
	path := filepath.Join(lm.libDir, filename)
	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("写入文件失败: %w", err)
	}

	// 更新内存缓存
	lm.mu.Lock()
	lm.libs[strings.ToLower(ajl.Name)] = ajl
	lm.mu.Unlock()

	log.Printf("[JSLibs] 保存库: %s v%s", ajl.Name, ajl.Version)
	return nil
}

// DeleteLib 删除库
func (lm *LibManager) DeleteLib(name string) error {
	lm.mu.Lock()
	defer lm.mu.Unlock()

	filename := strings.ToLower(name) + ".ajl"
	path := filepath.Join(lm.libDir, filename)
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("删除文件失败: %w", err)
	}
	delete(lm.libs, strings.ToLower(name))
	log.Printf("[JSLibs] 删除库: %s", name)
	return nil
}

// generateAJLSignature 为 AJL 文件生成签名
// 使用双重哈希 + 内置盐 + 迭代派生，增加破解难度
// 签名流程: HMAC-SHA512(deriveKey(signKey), name + "\x00" + version + "\x00" + content)
// 其中 deriveKey 使用 1000 轮 HMAC-SHA256 迭代派生
func generateAJLSignature(ajl *AJLFile, key string) string {
	derivedKey := deriveSignKey(key)
	mac := hmac.New(sha512.New, derivedKey)
	mac.Write([]byte(ajl.Name + "\x00" + ajl.Version + "\x00" + ajl.Content))
	return hex.EncodeToString(mac.Sum(nil))
}

// verifyAJLSignature 校验 AJL 文件签名
func verifyAJLSignature(ajl *AJLFile, key string) bool {
	if ajl.Signature == "" {
		return false
	}
	expected := generateAJLSignature(ajl, key)
	return hmac.Equal([]byte(ajl.Signature), []byte(expected))
}

// ajlSignPepper 内置盐，增加离线破解难度
var ajlSignPepper = []byte("CsAC-AJL-Sign-v2.2.1-pepper-x9K3mQ7rT")

// deriveSignKey 从 BotSecret 派生签名密钥
// 使用 1000 轮 HMAC-SHA256 迭代，类似 PBKDF2
func deriveSignKey(key string) []byte {
	salted := append([]byte(key), ajlSignPepper...)
	mac := hmac.New(sha256.New, salted)
	mac.Write([]byte(key))
	result := mac.Sum(nil)
	// 迭代 1000 轮
	for i := 0; i < 999; i++ {
		mac = hmac.New(sha256.New, salted)
		mac.Write(result)
		result = mac.Sum(nil)
	}
	return result
}

// ---- import 解析 ----

var (
	// import { x, y } from "libname"  或  import { x, y } from 'libname'
	reImportFrom = regexp.MustCompile(`(?m)^\s*import\s*\{([^}]*)\}\s*from\s*['"]([^'"]+)['"]\s*;?\s*$`)
	// import ("https://example.com/lib.js")  第三方库导入
	reImportURL = regexp.MustCompile(`(?m)^\s*import\s*\(\s*['"]([^'"]+)['"]\s*\)\s*;?\s*$`)
)

// resolveImports 预处理脚本中的 import 语句，将库代码注入
// 返回处理后的脚本和可能的错误
func resolveImports(script string, allowTParty bool) (string, error) {
	// 处理 import { ... } from "libname"
	importMap := make(map[string][]string) // libName -> [export1, export2, ...]
	matches := reImportFrom.FindAllStringSubmatch(script, -1)
	for _, m := range matches {
		fullMatch := m[0]
		exportsStr := strings.TrimSpace(m[1])
		libName := strings.TrimSpace(m[2])
		exports := parseExports(exportsStr)
		importMap[libName] = append(importMap[libName], exports...)
		// 从脚本中移除 import 行
		script = strings.Replace(script, fullMatch, fmt.Sprintf("// [JSLibs] import from %s", libName), 1)
	}

	// 处理 import ("url") 第三方库
	var tpartyURLs []string
	tpartyMatches := reImportURL.FindAllStringSubmatch(script, -1)
	for _, m := range tpartyMatches {
		fullMatch := m[0]
		url := strings.TrimSpace(m[1])
		if !allowTParty {
			return "", fmt.Errorf("第三方库导入被禁止: import(\"%s\")，需设置 SB_ALLOW_TPARTY_LIB=1", url)
		}
		tpartyURLs = append(tpartyURLs, url)
		script = strings.Replace(script, fullMatch, fmt.Sprintf("// [JSLibs] import from %s", url), 1)
	}

	// 构建注入代码
	var injectBuilder strings.Builder
	injectBuilder.WriteString("// ---- JSLibs injected ----\n")

	for libName, exports := range importMap {
		lib, ok := globalLibManager.GetLib(libName)
		if !ok {
			return "", fmt.Errorf("库 \"%s\" 不存在", libName)
		}
		// 直接注入库代码到全局作用域，使 function 声明对外可见
		injectBuilder.WriteString(fmt.Sprintf("// [JSLibs] lib: %s v%s (%s)\n", lib.Name, lib.Version, strings.Join(exports, ", ")))
		injectBuilder.WriteString(lib.Content)
		injectBuilder.WriteString("\n")
	}

	// 第三方库：同步 fetch 并注入
	for _, url := range tpartyURLs {
		code, err := fetchThirdPartyLib(url)
		if err != nil {
			return "", fmt.Errorf("第三方库导入失败 %s: %w", url, err)
		}
		injectBuilder.WriteString(fmt.Sprintf("// [JSLibs] third-party: %s\n", url))
		injectBuilder.WriteString("(function() {\n")
		injectBuilder.WriteString(code)
		injectBuilder.WriteString("\n})();\n")
	}

	injectBuilder.WriteString("// ---- JSLibs injected end ----\n\n")

	return injectBuilder.String() + script, nil
}

// parseExports 解析 import { a, b as c } 中的导出列表
func parseExports(s string) []string {
	var result []string
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		// 支持 as 语法: "a as b" -> 使用 b 作为变量名
		if idx := strings.Index(strings.ToLower(part), " as "); idx >= 0 {
			alias := strings.TrimSpace(part[idx+4:])
			if alias != "" {
				result = append(result, alias)
			}
		} else {
			result = append(result, part)
		}
	}
	return result
}

// fetchThirdPartyLib 从 URL 获取第三方库代码
// 仅允许 HTTPS 协议，禁止访问内网地址（防 SSRF）
func fetchThirdPartyLib(rawURL string) (string, error) {
	parsed, err := neturl.Parse(rawURL)
	if err != nil {
		return "", fmt.Errorf("无效的URL: %w", err)
	}
	if parsed.Scheme != "https" {
		return "", fmt.Errorf("仅允许 HTTPS 协议")
	}
	// 解析主机名，禁止内网地址
	ips, err := net.LookupIP(parsed.Hostname())
	if err != nil {
		return "", fmt.Errorf("域名解析失败: %w", err)
	}
	for _, ip := range ips {
		if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() {
			return "", fmt.Errorf("禁止访问内网地址: %s", ip)
		}
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get(rawURL)
	if err != nil {
		return "", fmt.Errorf("请求失败: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	// 限制大小 1MB
	limited := io.LimitReader(resp.Body, 1024*1024)
	data, err := io.ReadAll(limited)
	if err != nil {
		return "", fmt.Errorf("读取失败: %w", err)
	}
	return string(data), nil
}
