// Copyright (c) Chemsource Studio. All rights reserved.
// Contact: swcsstudio@126.com

package main

import (
	"bufio"
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"path/filepath"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

func apiMessageSendGroupMsg(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	content := c.InputString("content")
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的房间ID"})
		return
	}
	if !requireRoomNotBanned(c, roomID) {
		return
	}
	member, _ := c.app.fetchOne("SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?", roomID, uid)
	if member == nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你不是该群成员"})
		return
	}
	if muteUntil := intval(member, "mute_until"); muteUntil > time.Now().Unix() {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你已被禁言至 " + localDateTime(muteUntil)})
		return
	}

	user := getUser(c.app, uid, "nickname, username")
	nickname := str(user, "nickname")
	if nickname == "" {
		nickname = "未知用户"
	}
	replyTo := c.InputInt("reply_to")
	mentions := c.InputString("mention_uids")
	msgType := int64(1)
	if hasMultipartFile(c, "img") {
		url, uploaded := uploadFile(c, "img", imageMimes, c.app.config.MaxImageBytes, filepath.Join(c.app.config.UploadDir, "img"), "upload/img", fmt.Sprintf("img_%d_%d", roomID, uid))
		if !uploaded {
			return
		}
		content = url
		msgType = 2
	} else if content == "" {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "消息内容不能为空"})
		return
	}

	msgID, err := c.app.insertRow("chat_msg", map[string]any{
		"room_id":        roomID,
		"uid":            uid,
		"nickname":       nickname,
		"content":        content,
		"msg_type":       msgType,
		"voice_duration": 0,
		"add_time":       utcDateTime(time.Now().Unix()),
		"reply_to":       nullablePositiveInt(replyTo),
		"mention_uids":   mentions,
		"was_replied":    0,
	})
	if err != nil {
		panic(err)
	}
	if mentions != "" {
		room := getRoom(c.app, roomID, "room_name")
		roomName := strDefault(room, "room_name", "未知群组")
		for _, part := range strings.Split(mentions, ",") {
			mentionedUID := toInt64Default(strings.TrimSpace(part), 0)
			if mentionedUID > 0 && mentionedUID != uid {
				notice(c.app, mentionedUID, "有人@你", fmt.Sprintf("%s 在群组【%s】中@了你", nickname, roomName))
			}
		}
	}
	level := refreshGroupMemberLevel(c.app, roomID, uid)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "发送成功", "msg_id": msgID, "member_level": level["level"], "member_title": level["title"]})
}

func apiMessageSendPrivateMsg(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	friendID := c.InputInt("friend_id")
	content := c.InputString("content")
	if friendID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	if _, ok := requireFriend(c, myUID, friendID); !ok {
		return
	}
	imageURL := ""
	if hasMultipartFile(c, "img") {
		url, uploaded := uploadFile(c, "img", imageMimes, c.app.config.MaxImageBytes, c.app.config.PrivateUploadDir, "uploads/chat", fmt.Sprintf("img_%d", myUID))
		if !uploaded {
			return
		}
		imageURL = url
		content = "[图片]"
	} else if content == "" {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "消息内容不能为空"})
		return
	}
	msgType := int64(1)
	if imageURL != "" {
		msgType = 2
	}
	msgID, err := c.app.insertRow("private_msg", map[string]any{
		"from_uid":    myUID,
		"to_uid":      friendID,
		"content":     content,
		"type":        "private",
		"room_id":     0,
		"created_at":  time.Now().Unix(),
		"is_read":     0,
		"image_url":   imageURL,
		"msg_type":    msgType,
		"is_recalled": 0,
		"reply_to":    nullablePositiveInt(c.InputInt("reply_to")),
	})
	if err != nil {
		panic(err)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "发送成功", "msg_id": msgID})
}

func apiMessageSendPatMsg(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id", c.InputInt("rid"))
	targetUID := c.InputInt("target_uid", c.InputInt("uid"))
	if roomID <= 0 || targetUID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	if _, ok := requireGroupMember(c, roomID, uid); !ok {
		return
	}
	if !isGroupMember(c.app, roomID, targetUID) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "用户不在该群内"})
		return
	}
	from := getUser(c.app, uid, "nickname, username, pat_action")
	to := getUser(c.app, targetUID, "nickname, username")
	fromName := str(from, "nickname")
	if fromName == "" {
		fromName = fmt.Sprintf("UID %d", uid)
	}
	toName := str(to, "nickname")
	if toName == "" {
		toName = fmt.Sprintf("UID %d", targetUID)
	}
	action := str(from, "pat_action")
	if action == "" {
		action = "拍了拍"
	}
	content := fromName + action + toName
	msgID, err := c.app.insertRow("chat_msg", map[string]any{
		"room_id":        roomID,
		"uid":            uid,
		"nickname":       fromName,
		"content":        content,
		"msg_type":       4,
		"voice_duration": 0,
		"add_time":       utcDateTime(time.Now().Unix()),
		"reply_to":       nil,
		"mention_uids":   "",
		"was_replied":    0,
	})
	if err != nil {
		panic(err)
	}
	level := refreshGroupMemberLevel(c.app, roomID, uid)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "发送成功", "msg_id": msgID, "content": content, "msg_type": 4, "member_level": level["level"], "member_title": level["title"]})
}

func apiMessageSendVoiceMsg(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	friendID := c.InputInt("friend_id")
	duration := c.InputInt("duration")
	if !hasMultipartFile(c, "voice") {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "语音文件上传失败"})
		return
	}
	if roomID > 0 {
		if !requireRoomNotBanned(c, roomID) {
			return
		}
		member, _ := c.app.fetchOne("SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?", roomID, uid)
		if member == nil {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你不是该群成员"})
			return
		}
		if muteUntil := intval(member, "mute_until"); muteUntil > time.Now().Unix() {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你已被禁言至 " + localDateTime(muteUntil)})
			return
		}
		voiceURL, uploaded := uploadFile(c, "voice", voiceMimes, c.app.config.MaxVoiceBytes, filepath.Join(c.app.config.UploadDir, "voice"), "upload/voice", fmt.Sprintf("voice_%d_%d", roomID, uid))
		if !uploaded {
			return
		}
		user := getUser(c.app, uid, "nickname")
		nickname := strDefault(user, "nickname", "未知用户")
		msgID, err := c.app.insertRow("chat_msg", map[string]any{"room_id": roomID, "uid": uid, "nickname": nickname, "content": voiceURL, "msg_type": 3, "voice_duration": duration, "add_time": utcDateTime(time.Now().Unix()), "was_replied": 0})
		if err != nil {
			panic(err)
		}
		level := refreshGroupMemberLevel(c.app, roomID, uid)
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "语音发送成功", "msg_id": msgID, "url": voiceURL, "member_level": level["level"], "member_title": level["title"]})
		return
	}
	if friendID > 0 {
		if _, ok := requireFriend(c, uid, friendID); !ok {
			return
		}
		voiceURL, uploaded := uploadFile(c, "voice", voiceMimes, c.app.config.MaxVoiceBytes, filepath.Join(c.app.config.UploadDir, "voice"), "upload/voice", fmt.Sprintf("voice_%d_%d", friendID, uid))
		if !uploaded {
			return
		}
		msgID, err := c.app.insertRow("private_msg", map[string]any{"from_uid": uid, "to_uid": friendID, "content": "[语音]", "type": "private", "room_id": 0, "created_at": time.Now().Unix(), "is_read": 0, "voice_url": voiceURL, "duration": duration, "msg_type": 3, "is_recalled": 0})
		if err != nil {
			panic(err)
		}
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "语音发送成功", "msg_id": msgID, "url": voiceURL})
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少房间或好友ID"})
}

