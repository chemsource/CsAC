// Copyright (c) Chemsource Studio. All rights reserved.
// Contact: swcsstudio@126.com

package main

import (
	"crypto/hmac"
	"crypto/md5"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

var platformPattern = regexp.MustCompile(`^[A-Za-z0-9_.]+-[A-Za-z0-9_.]+-[A-Za-z0-9_.-]+$`)

var imageMimes = []string{"image/jpeg", "image/png", "image/gif", "image/webp", "image/bmp"}

var voiceMimes = []string{
	"audio/webm", "video/webm", "audio/ogg", "application/ogg", "audio/opus", "audio/mpeg", "audio/mp3",
	"audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave", "audio/mp4", "audio/m4a", "audio/x-m4a",
	"video/mp4", "audio/aac", "audio/aacp", "audio/3gpp", "audio/3gpp2", "video/3gpp", "video/3gpp2",
	"audio/amr", "audio/x-amr", "audio/flac", "audio/x-flac", "audio/x-caf", "audio/caf", "audio/aiff", "audio/x-aiff",
}

func hashPassword(password, username string) string {
	sum := sha256.Sum256([]byte(password + username))
	return hex.EncodeToString(sum[:])
}

func isPasswordValid(user Row, password string) bool {
	stored := str(user, "pwd")
	username := str(user, "username")
	if len(stored) == 32 {
		md := md5.Sum([]byte(password))
		if hmac.Equal([]byte(stored), []byte(hex.EncodeToString(md[:]))) {
			return true
		}
	}
	return hmac.Equal([]byte(stored), []byte(hashPassword(password, username)))
}

func createInviteCode(length int) string {
	if length <= 0 {
		length = 7
	}
	chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	buf := make([]byte, length)
	rnd := make([]byte, length)
	if _, err := rand.Read(rnd); err != nil {
		panic(err)
	}
	for i := range buf {
		buf[i] = chars[int(rnd[i])%len(chars)]
	}
	return string(buf)
}

func resetRoomCode(a *App, roomID int64) string {
	code := createInviteCode(7)
	_, _ = a.updateRow("chat_room", map[string]any{"invite_code": code}, "id = ?", roomID)
	return code
}

func onlineStatus(lastActive any) string {
	t := parseAnyTime(lastActive)
	if t <= 0 {
		return "离线"
	}
	diff := time.Now().Unix() - t
	if diff < 300 {
		return "在线"
	}
	if diff < 3600 {
		return fmt.Sprintf("%d分钟前在线", diff/60)
	}
	if diff < 86400 {
		return fmt.Sprintf("%d小时前在线", diff/3600)
	}
	return fmt.Sprintf("%d天前在线", diff/86400)
}

func isOnline(lastActive any) bool {
	t := parseAnyTime(lastActive)
	return t > 0 && time.Now().Unix()-t < 300
}

func parseAnyTime(value any) int64 {
	text := strings.TrimSpace(toString(value))
	if text == "" {
		return 0
	}
	if i, err := parseIntString(text); err == nil {
		return i
	}
	return parseUTCDateTime(text)
}

func parseIntString(text string) (int64, error) {
	return strconv.ParseInt(strings.TrimSpace(text), 10, 64)
}

func normalizePlatform(platform string) string {
	platform = strings.TrimSpace(platform)
	if platform == "" {
		return ""
	}
	if len([]rune(platform)) > 100 {
		platform = string([]rune(platform)[:100])
	}
	if platformPattern.MatchString(platform) {
		return platform
	}
	return ""
}

func checkUserExists(a *App, uid int64) bool {
	row, err := a.fetchOne("SELECT id FROM chat_user WHERE id = ?", uid)
	return err == nil && row != nil
}

func checkUserBan(a *App, uid int64) map[string]any {
	user, err := a.fetchOne("SELECT ban_until, ban_reason FROM chat_user WHERE id = ?", uid)
	if err != nil || user == nil {
		return nil
	}
	until := intval(user, "ban_until")
	if until > time.Now().Unix() {
		reason := str(user, "ban_reason")
		if reason == "" {
			reason = "违反相关规定"
		}
		return map[string]any{"banned": true, "until": until, "reason": reason}
	}
	return nil
}

func requireLogin(c *Ctx) (int64, bool) {
	if sessionExtActive(c) {
		uid := sessionUIDFallback(c)
		touchUser(c, uid)
		return uid, true
	}
	uid := int64(0)
	if c.session != nil {
		uid = c.session.UID
	}
	if uid <= 0 || !checkUserExists(c.app, uid) {
		c.JSON(http.StatusUnauthorized, map[string]any{"success": false, "message": "未登录"})
		return 0, false
	}
	if ban := checkUserBan(c.app, uid); ban != nil {
		c.destroySession()
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "账号已封禁", "ban_info": ban})
		return 0, false
	}
	if c.app.config.RequireExistingUserEmailVerification && !userEmailVerified(c.app, uid) {
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "请先完成邮箱验证", "needs_email_verification": true})
		return 0, false
	}
	touchUser(c, uid)
	return uid, true
}

