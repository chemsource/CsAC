// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC ServerBot Framework Version 1.0.0.260614-r1

package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"regexp"
	"strings"
	"time"
)

// handleBotAPI 处理Bot的HTTP API请求
// 路由格式: /bot/api/{action}
// 认证方式: Header Authorization: Bot <token>
func (fw *BotFramework) handleBotAPI(w http.ResponseWriter, r *http.Request) {
	// CORS
	if origin := r.Header.Get("Origin"); origin != "" {
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Access-Control-Allow-Credentials", "true")
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}

	// 提取action
	path := strings.TrimPrefix(r.URL.Path, "/bot/api/")
	if path == "" {
		writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "缺少action"})
		return
	}

	// 验证Bot Token
	auth := r.Header.Get("Authorization")
	if !strings.HasPrefix(auth, "Bot ") {
		writeBotJSON(w, http.StatusUnauthorized, map[string]any{"success": false, "message": "缺少认证信息，格式: Authorization: Bot <token>"})
		return
	}
	token := strings.TrimSpace(strings.TrimPrefix(auth, "Bot "))

	botInfo, err := fw.authenticateBot(token)
	if err != nil {
		writeBotJSON(w, http.StatusUnauthorized, map[string]any{"success": false, "message": "认证失败"})
		return
	}

	botID := intval(botInfo, "id")
	botUID := intval(botInfo, "uid")

	// 速率限制
	if !fw.CheckRateLimit(botID) {
		writeBotJSON(w, http.StatusTooManyRequests, map[string]any{"success": false, "message": "请求过于频繁"})
		return
	}

	// 解析请求参数
	var params map[string]any
	if r.Method == http.MethodPost {
		contentType := r.Header.Get("Content-Type")
		if strings.Contains(contentType, "application/json") {
			_ = json.NewDecoder(r.Body).Decode(&params)
		} else {
			r.ParseForm()
			params = make(map[string]any)
			for k, v := range r.Form {
				if len(v) > 0 {
					params[k] = v[len(v)-1]
				}
			}
		}
	} else {
		params = make(map[string]any)
		for k, v := range r.URL.Query() {
			if len(v) > 0 {
				params[k] = v[len(v)-1]
			}
		}
	}
	if params == nil {
		params = make(map[string]any)
	}

	// 路由分发
	switch path {
	// ===== 基础方法 =====
	case "get_bot_id":
		writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "bot_id": botID, "uid": botUID})

	case "get_group_admin_pms":
		fw.apiGetGroupAdminPms(w, botUID, params)

	case "in_group":
		fw.apiInGroup(w, botUID, params)

	// ===== 群聊方法 =====
	case "send_group_msg":
		fw.apiSendGroupMsg(w, botUID, params)

	case "reply_group_msg":
		fw.apiReplyGroupMsg(w, botUID, params)

	case "rc_group_msg":
		fw.apiRcGroupMsg(w, botUID, params)

	case "set_group_ess":
		fw.apiSetGroupEss(w, botUID, params)

	case "unset_group_ess":
		fw.apiUnsetGroupEss(w, botUID, params)

	case "mute_group_mb":
		fw.apiMuteGroupMb(w, botUID, params)

	case "unmute_group_mb":
		fw.apiUnmuteGroupMb(w, botUID, params)

	// ===== 私聊方法 =====
	case "send_pvt_msg":
		fw.apiSendPvtMsg(w, botUID, params)

	case "reply_pvt_msg":
		fw.apiReplyPvtMsg(w, botUID, params)

	case "rc_pvt_msg":
		fw.apiRcPvtMsg(w, botUID, params)

	// ===== 通用通知方法 =====
	case "send_ntc":
		fw.apiSendNtc(w, botID, botUID, botInfo, params)

	// ===== 信息查询方法 =====
	case "get_user_info":
		fw.apiGetUserInfo(w, params)

	case "get_group_info":
		fw.apiGetGroupInfo(w, params)

	case "get_group_member_count":
		fw.apiGetGroupMemberCount(w, params)

	case "is_group_member":
		fw.apiIsGroupMember(w, params)

	// ===== Bot自身信息查询 =====
	case "get_bot_groups":
		fw.apiGetBotGroups(w, botUID)

	case "get_bot_friends":
		fw.apiGetBotFriends(w, botUID)

	// ===== 辅助与调试方法 =====
	case "log":
		fw.apiBotLog(w, botID, "log", params)

	case "err":
		fw.apiBotLog(w, botID, "error", params)

	// ===== 补充操作方法 =====
	case "send_group_image":
		fw.apiSendGroupImage(w, botUID, params)

	case "send_pvt_image":
		fw.apiSendPvtImage(w, botUID, params)

	case "leave_group":
		fw.apiLeaveGroup(w, botUID, params)

	// ===== 外部服务方法 =====
	case "http_get":
		fw.apiHttpGet(w, botID, botUID, botInfo, params)

	case "http_post":
		fw.apiHttpPost(w, botID, botUID, botInfo, params)

	// ===== v2.3.0: 群命令方法 =====
	case "get_group_commands":
		fw.apiGetGroupCommands(w, botUID, params)

	case "set_group_command":
		fw.apiSetGroupCommand(w, botUID, params)

	case "delete_group_command":
		fw.apiDeleteGroupCommand(w, botUID, params)

	default:
		writeBotJSON(w, http.StatusNotFound, map[string]any{"success": false, "message": "未知的action: " + path})
	}
}

// ===== 基础方法实现 =====