func apiMessageSendEmojiMsg(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	friendID := c.InputInt("friend_id")
	abbr := c.InputString("abbr")
	if abbr == "" {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "表情包缩写不能为空"})
		return
	}
	emoji, _ := c.app.fetchOne("SELECT abbr, full_name, address FROM emoji_list WHERE abbr = ?", abbr)
	if emoji == nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "表情包不存在"})
		return
	}
	if roomID > 0 {
		if !requireRoomNotBanned(c, roomID) {
			return
		}
		member, _ := c.app.fetchOne("SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?", roomID, uid)
		if member == nil {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你不是该群成员"})
			return
		}
		if muteUntil := intval(member, "mute_until"); muteUntil > time.Now().Unix() {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你已被禁言至 " + localDateTime(muteUntil)})
			return
		}
		user := getUser(c.app, uid, "nickname, username")
		nickname := strDefault(user, "nickname", "未知用户")
		msgID, err := c.app.insertRow("chat_msg", map[string]any{"room_id": roomID, "uid": uid, "nickname": nickname, "content": abbr, "msg_type": 5, "voice_duration": 0, "add_time": utcDateTime(time.Now().Unix()), "reply_to": nil, "mention_uids": "", "was_replied": 0})
		if err != nil {
			log.Printf("send group emoji failed: room_id=%d uid=%d abbr=%q err=%v", roomID, uid, abbr, err)
			c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "发送失败，请稍后再试"})
			return
		}
		level := refreshGroupMemberLevel(c.app, roomID, uid)
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "发送成功", "msg_id": msgID, "content": abbr, "msg_type": 5, "address": str(emoji, "address"), "member_level": level["level"], "member_title": level["title"]})
		return
	}
	if friendID > 0 {
		if _, ok := requireFriend(c, uid, friendID); !ok {
			return
		}
		msgID, err := c.app.insertRow("private_msg", map[string]any{"from_uid": uid, "to_uid": friendID, "content": abbr, "type": "private", "room_id": 0, "created_at": time.Now().Unix(), "is_read": 0, "msg_type": 5, "is_recalled": 0})
		if err != nil {
			panic(err)
		}
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "发送成功", "msg_id": msgID, "content": abbr, "msg_type": 5, "address": str(emoji, "address")})
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少房间或好友ID"})
}

func apiEmojiGetList(c *Ctx) {
	if _, ok := requireLogin(c); !ok {
		return
	}
	rows, err := c.app.fetchAll("SELECT full_name, abbr, address FROM emoji_list ORDER BY abbr")
	if err != nil {
		panic(err)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "emojis": rowListToMaps(rows)})
}

