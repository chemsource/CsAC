// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC Backend v2.3.0
// 文件消息功能

package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// FileMeta 文件消息元数据
type FileMeta struct {
	FileName  string `json:"file_name"`
	FileSize  int64  `json:"file_size"`
	FileType  string `json:"file_type"`  // 扩展名
	FilePath  string `json:"file_path"`  // 内部存储路径
	PublicURL string `json:"public_url"` // 公开下载URL
	ExpiresAt int64  `json:"expires_at"` // 过期时间戳
}

// apiMessageSendFileMsg 发送文件消息（群聊/私聊）
// msg_type=6 表示文件消息
func apiMessageSendFileMsg(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}

	roomID := c.InputInt("room_id")
	friendID := c.InputInt("friend_id")

	// 群聊或私聊二选一
	if roomID <= 0 && friendID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请指定room_id或friend_id"})
		return
	}
	if roomID > 0 && friendID > 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "不能同时指定room_id和friend_id"})
		return
	}

	// 检查上传文件
	if !hasMultipartFile(c, "file") {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请上传文件"})
		return
	}

	// 验证文件扩展名
	_, fileHeader, err := c.r.FormFile("file")
	if err != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件读取失败"})
		return
	}
	fileName := fileHeader.Filename
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(fileName), "."))
	if ext == "" || !isFileExtAllowed(c.app, ext) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": fmt.Sprintf("不支持的文件类型：.%s", ext)})
		return
	}
	if fileHeader.Size > c.app.config.FileMaxBytes {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": fmt.Sprintf("文件大小超出限制（最大%dKB）", c.app.config.FileMaxBytes/1024)})
		return
	}

	var (
		nickname     string
		storeDir     string
		publicPrefix string
		table        string
		insertData   map[string]any
	)

	now := time.Now().Unix()
	expiresAt := now + int64(c.app.config.FileExpireDays)*86400

	if roomID > 0 {
		// 群聊文件
		if !requireRoomNotBanned(c, roomID) {
			return
		}
		member, _ := c.app.fetchOne("SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?", roomID, uid)
		if member == nil {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你不是该群成员"})
			return
		}
		if muteUntil := intval(member, "mute_until"); muteUntil > now {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你已被禁言至 " + localDateTime(muteUntil)})
			return
		}
		user := getUser(c.app, uid, "nickname")
		nickname = strDefault(user, "nickname", "未知用户")
		storeDir = filepath.Join(c.app.config.UploadDir, "files", "groups", fmt.Sprintf("%d", roomID))
		publicPrefix = "upload/files/groups/" + fmt.Sprintf("%d", roomID)
		table = "chat_msg"
	} else {
		// 私聊文件
		if _, ok := requireFriend(c, uid, friendID); !ok {
			return
		}
		storeDir = filepath.Join(c.app.config.PrivateUploadDir, "files")
		publicPrefix = "uploads/chat/files"
		table = "private_msg"
	}

	// 上传文件（不限制MIME，因为已通过扩展名白名单校验）
	url, uploaded := uploadFileRaw(c, "file", c.app.config.FileMaxBytes, storeDir, publicPrefix, fmt.Sprintf("file_%d_%d", uid, now))
	if !uploaded {
		return
	}

	// 构建文件元数据
	meta := FileMeta{
		FileName:  fileName,
		FileSize:  fileHeader.Size,
		FileType:  ext,
		FilePath:  url,
		PublicURL: url,
		ExpiresAt: expiresAt,
	}
	metaJSON, _ := json.Marshal(meta)

	content := fmt.Sprintf("[文件] %s", fileName)

	if table == "chat_msg" {
		insertData = map[string]any{
			"room_id":        roomID,
			"uid":            uid,
			"nickname":       nickname,
			"content":        content,
			"msg_type":       6,
			"voice_duration": 0,
			"add_time":       utcDateTime(now),
			"reply_to":       nullablePositiveInt(c.InputInt("reply_to")),
			"mention_uids":   "",
			"was_replied":    0,
			"file_meta":      string(metaJSON),
		}
	} else {
		insertData = map[string]any{
			"from_uid":    uid,
			"to_uid":      friendID,
			"content":     content,
			"type":        "private",
			"room_id":     0,
			"created_at":  now,
			"is_read":     0,
			"image_url":   "",
			"msg_type":    6,
			"is_recalled": 0,
			"reply_to":    nullablePositiveInt(c.InputInt("reply_to")),
			"file_meta":   string(metaJSON),
		}
	}

	msgID, err := c.app.insertRow(table, insertData)
	if err != nil {
		log.Printf("send file msg failed: table=%s uid=%d err=%v", table, uid, err)
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "发送失败"})
		return
	}

	// 转发事件到ServerBot
	if table == "chat_msg" {
		pushBotEvent("group_message", map[string]any{
			"msg_id":    msgID,
			"room_id":   roomID,
			"uid":       uid,
			"nickname":  nickname,
			"content":   content,
			"msg_type":  6,
			"file_meta": string(metaJSON),
			"timestamp": now,
		})
	} else {
		pushBotEvent("private_message", map[string]any{
			"msg_id":    msgID,
			"from_uid":  uid,
			"to_uid":    friendID,
			"content":   content,
			"msg_type":  6,
			"file_meta": string(metaJSON),
			"timestamp": now,
		})
	}

	c.JSON(http.StatusOK, map[string]any{
		"success":   true,
		"message":   "发送成功",
		"msg_id":    msgID,
		"file_meta": meta,
	})
}

