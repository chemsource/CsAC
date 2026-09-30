// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC ServerBot Framework Version 1.0.0.260614-r1

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"
)

// handleInternalEvent 处理主服务器推送的内部事件
// 主服务器在收到群消息/私聊消息后，调用此端点将事件转发给Bot框架
// 需要验证 BotSecret 以确保是主服务器调用
func (fw *BotFramework) handleInternalEvent(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"success":false,"message":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	// 验证内部调用密钥
	secret := r.Header.Get("X-Bot-Secret")
	if secret != fw.config.BotSecret {
		http.Error(w, `{"success":false,"message":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var payload map[string]any
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, `{"success":false,"message":"invalid json"}`, http.StatusBadRequest)
		return
	}

	// 兼容两种格式：
	// 1. 主服务器格式: {"event": "group_message", "payload": {...}, "timestamp": ...}
	// 2. 扁平格式: {"event_type": "group_msg", ...}
	var eventType string
	var eventData map[string]any

	if e, ok := payload["event"].(string); ok {
		// 主服务器格式
		eventType = e
		if p, ok := payload["payload"].(map[string]any); ok {
			eventData = p
		} else {
			eventData = payload
		}
	} else if et, ok := payload["event_type"].(string); ok {
		// 扁平格式
		eventType = et
		eventData = payload
	}

	switch eventType {
	case "group_message":
		fw.onGroupMessage(eventData)
	case "private_message":
		fw.onPrivateMessage(eventData)
	case "group_member_join":
		fw.onGroupJoin(eventData)
	case "group_member_leave":
		fw.onGroupMemberLeave(eventData)
	case "group_member_mute", "group_member_unmute":
		fw.onGroupMute(eventData)
	case "group_member_kick":
		fw.onGroupMemberLeave(eventData)
	case "group_disband":
		fw.onGroupDisband(eventData)
	// 兼容旧格式
	case "group_msg":
		fw.onGroupMessage(eventData)
	case "private_msg":
		fw.onPrivateMessage(eventData)
	case "group_join":
		fw.onGroupJoin(eventData)
	case "group_leave":
		fw.onGroupMemberLeave(eventData)
	case "group_mute":
		fw.onGroupMute(eventData)
	default:
		log.Printf("ServerBot: unknown internal event type: %s", eventType)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"success":true}`))
}

// onGroupMessage 处理群消息事件
func (fw *BotFramework) onGroupMessage(payload map[string]any) {
	roomID := toInt64(payload["room_id"])
	senderUID := toInt64(payload["uid"])
	msgID := toInt64(payload["msg_id"])
	content, _ := payload["content"].(string)
	msgType := toInt64(payload["msg_type"])
	nickname, _ := payload["nickname"].(string)
	replyTo := toInt64(payload["reply_to"])
	imageUrls, _ := payload["image_urls"].(string)
	timestamp := toInt64(payload["timestamp"])
	if timestamp == 0 {
		timestamp = time.Now().Unix()
	}

	event := map[string]any{
		"type":        "event:group_msg",
		"room_id":     roomID,
		"uid":         senderUID,
		"nickname":    nickname,
		"msg_id":      msgID,
		"content":     content,
		"msg_type":    msgType,
		"reply_to":    replyTo,
		"image_urls":  imageUrls,
		"timestamp":   timestamp,
		"server_time": time.Now().Unix(),
	}

	// 推送给WebSocket在线Bot
	bots := fw.GetBotsInGroup(roomID)
	for _, bot := range bots {
		if bot.UID == senderUID {
			continue
		}
		if err := fw.SendToBot(bot.BotID, event); err != nil {
			log.Printf("ServerBot: failed to push group_msg to Bot [%s]: %v", bot.BotName, err)
		}
	}

	// 调度脚本引擎执行
	if fw.scriptMgr != nil {
		fw.scriptMgr.DispatchGroupMsg(roomID, senderUID, msgID, content, nickname, msgType, replyTo, imageUrls, timestamp)
	}
}