func apiMessagePollUpdates(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	conversationType := strings.ToLower(c.InputString("conversation_type", c.InputString("type")))
	roomID := c.InputInt("room_id", c.InputInt("rid"))
	friendID := c.InputInt("friend_id")
	afterID := c.InputInt("after_id", c.InputInt("last_id"))
	if afterID < 0 {
		afterID = 0
	}
	timeout := limitBetween(c.InputInt("timeout", 10), 0, int64(c.app.config.LongPollMaxSeconds))
	if roomID > 0 || conversationType == "group" || conversationType == "room" {
		if roomID <= 0 {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的房间ID"})
			return
		}
		if _, ok := requireGroupMember(c, roomID, uid); !ok {
			return
		}
		pollForUpdates(c, "group", roomID, afterID, timeout, func() int64 { return latestGroupMessageID(c.app, roomID, afterID) })
		return
	}
	if friendID > 0 || conversationType == "private" || conversationType == "friend" {
		if friendID <= 0 {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
			return
		}
		if _, ok := requireFriend(c, uid, friendID); !ok {
			return
		}
		pollForUpdates(c, "private", friendID, afterID, timeout, func() int64 { return latestPrivateMessageID(c.app, uid, friendID, afterID) })
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少房间或好友ID"})
}

func pollForUpdates(c *Ctx, conversationType string, conversationID, afterID, timeout int64, latestIDProvider func() int64) {
	started := time.Now()
	deadline := started.Add(time.Duration(timeout) * time.Second)
	latestID := int64(0)
	for {
		if next := latestIDProvider(); next > latestID {
			latestID = next
		}
		if latestID > afterID {
			c.JSON(http.StatusOK, pollResponse(conversationType, conversationID, afterID, latestID, true, started, timeout))
			return
		}
		if timeout <= 0 || time.Now().After(deadline) {
			break
		}
		sleep := time.Duration(c.app.config.LongPollSleepMillis) * time.Millisecond
		remaining := time.Until(deadline)
		if remaining <= 0 {
			break
		}
		if sleep > remaining {
			sleep = remaining
		}
		time.Sleep(sleep)
	}
	c.JSON(http.StatusOK, pollResponse(conversationType, conversationID, afterID, latestID, false, started, timeout))
}

func pollResponse(conversationType string, conversationID, afterID, latestID int64, hasUpdates bool, started time.Time, timeout int64) map[string]any {
	nextAfterID := afterID
	if hasUpdates {
		nextAfterID = latestID
	}
	elapsed := int64((time.Since(started) + time.Millisecond/2) / time.Millisecond)
	return map[string]any{"success": true, "conversation_type": conversationType, "conversation_id": conversationID, "has_updates": hasUpdates, "after_id": afterID, "latest_id": latestID, "next_after_id": nextAfterID, "timeout": timeout, "elapsed_ms": elapsed, "server_time": time.Now().Unix()}
}

func latestGroupMessageID(a *App, roomID, afterID int64) int64 {
	row, _ := a.fetchOne("SELECT MAX(id) AS latest_id FROM chat_msg WHERE room_id = ? AND id > ?", roomID, afterID)
	return intval(row, "latest_id")
}

func latestPrivateMessageID(a *App, myUID, friendID, afterID int64) int64 {
	row, _ := a.fetchOne(`SELECT MAX(id) AS latest_id
		FROM private_msg
		WHERE id > ? AND type = 'private'
		AND ((from_uid = ? AND to_uid = ?) OR (from_uid = ? AND to_uid = ?))`, afterID, myUID, friendID, friendID, myUID)
	return intval(row, "latest_id")
}

func apiMessageGetGroupMsg(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id", c.InputInt("rid"))
	beforeID := c.InputInt("before_id")
	afterID := c.InputInt("after_id")
	limit := limitBetween(c.InputInt("limit", 80), 20, 200)
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的房间ID"})
		return
	}
	room, ok := requireGroupMember(c, roomID, uid)
	if !ok {
		return
	}
	isOwner := intval(room, "owner_uid") == uid
	isAdmin := isGroupAdmin(c.app, roomID, uid)
	adminRows, _ := c.app.fetchAll("SELECT uid FROM chat_group_admin WHERE room_id = ?", roomID)
	admins := sortedIntSet(adminRows, "uid")
	essenceRows, _ := c.app.fetchAll("SELECT msg_id FROM chat_essence WHERE room_id = ?", roomID)
	essenceIDs := sortedIntSet(essenceRows, "msg_id")

	where := "WHERE m.room_id = ?"
	args := []any{roomID}
	if beforeID > 0 {
		where += " AND m.id < ?"
		args = append(args, beforeID)
	}
	if afterID > 0 {
		where += " AND m.id > ?"
		args = append(args, afterID)
	}
	order := "DESC"
	if afterID > 0 {
		order = "ASC"
	}
	rows, err := c.app.fetchAll(`SELECT m.id, m.uid, m.nickname, m.content, m.msg_type, m.voice_duration,
		m.add_time, UNIX_TIMESTAMP(m.add_time) AS created_at, m.reply_to, m.mention_uids, m.was_replied, u.avatar,
		gu.title AS member_title, gu.level AS member_level,
		rply.content AS reply_content, rply.uid AS reply_from_uid, ru.nickname AS reply_nickname
		FROM chat_msg m
		LEFT JOIN chat_user u ON m.uid = u.id
		LEFT JOIN chat_group_user gu ON gu.room_id = m.room_id AND gu.uid = m.uid
		LEFT JOIN chat_msg rply ON m.reply_to = rply.id
		LEFT JOIN chat_user ru ON rply.uid = ru.id
		`+where+`
		ORDER BY m.id `+order+`
		LIMIT `+fmt.Sprintf("%d", limit), args...)
	if err != nil {
		panic(err)
	}
	if afterID <= 0 {
		reverseRows(rows)
	}
	messages := []map[string]any{}
	now := time.Now().Unix()
	for _, row := range rows {
		sender := intval(row, "uid")
		msgTime := parseAnyTime(row["created_at"])
		if msgTime <= 0 {
			msgTime = parseAnyTime(row["add_time"])
		}
		canRecall := (sender == uid && now-msgTime <= 120) || isOwner || (isAdmin && sender != uid && !admins[sender])
		mentionUIDs := str(row, "mention_uids")
		replyToMe := false
		if intval(row, "reply_to") > 0 {
			replyToMe = intval(row, "reply_from_uid") == uid
		}
		messages = append(messages, normalizeMessageRow(c.app, row, uid, map[string]any{"is_essence": essenceIDs[intval(row, "id")], "can_recall": canRecall, "is_mentioned": mentioned(mentionUIDs, uid), "reply_to_me": replyToMe, "mention_uids": mentionUIDs}))
	}
	hasMore := false
	if len(messages) > 0 {
		firstID := toInt64Default(messages[0]["id"], 0)
		older, _ := c.app.fetchOne("SELECT id FROM chat_msg WHERE room_id = ? AND id < ? LIMIT 1", roomID, firstID)
		hasMore = older != nil
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "messages": messages, "has_more": hasMore, "limit": limit, "before_id": beforeID, "after_id": afterID})
}

func apiMessageGetPrivateMsg(c *Ctx) {
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	friendID := c.InputInt("friend_id")
	lastID := c.InputInt("last_id")
	beforeID := c.InputInt("before_id")
	afterID := c.InputInt("after_id", lastID)
	limit := limitBetween(c.InputInt("limit", 80), 20, 200)
	if friendID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	if _, ok := requireFriend(c, myUID, friendID); !ok {
		return
	}
	where := "WHERE ((pm.from_uid = ? AND pm.to_uid = ?) OR (pm.from_uid = ? AND pm.to_uid = ?)) AND pm.type = 'private'"
	args := []any{myUID, friendID, friendID, myUID}
	if beforeID > 0 {
		where += " AND pm.id < ?"
		args = append(args, beforeID)
	}
	if afterID > 0 {
		where += " AND pm.id > ?"
		args = append(args, afterID)
	}
	order := "DESC"
	if afterID > 0 {
		order = "ASC"
	}
	rows, err := c.app.fetchAll(`SELECT pm.*, cu.nickname, cu.avatar, cu.username,
		rply.content AS reply_content, rply.from_uid AS reply_from_uid,
		ru.nickname AS reply_nickname
		FROM private_msg pm
		JOIN chat_user cu ON pm.from_uid = cu.id
		LEFT JOIN private_msg rply ON pm.reply_to = rply.id
		LEFT JOIN chat_user ru ON rply.from_uid = ru.id
		`+where+`
		ORDER BY pm.id `+order+`
		LIMIT `+fmt.Sprintf("%d", limit), args...)
	if err != nil {
		panic(err)
	}
	if afterID <= 0 {
		reverseRows(rows)
	}
	messages := []map[string]any{}
	for _, row := range rows {
		messages = append(messages, normalizeMessageRow(c.app, row, myUID, nil))
	}
	newLastID := lastID
	if len(messages) > 0 {
		newLastID = toInt64Default(messages[len(messages)-1]["id"], lastID)
	}
	_, _ = c.app.exec("UPDATE private_msg SET is_read = 1 WHERE from_uid = ? AND to_uid = ? AND is_read = 0 AND type = 'private'", friendID, myUID)
	hasMore := false
	if len(messages) > 0 {
		firstID := toInt64Default(messages[0]["id"], 0)
		older, _ := c.app.fetchOne("SELECT id FROM private_msg WHERE ((from_uid = ? AND to_uid = ?) OR (from_uid = ? AND to_uid = ?)) AND id < ? LIMIT 1", myUID, friendID, friendID, myUID, firstID)
		hasMore = older != nil
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "messages": messages, "last_id": newLastID, "has_more": hasMore, "limit": limit, "before_id": beforeID, "after_id": afterID})
}