func (fw *BotFramework) apiGetGroupAdminPms(w http.ResponseWriter, botUID int64, params map[string]any) {
	roomID := toInt64(params["gid"])
	if roomID <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid"})
		return
	}
	row, err := fw.fetchOne("SELECT uid FROM chat_group_admin WHERE room_id = ? AND uid = ? LIMIT 1", roomID, botUID)
	isAdmin := err == nil && row != nil
	// 也检查是否是群主
	room, _ := fw.fetchOne("SELECT owner_uid FROM chat_room WHERE id = ? AND is_disband = 0", roomID)
	isOwner := room != nil && intval(room, "owner_uid") == botUID
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "is_admin": isAdmin || isOwner, "is_owner": isOwner})
}

func (fw *BotFramework) apiInGroup(w http.ResponseWriter, botUID int64, params map[string]any) {
	roomID := toInt64(params["gid"])
	if roomID <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid"})
		return
	}
	row, _ := fw.fetchOne("SELECT room_id FROM chat_group_user WHERE room_id = ? AND uid = ? LIMIT 1", roomID, botUID)
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "in_group": row != nil})
}

// ===== 群聊方法实现 =====

func (fw *BotFramework) apiSendGroupMsg(w http.ResponseWriter, botUID int64, params map[string]any) {
	roomID := toInt64(params["gid"])
	content, _ := params["cont"].(string)
	if roomID <= 0 || content == "" {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid或cont"})
		return
	}
	// v2.3.0: 替换群命令占位符 {{cmd:命令名}}
	content = fw.resolveGroupCommands(roomID, content)
	// 检查Bot是否在群内
	member, _ := fw.fetchOne("SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?", roomID, botUID)
	if member == nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "Bot不在该群内"})
		return
	}
	// 检查是否被禁言
	if muteUntil := intval(member, "mute_until"); muteUntil > time.Now().Unix() {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "Bot已被禁言"})
		return
	}
	// 获取Bot昵称
	user, _ := fw.fetchOne("SELECT nickname FROM chat_user WHERE id = ?", botUID)
	nickname := str(user, "nickname")
	if nickname == "" {
		nickname = "Bot"
	}
	// 插入消息
	msgID, err := fw.insertBotRow("chat_msg", map[string]any{
		"room_id":        roomID,
		"uid":            botUID,
		"nickname":       nickname,
		"content":        content,
		"msg_type":       1,
		"voice_duration": 0,
		"add_time":       time.Now().UTC().Format("2006-01-02 15:04:05"),
		"reply_to":       nil,
		"mention_uids":   "",
		"was_replied":    0,
	})
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "发送失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "msg_id": msgID})
}

func (fw *BotFramework) apiReplyGroupMsg(w http.ResponseWriter, botUID int64, params map[string]any) {
	roomID := toInt64(params["gid"])
	oriMsgID := toInt64(params["ori_msgid"])
	content, _ := params["cont"].(string)
	if roomID <= 0 || oriMsgID <= 0 || content == "" {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid、ori_msgid或cont"})
		return
	}
	// 验证原消息存在
	oriMsg, _ := fw.fetchOne("SELECT id FROM chat_msg WHERE id = ? AND room_id = ?", oriMsgID, roomID)
	if oriMsg == nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "InvalidMsg", "message": "原消息不存在"})
		return
	}
	// 检查Bot是否在群内
	member, _ := fw.fetchOne("SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?", roomID, botUID)
	if member == nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "Bot不在该群内"})
		return
	}
	if muteUntil := intval(member, "mute_until"); muteUntil > time.Now().Unix() {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "Bot已被禁言"})
		return
	}
	user, _ := fw.fetchOne("SELECT nickname FROM chat_user WHERE id = ?", botUID)
	nickname := str(user, "nickname")
	if nickname == "" {
		nickname = "Bot"
	}
	msgID, err := fw.insertBotRow("chat_msg", map[string]any{
		"room_id":        roomID,
		"uid":            botUID,
		"nickname":       nickname,
		"content":        content,
		"msg_type":       1,
		"voice_duration": 0,
		"add_time":       time.Now().UTC().Format("2006-01-02 15:04:05"),
		"reply_to":       oriMsgID,
		"mention_uids":   "",
		"was_replied":    0,
	})
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "发送失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "msg_id": msgID})
}

func (fw *BotFramework) apiRcGroupMsg(w http.ResponseWriter, botUID int64, params map[string]any) {
	roomID := toInt64(params["gid"])
	msgID := toInt64(params["msgid"])
	if roomID <= 0 || msgID <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid或msgid"})
		return
	}
	// 检查Bot是否有管理员权限
	if !fw.isGroupAdminOrOwner(roomID, botUID) {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "HnPmsDenied", "message": "缺少管理员权限"})
		return
	}
	// 验证消息存在
	msg, _ := fw.fetchOne("SELECT id FROM chat_msg WHERE id = ? AND room_id = ?", msgID, roomID)
	if msg == nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "InvalidMsg", "message": "消息不存在"})
		return
	}
	_, err := fw.exec("UPDATE chat_msg SET was_replied = 2 WHERE id = ? AND room_id = ?", msgID, roomID)
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "撤回失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "撤回成功"})
}

func (fw *BotFramework) apiSetGroupEss(w http.ResponseWriter, botUID int64, params map[string]any) {
	roomID := toInt64(params["gid"])
	msgID := toInt64(params["msgid"])
	if roomID <= 0 || msgID <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid或msgid"})
		return
	}
	if !fw.isGroupAdminOrOwner(roomID, botUID) {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "HnPmsDenied", "message": "缺少管理员权限"})
		return
	}
	// 检查消息是否存在
	msg, _ := fw.fetchOne("SELECT id FROM chat_msg WHERE id = ? AND room_id = ?", msgID, roomID)
	if msg == nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "InvalidMsg", "message": "消息不存在"})
		return
	}
	// 检查精华表是否存在
	_, err := fw.fetchOne("SELECT id FROM chat_essence WHERE msg_id = ? AND room_id = ?", msgID, roomID)
	if err == nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "该消息已是精华"})
		return
	}
	// 插入精华
	_, err = fw.insertBotRow("chat_essence", map[string]any{
		"room_id":    roomID,
		"msg_id":     msgID,
		"set_by_uid": botUID,
		"created_at": time.Now().Unix(),
	})
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "设置精华失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "设置精华成功"})
}