// onPrivateMessage 处理私聊消息事件
func (fw *BotFramework) onPrivateMessage(payload map[string]any) {
	fromUID := toInt64(payload["from_uid"])
	toUID := toInt64(payload["to_uid"])
	msgID := toInt64(payload["msg_id"])
	content, _ := payload["content"].(string)
	msgType := toInt64(payload["msg_type"])
	replyTo := toInt64(payload["reply_to"])
	imageUrls, _ := payload["image_urls"].(string)
	timestamp := toInt64(payload["timestamp"])
	if timestamp == 0 {
		timestamp = time.Now().Unix()
	}

	// 判断哪个UID是Bot
	event := map[string]any{
		"type":        "event:private_msg",
		"from_uid":    fromUID,
		"to_uid":      toUID,
		"msg_id":      msgID,
		"content":     content,
		"msg_type":    msgType,
		"reply_to":    replyTo,
		"image_urls":  imageUrls,
		"timestamp":   timestamp,
		"server_time": time.Now().Unix(),
	}

	// 推送给接收者是Bot的那个（需验证好友关系）
	if bot := fw.GetBotByUID(toUID); bot != nil {
		if fw.isFriend(fromUID, toUID) {
			if err := fw.SendToBot(bot.BotID, event); err != nil {
				log.Printf("ServerBot: failed to push private_msg to Bot [%s]: %v", bot.BotName, err)
			}
		} else {
			log.Printf("ServerBot: Bot [%s] UID[%d] 与发送者 UID[%d] 非好友，跳过私聊推送", bot.BotName, toUID, fromUID)
		}
	}

	// 调度脚本引擎执行
	if fw.scriptMgr != nil {
		fw.scriptMgr.DispatchPrivateMsg(fromUID, toUID, msgID, content, msgType, replyTo, imageUrls, timestamp)
	}
}

// onGroupJoin 处理入群事件
func (fw *BotFramework) onGroupJoin(payload map[string]any) {
	roomID := toInt64(payload["room_id"])
	uid := toInt64(payload["uid"])

	event := map[string]any{
		"type":        "event:group_join",
		"room_id":     roomID,
		"uid":         uid,
		"server_time": time.Now().Unix(),
	}

	bots := fw.GetBotsInGroup(roomID)
	for _, bot := range bots {
		if bot.UID == uid {
			continue
		}
		_ = fw.SendToBot(bot.BotID, event)
	}
	// 调度脚本引擎
	if fw.scriptMgr != nil {
		fw.scriptMgr.DispatchGroupMemberJoin(roomID, uid)
	}
}

// onGroupLeave 处理退群事件
func (fw *BotFramework) onGroupMemberLeave(payload map[string]any) {
	roomID := toInt64(payload["room_id"])
	uid := toInt64(payload["uid"])

	event := map[string]any{
		"type":        "event:group_leave",
		"room_id":     roomID,
		"uid":         uid,
		"server_time": time.Now().Unix(),
	}

	bots := fw.GetBotsInGroup(roomID)
	for _, bot := range bots {
		if bot.UID == uid {
			continue
		}
		_ = fw.SendToBot(bot.BotID, event)
	}
	// 调度脚本引擎
	if fw.scriptMgr != nil {
		fw.scriptMgr.DispatchGroupMemberLeave(roomID, uid)
	}
}

// onGroupMute 处理群成员禁言事件
func (fw *BotFramework) onGroupMute(payload map[string]any) {
	roomID := toInt64(payload["room_id"])
	uid := toInt64(payload["uid"])
	operatorUID := toInt64(payload["operator_uid"])
	until := toInt64(payload["until"])

	event := map[string]any{
		"type":         "event:group_mute",
		"room_id":      roomID,
		"uid":          uid,
		"operator_uid": operatorUID,
		"until":        until,
		"server_time":  time.Now().Unix(),
	}

	bots := fw.GetBotsInGroup(roomID)
	for _, bot := range bots {
		_ = fw.SendToBot(bot.BotID, event)
	}
	if fw.scriptMgr != nil {
		fw.scriptMgr.DispatchGroupMemberMute(roomID, uid, operatorUID, until)
	}
}