func requirePendingEmailUser(c *Ctx) (int64, bool) {
	uid := int64(0)
	if c.session != nil {
		uid = c.session.UID
	}
	if uid <= 0 || !checkUserExists(c.app, uid) {
		c.JSON(http.StatusUnauthorized, map[string]any{"success": false, "message": "未登录"})
		return 0, false
	}
	if ban := checkUserBan(c.app, uid); ban != nil {
		c.destroySession()
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "账号已封禁", "ban_info": ban})
		return 0, false
	}
	if userEmailVerified(c.app, uid) {
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "邮箱已验证"})
		return 0, false
	}
	return uid, true
}

func userEmailVerified(a *App, uid int64) bool {
	row, err := a.fetchOne("SELECT email FROM chat_user WHERE id = ?", uid)
	return err == nil && row != nil && strings.TrimSpace(str(row, "email")) != ""
}

func touchUser(c *Ctx, uid int64) {
	now := time.Now().Unix()
	if c.session != nil {
		if c.session.LastTouch > 0 && now-c.session.LastTouch < 60 {
			return
		}
		c.session.LastTouch = now
		c.markSessionDirty()
	}
	data := map[string]any{"last_active": now}
	if c.session != nil && c.session.Platform != "" {
		data["platform"] = c.session.Platform
	}
	_, _ = c.app.updateRow("chat_user", data, "id = ?", uid)
}

func updateUserPlatform(a *App, uid int64, platform string) {
	if platform == "" {
		platform = "none"
	}
	_, _ = a.exec("UPDATE chat_user SET platform = ? WHERE id = ?", platform, uid)
}

func getUser(a *App, uid int64, columns string) Row {
	row, err := a.fetchOne("SELECT "+selectColumns(a, "chat_user", columns)+" FROM chat_user WHERE id = ?", uid)
	if err != nil {
		return nil
	}
	return row
}

func getRoom(a *App, roomID int64, columns string) Row {
	row, err := a.fetchOne("SELECT "+selectColumns(a, "chat_room", columns)+" FROM chat_room WHERE id = ?", roomID)
	if err != nil {
		return nil
	}
	return row
}

func roomBanInfo(room Row) map[string]any {
	until := intval(room, "ban_until")
	if until <= time.Now().Unix() {
		return nil
	}
	reason := str(room, "ban_reason")
	if reason == "" {
		reason = "违反相关规定"
	}
	return map[string]any{"banned": true, "until": until, "until_text": localDateTime(until), "reason": reason}
}

func roomBanFields(room Row) map[string]any {
	ban := roomBanInfo(room)
	untilText := ""
	if ban != nil {
		untilText = toString(ban["until_text"])
	}
	return map[string]any{
		"is_banned":      ban != nil,
		"ban_until":      intval(room, "ban_until"),
		"ban_until_text": untilText,
		"ban_reason":     str(room, "ban_reason"),
		"room_ban_info":  ban,
	}
}