func (fw *BotFramework) apiUnsetGroupEss(w http.ResponseWriter, botUID int64, params map[string]any) {
	roomID := toInt64(params["gid"])
	msgID := toInt64(params["msgid"])
	if roomID <= 0 || msgID <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid或msgid"})
		return
	}
	if !fw.isGroupAdminOrOwner(roomID, botUID) {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "HnPmsDenied", "message": "缺少管理员权限"})
		return
	}
	_, err := fw.exec("DELETE FROM chat_essence WHERE msg_id = ? AND room_id = ?", msgID, roomID)
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "取消精华失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "取消精华成功"})
}

func (fw *BotFramework) apiMuteGroupMb(w http.ResponseWriter, botUID int64, params map[string]any) {
	roomID := toInt64(params["gid"])
	targetUID := toInt64(params["uid"])
	muteSeconds := toInt64(params["time"])
	if roomID <= 0 || targetUID <= 0 || muteSeconds <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid、uid或time"})
		return
	}
	if !fw.isGroupAdminOrOwner(roomID, botUID) {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "HnPmsDenied", "message": "缺少管理员权限"})
		return
	}
	muteUntil := time.Now().Unix() + muteSeconds
	_, err := fw.exec("UPDATE chat_group_user SET mute_until = ? WHERE room_id = ? AND uid = ?", muteUntil, roomID, targetUID)
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "禁言失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "禁言成功", "mute_until": muteUntil})
}

func (fw *BotFramework) apiUnmuteGroupMb(w http.ResponseWriter, botUID int64, params map[string]any) {
	roomID := toInt64(params["gid"])
	targetUID := toInt64(params["uid"])
	if roomID <= 0 || targetUID <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid或uid"})
		return
	}
	if !fw.isGroupAdminOrOwner(roomID, botUID) {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "HnPmsDenied", "message": "缺少管理员权限"})
		return
	}
	_, err := fw.exec("UPDATE chat_group_user SET mute_until = 0 WHERE room_id = ? AND uid = ?", roomID, targetUID)
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "取消禁言失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "取消禁言成功"})
}

// ===== 私聊方法实现 =====

func (fw *BotFramework) apiSendPvtMsg(w http.ResponseWriter, botUID int64, params map[string]any) {
	targetUID := toInt64(params["uid"])
	content, _ := params["cont"].(string)
	if targetUID <= 0 || content == "" {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数uid或cont"})
		return
	}
	// 检查是否是好友
	rel, _ := fw.fetchOne("SELECT status FROM friend_relation WHERE (uid1 = ? AND uid2 = ?) OR (uid1 = ? AND uid2 = ?)",
		min64(botUID, targetUID), max64(botUID, targetUID), max64(botUID, targetUID), min64(botUID, targetUID))
	if rel == nil || intval(rel, "status") != 1 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "Bot与目标用户不是好友"})
		return
	}
	msgID, err := fw.insertBotRow("private_msg", map[string]any{
		"from_uid":    botUID,
		"to_uid":      targetUID,
		"content":     content,
		"type":        "private",
		"room_id":     0,
		"created_at":  time.Now().Unix(),
		"is_read":     0,
		"msg_type":    1,
		"is_recalled": 0,
		"reply_to":    nil,
	})
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "发送失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "msg_id": msgID})
}

func (fw *BotFramework) apiReplyPvtMsg(w http.ResponseWriter, botUID int64, params map[string]any) {
	targetUID := toInt64(params["uid"])
	oriMsgID := toInt64(params["ori_msgid"])
	content, _ := params["cont"].(string)
	if targetUID <= 0 || oriMsgID <= 0 || content == "" {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数uid、ori_msgid或cont"})
		return
	}
	// 验证原消息
	oriMsg, _ := fw.fetchOne("SELECT id FROM private_msg WHERE id = ? AND ((from_uid = ? AND to_uid = ?) OR (from_uid = ? AND to_uid = ?))",
		oriMsgID, botUID, targetUID, targetUID, botUID)
	if oriMsg == nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "InvalidMsg", "message": "原消息不存在"})
		return
	}
	msgID, err := fw.insertBotRow("private_msg", map[string]any{
		"from_uid":    botUID,
		"to_uid":      targetUID,
		"content":     content,
		"type":        "private",
		"room_id":     0,
		"created_at":  time.Now().Unix(),
		"is_read":     0,
		"msg_type":    1,
		"is_recalled": 0,
		"reply_to":    oriMsgID,
	})
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "发送失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "msg_id": msgID})
}

func (fw *BotFramework) apiRcPvtMsg(w http.ResponseWriter, botUID int64, params map[string]any) {
	targetUID := toInt64(params["uid"])
	msgID := toInt64(params["msgid"])
	if targetUID <= 0 || msgID <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数uid或msgid"})
		return
	}
	// 只能撤回Bot自己发的消息
	msg, _ := fw.fetchOne("SELECT id FROM private_msg WHERE id = ? AND from_uid = ? AND to_uid = ? AND is_recalled = 0", msgID, botUID, targetUID)
	if msg == nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "InvalidMsg", "message": "消息不存在或不允许操作"})
		return
	}
	_, err := fw.exec("UPDATE private_msg SET is_recalled = 1 WHERE id = ?", msgID)
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "撤回失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "撤回成功"})
}