// apiMessageGetFile 获取文件（下载）
func apiMessageGetFile(c *Ctx) {
	if !c.RequireMethod(http.MethodGet) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	msgID := c.InputInt("msg_id")
	roomID := c.InputInt("room_id")
	friendID := c.InputInt("friend_id")

	if msgID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "msg_id无效"})
		return
	}

	var metaStr string
	if roomID > 0 {
		// 群消息：验证成员身份
		if !isGroupMember(c.app, roomID, uid) {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无权访问"})
			return
		}
		row, _ := c.app.fetchOne("SELECT file_meta FROM chat_msg WHERE id = ? AND room_id = ? AND msg_type = 6", msgID, roomID)
		if row == nil {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件不存在"})
			return
		}
		metaStr = str(row, "file_meta")
	} else if friendID > 0 {
		// 私聊消息：验证是发送者或接收者
		row, _ := c.app.fetchOne("SELECT file_meta, from_uid, to_uid FROM private_msg WHERE id = ? AND msg_type = 6", msgID)
		if row == nil {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件不存在"})
			return
		}
		fromUID := intval(row, "from_uid")
		toUID := intval(row, "to_uid")
		if uid != fromUID && uid != toUID {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无权访问"})
			return
		}
		metaStr = str(row, "file_meta")
	} else {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请指定room_id或friend_id"})
		return
	}

	var meta FileMeta
	if err := json.Unmarshal([]byte(metaStr), &meta); err != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件元数据损坏"})
		return
	}

	// 检查是否过期
	if meta.ExpiresAt > 0 && time.Now().Unix() > meta.ExpiresAt {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件已过期"})
		return
	}

	// 返回文件元数据（前端通过public_url下载）
	c.JSON(http.StatusOK, map[string]any{
		"success":   true,
		"file_meta": meta,
	})
}

// isFileExtAllowed 检查文件扩展名是否在白名单中
func isFileExtAllowed(app *App, ext string) bool {
	allowed := strings.Split(app.config.FileAllowedTypes, ",")
	for _, a := range allowed {
		if strings.TrimSpace(a) == ext {
			return true
		}
	}
	return false
}

// uploadFileRaw 上传文件（不限制MIME类型，仅限制大小）
func uploadFileRaw(c *Ctx, field string, maxBytes int64, absoluteDir, publicPrefix, namePrefix string) (string, bool) {
	if err := c.r.ParseMultipartForm(maxBytes + 1024*1024); err != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件上传失败"})
		return "", false
	}
	file, header, err := c.r.FormFile(field)
	if err != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件上传失败"})
		return "", false
	}
	defer file.Close()
	if header.Size > maxBytes {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件大小超出限制"})
		return "", false
	}
	if err := os.MkdirAll(absoluteDir, 0775); err != nil {
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "上传目录不可用"})
		return "", false
	}

	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(header.Filename), "."))
	name := fmt.Sprintf("%s_%s_%d.%s", namePrefix, randomHex(6), time.Now().Unix(), ext)
	dest := filepath.Join(absoluteDir, name)
	out, err := os.OpenFile(dest, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0664)
	if err != nil {
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "文件保存失败"})
		return "", false
	}
	defer out.Close()
	if _, err := io.Copy(out, file); err != nil {
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "文件保存失败"})
		return "", false
	}
	return strings.TrimRight(publicPrefix, "/") + "/" + name, true
}