func requireRoomNotBanned(c *Ctx, roomID int64, room ...Row) bool {
	if sessionExtActive(c) {
		return true
	}
	var r Row
	if len(room) > 0 {
		r = room[0]
	} else {
		r = getRoom(c.app, roomID, "ban_until, ban_reason")
	}
	if ban := roomBanInfo(r); ban != nil {
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "群组已被封禁至 " + toString(ban["until_text"]) + "，暂不可使用", "room_ban_info": ban})
		return false
	}
	return true
}

func isGroupMember(a *App, roomID, uid int64) bool {
	row, err := a.fetchOne("SELECT room_id FROM chat_group_user WHERE room_id = ? AND uid = ? LIMIT 1", roomID, uid)
	return err == nil && row != nil
}

func isGroupAdmin(a *App, roomID, uid int64) bool {
	row, err := a.fetchOne("SELECT uid FROM chat_group_admin WHERE room_id = ? AND uid = ? LIMIT 1", roomID, uid)
	return err == nil && row != nil
}

func requireGroupMember(c *Ctx, roomID, uid int64, allowBanned ...bool) (Row, bool) {
	room := getRoom(c.app, roomID, "*")
	if room == nil || intval(room, "is_disband") != 0 {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "群组不存在"})
		return nil, false
	}
	if sessionExtActive(c) {
		return room, true
	}
	if !isGroupMember(c.app, roomID, uid) {
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "你不是该群成员"})
		return nil, false
	}
	if (len(allowBanned) == 0 || !allowBanned[0]) && !requireRoomNotBanned(c, roomID, room) {
		return nil, false
	}
	return room, true
}

func requireGroupOwner(c *Ctx, roomID, uid int64, allowBanned ...bool) (Row, bool) {
	room := getRoom(c.app, roomID, "*")
	if room == nil || intval(room, "is_disband") != 0 {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "群组不存在"})
		return nil, false
	}
	if sessionExtActive(c) {
		return room, true
	}
	if intval(room, "owner_uid") != uid {
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "仅群主可操作"})
		return nil, false
	}
	if (len(allowBanned) == 0 || !allowBanned[0]) && !requireRoomNotBanned(c, roomID, room) {
		return nil, false
	}
	return room, true
}

func requireGroupOwnerOrAdmin(c *Ctx, roomID, uid int64, allowBanned ...bool) (Row, bool) {
	room := getRoom(c.app, roomID, "*")
	if room == nil || intval(room, "is_disband") != 0 {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "群组不存在"})
		return nil, false
	}
	if sessionExtActive(c) {
		return room, true
	}
	if intval(room, "owner_uid") != uid && !isGroupAdmin(c.app, roomID, uid) {
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "无权限"})
		return nil, false
	}
	if (len(allowBanned) == 0 || !allowBanned[0]) && !requireRoomNotBanned(c, roomID, room) {
		return nil, false
	}
	return room, true
}

func groupDefaultTitle(level int64) string {
	if level < 1 {
		level = 1
	}
	if level > 100 {
		level = 100
	}
	switch {
	case level <= 10:
		return "青铜"
	case level <= 20:
		return "白银"
	case level <= 40:
		return "黄金"
	case level <= 80:
		return "铂金"
	default:
		return "王者"
	}
}

func groupTitleIsDefault(title string) bool {
	switch title {
	case "", "青铜", "白银", "黄金", "铂金", "王者":
		return true
	}
	return false
}