// ===== 通知方法实现 =====

func (fw *BotFramework) apiSendNtc(w http.ResponseWriter, botID, botUID int64, botInfo map[string]any, params map[string]any) {
	targetUID := toInt64(params["uid"])
	title, _ := params["title"].(string)
	content, _ := params["cont"].(string)
	if targetUID <= 0 || title == "" || content == "" {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数uid、title或cont"})
		return
	}
	// 检查通知权限
	if intval(botInfo, "can_notify") != 1 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "NtcNAuth", "message": "未获得通知权限"})
		return
	}
	_, err := fw.insertBotRow("chat_user_notice", map[string]any{
		"uid":      targetUID,
		"title":    title,
		"content":  content,
		"is_read":  0,
		"add_time": time.Now().UTC().Format("2006-01-02 15:04:05"),
	})
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "发送通知失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "通知已发送"})
}

// ===== 信息查询方法实现 =====

func (fw *BotFramework) apiGetUserInfo(w http.ResponseWriter, params map[string]any) {
	uid := toInt64(params["uid"])
	if uid <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数uid"})
		return
	}
	user, err := fw.fetchOne("SELECT id, nickname, username, avatar, email, platform, last_active FROM chat_user WHERE id = ?", uid)
	if err != nil || user == nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "用户不存在"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{
		"success": true,
		"data": map[string]any{
			"uid":         intval(user, "id"),
			"nickname":    str(user, "nickname"),
			"username":    str(user, "username"),
			"avatar":      str(user, "avatar"),
			"platform":    str(user, "platform"),
			"last_active": intval(user, "last_active"),
		},
	})
}

func (fw *BotFramework) apiGetGroupInfo(w http.ResponseWriter, params map[string]any) {
	gid := toInt64(params["gid"])
	if gid <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid"})
		return
	}
	room, err := fw.fetchOne("SELECT id, room_name, owner_uid, invite_code, avatar, is_disband FROM chat_room WHERE id = ?", gid)
	if err != nil || room == nil || intval(room, "is_disband") != 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "群不存在"})
		return
	}
	// 获取成员数
	var memberCount int64
	fw.db.QueryRow("SELECT COUNT(*) FROM chat_group_user WHERE room_id = ?", gid).Scan(&memberCount)
	writeBotJSON(w, http.StatusOK, map[string]any{
		"success": true,
		"data": map[string]any{
			"gid":          intval(room, "id"),
			"room_name":    str(room, "room_name"),
			"owner_uid":    intval(room, "owner_uid"),
			"invite_code":  str(room, "invite_code"),
			"avatar":       str(room, "avatar"),
			"member_count": memberCount,
		},
	})
}

func (fw *BotFramework) apiGetGroupMemberCount(w http.ResponseWriter, params map[string]any) {
	gid := toInt64(params["gid"])
	if gid <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid"})
		return
	}
	var count int64
	fw.db.QueryRow("SELECT COUNT(*) FROM chat_group_user WHERE room_id = ?", gid).Scan(&count)
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "count": count})
}

func (fw *BotFramework) apiIsGroupMember(w http.ResponseWriter, params map[string]any) {
	gid := toInt64(params["gid"])
	uid := toInt64(params["uid"])
	if gid <= 0 || uid <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid或uid"})
		return
	}
	row, _ := fw.fetchOne("SELECT room_id FROM chat_group_user WHERE room_id = ? AND uid = ? LIMIT 1", gid, uid)
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "is_member": row != nil})
}

// ===== 辅助与调试方法实现 =====

func (fw *BotFramework) apiBotLog(w http.ResponseWriter, botID int64, level string, params map[string]any) {
	content, _ := params["cont"].(string)
	if content == "" {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数cont"})
		return
	}
	_, _ = fw.insertBotRow("bot_logs", map[string]any{
		"bot_id":     botID,
		"level":      level,
		"content":    content,
		"created_at": time.Now().Unix(),
	})
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true})
}

// ===== 辅助函数 =====

func (fw *BotFramework) isGroupAdminOrOwner(roomID, uid int64) bool {
	room, _ := fw.fetchOne("SELECT owner_uid FROM chat_room WHERE id = ?", roomID)
	if room != nil && intval(room, "owner_uid") == uid {
		return true
	}
	admin, _ := fw.fetchOne("SELECT uid FROM chat_group_admin WHERE room_id = ? AND uid = ? LIMIT 1", roomID, uid)
	return admin != nil
}

// insertBotRow 插入数据行
func (fw *BotFramework) insertBotRow(table string, data map[string]any) (int64, error) {
	if !safeIdent.MatchString(table) {
		return 0, fmt.Errorf("invalid table name")
	}
	names := make([]string, 0, len(data))
	values := make([]any, 0, len(data))
	placeholders := make([]string, 0, len(data))
	for k, v := range data {
		if !safeIdent.MatchString(k) {
			continue
		}
		names = append(names, k)
		values = append(values, v)
		placeholders = append(placeholders, "?")
	}
	query := fmt.Sprintf("INSERT INTO `%s` (`%s`) VALUES (%s)",
		table, strings.Join(names, "`, `"), strings.Join(placeholders, ", "))
	res, err := fw.db.Exec(query, values...)
	if err != nil {
		log.Printf("ServerBot: insert into %s failed: %v", table, err)
		return 0, err
	}
	id, _ := res.LastInsertId()
	return id, nil
}