// startFileExpireCleaner 启动过期文件清理协程
func startFileExpireCleaner(app *App) {
	go func() {
		ticker := time.NewTicker(1 * time.Hour)
		defer ticker.Stop()
		for range ticker.C {
			cleanExpiredFiles(app)
		}
	}()
}

// cleanExpiredFiles 清理过期的文件消息
func cleanExpiredFiles(app *App) {
	now := time.Now().Unix()
	// 只查最近7天内创建的文件消息，避免全表扫描
	cutoff := now - 86400*7

	// 清理群聊过期文件
	rows, err := app.fetchAll("SELECT id, file_meta FROM chat_msg WHERE msg_type = 6 AND file_meta != '' AND UNIX_TIMESTAMP(add_time) > ?", cutoff)
	if err != nil {
		return
	}
	for _, row := range rows {
		metaStr := str(row, "file_meta")
		if metaStr == "" {
			continue
		}
		var meta FileMeta
		if json.Unmarshal([]byte(metaStr), &meta) != nil {
			continue
		}
		if meta.ExpiresAt > 0 && now > meta.ExpiresAt {
			deleteFileFromPath(app, meta.FilePath)
			_, _ = app.updateRow("chat_msg", map[string]any{
				"content":   "[文件已过期] " + meta.FileName,
				"file_meta": "",
			}, "id = ?", intval(row, "id"))
		}
	}

	// 清理私聊过期文件
	rows, err = app.fetchAll("SELECT id, file_meta FROM private_msg WHERE msg_type = 6 AND file_meta != '' AND created_at > ?", cutoff)
	if err != nil {
		return
	}
	for _, row := range rows {
		metaStr := str(row, "file_meta")
		if metaStr == "" {
			continue
		}
		var meta FileMeta
		if json.Unmarshal([]byte(metaStr), &meta) != nil {
			continue
		}
		if meta.ExpiresAt > 0 && now > meta.ExpiresAt {
			deleteFileFromPath(app, meta.FilePath)
			_, _ = app.updateRow("private_msg", map[string]any{
				"content":   "[文件已过期] " + meta.FileName,
				"file_meta": "",
			}, "id = ?", intval(row, "id"))
		}
	}

	// 清理群文件表过期文件
	gfRows, err := app.fetchAll("SELECT id, file_path, file_name FROM group_files WHERE expires_at > 0 AND expires_at < ?", now)
	if err != nil {
		return
	}
	for _, row := range gfRows {
		deleteFileFromPath(app, str(row, "file_path"))
		_, _ = app.exec("DELETE FROM group_files WHERE id = ?", intval(row, "id"))
		log.Printf("[FileExpire] 清理过期群文件: %s", str(row, "file_name"))
	}
}

// deleteFileFromPath 从公开URL路径删除文件
func deleteFileFromPath(app *App, publicPath string) {
	if publicPath == "" {
		return
	}
	// 尝试在多个上传目录中查找
	candidates := []string{
		filepath.Join(filepath.Dir(app.config.UploadDir), publicPath),
		filepath.Join(filepath.Dir(app.config.PrivateUploadDir), publicPath),
	}
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			os.Remove(p)
			log.Printf("[FileExpire] 删除过期文件: %s", p)
			return
		}
	}
}

// ===== v2.3.0: 群文件功能 =====

// apiGroupFileList 获取群文件列表（支持按分组筛选）
func apiGroupFileList(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "room_id无效"})
		return
	}
	if !isGroupMember(c.app, roomID, uid) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你不是该群成员"})
		return
	}

	fileGroup := c.InputString("group")
	query := "SELECT id, uploader_uid, file_name, file_size, file_type, file_path, file_group, expires_at, created_at FROM group_files WHERE room_id = ?"
	args := []any{roomID}
	if fileGroup != "" {
		query += " AND file_group = ?"
		args = append(args, fileGroup)
	}
	query += " ORDER BY created_at DESC"

	rows, err := c.app.fetchAll(query, args...)
	if err != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
		return
	}

	now := time.Now().Unix()
	result := make([]map[string]any, 0, len(rows))
	for _, row := range rows {
		expiresAt := intval(row, "expires_at")
		if expiresAt > 0 && now > expiresAt {
			continue // 已过期，不返回
		}
		uploaderUID := intval(row, "uploader_uid")
		uploader := getUser(c.app, uploaderUID, "nickname")
		result = append(result, map[string]any{
			"id":            intval(row, "id"),
			"uploader_uid":  uploaderUID,
			"uploader_name": strDefault(uploader, "nickname", "未知用户"),
			"file_name":     str(row, "file_name"),
			"file_size":     intval(row, "file_size"),
			"file_type":     str(row, "file_type"),
			"file_path":     str(row, "file_path"),
			"file_group":    str(row, "file_group"),
			"expires_at":    expiresAt,
			"created_at":    intval(row, "created_at"),
		})
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "files": result})
}