func refreshGroupMemberLevel(a *App, roomID, uid int64) map[string]any {
	if !a.hasColumn("chat_group_user", "level") {
		return map[string]any{"level": int64(1), "title": groupDefaultTitle(1)}
	}
	member, err := a.fetchOne("SELECT level, title, level_custom, title_custom FROM chat_group_user WHERE room_id = ? AND uid = ? LIMIT 1", roomID, uid)
	if err != nil {
		return map[string]any{"level": int64(1), "title": groupDefaultTitle(1)}
	}
	if member != nil && intval(member, "level_custom") == 1 {
		level := intval(member, "level")
		if level < 1 {
			level = 1
		}
		title := str(member, "title")
		if title == "" {
			title = groupDefaultTitle(level)
		}
		return map[string]any{"level": level, "title": title}
	}
	activity, err := a.fetchOne("SELECT COUNT(DISTINCT DATE(add_time)) AS active_days FROM chat_msg WHERE room_id = ? AND uid = ?", roomID, uid)
	if err != nil {
		return map[string]any{"level": int64(1), "title": groupDefaultTitle(1)}
	}
	level := groupLevelFromActivity(intval(activity, "active_days"))
	defaultTitle := groupDefaultTitle(level)
	currentTitle := str(member, "title")
	updates := map[string]any{"level": level}
	if groupTitleIsDefault(currentTitle) {
		updates["title"] = defaultTitle
		currentTitle = defaultTitle
	}
	if _, err := a.updateRow("chat_group_user", updates, "room_id = ? AND uid = ?", roomID, uid); err != nil {
		return map[string]any{"level": level, "title": currentTitle}
	}
	return map[string]any{"level": level, "title": currentTitle}
}

func groupLevelFromActivity(activeDays int64) int64 {
	thresholds := map[int64]int64{1: 0, 2: 7, 3: 14, 4: 30, 5: 60, 6: 90, 7: 130, 8: 180, 9: 240, 10: 320, 11: 420, 12: 540, 13: 680, 14: 840, 15: 1020, 16: 1220, 17: 1450, 18: 1710, 19: 2000, 20: 2320}
	level := int64(1)
	for candidate, required := range thresholds {
		if activeDays >= required && candidate > level {
			level = candidate
		}
	}
	if activeDays > 2320 {
		level = 20 + int64((activeDays-2320)/300)
	}
	if level < 1 {
		level = 1
	}
	if level > 100 {
		level = 100
	}
	return level
}

func friendPair(a, b int64) (int64, int64) {
	if a < b {
		return a, b
	}
	return b, a
}

func friendRelation(app *App, a, b int64) Row {
	uid1, uid2 := friendPair(a, b)
	row, err := app.fetchOne("SELECT * FROM friend_relation WHERE uid1 = ? AND uid2 = ?", uid1, uid2)
	if err != nil {
		return nil
	}
	return row
}

func requireFriend(c *Ctx, myUID, friendID int64) (Row, bool) {
	rel := friendRelation(c.app, myUID, friendID)
	if rel == nil || intval(rel, "status") != 1 {
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "你们不是好友"})
		return nil, false
	}
	return rel, true
}

func notice(a *App, uid int64, title, content string, link ...string) {
	value := ""
	if len(link) > 0 {
		value = link[0]
	}
	_, _ = a.insertRow("chat_user_notice", map[string]any{"uid": uid, "title": title, "content": content, "link": value, "is_read": 0, "add_time": localDateTime(time.Now().Unix())})
}

func privateSystemMessage(a *App, fromUID, toUID int64, content string) {
	_, _ = a.insertRow("private_msg", map[string]any{"from_uid": fromUID, "to_uid": toUID, "content": content, "type": "system", "room_id": 0, "created_at": time.Now().Unix(), "is_read": 0, "msg_type": 1})
}