func writeBotJSON(w http.ResponseWriter, status int, data map[string]any) {
	payload, _ := json.Marshal(data)
	w.WriteHeader(status)
	_, _ = w.Write(payload)
}

func min64(a, b int64) int64 {
	if a < b {
		return a
	}
	return b
}

func max64(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}

// ===== 补充操作方法实现 =====

func (fw *BotFramework) apiSendGroupImage(w http.ResponseWriter, botUID int64, params map[string]any) {
	roomID := toInt64(params["gid"])
	imageURL, _ := params["url"].(string)
	if roomID <= 0 || imageURL == "" {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid或url"})
		return
	}
	member, _ := fw.fetchOne("SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?", roomID, botUID)
	if member == nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "Bot不在该群内"})
		return
	}
	if muteUntil := intval(member, "mute_until"); muteUntil > time.Now().Unix() {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "Bot已被禁言"})
		return
	}
	user, _ := fw.fetchOne("SELECT nickname FROM chat_user WHERE id = ?", botUID)
	nickname := str(user, "nickname")
	if nickname == "" {
		nickname = "Bot"
	}
	msgID, err := fw.insertBotRow("chat_msg", map[string]any{
		"room_id":        roomID,
		"uid":            botUID,
		"nickname":       nickname,
		"content":        imageURL,
		"msg_type":       2,
		"voice_duration": 0,
		"add_time":       time.Now().UTC().Format("2006-01-02 15:04:05"),
		"reply_to":       nil,
		"mention_uids":   "",
		"was_replied":    0,
	})
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "发送图片失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "msg_id": msgID})
}

func (fw *BotFramework) apiSendPvtImage(w http.ResponseWriter, botUID int64, params map[string]any) {
	targetUID := toInt64(params["uid"])
	imageURL, _ := params["url"].(string)
	if targetUID <= 0 || imageURL == "" {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数uid或url"})
		return
	}
	rel, _ := fw.fetchOne("SELECT status FROM friend_relation WHERE (uid1 = ? AND uid2 = ?) OR (uid1 = ? AND uid2 = ?)",
		min64(botUID, targetUID), max64(botUID, targetUID), max64(botUID, targetUID), min64(botUID, targetUID))
	if rel == nil || intval(rel, "status") != 1 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "Bot与目标用户不是好友"})
		return
	}
	msgID, err := fw.insertBotRow("private_msg", map[string]any{
		"from_uid":    botUID,
		"to_uid":      targetUID,
		"content":     "[图片]",
		"type":        "private",
		"room_id":     0,
		"created_at":  time.Now().Unix(),
		"is_read":     0,
		"image_url":   imageURL,
		"msg_type":    2,
		"is_recalled": 0,
		"reply_to":    nil,
	})
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "发送图片失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "msg_id": msgID})
}

func (fw *BotFramework) apiLeaveGroup(w http.ResponseWriter, botUID int64, params map[string]any) {
	roomID := toInt64(params["gid"])
	if roomID <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid"})
		return
	}
	member, _ := fw.fetchOne("SELECT room_id FROM chat_group_user WHERE room_id = ? AND uid = ?", roomID, botUID)
	if member == nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "Bot不在该群内"})
		return
	}
	_, err := fw.exec("DELETE FROM chat_group_user WHERE room_id = ? AND uid = ?", roomID, botUID)
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "退群失败"})
		return
	}
	// 如果Bot是群主，解散群聊
	room, _ := fw.fetchOne("SELECT owner_uid FROM chat_room WHERE id = ? AND is_disband = 0", roomID)
	if room != nil && intval(room, "owner_uid") == botUID {
		_, _ = fw.exec("UPDATE chat_room SET is_disband = 1 WHERE id = ?", roomID)
		_, _ = fw.exec("DELETE FROM chat_group_user WHERE room_id = ?", roomID)
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "已退群"})
}

// ===== 外部服务方法实现 =====

func (fw *BotFramework) apiHttpGet(w http.ResponseWriter, botID, botUID int64, botInfo map[string]any, params map[string]any) {
	url, _ := params["url"].(string)
	if url == "" {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数url"})
		return
	}
	if intval(botInfo, "can_http") != 1 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "HnPmsDenied", "message": "未获得HTTP请求权限"})
		return
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "请求失败: " + err.Error()})
		return
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "读取响应失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{
		"success":      true,
		"status":       resp.StatusCode,
		"body":         string(body),
		"content_type": resp.Header.Get("Content-Type"),
	})
}

func (fw *BotFramework) apiHttpPost(w http.ResponseWriter, botID, botUID int64, botInfo map[string]any, params map[string]any) {
	url, _ := params["url"].(string)
	bodyStr, _ := params["body"].(string)
	contentType, _ := params["content_type"].(string)
	if contentType == "" {
		contentType = "application/json"
	}
	if url == "" {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数url"})
		return
	}
	if intval(botInfo, "can_http") != 1 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "HnPmsDenied", "message": "未获得HTTP请求权限"})
		return
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Post(url, contentType, strings.NewReader(bodyStr))
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "请求失败: " + err.Error()})
		return
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "读取响应失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{
		"success":      true,
		"status":       resp.StatusCode,
		"body":         string(body),
		"content_type": resp.Header.Get("Content-Type"),
	})
}

// ===== Bot自身信息查询方法实现 =====