func apiMessageMarkRead(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	friendID := c.InputInt("friend_id")
	roomID := c.InputInt("room_id")
	if friendID > 0 {
		_, _ = c.app.exec("UPDATE private_msg SET is_read = 1 WHERE from_uid = ? AND to_uid = ? AND is_read = 0 AND type = 'private'", friendID, uid)
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "私聊已标记已读"})
		return
	}
	if roomID > 0 {
		if _, ok := requireGroupMember(c, roomID, uid); !ok {
			return
		}
		if lastID := c.InputInt("last_msg_id"); lastID > 0 {
			_, _ = c.app.updateRow("chat_group_user", map[string]any{"last_read_msg_id": lastID}, "room_id = ? AND uid = ?", roomID, uid)
		}
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "群聊已读位置更新"})
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少参数"})
}

func apiMessageRecallMsg(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	msgID := c.InputInt("msg_id")
	roomID := c.InputInt("room_id")
	msgType := c.InputString("type", "group")
	if msgID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误：消息ID无效"})
		return
	}
	if msgType == "group" {
		if roomID <= 0 {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误：房间ID无效"})
			return
		}
		if _, ok := requireGroupMember(c, roomID, uid); !ok {
			return
		}
		msg, _ := c.app.fetchOne("SELECT uid, add_time, UNIX_TIMESTAMP(add_time) AS created_at, was_replied FROM chat_msg WHERE id = ? AND room_id = ?", msgID, roomID)
		if msg == nil {
			c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "消息不存在"})
			return
		}
		if intval(msg, "was_replied") > 0 {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "消息已撤回"})
			return
		}
		room := getRoom(c.app, roomID, "owner_uid")
		isOwner := intval(room, "owner_uid") == uid
		isAdmin := isGroupAdmin(c.app, roomID, uid)
		targetIsAdmin := isGroupAdmin(c.app, roomID, intval(msg, "uid"))
		isSelf := intval(msg, "uid") == uid
		msgTime := parseAnyTime(msg["created_at"])
		if msgTime <= 0 {
			msgTime = parseAnyTime(msg["add_time"])
		}
		canRecall := (isSelf && time.Now().Unix()-msgTime <= 120) || isOwner || (isAdmin && !isSelf && !targetIsAdmin)
		if !canRecall {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无权限撤回该消息"})
			return
		}
		recallStatus := int64(2)
		if isSelf {
			recallStatus = 1
		} else if isOwner {
			recallStatus = 3
		}
		_, _ = c.app.exec("DELETE FROM chat_essence WHERE msg_id = ? AND room_id = ?", msgID, roomID)
		_, _ = c.app.updateRow("chat_msg", map[string]any{"was_replied": recallStatus, "is_essence": 0}, "id = ? AND room_id = ?", msgID, roomID)
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "撤回成功"})
		return
	}
	msg, _ := c.app.fetchOne("SELECT from_uid, created_at FROM private_msg WHERE id = ? AND type = 'private'", msgID)
	if msg == nil || intval(msg, "from_uid") != uid {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "消息不存在或无权操作"})
		return
	}
	if time.Now().Unix()-intval(msg, "created_at") > 120 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "超过2分钟，无法撤回"})
		return
	}
	_, _ = c.app.exec("DELETE FROM private_msg WHERE id = ?", msgID)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "撤回成功"})
}

func apiMessageGetMentions(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	limit := limitBetween(c.InputInt("limit", 50), 0, 100)
	mentions, _ := c.app.fetchOne(`SELECT COUNT(*) AS c
		FROM chat_msg m
		JOIN chat_group_user gu ON gu.room_id = m.room_id AND gu.uid = ?
		WHERE m.id > COALESCE(gu.last_read_msg_id, 0)
		AND FIND_IN_SET(?, m.mention_uids)`, uid, uid)
	replies, _ := c.app.fetchOne(`SELECT COUNT(*) AS c
		FROM chat_msg m
		JOIN chat_msg r ON m.reply_to = r.id
		JOIN chat_group_user gu ON gu.room_id = m.room_id AND gu.uid = ?
		WHERE m.id > COALESCE(gu.last_read_msg_id, 0)
		AND r.uid = ?`, uid, uid)
	mentionRows := []map[string]any{}
	replyRows := []map[string]any{}
	if limit > 0 {
		mentionRows = mentionNoticeRows(c.app, uid, "mention", limit)
		replyRows = mentionNoticeRows(c.app, uid, "reply", limit)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "unread_mentions": intval(mentions, "c"), "unread_replies": intval(replies, "c"), "mention_count": intval(mentions, "c"), "reply_count": intval(replies, "c"), "mentions": mentionRows, "replies": replyRows, "limit": limit})
}

func mentionNoticeRows(a *App, uid int64, kind string, limit int64) []map[string]any {
	var rows []Row
	var err error
	if kind == "reply" {
		rows, err = a.fetchAll(`SELECT m.id, m.room_id, m.uid, m.nickname, m.content, m.msg_type, m.voice_duration,
			m.add_time, UNIX_TIMESTAMP(m.add_time) AS created_at, m.reply_to, m.mention_uids, m.was_replied, u.avatar,
			r.room_name, gu.title AS member_title, gu.level AS member_level,
			original.content AS reply_content, original.uid AS reply_from_uid, ou.nickname AS reply_nickname
			FROM chat_msg m
			JOIN chat_msg original ON m.reply_to = original.id
			JOIN chat_group_user me ON me.room_id = m.room_id AND me.uid = ?
			LEFT JOIN chat_room r ON r.id = m.room_id
			LEFT JOIN chat_user u ON m.uid = u.id
			LEFT JOIN chat_user ou ON original.uid = ou.id
			LEFT JOIN chat_group_user gu ON gu.room_id = m.room_id AND gu.uid = m.uid
			WHERE m.id > COALESCE(me.last_read_msg_id, 0)
			AND original.uid = ?
			ORDER BY m.id DESC
			LIMIT `+fmt.Sprintf("%d", limit), uid, uid)
	} else {
		rows, err = a.fetchAll(`SELECT m.id, m.room_id, m.uid, m.nickname, m.content, m.msg_type, m.voice_duration,
			m.add_time, UNIX_TIMESTAMP(m.add_time) AS created_at, m.reply_to, m.mention_uids, m.was_replied, u.avatar,
			r.room_name, gu.title AS member_title, gu.level AS member_level,
			replied.content AS reply_content, replied.uid AS reply_from_uid, ru.nickname AS reply_nickname
			FROM chat_msg m
			JOIN chat_group_user me ON me.room_id = m.room_id AND me.uid = ?
			LEFT JOIN chat_room r ON r.id = m.room_id
			LEFT JOIN chat_user u ON m.uid = u.id
			LEFT JOIN chat_msg replied ON m.reply_to = replied.id
			LEFT JOIN chat_user ru ON replied.uid = ru.id
			LEFT JOIN chat_group_user gu ON gu.room_id = m.room_id AND gu.uid = m.uid
			WHERE m.id > COALESCE(me.last_read_msg_id, 0)
			AND FIND_IN_SET(?, m.mention_uids)
			ORDER BY m.id DESC
			LIMIT `+fmt.Sprintf("%d", limit), uid, uid)
	}
	if err != nil {
		panic(err)
	}
	notices := []map[string]any{}
	for _, row := range rows {
		notices = append(notices, mentionNoticeFromRow(a, row, uid, kind))
	}
	return notices
}