func uploadFile(c *Ctx, field string, allowedMimes []string, maxBytes int64, absoluteDir, publicPrefix, namePrefix string) (string, bool) {
	if err := c.r.ParseMultipartForm(maxBytes + 1024*1024); err != nil && !strings.Contains(err.Error(), "request Content-Type isn't multipart/form-data") {
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

	mime, first, err := detectUploadMime(file, header)
	if err != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件上传失败"})
		return "", false
	}
	if len(allowedMimes) > 0 && mime != "" && !mimeAllowed(mime, allowedMimes, header.Filename) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "不支持的文件类型"})
		return "", false
	}
	ext := uploadExt(mime, header.Filename, allowedMimes)
	name := fmt.Sprintf("%s_%s_%d.%s", namePrefix, randomHex(6), time.Now().Unix(), ext)
	dest := filepath.Join(absoluteDir, name)
	out, err := os.OpenFile(dest, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0664)
	if err != nil {
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "文件保存失败"})
		return "", false
	}
	defer out.Close()
	if len(first) > 0 {
		if _, err := out.Write(first); err != nil {
			c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "文件保存失败"})
			return "", false
		}
	}
	if _, err := io.Copy(out, file); err != nil {
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "文件保存失败"})
		return "", false
	}
	return strings.TrimRight(publicPrefix, "/") + "/" + name, true
}

func detectUploadMime(file multipart.File, header *multipart.FileHeader) (string, []byte, error) {
	buf := make([]byte, 512)
	n, err := file.Read(buf)
	if err != nil && err != io.EOF {
		return "", nil, err
	}
	first := buf[:n]
	mime := ""
	if n > 0 {
		mime = http.DetectContentType(first)
	}
	if mime == "application/octet-stream" || mime == "text/plain; charset=utf-8" {
		mime = header.Header.Get("Content-Type")
	}
	return mime, first, nil
}

func mimeAllowed(mime string, allowed []string, filename string) bool {
	for _, item := range allowed {
		if strings.EqualFold(item, mime) {
			return true
		}
	}
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(filename), "."))
	if ext != "" {
		for _, item := range allowed {
			if uploadExt(item, filename, nil) == ext {
				return true
			}
		}
	}
	return false
}

func uploadExt(mime, filename string, allowed []string) string {
	mapping := map[string]string{
		"image/jpeg": "jpg", "image/png": "png", "image/gif": "gif", "image/webp": "webp", "image/bmp": "bmp",
		"audio/webm": "webm", "video/webm": "webm", "audio/ogg": "ogg", "application/ogg": "ogg", "audio/opus": "opus",
		"audio/mpeg": "mp3", "audio/mp3": "mp3", "audio/wav": "wav", "audio/x-wav": "wav", "audio/wave": "wav", "audio/vnd.wave": "wav",
		"audio/mp4": "m4a", "audio/m4a": "m4a", "audio/x-m4a": "m4a", "video/mp4": "m4a", "audio/aac": "aac", "audio/aacp": "aac",
		"audio/3gpp": "3gp", "audio/3gpp2": "3g2", "video/3gpp": "3gp", "video/3gpp2": "3g2", "audio/amr": "amr", "audio/x-amr": "amr",
		"audio/flac": "flac", "audio/x-flac": "flac", "audio/x-caf": "caf", "audio/caf": "caf", "audio/aiff": "aiff", "audio/x-aiff": "aiff",
	}
	if ext := mapping[strings.ToLower(mime)]; ext != "" {
		return ext
	}
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(filename), "."))
	if regexp.MustCompile(`^[a-z0-9]{1,8}$`).MatchString(ext) {
		return ext
	}
	if len(allowed) > 0 && strings.HasPrefix(allowed[0], "audio/") {
		return "webm"
	}
	return "jpg"
}

func randomHex(n int) string {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		panic(err)
	}
	return hex.EncodeToString(buf)
}