func (fw *BotFramework) apiGetBotGroups(w http.ResponseWriter, botUID int64) {
	rows, err := fw.db.Query(
		"SELECT r.id, r.room_name, r.owner_uid, r.avatar FROM chat_group_user gu JOIN chat_room r ON gu.room_id = r.id WHERE gu.uid = ? AND r.is_disband = 0",
		botUID)
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	defer rows.Close()

	var groups []map[string]any
	for rows.Next() {
		var id, ownerUID int64
		var roomName, avatar string
		if err := rows.Scan(&id, &roomName, &ownerUID, &avatar); err != nil {
			continue
		}
		groups = append(groups, map[string]any{
			"room_id":   id,
			"room_name": roomName,
			"owner_uid": ownerUID,
			"avatar":    avatar,
		})
	}
	if groups == nil {
		groups = []map[string]any{}
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "groups": groups})
}

func (fw *BotFramework) apiGetBotFriends(w http.ResponseWriter, botUID int64) {
	rows, err := fw.db.Query(
		"SELECT u.id, u.nickname, u.username, u.avatar FROM friend_relation fr JOIN chat_user u ON (CASE WHEN fr.uid1 = ? THEN fr.uid2 ELSE fr.uid1 END) = u.id WHERE (fr.uid1 = ? OR fr.uid2 = ?) AND fr.status = 1",
		botUID, botUID, botUID)
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	defer rows.Close()

	var friends []map[string]any
	for rows.Next() {
		var id int64
		var nickname, username, avatar string
		if err := rows.Scan(&id, &nickname, &username, &avatar); err != nil {
			continue
		}
		friends = append(friends, map[string]any{
			"uid":      id,
			"nickname": nickname,
			"username": username,
			"avatar":   avatar,
		})
	}
	if friends == nil {
		friends = []map[string]any{}
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "friends": friends})
}

// ===== v2.2.1: JSLibs 库管理 API =====

// handleLibAPI 处理内部库管理请求
// 路由格式: /bot/internal/lib/{action}
// 认证方式: Header X-Bot-Secret
func (fw *BotFramework) handleLibAPI(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	// 验证内部密钥
	secret := r.Header.Get("X-Bot-Secret")
	if secret == "" {
		secret = r.URL.Query().Get("secret")
	}
	if secret != fw.config.BotSecret {
		writeBotJSON(w, http.StatusUnauthorized, map[string]any{"success": false, "message": "认证失败"})
		return
	}

	action := strings.TrimPrefix(r.URL.Path, "/bot/internal/lib/")
	if action == "" {
		writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "缺少action"})
		return
	}

	switch action {
	case "list":
		libs := globalLibManager.ListLibs()
		// 不返回 content 字段
		result := make([]map[string]any, 0, len(libs))
		for _, lib := range libs {
			result = append(result, map[string]any{
				"name":    lib.Name,
				"version": lib.Version,
				"author":  lib.Author,
				"desc":    lib.Desc,
			})
		}
		writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "libs": result})

	case "get":
		name := r.URL.Query().Get("name")
		if name == "" {
			writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "缺少name参数"})
			return
		}
		lib, ok := globalLibManager.GetLib(name)
		if !ok {
			writeBotJSON(w, http.StatusNotFound, map[string]any{"success": false, "message": "库不存在"})
			return
		}
		writeBotJSON(w, http.StatusOK, map[string]any{
			"success": true,
			"lib": map[string]any{
				"name":    lib.Name,
				"version": lib.Version,
				"content": lib.Content,
				"author":  lib.Author,
				"desc":    lib.Desc,
			},
		})

	case "reload":
		globalLibManager.Reload()
		writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "库已重新加载"})

	// ===== v2.2.1: 库上传与审核 =====

	case "upload":
		fw.apiLibUpload(w, r)

	case "pending":
		fw.apiLibPending(w, r)

	case "review":
		fw.apiLibReview(w, r)

	case "my_libs":
		fw.apiLibMyLibs(w, r)

	case "approve":
		fw.apiLibApprove(w, r)

	default:
		writeBotJSON(w, http.StatusNotFound, map[string]any{"success": false, "message": "未知的action: " + action})
	}
}