// onGroupDisband 处理群解散事件
func (fw *BotFramework) onGroupDisband(payload map[string]any) {
	roomID := toInt64(payload["room_id"])
	operatorUID := toInt64(payload["operator_uid"])

	event := map[string]any{
		"type":         "event:group_disband",
		"room_id":      roomID,
		"operator_uid": operatorUID,
		"server_time":  time.Now().Unix(),
	}

	bots := fw.GetBotsInGroup(roomID)
	for _, bot := range bots {
		_ = fw.SendToBot(bot.BotID, event)
	}
	if fw.scriptMgr != nil {
		fw.scriptMgr.DispatchGroupDisband(roomID, operatorUID)
	}
}

// GetBotsInGroup 获取某个群中所有在线的Bot
func (fw *BotFramework) GetBotsInGroup(roomID int64) []*BotConn {
	// 查询该群中所有Bot的UID
	rows, err := fw.fetchAll(
		"SELECT gu.uid FROM chat_group_user gu JOIN bot_accounts ba ON gu.uid = ba.uid WHERE gu.room_id = ? AND ba.status = 1",
		roomID,
	)
	if err != nil || len(rows) == 0 {
		return nil
	}

	var result []*BotConn
	fw.botsMu.RLock()
	defer fw.botsMu.RUnlock()
	for _, row := range rows {
		uid := intval(row, "uid")
		for _, bot := range fw.bots {
			if bot.UID == uid {
				result = append(result, bot)
				break
			}
		}
	}
	return result
}

// isFriend 检查两个用户是否是好友关系
func (fw *BotFramework) isFriend(uid1, uid2 int64) bool {
	a, b := uid1, uid2
	if a > b {
		a, b = b, a
	}
	row, _ := fw.fetchOne("SELECT status FROM friend_relation WHERE uid1 = ? AND uid2 = ? AND status = 1 LIMIT 1", a, b)
	return row != nil
}

// PushGroupMessage 供主服务器调用的便捷方法：推送群消息给所有相关Bot
// 主服务器在 apiMessageSendGroupMsg 成功后调用此函数
func PushGroupMessage(fw *BotFramework, roomID, senderUID, msgID int64, content, nickname string, msgType int64) {
	if fw == nil {
		return
	}
	fw.onGroupMessage(map[string]any{
		"room_id":  roomID,
		"uid":      senderUID,
		"msg_id":   msgID,
		"content":  content,
		"nickname": nickname,
		"msg_type": msgType,
	})
}

// PushPrivateMessage 供主服务器调用的便捷方法：推送私聊消息给Bot
func PushPrivateMessage(fw *BotFramework, fromUID, toUID, msgID int64, content string, msgType int64) {
	if fw == nil {
		return
	}
	fw.onPrivateMessage(map[string]any{
		"from_uid": fromUID,
		"to_uid":   toUID,
		"msg_id":   msgID,
		"content":  content,
		"msg_type": msgType,
	})
}

// handleReloadScripts 处理脚本重载请求
func (fw *BotFramework) handleReloadScripts(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"success":false,"message":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}
	secret := r.Header.Get("X-Bot-Secret")
	if secret != fw.config.BotSecret {
		http.Error(w, `{"success":false,"message":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	if fw.scriptMgr == nil {
		http.Error(w, `{"success":false,"message":"script manager not initialized"}`, http.StatusInternalServerError)
		return
	}

	// 尝试解析bot_id，支持指定Bot重载
	var body map[string]any
	if err := json.NewDecoder(r.Body).Decode(&body); err == nil {
		if botID, ok := body["bot_id"]; ok {
			bid := toInt64(botID)
			if bid > 0 {
				fw.scriptMgr.ReloadBot(bid)
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write([]byte(`{"success":true,"message":"bot scripts reloaded"}`))
				return
			}
		}
	}

	// 无bot_id时重载所有脚本
	fw.scriptMgr.loadAllScripts()
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"success":true,"message":"all scripts reloaded"}`))
}