func mentionNoticeFromRow(a *App, row Row, uid int64, kind string) map[string]any {
	mentionUIDs := str(row, "mention_uids")
	message := normalizeMessageRow(a, row, uid, map[string]any{"is_mentioned": mentioned(mentionUIDs, uid), "reply_to_me": kind == "reply", "mention_uids": mentionUIDs})
	title := "@ me"
	if kind == "reply" {
		title = "Reply to me"
	}
	result := map[string]any{"id": intval(row, "id"), "notice_id": intval(row, "id"), "kind": kind, "notice_type": kind, "conversation_type": "group", "room_id": intval(row, "room_id"), "room_name": str(row, "room_name"), "title": title, "is_read": 0, "message": message}
	for k, v := range message {
		if _, exists := result[k]; !exists {
			result[k] = v
		}
	}
	return result
}

func apiEssenceSet(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	msgID := c.InputInt("msg_id")
	roomID := c.InputInt("room_id")
	if msgID <= 0 || roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	if _, ok := requireGroupOwnerOrAdmin(c, roomID, uid); !ok {
		return
	}
	msg, _ := c.app.fetchOne("SELECT id FROM chat_msg WHERE id = ? AND room_id = ? LIMIT 1", msgID, roomID)
	if msg == nil {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "消息不存在"})
		return
	}
	exists, _ := c.app.fetchOne("SELECT id FROM chat_essence WHERE msg_id = ? AND room_id = ?", msgID, roomID)
	if exists != nil {
		_, _ = c.app.exec("DELETE FROM chat_essence WHERE msg_id = ? AND room_id = ?", msgID, roomID)
		_, _ = c.app.updateRow("chat_msg", map[string]any{"is_essence": 0}, "id = ? AND room_id = ?", msgID, roomID)
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "已取消精华"})
		return
	}
	setNick := ""
	if c.session != nil {
		setNick = c.session.Nickname
	}
	_, err := c.app.insertRow("chat_essence", map[string]any{"msg_id": msgID, "room_id": roomID, "set_uid": uid, "set_nick": setNick, "set_time": localDateTime(time.Now().Unix())})
	if err != nil {
		panic(err)
	}
	_, _ = c.app.updateRow("chat_msg", map[string]any{"is_essence": 1}, "id = ? AND room_id = ?", msgID, roomID)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "已设为精华"})
}

func apiEssenceGet(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的群组ID"})
		return
	}
	room, ok := requireGroupMember(c, roomID, uid)
	if !ok {
		return
	}
	rows, err := c.app.fetchAll(`SELECT m.id, m.uid, m.nickname, m.content, m.msg_type, m.voice_duration,
		m.add_time, UNIX_TIMESTAMP(m.add_time) AS created_at, m.was_replied, u.avatar, gu.title AS member_title, gu.level AS member_level,
		e.set_uid, e.set_nick, e.set_time
		FROM chat_msg m
		JOIN chat_essence e ON m.id = e.msg_id AND m.room_id = e.room_id
		LEFT JOIN chat_user u ON m.uid = u.id
		LEFT JOIN chat_group_user gu ON gu.room_id = m.room_id AND gu.uid = m.uid
		WHERE m.room_id = ?
		ORDER BY m.id DESC`, roomID)
	if err != nil {
		panic(err)
	}
	list := []map[string]any{}
	for _, row := range rows {
		list = append(list, normalizeMessageRow(c.app, row, uid, map[string]any{"is_essence": true, "set_uid": intval(row, "set_uid"), "set_nick": str(row, "set_nick"), "set_time": str(row, "set_time")}))
	}
	canRemove := intval(room, "owner_uid") == uid || isGroupAdmin(c.app, roomID, uid)
	c.JSON(http.StatusOK, map[string]any{"success": true, "essence_list": list, "can_remove": canRemove})
}

func apiEssenceStats(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	statType := c.InputString("type", "today")
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的群组ID"})
		return
	}
	if _, ok := requireGroupMember(c, roomID, uid); !ok {
		return
	}
	start := int64(0)
	switch statType {
	case "all":
		start = 0
	case "week":
		start = time.Now().Unix() - 604800
	case "month":
		start = time.Now().Unix() - 2592000
	default:
		statType = "today"
		now := time.Now()
		start = time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location()).Unix()
	}
	typeNames := map[string]string{"today": "今天", "week": "近7天", "month": "近一个月", "all": "全部"}
	periodWhere := ""
	args := []any{roomID}
	if start > 0 {
		periodWhere = " AND e.set_time >= FROM_UNIXTIME(?)"
		args = append(args, start)
	}
	count := func(extra string) int64 {
		row, _ := c.app.fetchOne("SELECT COUNT(*) AS c FROM chat_essence e JOIN chat_msg m ON e.msg_id = m.id AND e.room_id = m.room_id WHERE e.room_id = ?"+extra+periodWhere, args...)
		return intval(row, "c")
	}
	total := count("")
	text := count(" AND m.msg_type = 1")
	image := count(" AND m.msg_type = 2")
	voice := count(" AND m.msg_type = 3")
	rankRows, err := c.app.fetchAll(`SELECT m.uid, m.nickname, COUNT(*) AS essence_count
		FROM chat_essence e
		JOIN chat_msg m ON e.msg_id = m.id AND e.room_id = m.room_id
		WHERE e.room_id = ?`+periodWhere+`
		GROUP BY m.uid, m.nickname
		ORDER BY essence_count DESC
		LIMIT 10`, args...)
	if err != nil {
		panic(err)
	}
	rank := []map[string]any{}
	for i, row := range rankRows {
		item := map[string]any{}
		for k, v := range row {
			item[k] = v
		}
		item["rank"] = i + 1
		item["uid"] = intval(row, "uid")
		item["count"] = intval(row, "essence_count")
		rank = append(rank, item)
	}
	latest, _ := c.app.fetchOne("SELECT MAX(set_time) AS latest_set_time FROM chat_essence WHERE room_id = ?", roomID)
	c.JSON(http.StatusOK, map[string]any{"success": true, "type": statType, "type_name": typeNames[statType], "total": total, "text_count": text, "image_count": image, "voice_count": voice, "rank": rank, "latest_set_time": str(latest, "latest_set_time")})
}