// apiLibUpload 开发者上传库（需 allow_ajl_upload 权限）
func (fw *BotFramework) apiLibUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeBotJSON(w, http.StatusMethodNotAllowed, map[string]any{"success": false, "message": "仅支持POST"})
		return
	}
	devIDStr := r.URL.Query().Get("dev_id")
	if devIDStr == "" {
		writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "缺少dev_id参数"})
		return
	}
	var devID int64
	fmt.Sscanf(devIDStr, "%d", &devID)
	if devID <= 0 {
		writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "dev_id无效"})
		return
	}

	// 检查开发者是否有上传权限
	dev, _ := fw.fetchOne("SELECT id, allow_ajl_upload, status FROM open_dev_accounts WHERE id = ?", devID)
	if dev == nil {
		writeBotJSON(w, http.StatusForbidden, map[string]any{"success": false, "message": "开发者账号不存在"})
		return
	}
	if intval(dev, "status") != 1 {
		writeBotJSON(w, http.StatusForbidden, map[string]any{"success": false, "message": "开发者账号已被封禁"})
		return
	}
	if intval(dev, "allow_ajl_upload") != 1 {
		writeBotJSON(w, http.StatusForbidden, map[string]any{"success": false, "message": "未获得AJL库上传权限，请联系管理员申请"})
		return
	}

	// 解析上传内容
	var req struct {
		Name    string `json:"name"`
		Version string `json:"version"`
		Content string `json:"content"`
		Author  string `json:"author"`
		Desc    string `json:"desc"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "请求体解析失败"})
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	req.Version = strings.TrimSpace(req.Version)
	req.Content = strings.TrimSpace(req.Content)
	if req.Name == "" || req.Content == "" {
		writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "库名和内容不能为空"})
		return
	}
	if req.Version == "" {
		req.Version = "1.0.0"
	}
	// 限制库名格式
	if !regexp.MustCompile(`^[a-zA-Z][a-zA-Z0-9_-]{0,49}$`).MatchString(req.Name) {
		writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "库名格式无效：需以字母开头，仅允许字母数字下划线连字符，最长50字符"})
		return
	}
	// 限制内容大小 512KB
	if len(req.Content) > 512*1024 {
		writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "库内容超过512KB限制"})
		return
	}

	// 检查是否已存在同名同版本
	existing, _ := fw.fetchOne("SELECT id, status FROM bot_libs WHERE name = ? AND version = ?", req.Name, req.Version)
	if existing != nil {
		writeBotJSON(w, http.StatusConflict, map[string]any{"success": false, "message": "该库版本已存在"})
		return
	}

	// 生成签名
	ajl := &AJLFile{Name: req.Name, Version: req.Version, Content: req.Content, Author: req.Author, Desc: req.Desc}
	signature := generateAJLSignature(ajl, fw.config.BotSecret)

	now := time.Now().Unix()
	_, err := fw.exec(
		"INSERT INTO bot_libs (name, version, content, signature, author, `desc`, dev_id, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)",
		req.Name, req.Version, req.Content, signature, req.Author, req.Desc, devID, now,
	)
	if err != nil {
		writeBotJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": "上传失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "库已提交，等待管理员审核"})
}

// apiLibPending 获取待审核库列表
func (fw *BotFramework) apiLibPending(w http.ResponseWriter, r *http.Request) {
	rows, err := fw.fetchAll("SELECT l.id, l.name, l.version, l.author, l.`desc`, l.dev_id, l.created_at, d.dev_name FROM bot_libs l JOIN open_dev_accounts d ON l.dev_id = d.id WHERE l.status = 0 ORDER BY l.created_at ASC")
	if err != nil {
		writeBotJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	result := make([]map[string]any, 0, len(rows))
	for _, row := range rows {
		result = append(result, map[string]any{
			"id":         intval(row, "id"),
			"name":       str(row, "name"),
			"version":    str(row, "version"),
			"author":     str(row, "author"),
			"desc":       str(row, "desc"),
			"dev_id":     intval(row, "dev_id"),
			"dev_name":   str(row, "dev_name"),
			"created_at": intval(row, "created_at"),
		})
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "libs": result})
}

// apiLibReview 管理员审核库（通过/拒绝）
func (fw *BotFramework) apiLibReview(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeBotJSON(w, http.StatusMethodNotAllowed, map[string]any{"success": false, "message": "仅支持POST"})
		return
	}
	var req struct {
		ID        int64  `json:"id"`
		Action    string `json:"action"` // "approve" 或 "reject"
		AdminNote string `json:"admin_note"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "请求体解析失败"})
		return
	}
	if req.ID <= 0 || (req.Action != "approve" && req.Action != "reject") {
		writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "参数无效"})
		return
	}

	lib, _ := fw.fetchOne("SELECT id, name, version, content, signature, author, `desc`, status FROM bot_libs WHERE id = ?", req.ID)
	if lib == nil {
		writeBotJSON(w, http.StatusNotFound, map[string]any{"success": false, "message": "库不存在"})
		return
	}
	if intval(lib, "status") != 0 {
		writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "该库已被审核"})
		return
	}

	now := time.Now().Unix()
	if req.Action == "approve" {
		// 更新审核状态
		_, err := fw.exec("UPDATE bot_libs SET status = 1, reviewed_at = ?, admin_note = ? WHERE id = ?", now, req.AdminNote, req.ID)
		if err != nil {
			writeBotJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": "审核失败"})
			return
		}
		// 保存到磁盘并加载到内存
		ajl := &AJLFile{
			Name:    str(lib, "name"),
			Version: str(lib, "version"),
			Content: str(lib, "content"),
			Author:  str(lib, "author"),
			Desc:    str(lib, "desc"),
		}
		// 使用已有的签名
		ajl.Signature = str(lib, "signature")
		if err := globalLibManager.SaveLib(ajl); err != nil {
			log.Printf("[JSLibs] 审核通过但保存库失败: %v", err)
			writeBotJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": "保存库文件失败"})
			return
		}
		writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "库已审核通过并发布"})
	} else {
		_, err := fw.exec("UPDATE bot_libs SET status = 2, reviewed_at = ?, admin_note = ? WHERE id = ?", now, req.AdminNote, req.ID)
		if err != nil {
			writeBotJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": "审核失败"})
			return
		}
		writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "库已拒绝"})
	}
}

// apiLibMyLibs 获取开发者自己上传的库列表
func (fw *BotFramework) apiLibMyLibs(w http.ResponseWriter, r *http.Request) {
	devIDStr := r.URL.Query().Get("dev_id")
	if devIDStr == "" {
		writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "缺少dev_id参数"})
		return
	}
	var devID int64
	fmt.Sscanf(devIDStr, "%d", &devID)

	rows, err := fw.fetchAll("SELECT id, name, version, author, `desc`, status, admin_note, created_at, reviewed_at FROM bot_libs WHERE dev_id = ? ORDER BY created_at DESC", devID)
	if err != nil {
		writeBotJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	result := make([]map[string]any, 0, len(rows))
	statusMap := map[int64]string{0: "pending", 1: "approved", 2: "rejected"}
	for _, row := range rows {
		status := intval(row, "status")
		result = append(result, map[string]any{
			"id":          intval(row, "id"),
			"name":        str(row, "name"),
			"version":     str(row, "version"),
			"author":      str(row, "author"),
			"desc":        str(row, "desc"),
			"status":      statusMap[status],
			"admin_note":  str(row, "admin_note"),
			"created_at":  intval(row, "created_at"),
			"reviewed_at": intval(row, "reviewed_at"),
		})
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "libs": result})
}