// toInt64 将any转为int64
func toInt64(v any) int64 {
	switch val := v.(type) {
	case int:
		return int64(val)
	case int32:
		return int64(val)
	case int64:
		return val
	case float64:
		return int64(val)
	case json.Number:
		n, _ := val.Int64()
		return n
	case string:
		var n int64
		fmt.Sscanf(strings.TrimSpace(val), "%d", &n)
		return n
	default:
		return 0
	}
}

// handleTestScript 处理脚本测试请求
func (fw *BotFramework) handleTestScript(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"success":false,"message":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}
	secret := r.Header.Get("X-Bot-Secret")
	if secret != fw.config.BotSecret {
		http.Error(w, `{"success":false,"message":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var body map[string]any
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, `{"success":false,"message":"invalid request"}`, http.StatusBadRequest)
		return
	}

	botID := toInt64(body["bot_id"])
	scriptContent, _ := body["script_content"].(string)
	eventType, _ := body["event_type"].(string)
	if eventType == "" {
		eventType = "group_message"
	}

	if botID <= 0 || scriptContent == "" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"success":false,"message":"缺少bot_id或script_content"}`))
		return
	}

	// 构造事件数据
	eventDataMap := map[string]any{}
	if ed, ok := body["event_data"].(map[string]any); ok {
		eventDataMap = ed
	} else if edStr, ok := body["event_data"].(string); ok && edStr != "" {
		json.Unmarshal([]byte(edStr), &eventDataMap)
	}
	// 默认测试数据
	if _, ok := eventDataMap["room_id"]; !ok {
		eventDataMap["room_id"] = float64(1)
	}
	if _, ok := eventDataMap["uid"]; !ok {
		eventDataMap["uid"] = float64(1001)
	}
	if _, ok := eventDataMap["content"]; !ok {
		eventDataMap["content"] = "test message"
	}
	if _, ok := eventDataMap["msg_id"]; !ok {
		eventDataMap["msg_id"] = float64(1)
	}
	if _, ok := eventDataMap["nickname"]; !ok {
		eventDataMap["nickname"] = "TestUser"
	}

	// 获取Bot UID
	botInfo, _ := fw.fetchOne("SELECT uid FROM bot_accounts WHERE id = ?", botID)
	if botInfo == nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"success":false,"message":"Bot不存在"}`))
		return
	}
	botUID := intval(botInfo, "uid")

	eventName := ""
	switch eventType {
	case "group_message":
		eventName = "group.message"
	case "private_message":
		eventName = "private.message"
	case "group_member_join":
		eventName = "group.member.join"
	case "group_member_leave":
		eventName = "group.member.leave"
	case "group_member_mute", "group_member_unmute":
		eventName = "group.member.mute"
	case "group_disband":
		eventName = "group.disband"
	default:
		eventName = eventType
	}

	rt := NewJSRuntime(fw, botID, botUID)
	if err := rt.Compile(scriptContent); err != nil {
		result, _ := json.Marshal(map[string]any{
			"success": false,
			"message": "编译错误",
			"errors":  []string{err.Error()},
		})
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(result)
		return
	}
	logs, execErr := rt.Test(eventName, eventDataMap)
	if execErr != nil {
		result, _ := json.Marshal(map[string]any{
			"success": false,
			"message": "执行错误",
			"errors":  []string{execErr.Error()},
			"logs":    logs,
		})
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(result)
		return
	}

	result, _ := json.Marshal(map[string]any{
		"success": true,
		"logs":    logs,
	})
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(result)
}