// apiGroupFileUpload 上传群文件
func apiGroupFileUpload(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "room_id无效"})
		return
	}
	if !isGroupMember(c.app, roomID, uid) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你不是该群成员"})
		return
	}

	if !hasMultipartFile(c, "file") {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请上传文件"})
		return
	}

	// 验证文件扩展名
	_, fileHeader, err := c.r.FormFile("file")
	if err != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件读取失败"})
		return
	}
	fileName := fileHeader.Filename
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(fileName), "."))
	if ext == "" || !isFileExtAllowed(c.app, ext) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": fmt.Sprintf("不支持的文件类型：.%s", ext)})
		return
	}
	if fileHeader.Size > c.app.config.FileMaxBytes {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": fmt.Sprintf("文件大小超出限制（最大%dKB）", c.app.config.FileMaxBytes/1024)})
		return
	}

	fileGroup := c.InputString("group")
	now := time.Now().Unix()
	expiresAt := now + int64(c.app.config.FileExpireDays)*86400

	storeDir := filepath.Join(c.app.config.UploadDir, "files", "groups", fmt.Sprintf("%d", roomID))
	publicPrefix := "upload/files/groups/" + fmt.Sprintf("%d", roomID)

	url, uploaded := uploadFileRaw(c, "file", c.app.config.FileMaxBytes, storeDir, publicPrefix, fmt.Sprintf("gfile_%d_%d", uid, now))
	if !uploaded {
		return
	}

	fileID, err := c.app.insertRow("group_files", map[string]any{
		"room_id":      roomID,
		"uploader_uid": uid,
		"file_name":    fileName,
		"file_size":    fileHeader.Size,
		"file_type":    ext,
		"file_path":    url,
		"file_group":   fileGroup,
		"expires_at":   expiresAt,
		"created_at":   now,
	})
	if err != nil {
		log.Printf("upload group file failed: room_id=%d uid=%d err=%v", roomID, uid, err)
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "上传失败"})
		return
	}

	c.JSON(http.StatusOK, map[string]any{
		"success": true,
		"message": "上传成功",
		"file_id": fileID,
		"file": map[string]any{
			"id":         fileID,
			"file_name":  fileName,
			"file_size":  fileHeader.Size,
			"file_type":  ext,
			"file_path":  url,
			"file_group": fileGroup,
			"expires_at": expiresAt,
		},
	})
}

// apiGroupFileDelete 删除群文件（上传者或管理员可删）
func apiGroupFileDelete(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	fileID := c.InputInt("file_id")
	if fileID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "file_id无效"})
		return
	}

	file, _ := c.app.fetchOne("SELECT id, room_id, uploader_uid, file_path FROM group_files WHERE id = ?", fileID)
	if file == nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件不存在"})
		return
	}

	roomID := intval(file, "room_id")
	uploaderUID := intval(file, "uploader_uid")

	// 验证权限：上传者本人或群主/管理员
	if uid != uploaderUID {
		member, _ := c.app.fetchOne("SELECT title FROM chat_group_user WHERE room_id = ? AND uid = ?", roomID, uid)
		if member == nil {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无权删除"})
			return
		}
		title := str(member, "title")
		if title != "群主" && title != "管理员" {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无权删除"})
			return
		}
	}

	// 删除文件
	deleteFileFromPath(c.app, str(file, "file_path"))
	_, err := c.app.exec("DELETE FROM group_files WHERE id = ?", fileID)
	if err != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "删除失败"})
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "已删除"})
}