func apiReportSubmit(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	reportType := c.InputString("type")
	targetUID := c.InputInt("uid")
	targetRID := c.InputInt("rid")
	reason := c.InputString("reason")
	anonymous := boolInt(c.InputBool("anonymous"))
	if reportType != "user" && reportType != "group" {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "举报类型错误"})
		return
	}
	if utf8.RuneCountInString(reason) < 10 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "举报原因至少10个字符"})
		return
	}
	targetID := targetRID
	if reportType == "user" {
		targetID = targetUID
	}
	if targetID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "被举报对象无效"})
		return
	}
	if reportType == "user" && getUser(c.app, targetID, "id") == nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "被举报用户不存在"})
		return
	}
	if reportType == "group" && getRoom(c.app, targetID, "id") == nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "被举报群组不存在"})
		return
	}
	targetName := c.InputString("room_name")
	if reportType == "user" {
		targetName = c.InputString("nickname", c.InputString("username"))
	}
	reporterUID := myUID
	if anonymous == 1 {
		reporterUID = 0
	}
	_, err := c.app.insertRow("chat_report", map[string]any{"reporter_uid": reporterUID, "report_type": reportType, "target_id": targetID, "target_name": targetName, "reason": reason, "is_anonymous": anonymous, "add_time": time.Now().Unix()})
	if err != nil {
		panic(err)
	}
	label := "群组"
	if reportType == "user" {
		label = "用户"
	}
	notice(c.app, c.app.config.AdminUID, "收到新的"+label+"举报", fmt.Sprintf("被举报对象：%s (ID: %d)\n举报原因：%s", targetName, targetID, reason))
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "举报已提交"})
}

func apiAdminGenerateToken(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	if !sessionExtActive(c) && uid != c.app.config.AdminUID {
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "无权限"})
		return
	}
	_, _ = c.app.exec("DELETE FROM admin_tokens WHERE expires_at < ?", time.Now().Unix())
	token := randomHex(64)
	_, err := c.app.insertRow("admin_tokens", map[string]any{"token": token, "created_at": time.Now().Unix(), "expires_at": time.Now().Unix() + 300, "used": 0, "ip_address": clientIP(c.r), "user_agent": c.r.UserAgent()})
	if err != nil {
		panic(err)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "token": token, "expires_in": 300})
}

func apiAdminBan(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	if !sessionExtActive(c) {
		if uid != c.app.config.AdminUID {
			c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "无权限"})
			return
		}
		if !adminRequireToken(c, strings.EqualFold(c.r.Method, http.MethodPost)) {
			return
		}
	}
	action := c.InputString("action", "list")
	if strings.EqualFold(c.r.Method, http.MethodPost) {
		adminBanPost(c, action)
		return
	}
	users, err := c.app.fetchAll("SELECT id, username, nickname, ban_until, ban_reason FROM chat_user WHERE ban_until > ? ORDER BY ban_until DESC", time.Now().Unix())
	if err != nil {
		panic(err)
	}
	rooms, err := c.app.fetchAll("SELECT r.id, r.room_name, r.ban_until, r.ban_reason, u.nickname AS owner_nickname FROM chat_room r LEFT JOIN chat_user u ON r.owner_uid = u.id WHERE r.ban_until > ? ORDER BY r.ban_until DESC", time.Now().Unix())
	if err != nil {
		panic(err)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "users": banRows(users), "rooms": banRows(rooms)})
}

func adminRequireToken(c *Ctx, consume bool) bool {
	token := c.InputString("token")
	if token == "" {
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "无效或过期的令牌"})
		return false
	}
	row, _ := c.app.fetchOne("SELECT * FROM admin_tokens WHERE token = ? AND expires_at > ? AND used = 0 LIMIT 1", token, time.Now().Unix())
	if row == nil {
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "无效或过期的令牌"})
		return false
	}
	if consume {
		_, _ = c.app.updateRow("admin_tokens", map[string]any{"used": 1}, "id = ?", intval(row, "id"))
	}
	return true
}

func adminBanPost(c *Ctx, action string) {
	switch action {
	case "ban_user":
		target := c.InputInt("user_id")
		days := c.InputInt("ban_days")
		reason := c.InputString("ban_reason")
		if target <= 0 || days <= 0 || reason == "" {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
			return
		}
		until := time.Now().Unix() + days*86400
		_, _ = c.app.updateRow("chat_user", map[string]any{"ban_until": until, "ban_reason": reason}, "id = ?", target)
		notice(c.app, target, "账号封禁通知", fmt.Sprintf("您的账号已被封禁。\n封禁时长：%d 天\n解封时间：%s\n封禁原因：%s", days, localDateTime(until), reason))
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": fmt.Sprintf("用户 %d 已封禁 %d 天", target, days)})
	case "unban_user":
		target := c.InputInt("user_id")
		_, _ = c.app.updateRow("chat_user", map[string]any{"ban_until": 0, "ban_reason": ""}, "id = ?", target)
		notice(c.app, target, "账号解封通知", "您的账号已解除封禁，现在可以正常使用所有功能。")
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": fmt.Sprintf("用户 %d 已解封", target)})
	case "ban_room":
		roomID := c.InputInt("room_id")
		days := c.InputInt("ban_days")
		reason := c.InputString("ban_reason")
		if roomID <= 0 || days <= 0 || reason == "" {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
			return
		}
		until := time.Now().Unix() + days*86400
		_, _ = c.app.updateRow("chat_room", map[string]any{"ban_until": until, "ban_reason": reason}, "id = ?", roomID)
		room := getRoom(c.app, roomID, "owner_uid, room_name")
		if room != nil {
			notice(c.app, intval(room, "owner_uid"), "群组封禁通知", fmt.Sprintf("您的群组「%s」已被封禁。\n封禁时长：%d 天\n解封时间：%s\n封禁原因：%s", str(room, "room_name"), days, localDateTime(until), reason))
		}
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": fmt.Sprintf("群组 %d 已封禁 %d 天", roomID, days)})
	case "unban_room":
		roomID := c.InputInt("room_id")
		_, _ = c.app.updateRow("chat_room", map[string]any{"ban_until": 0, "ban_reason": ""}, "id = ?", roomID)
		room := getRoom(c.app, roomID, "owner_uid, room_name")
		if room != nil {
			notice(c.app, intval(room, "owner_uid"), "群组解封通知", fmt.Sprintf("您的群组「%s」已解除封禁。", str(room, "room_name")))
		}
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": fmt.Sprintf("群组 %d 已解封", roomID)})
	default:
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "未知操作"})
	}
}