func normalizeMessageRow(a *App, row Row, myUID int64, extra map[string]any) map[string]any {
	content := str(row, "content")
	imageURL := str(row, "image_url")
	voiceURL := str(row, "voice_url")
	msgType := intval(row, "msg_type")
	if msgType == 0 {
		switch {
		case imageURL != "":
			msgType = 2
		case voiceURL != "":
			msgType = 3
		default:
			msgType = 1
		}
	}
	recallStatus := intval(row, "was_replied")
	if recallStatus == 0 {
		recallStatus = intval(row, "is_recalled")
	}
	createdAt := intval(row, "created_at")
	addTime := str(row, "add_time")
	if createdAt <= 0 && addTime != "" {
		createdAt = parseUTCDateTime(addTime)
	}
	isoTime := addTime
	if createdAt > 0 {
		isoTime = time.Unix(createdAt, 0).UTC().Format(time.RFC3339)
	}
	memberLevel := intval(row, "member_level")
	if memberLevel <= 0 {
		memberLevel = intval(row, "level")
	}
	if memberLevel <= 0 {
		memberLevel = 1
	}
	memberTitle := str(row, "member_title")
	if memberTitle == "" {
		memberTitle = str(row, "title")
	}
	if memberTitle == "" {
		memberTitle = groupDefaultTitle(memberLevel)
	}
	normalized := map[string]any{
		"id": intval(row, "id"), "uid": nullableInt(row, "uid"), "from_uid": nullableInt(row, "from_uid"), "to_uid": nullableInt(row, "to_uid"),
		"nickname": str(row, "nickname"), "username": str(row, "username"), "content": content, "msg_type": msgType,
		"image_url": imageURL, "voice_url": voiceURL, "duration": intval(row, "duration"), "voice_duration": intval(row, "voice_duration"),
		"add_time": isoTime, "created_at": createdAt, "avatar": avatarOrDefault(a, str(row, "avatar")), "member_title": memberTitle, "member_level": memberLevel,
		"is_recalled": intval(row, "is_recalled"), "was_replied": recallStatus, "recall_status": recallStatus, "is_read": intval(row, "is_read"),
		"reply_to": intval(row, "reply_to"), "reply_content": str(row, "reply_content"), "reply_from_uid": intval(row, "reply_from_uid"), "reply_nickname": str(row, "reply_nickname"),
		"mention_uids": str(row, "mention_uids"),
	}
	if msgType == 2 && normalized["image_url"] == "" && content != "" {
		normalized["image_url"] = content
	}
	if msgType == 3 && normalized["voice_url"] == "" && content != "" {
		normalized["voice_url"] = content
	}
	if msgType == 5 && content != "" {
		emoji, _ := a.fetchOne("SELECT address, full_name FROM emoji_list WHERE abbr = ?", content)
		normalized["emoji_address"] = str(emoji, "address")
		normalized["emoji_full_name"] = str(emoji, "full_name")
	}
	if recallStatus > 0 {
		normalized["is_recalled"] = int64(1)
		switch recallStatus {
		case 1:
			normalized["content"] = "消息已被发送者撤回"
		case 2:
			normalized["content"] = "消息已被管理员撤回"
		case 3:
			normalized["content"] = "消息已被群主撤回"
		default:
			normalized["content"] = "消息已撤回"
		}
		normalized["image_url"] = ""
		normalized["voice_url"] = ""
		normalized["emoji_address"] = ""
		normalized["emoji_full_name"] = ""
	}
	for key, value := range extra {
		normalized[key] = value
	}
	return normalized
}

func nullableInt(row Row, key string) any {
	if row == nil {
		return nil
	}
	if _, ok := row[key]; !ok || row[key] == nil {
		return nil
	}
	return intval(row, key)
}

func avatarOrDefault(a *App, avatar string) string {
	if avatar != "" {
		return avatar
	}
	return a.config.DefaultAvatar
}

func parseUTCDateTime(value string) int64 {
	value = strings.TrimSpace(value)
	if value == "" {
		return 0
	}
	if i, err := parseIntString(value); err == nil {
		return i
	}
	layouts := []string{"2006-01-02 15:04:05", time.RFC3339, "2006-01-02T15:04:05Z07:00"}
	if strings.Contains(value, ".") {
		layouts = append([]string{"2006-01-02 15:04:05.999999", "2006-01-02 15:04:05.999999999"}, layouts...)
	}
	for _, layout := range layouts {
		if t, err := time.ParseInLocation(layout, value, time.UTC); err == nil {
			return t.Unix()
		}
	}
	return 0
}

func localDateTime(ts int64) string {
	return time.Unix(ts, 0).Format("2006-01-02 15:04:05")
}