// apiLibApprove ACOP通知ServerBot审核通过了一个库，ServerBot签名并保存到磁盘
func (fw *BotFramework) apiLibApprove(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeBotJSON(w, http.StatusMethodNotAllowed, map[string]any{"success": false, "message": "仅支持POST"})
		return
	}
	var req struct {
		ID      int64  `json:"id"`
		Name    string `json:"name"`
		Version string `json:"version"`
		Content string `json:"content"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "请求体解析失败"})
		return
	}
	if req.Name == "" || req.Content == "" {
		writeBotJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "库名和内容不能为空"})
		return
	}

	// 生成签名并保存到磁盘
	ajl := &AJLFile{Name: req.Name, Version: req.Version, Content: req.Content}
	if err := globalLibManager.SaveLib(ajl); err != nil {
		log.Printf("[JSLibs] ACOP审核通知但保存库失败: %v", err)
		writeBotJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": "保存库文件失败"})
		return
	}

	// 更新数据库中的签名
	_, _ = fw.exec("UPDATE bot_libs SET signature = ? WHERE id = ?", ajl.Signature, req.ID)

	log.Printf("[JSLibs] ACOP审核通知：库 %s v%s 已保存到磁盘", req.Name, req.Version)
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "库已保存到磁盘"})
}

// ===== v2.3.0: 群命令功能 =====

// resolveGroupCommands 替换内容中的 {{cmd:命令名}} 占位符为群配置的消息内容
func (fw *BotFramework) resolveGroupCommands(roomID int64, content string) string {
	if !strings.Contains(content, "{{cmd:") {
		return content
	}
	// 预加载该群所有命令
	cmds, err := fw.fetchAll("SELECT command, content FROM group_commands WHERE room_id = ?", roomID)
	if err != nil || len(cmds) == 0 {
		return content
	}
	cmdMap := make(map[string]string, len(cmds))
	for _, cmd := range cmds {
		cmdMap[str(cmd, "command")] = str(cmd, "content")
	}
	// 替换所有 {{cmd:xxx}} 占位符
	for cmdName, cmdContent := range cmdMap {
		placeholder := "{{cmd:" + cmdName + "}}"
		content = strings.ReplaceAll(content, placeholder, cmdContent)
	}
	return content
}

// apiGetGroupCommands 获取群命令列表
func (fw *BotFramework) apiGetGroupCommands(w http.ResponseWriter, botUID int64, params map[string]any) {
	roomID := toInt64(params["gid"])
	if roomID <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid"})
		return
	}
	rows, err := fw.fetchAll("SELECT id, command, content, created_by, created_at FROM group_commands WHERE room_id = ? ORDER BY command", roomID)
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	commands := make([]map[string]any, 0, len(rows))
	for _, row := range rows {
		commands = append(commands, map[string]any{
			"id":         intval(row, "id"),
			"command":    str(row, "command"),
			"content":    str(row, "content"),
			"created_by": intval(row, "created_by"),
			"created_at": intval(row, "created_at"),
		})
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "commands": commands})
}

// apiSetGroupCommand 设置群命令（群主/管理员操作）
func (fw *BotFramework) apiSetGroupCommand(w http.ResponseWriter, botUID int64, params map[string]any) {
	roomID := toInt64(params["gid"])
	command, _ := params["command"].(string)
	content, _ := params["cont"].(string)
	if roomID <= 0 || command == "" || content == "" {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid、command或cont"})
		return
	}
	command = strings.TrimSpace(command)
	if len(command) > 100 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "命令名过长（最多100字符）"})
		return
	}
	// 验证Bot有管理员权限
	if !fw.isGroupAdminOrOwner(roomID, botUID) {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "HnPmsDenied", "message": "需要群主或管理员权限"})
		return
	}
	now := time.Now().Unix()
	// 使用 INSERT ... ON DUPLICATE KEY UPDATE 实现插入或更新
	_, err := fw.db.Exec(
		"INSERT INTO group_commands (room_id, command, content, created_by, created_at) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE content = VALUES(content), created_by = VALUES(created_by), created_at = VALUES(created_at)",
		roomID, command, content, botUID, now,
	)
	if err != nil {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "设置命令失败"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "命令已设置"})
}

// apiDeleteGroupCommand 删除群命令（群主/管理员操作）
func (fw *BotFramework) apiDeleteGroupCommand(w http.ResponseWriter, botUID int64, params map[string]any) {
	roomID := toInt64(params["gid"])
	command, _ := params["command"].(string)
	cmdID := toInt64(params["cmd_id"])
	if roomID <= 0 {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数gid"})
		return
	}
	if !fw.isGroupAdminOrOwner(roomID, botUID) {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "HnPmsDenied", "message": "需要群主或管理员权限"})
		return
	}
	if cmdID > 0 {
		_, err := fw.exec("DELETE FROM group_commands WHERE id = ? AND room_id = ?", cmdID, roomID)
		if err != nil {
			writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "删除失败"})
			return
		}
	} else if command != "" {
		_, err := fw.exec("DELETE FROM group_commands WHERE command = ? AND room_id = ?", command, roomID)
		if err != nil {
			writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "message": "删除失败"})
			return
		}
	} else {
		writeBotJSON(w, http.StatusOK, map[string]any{"success": false, "error": "ArgErr", "message": "缺少参数command或cmd_id"})
		return
	}
	writeBotJSON(w, http.StatusOK, map[string]any{"success": true, "message": "命令已删除"})
}