func banRows(rows []Row) []map[string]any {
	list := []map[string]any{}
	now := time.Now().Unix()
	for _, row := range rows {
		item := map[string]any{}
		for k, v := range row {
			item[k] = v
		}
		until := intval(row, "ban_until")
		item["ban_until_date"] = time.Unix(until, 0).Format("2006-01-02 15:04")
		left := int64(0)
		if until > now {
			left = (until - now + 86399) / 86400
		}
		item["days_left"] = left
		list = append(list, item)
	}
	return list
}

func apiUtilsUploadImage(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	if !hasMultipartFile(c, "image") {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "未上传图片"})
		return
	}
	url, uploaded := uploadFile(c, "image", imageMimes, c.app.config.MaxImageBytes, filepath.Join(c.app.config.UploadDir, "img"), "upload/img", fmt.Sprintf("img_%d", uid))
	if !uploaded {
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "url": url})
}

func apiUtilsUploadVoice(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	if !hasMultipartFile(c, "voice") {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "未上传语音文件"})
		return
	}
	url, uploaded := uploadFile(c, "voice", voiceMimes, c.app.config.MaxVoiceBytes, filepath.Join(c.app.config.UploadDir, "voice"), "upload/voice", fmt.Sprintf("voice_%d", uid))
	if !uploaded {
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "url": url})
}

func apiBugReport(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	title := c.InputString("title")
	description := c.InputString("description")
	if title == "" || description == "" {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "标题和描述不能为空"})
		return
	}
	user := getUser(c.app, uid, "nickname, username")
	notice(c.app, c.app.config.AdminUID, "Bug反馈: "+title, fmt.Sprintf("来自用户：%s (@%s, UID: %d)\n\n%s", str(user, "nickname"), str(user, "username"), uid, description))
	privateSystemMessage(c.app, uid, c.app.config.AdminUID, fmt.Sprintf("Bug反馈\n标题: %s\n\n%s", title, description))
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "反馈已提交，感谢！"})
}

func apiTest(c *Ctx) {
	if _, err := c.app.fetchOne("SELECT id FROM chat_user LIMIT 1"); err != nil {
		panic(err)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "Database OK"})
}

func apiUtilsSessionExtend(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	key := c.InputString("key")
	if key == "" || !hmac.Equal([]byte(c.app.config.CacheSalt), []byte(key)) {
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	expiry := time.Now().Unix() + 8*3600
	c.ensureSession()
	c.session.SX = true
	c.session.SE = expiry
	c.markSessionDirty()
	setSessionExtCookie(c, expiry)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "ok", "active": true, "expires_at": expiry, "expires_in": 8 * 3600})
}

func apiUtilsSessionReset(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	if c.session != nil && c.session.SID != "" {
		c.session.SX = false
		c.session.SE = 0
		c.markSessionDirty()
	}
	clearSessionExtCookie(c)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "ok"})
}

func apiUtilsSessionInfo(c *Ctx) {
	active := sessionExtActive(c)
	expiry := int64(0)
	if active {
		expiry = sessionExtExpiry(c)
	}
	expiresIn := int64(0)
	if active && expiry > time.Now().Unix() {
		expiresIn = expiry - time.Now().Unix()
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "active": active, "expires_at": expiry, "expires_in": expiresIn})
}

func nullablePositiveInt(v int64) any {
	if v > 0 {
		return v
	}
	return nil
}

func reverseRows(rows []Row) {
	for i, j := 0, len(rows)-1; i < j; i, j = i+1, j-1 {
		rows[i], rows[j] = rows[j], rows[i]
	}
}

func clientIP(r *http.Request) string {
	if ip := strings.TrimSpace(r.Header.Get("CF-Connecting-IP")); ip != "" {
		return ip
	}
	if ip := strings.TrimSpace(r.Header.Get("X-Forwarded-For")); ip != "" {
		return strings.TrimSpace(strings.Split(ip, ",")[0])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}

func isWebSocketRequest(r *http.Request) bool {
	if !strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
		return false
	}
	for _, part := range strings.Split(r.Header.Get("Connection"), ",") {
		if strings.EqualFold(strings.TrimSpace(part), "upgrade") {
			return true
		}
	}
	return false
}

type wsSubscription struct {
	Type   string
	ID     int64
	Latest int64
}

type wsClient struct {
	uid           int64
	sessionExt    bool
	writer        *bufio.Writer
	subscriptions map[string]wsSubscription
}

type wsFrame struct {
	opcode  byte
	payload []byte
}

func (a *App) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	var conn net.Conn
	defer func() {
		if rec := recover(); rec != nil {
			log.Printf("panic handling websocket %s: %v", r.URL.String(), rec)
			if conn != nil {
				_ = conn.Close()
			} else {
				wsHTTPError(w, http.StatusInternalServerError)
			}
		}
	}()

	key := strings.TrimSpace(r.Header.Get("Sec-WebSocket-Key"))
	if key == "" {
		wsHTTPError(w, http.StatusBadRequest)
		return
	}
	ctx := NewCtx(a, w, r)
	uid, sessionExt, ok := a.authenticateWebSocket(ctx)
	if !ok {
		wsHTTPError(w, http.StatusUnauthorized)
		return
	}

	hijacker, ok := w.(http.Hijacker)
	if !ok {
		wsHTTPError(w, http.StatusInternalServerError)
		return
	}
	rwConn, rw, err := hijacker.Hijack()
	if err != nil {
		return
	}
	conn = rwConn
	accept := websocketAcceptKey(key)
	_, _ = fmt.Fprintf(rw.Writer, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\nCache-Control: no-store\r\n\r\n", accept)
	if err := rw.Writer.Flush(); err != nil {
		_ = conn.Close()
		return
	}

	client := &wsClient{uid: uid, sessionExt: sessionExt, writer: rw.Writer, subscriptions: map[string]wsSubscription{}}
	if err := wsSendJSON(client, map[string]any{"type": "hello", "server_time": time.Now().Unix()}); err != nil {
		_ = conn.Close()
		return
	}

	frames := make(chan wsFrame, 16)
	done := make(chan struct{})
	go func() {
		defer close(frames)
		for {
			frame, err := wsReadFrame(rw.Reader)
			if err != nil {
				return
			}
			select {
			case frames <- frame:
			case <-done:
				return
			}
		}
	}()

	ticker := time.NewTicker(time.Duration(a.config.LongPollSleepMillis) * time.Millisecond)
	defer func() {
		ticker.Stop()
		close(done)
		_ = conn.Close()
	}()
	for {
		select {
		case frame, open := <-frames:
			if !open {
				return
			}
			keep, err := a.wsHandleFrame(client, frame)
			if err != nil || !keep {
				return
			}
		case <-ticker.C:
			if err := a.wsEmitUpdates(client); err != nil {
				return
			}
		}
	}
}