func utcDateTime(ts int64) string {
	return time.Unix(ts, 0).UTC().Format("2006-01-02 15:04:05")
}

func sessionExtActive(c *Ctx) bool {
	if c.session != nil && c.session.SX && c.session.SE > time.Now().Unix() {
		return true
	}
	return sessionExtCookieExpiry(c) > time.Now().Unix()
}

func sessionExtExpiry(c *Ctx) int64 {
	expiry := int64(0)
	if c.session != nil && c.session.SX {
		expiry = c.session.SE
	}
	if cookie := sessionExtCookieExpiry(c); cookie > expiry {
		expiry = cookie
	}
	return expiry
}

func sessionExtCookieExpiry(c *Ctx) int64 {
	cookie, err := c.r.Cookie("csac_sx")
	if err != nil || !strings.Contains(cookie.Value, ".") {
		return 0
	}
	parts := strings.SplitN(cookie.Value, ".", 2)
	expiry, err := parseIntString(parts[0])
	if err != nil || expiry <= time.Now().Unix() {
		return 0
	}
	expected := sessionExtCookieValue(c.app, expiry)
	if hmac.Equal([]byte(expected), []byte(cookie.Value)) {
		return expiry
	}
	return 0
}

func sessionExtCookieValue(a *App, expiry int64) string {
	mac := hmac.New(sha256.New, []byte(a.config.CacheSalt))
	mac.Write([]byte(fmt.Sprintf("%d", expiry)))
	return fmt.Sprintf("%d.%s", expiry, hex.EncodeToString(mac.Sum(nil)))
}

func setSessionExtCookie(c *Ctx, expiry int64) {
	http.SetCookie(c.w, &http.Cookie{Name: "csac_sx", Value: sessionExtCookieValue(c.app, expiry), Path: "/", Expires: time.Unix(expiry, 0), HttpOnly: true, SameSite: http.SameSiteLaxMode, Secure: requestIsSecure(c.r)})
}

func clearSessionExtCookie(c *Ctx) {
	http.SetCookie(c.w, &http.Cookie{Name: "csac_sx", Value: "", Path: "/", Expires: time.Now().Add(-time.Hour), MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteLaxMode})
}

func sessionUIDFallback(c *Ctx) int64 {
	if c.session != nil && c.session.UID > 0 {
		return c.session.UID
	}
	return c.app.config.AdminUID
}

func mentioned(mentionUIDs string, uid int64) bool {
	want := fmt.Sprintf("%d", uid)
	for _, part := range strings.Split(mentionUIDs, ",") {
		if strings.TrimSpace(part) == want {
			return true
		}
	}
	return false
}

func sortedIntSet(rows []Row, key string) map[int64]bool {
	set := map[int64]bool{}
	for _, row := range rows {
		set[intval(row, key)] = true
	}
	return set
}

func limitBetween(v, min, max int64) int64 {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}

func noticeRoute(link string) string {
	link = strings.TrimSpace(link)
	if link == "" {
		return ""
	}
	if strings.HasPrefix(link, "#/") {
		return link
	}
	if idx := strings.Index(link, "/#/"); idx >= 0 {
		return "#/" + strings.TrimLeft(link[idx+3:], "/")
	}
	return ""
}

func txFetchOne(tx *sql.Tx, query string, args ...any) Row {
	row, err := fetchOne(tx, query, args...)
	if err != nil {
		return nil
	}
	return row
}

func txExec(tx *sql.Tx, query string, args ...any) int64 {
	res, err := tx.Exec(query, args...)
	if err != nil {
		panic(err)
	}
	affected, _ := res.RowsAffected()
	return affected
}

func rowListToMaps(rows []Row) []map[string]any {
	list := make([]map[string]any, 0, len(rows))
	for _, row := range rows {
		m := map[string]any{}
		keys := make([]string, 0, len(row))
		for key := range row {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			m[key] = row[key]
		}
		list = append(list, m)
	}
	return list
}