// apiGroupFileMove 移动群文件到指定分组
func apiGroupFileMove(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	fileID := c.InputInt("file_id")
	targetGroup := c.InputString("target_group")
	if fileID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "file_id无效"})
		return
	}

	file, _ := c.app.fetchOne("SELECT id, room_id, uploader_uid FROM group_files WHERE id = ?", fileID)
	if file == nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件不存在"})
		return
	}

	roomID := intval(file, "room_id")
	uploaderUID := intval(file, "uploader_uid")

	// 验证权限
	if uid != uploaderUID {
		member, _ := c.app.fetchOne("SELECT title FROM chat_group_user WHERE room_id = ? AND uid = ?", roomID, uid)
		if member == nil || (str(member, "title") != "群主" && str(member, "title") != "管理员") {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无权移动"})
			return
		}
	}

	// 验证目标分组是否在该群的分组列表中
	if targetGroup != "" {
		room, _ := c.app.fetchOne("SELECT file_groups FROM chat_room WHERE id = ?", roomID)
		if room != nil {
			var groups []string
			if json.Unmarshal([]byte(str(room, "file_groups")), &groups) == nil {
				found := false
				for _, g := range groups {
					if g == targetGroup {
						found = true
						break
					}
				}
				if !found {
					c.JSON(http.StatusOK, map[string]any{"success": false, "message": "目标分组不存在"})
					return
				}
			}
		}
	}

	_, err := c.app.updateRow("group_files", map[string]any{"file_group": targetGroup}, "id = ?", fileID)
	if err != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "移动失败"})
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "已移动"})
}

// apiGroupFileGroups 管理群文件分组（增/删/重命名）
func apiGroupFileGroups(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	action := c.InputString("action") // add / remove / rename
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "room_id无效"})
		return
	}

	// 仅群主/管理员可管理分组
	member, _ := c.app.fetchOne("SELECT title FROM chat_group_user WHERE room_id = ? AND uid = ?", roomID, uid)
	if member == nil || (str(member, "title") != "群主" && str(member, "title") != "管理员") {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "需要群主或管理员权限"})
		return
	}

	room, _ := c.app.fetchOne("SELECT file_groups FROM chat_room WHERE id = ?", roomID)
	if room == nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "群不存在"})
		return
	}

	var groups []string
	rawGroups := str(room, "file_groups")
	if rawGroups == "" || rawGroups == "[]" {
		groups = []string{}
	} else {
		if json.Unmarshal([]byte(rawGroups), &groups) != nil {
			groups = []string{}
		}
	}

	switch action {
	case "add":
		name := c.InputString("name")
		name = strings.TrimSpace(name)
		if name == "" {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "分组名不能为空"})
			return
		}
		if len(name) > 50 {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "分组名过长"})
			return
		}
		for _, g := range groups {
			if g == name {
				c.JSON(http.StatusOK, map[string]any{"success": false, "message": "分组已存在"})
				return
			}
		}
		groups = append(groups, name)

	case "remove":
		name := c.InputString("name")
		found := false
		newGroups := make([]string, 0, len(groups))
		for _, g := range groups {
			if g == name {
				found = true
			} else {
				newGroups = append(newGroups, g)
			}
		}
		if !found {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "分组不存在"})
			return
		}
		groups = newGroups
		// 将该分组下的文件移到默认分组
		_, _ = c.app.exec("UPDATE group_files SET file_group = '' WHERE room_id = ? AND file_group = ?", roomID, name)

	case "rename":
		oldName := c.InputString("old_name")
		newName := strings.TrimSpace(c.InputString("new_name"))
		if oldName == "" || newName == "" {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数无效"})
			return
		}
		found := false
		for i, g := range groups {
			if g == oldName {
				groups[i] = newName
				found = true
			}
		}
		if !found {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "分组不存在"})
			return
		}
		// 更新文件分组名
		_, _ = c.app.exec("UPDATE group_files SET file_group = ? WHERE room_id = ? AND file_group = ?", newName, roomID, oldName)

	case "":
		// 无action，仅查询
		c.JSON(http.StatusOK, map[string]any{"success": true, "groups": groups})
		return

	default:
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "未知action: " + action})
		return
	}

	groupsJSON, _ := json.Marshal(groups)
	_, err := c.app.updateRow("chat_room", map[string]any{"file_groups": string(groupsJSON)}, "id = ?", roomID)
	if err != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "更新失败"})
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "groups": groups})
}