func (a *App) authenticateWebSocket(c *Ctx) (int64, bool, bool) {
	sessionExt := sessionExtActive(c)
	uid := int64(0)
	if sessionExt {
		uid = sessionUIDFallback(c)
	} else if c.session != nil {
		uid = c.session.UID
	}
	if uid <= 0 || !checkUserExists(a, uid) || checkUserBan(a, uid) != nil {
		return 0, false, false
	}
	if a.config.RequireExistingUserEmailVerification && !userEmailVerified(a, uid) {
		return 0, false, false
	}
	touchUser(c, uid)
	return uid, sessionExt, true
}

func wsHTTPError(w http.ResponseWriter, status int) {
	w.Header().Set("Connection", "close")
	w.Header().Set("Content-Length", "0")
	w.WriteHeader(status)
}

func websocketAcceptKey(key string) string {
	sum := sha1.Sum([]byte(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
	return base64.StdEncoding.EncodeToString(sum[:])
}

func (a *App) wsHandleFrame(client *wsClient, frame wsFrame) (bool, error) {
	switch frame.opcode {
	case 8:
		return false, nil
	case 9:
		return true, wsSendFrame(client.writer, frame.payload, 10)
	case 1:
		var data map[string]any
		if err := json.Unmarshal(frame.payload, &data); err != nil {
			return true, nil
		}
		switch toString(data["type"]) {
		case "ping":
			return true, wsSendJSON(client, map[string]any{"type": "pong", "server_time": time.Now().Unix()})
		case "subscribe":
			conversations, _ := data["conversations"].([]any)
			if err := a.wsApplySubscriptions(client, conversations); err != nil {
				_ = wsSendJSON(client, map[string]any{"type": "error", "message": "Subscription failed."})
				return false, err
			}
		}
	}
	return true, nil
}

func (a *App) wsApplySubscriptions(client *wsClient, conversations []any) error {
	subscriptions := map[string]wsSubscription{}
	for _, raw := range conversations {
		item, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		conversationType := strings.ToLower(toString(inputAny(item, "conversation_type", inputAny(item, "type", ""))))
		id := toInt64Default(inputAny(item, "conversation_id", inputAny(item, "id", 0)), 0)
		if (conversationType == "room" || conversationType == "group") && id > 0 {
			conversationType = "group"
		} else if (conversationType == "friend" || conversationType == "private") && id > 0 {
			conversationType = "private"
		} else {
			continue
		}
		if !a.wsCanSubscribe(client.uid, conversationType, id, client.sessionExt) {
			continue
		}
		key := fmt.Sprintf("%s:%d", conversationType, id)
		subscriptions[key] = wsSubscription{Type: conversationType, ID: id, Latest: a.wsLatestID(client.uid, conversationType, id, 0)}
	}
	client.subscriptions = subscriptions
	return wsSendJSON(client, map[string]any{"type": "subscribed", "count": len(subscriptions), "server_time": time.Now().Unix()})
}

func (a *App) wsCanSubscribe(uid int64, conversationType string, id int64, sessionExt bool) bool {
	if sessionExt {
		return true
	}
	if conversationType == "group" {
		return isGroupMember(a, id, uid)
	}
	rel := friendRelation(a, uid, id)
	return rel != nil && intval(rel, "status") == 1
}

func (a *App) wsLatestID(uid int64, conversationType string, id int64, afterID int64) int64 {
	if conversationType == "group" {
		return latestGroupMessageID(a, id, afterID)
	}
	return latestPrivateMessageID(a, uid, id, afterID)
}

func (a *App) wsEmitUpdates(client *wsClient) error {
	keys := make([]string, 0, len(client.subscriptions))
	for key := range client.subscriptions {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		sub := client.subscriptions[key]
		latest := a.wsLatestID(client.uid, sub.Type, sub.ID, sub.Latest)
		if latest <= sub.Latest {
			continue
		}
		sub.Latest = latest
		client.subscriptions[key] = sub
		if err := wsSendJSON(client, map[string]any{"type": "conversation:update", "conversation_type": sub.Type, "conversation_id": sub.ID, "latest_id": latest, "server_time": time.Now().Unix()}); err != nil {
			return err
		}
	}
	return nil
}

func wsReadFrame(r *bufio.Reader) (wsFrame, error) {
	b1, err := r.ReadByte()
	if err != nil {
		return wsFrame{}, err
	}
	b2, err := r.ReadByte()
	if err != nil {
		return wsFrame{}, err
	}
	opcode := b1 & 0x0f
	masked := b2&0x80 != 0
	length := uint64(b2 & 0x7f)
	if length == 126 {
		buf := make([]byte, 2)
		if _, err := io.ReadFull(r, buf); err != nil {
			return wsFrame{}, err
		}
		length = uint64(binary.BigEndian.Uint16(buf))
	} else if length == 127 {
		buf := make([]byte, 8)
		if _, err := io.ReadFull(r, buf); err != nil {
			return wsFrame{}, err
		}
		length = binary.BigEndian.Uint64(buf)
	}
	if length > 1<<20 {
		return wsFrame{}, fmt.Errorf("websocket frame too large")
	}
	mask := make([]byte, 4)
	if masked {
		if _, err := io.ReadFull(r, mask); err != nil {
			return wsFrame{}, err
		}
	}
	payload := make([]byte, int(length))
	if length > 0 {
		if _, err := io.ReadFull(r, payload); err != nil {
			return wsFrame{}, err
		}
	}
	if masked {
		for i := range payload {
			payload[i] ^= mask[i%4]
		}
	}
	return wsFrame{opcode: opcode, payload: payload}, nil
}

func wsSendJSON(client *wsClient, data map[string]any) error {
	payload, err := json.Marshal(data)
	if err != nil {
		return err
	}
	return wsSendFrame(client.writer, payload, 1)
}

func wsSendFrame(w *bufio.Writer, payload []byte, opcode byte) error {
	header := []byte{0x80 | opcode}
	length := len(payload)
	if length <= 125 {
		header = append(header, byte(length))
	} else if length <= 65535 {
		header = append(header, 126, byte(length>>8), byte(length))
	} else {
		header = append(header, 127, 0, 0, 0, 0, byte(length>>24), byte(length>>16), byte(length>>8), byte(length))
	}
	if _, err := w.Write(header); err != nil {
		return err
	}
	if len(payload) > 0 {
		if _, err := w.Write(payload); err != nil {
			return err
		}
	}
	return w.Flush()
}

func inputAny(m map[string]any, key string, fallback any) any {
	if value, ok := m[key]; ok {
		return value
	}
	return fallback
}
