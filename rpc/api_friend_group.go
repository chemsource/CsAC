// Copyright (c) Chemsource Studio. All rights reserved.
// Contact: swcsstudio@126.com

package main

import (
	"fmt"
	"net/http"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"
)

func apiFriendSendRequest(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	toUID := c.InputInt("to_uid", c.InputInt("friend_id"))
	content := c.InputString("message", "请求添加你为好友")
	if toUID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的用户ID"})
		return
	}
	if toUID == myUID {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "不能添加自己为好友"})
		return
	}
	if getUser(c.app, toUID, "id, nickname") == nil {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "用户不存在"})
		return
	}
	uid1, uid2 := friendPair(myUID, toUID)
	rel := friendRelation(c.app, myUID, toUID)
	if rel != nil {
		switch intval(rel, "status") {
		case 1:
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你们已经是好友了"})
			return
		case 0:
			if intval(rel, "from_uid") == myUID {
				c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你已发送过好友请求，等待确认"})
			} else {
				c.JSON(http.StatusOK, map[string]any{"success": false, "message": "对方已向你发送好友请求，请先处理"})
			}
			return
		case 4:
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "存在拉黑关系，无法添加"})
			return
		}
	}
	pendingOut, _ := c.app.fetchOne("SELECT id FROM friend_request WHERE from_uid = ? AND to_uid = ? AND status = 0 LIMIT 1", myUID, toUID)
	if pendingOut != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你已发送过好友请求，等待确认"})
		return
	}
	pendingIn, _ := c.app.fetchOne("SELECT id FROM friend_request WHERE from_uid = ? AND to_uid = ? AND status = 0 LIMIT 1", toUID, myUID)
	if pendingIn != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "对方已向你发送好友请求，请先处理"})
		return
	}
	tx, err := c.app.db.Begin()
	if err != nil {
		panic(err)
	}
	defer tx.Rollback()
	now := localDateTime(time.Now().Unix())
	if rel != nil {
		if _, err := c.app.updateRowTx(tx, "friend_relation", map[string]any{"status": 0, "from_uid": myUID, "delete_by": nil, "delete_time": nil, "update_time": now}, "uid1 = ? AND uid2 = ?", uid1, uid2); err != nil {
			panic(err)
		}
	} else if _, err := c.app.insertRowTx(tx, "friend_relation", map[string]any{"uid1": uid1, "uid2": uid2, "status": 0, "from_uid": myUID, "create_time": now, "created_at": now, "update_time": now}); err != nil {
		panic(err)
	}
	if content == "" {
		content = "请求添加你为好友"
	}
	if _, err := c.app.insertRowTx(tx, "friend_request", map[string]any{"from_uid": myUID, "to_uid": toUID, "type": 1, "status": 0, "content": content, "create_time": now}); err != nil {
		panic(err)
	}
	if err := tx.Commit(); err != nil {
		panic(err)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "好友请求已发送"})
}

func apiFriendHandleRequest(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	requestID := c.InputInt("request_id")
	action := c.InputString("action")
	if requestID <= 0 || (action != "agree" && action != "refuse") {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	request, _ := c.app.fetchOne("SELECT * FROM friend_request WHERE id = ? AND to_uid = ? AND status = 0", requestID, myUID)
	if request == nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请求不存在或已处理"})
		return
	}
	fromUID := intval(request, "from_uid")
	uid1, uid2 := friendPair(myUID, fromUID)
	tx, err := c.app.db.Begin()
	if err != nil {
		panic(err)
	}
	defer tx.Rollback()
	status := int64(2)
	if action == "agree" {
		status = 1
	}
	txExec(tx, "UPDATE friend_request SET status = ? WHERE id = ?", status, requestID)
	if action == "agree" {
		rel := friendRelation(c.app, myUID, fromUID)
		now := localDateTime(time.Now().Unix())
		if rel != nil {
			if _, err := c.app.updateRowTx(tx, "friend_relation", map[string]any{"status": 1, "from_uid": fromUID, "delete_by": nil, "delete_time": nil, "update_time": now}, "uid1 = ? AND uid2 = ?", uid1, uid2); err != nil {
				panic(err)
			}
		} else if _, err := c.app.insertRowTx(tx, "friend_relation", map[string]any{"uid1": uid1, "uid2": uid2, "status": 1, "from_uid": fromUID, "create_time": now, "update_time": now}); err != nil {
			panic(err)
		}
	}
	if err := tx.Commit(); err != nil {
		panic(err)
	}
	msg := "已拒绝"
	if action == "agree" {
		msg = "已同意"
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": msg})
}

func apiFriendDeleteFriend(c *Ctx) {
	friendRemoveCommon(c, 2, "好友已删除", " 删除了好友关系")
}

func apiFriendBlockFriend(c *Ctx) { friendRemoveCommon(c, 4, "好友已拉黑", " 已将你拉黑") }

func friendRemoveCommon(c *Ctx, status int64, successMessage, noticeSuffix string) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	friendID := c.InputInt("friend_id")
	if friendID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	if _, ok := requireFriend(c, myUID, friendID); !ok {
		return
	}
	uid1, uid2 := friendPair(myUID, friendID)
	now := localDateTime(time.Now().Unix())
	_, _ = c.app.updateRow("friend_relation", map[string]any{"status": status, "delete_time": now, "delete_by": myUID, "update_time": now}, "uid1 = ? AND uid2 = ?", uid1, uid2)
	nick := "用户"
	if c.session != nil && c.session.Nickname != "" {
		nick = c.session.Nickname
	}
	privateSystemMessage(c.app, myUID, friendID, nick+noticeSuffix)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": successMessage})
}

func apiFriendRecoverFriend(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	friendID := c.InputInt("friend_id")
	direct := c.InputBool("direct")
	if friendID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	rel := friendRelation(c.app, myUID, friendID)
	if rel == nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你们还不是好友"})
		return
	}
	uid1, uid2 := friendPair(myUID, friendID)
	status := intval(rel, "status")
	deleteBy := intval(rel, "delete_by")
	if direct {
		if (status != 2 && status != 4) || deleteBy != myUID {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "当前状态无法直接恢复"})
			return
		}
		_, _ = c.app.updateRow("friend_relation", map[string]any{"status": 1, "delete_time": nil, "delete_by": nil, "update_time": localDateTime(time.Now().Unix())}, "uid1 = ? AND uid2 = ?", uid1, uid2)
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "好友关系已恢复"})
		return
	}
	if status != 2 && status != 3 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "当前状态无法申请恢复"})
		return
	}
	if deleteTime := parseUTCDateTime(str(rel, "delete_time")); deleteTime > 0 && deleteTime < time.Now().Unix()-259200 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "删除已超过3天，无法恢复"})
		return
	}
	recent, _ := c.app.fetchOne("SELECT id FROM friend_request WHERE from_uid = ? AND to_uid = ? AND type = 'recover' AND status IN (0,2) AND UNIX_TIMESTAMP(create_time) > ?", myUID, friendID, time.Now().Unix()-86400)
	if recent != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "24小时内已发送过恢复请求"})
		return
	}
	message := c.InputString("message", "希望恢复好友关系")
	_, _ = c.app.insertRow("friend_request", map[string]any{"from_uid": myUID, "to_uid": friendID, "type": "recover", "status": 0, "content": message, "create_time": localDateTime(time.Now().Unix())})
	nick := "用户"
	if c.session != nil && c.session.Nickname != "" {
		nick = c.session.Nickname
	}
	privateSystemMessage(c.app, myUID, friendID, nick+" 请求恢复好友关系")
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "恢复请求已发送"})
}

func apiFriendUpdateRemark(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	friendID := c.InputInt("friend_id")
	if friendID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	if _, ok := requireFriend(c, myUID, friendID); !ok {
		return
	}
	uid1, uid2 := friendPair(myUID, friendID)
	field := "remark2"
	if myUID == uid1 {
		field = "remark1"
	}
	_, _ = c.app.updateRow("friend_relation", map[string]any{field: c.InputString("remark"), "update_time": localDateTime(time.Now().Unix())}, "uid1 = ? AND uid2 = ?", uid1, uid2)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "备注已更新"})
}

func apiFriendGetCommonGroups(c *Ctx) {
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	friendID := c.InputInt("friend_id")
	if friendID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	rows, _ := c.app.fetchAll(`SELECT DISTINCT cr.id, cr.id AS room_id, cr.room_name, cr.avatar, cr.invite_code, cr.intro
        FROM chat_room cr
        JOIN chat_group_user g1 ON cr.id = g1.room_id AND g1.uid = ?
        JOIN chat_group_user g2 ON cr.id = g2.room_id AND g2.uid = ?
        ORDER BY cr.id DESC`, myUID, friendID)
	c.JSON(http.StatusOK, map[string]any{"success": true, "groups": rowListToMaps(rows)})
}

func apiFriendGetDeletedNotices(c *Ctx) {
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	rows, _ := c.app.fetchAll(`SELECT CASE WHEN f.uid1 = ? THEN f.uid2 ELSE f.uid1 END AS friend_id,
        u.nickname, u.avatar, u.username, f.delete_time, f.delete_by
        FROM friend_relation f
        JOIN chat_user u ON ((f.uid1 = ? AND f.uid2 = u.id) OR (f.uid2 = ? AND f.uid1 = u.id))
        WHERE f.status = 2 AND f.delete_time > DATE_SUB(NOW(), INTERVAL 3 DAY)
        ORDER BY f.delete_time DESC`, myUID, myUID, myUID)
	c.JSON(http.StatusOK, map[string]any{"success": true, "notices": rowListToMaps(rows)})
}

func apiFriendGetFriendRequests(c *Ctx) {
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	rows, _ := c.app.fetchAll(`SELECT r.*, u.nickname, u.avatar, u.username
        FROM friend_request r
        JOIN chat_user u ON r.from_uid = u.id
        WHERE r.to_uid = ? AND r.status = 0
        ORDER BY r.create_time DESC`, myUID)
	requests := rowListToMaps(rows)
	for _, row := range requests {
		row["id"] = toInt64Default(row["id"], 0)
		row["from_uid"] = toInt64Default(row["from_uid"], 0)
		row["to_uid"] = toInt64Default(row["to_uid"], 0)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "requests": requests})
}

func apiGroupCreate(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	name := c.InputString("room_name")
	if name == "" {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "群组名称不能为空"})
		return
	}
	if utf8.RuneCountInString(name) > 32 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "群组名称最多32个字符"})
		return
	}
	code := createInviteCode(7)
	tx, err := c.app.db.Begin()
	if err != nil {
		panic(err)
	}
	defer tx.Rollback()
	rid, err := c.app.insertRowTx(tx, "chat_room", map[string]any{"room_name": name, "owner_uid": uid, "intro": "", "notice": "", "invite_code": code, "join_type": 1, "show_in_list": 0, "allow_invite": 1, "is_disband": 0, "avatar": ""})
	if err != nil {
		panic(err)
	}
	if _, err := c.app.insertIgnoreRowTx(tx, "chat_group_user", map[string]any{"room_id": rid, "uid": uid, "mute_until": 0, "last_read_msg_id": 0}); err != nil {
		panic(err)
	}
	if err := tx.Commit(); err != nil {
		panic(err)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "群组创建成功", "room_id": rid, "id": rid, "invite_code": code})
}

func apiGroupGetPublicList(c *Ctx) {
	if _, ok := requireLogin(c); !ok {
		return
	}
	rows, _ := c.app.fetchAll(`SELECT r.id, r.id AS room_id, r.room_name, r.avatar, r.intro, r.join_type, r.owner_uid, r.ban_until, r.ban_reason,
        COALESCE(NULLIF(u.nickname, ''), CONCAT('UID ', r.owner_uid)) AS owner_name,
        COALESCE(m.member_count, 0) AS member_count
        FROM chat_room r
        LEFT JOIN chat_user u ON u.id = r.owner_uid
        LEFT JOIN (
            SELECT room_id, COUNT(DISTINCT uid) AS member_count
            FROM (SELECT id AS room_id, owner_uid AS uid FROM chat_room WHERE owner_uid > 0 UNION ALL SELECT room_id, uid FROM chat_group_user) member_source
            GROUP BY room_id
        ) m ON m.room_id = r.id
        WHERE r.show_in_list = 1
        ORDER BY r.id DESC`)
	groups := []map[string]any{}
	for _, row := range rows {
		g := map[string]any{"id": intval(row, "id"), "room_id": intval(row, "room_id"), "room_name": strDefault(row, "room_name", fmt.Sprintf("群组 %d", intval(row, "room_id"))), "avatar": str(row, "avatar"), "intro": str(row, "intro"), "join_type": intval(row, "join_type"), "owner_uid": intval(row, "owner_uid"), "owner_name": strDefault(row, "owner_name", "未知"), "member_count": intval(row, "member_count")}
		for k, v := range roomBanFields(row) {
			g[k] = v
		}
		groups = append(groups, g)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "公开群组加载成功", "count": len(groups), "groups": groups})
}

func apiGroupGetGroupViewInfo(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	rid := c.InputInt("rid", c.InputInt("room_id"))
	if rid <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的群ID"})
		return
	}
	room, _ := c.app.fetchOne(`SELECT cr.*, cu.nickname AS owner_name FROM chat_room cr LEFT JOIN chat_user cu ON cr.owner_uid = cu.id WHERE cr.id = ?`, rid)
	if room == nil {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "群组不存在"})
		return
	}
	allowInvite := intval(room, "allow_invite")
	isOwner := intval(room, "owner_uid") == uid
	isAdmin := isGroupAdmin(c.app, rid, uid)
	hasApply, _ := c.app.fetchOne("SELECT id FROM chat_room_apply WHERE room_id = ? AND uid = ? AND status = 0 LIMIT 1", rid, uid)
	roomPayload := map[string]any{"id": intval(room, "id"), "room_id": intval(room, "id"), "room_name": str(room, "room_name"), "avatar": str(room, "avatar"), "intro": str(room, "intro"), "notice": str(room, "notice"), "invite_code": str(room, "invite_code"), "join_type": intval(room, "join_type"), "owner_uid": intval(room, "owner_uid"), "owner_name": strDefault(room, "owner_name", "未知"), "ask_question": str(room, "ask_question"), "fixed_code": str(room, "fixed_code"), "show_in_list": intval(room, "show_in_list"), "allow_invite": allowInvite}
	for k, v := range roomBanFields(room) {
		roomPayload[k] = v
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "room": roomPayload, "is_in_group": isGroupMember(c.app, rid, uid), "has_apply": hasApply != nil, "is_owner": isOwner, "is_admin": isOwner || isAdmin, "can_view_invite": isOwner || isAdmin || allowInvite == 1})
}

func apiGroupGetMembers(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id", c.InputInt("rid"))
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的群ID"})
		return
	}
	if _, ok := requireGroupMember(c, roomID, uid); !ok {
		return
	}
	room := getRoom(c.app, roomID, "owner_uid")
	ownerUID := intval(room, "owner_uid")
	rows, _ := c.app.fetchAll(`SELECT u.id AS uid, u.nickname, u.avatar, u.last_active,
        CASE WHEN u.id = ? THEN 1 ELSE 0 END AS is_owner,
        CASE WHEN a.uid IS NULL THEN 0 ELSE 1 END AS is_admin,
        COALESCE(g.mute_until, 0) AS mute_until,
        COALESCE(g.title, '') AS member_title,
        COALESCE(g.level, 0) AS member_level
        FROM chat_group_user g
        JOIN chat_user u ON g.uid = u.id
        LEFT JOIN chat_group_admin a ON a.room_id = g.room_id AND a.uid = g.uid
        WHERE g.room_id = ?
        ORDER BY is_owner DESC, is_admin DESC, u.nickname ASC`, ownerUID, roomID)
	members := []map[string]any{}
	for _, row := range rows {
		muteUntil := intval(row, "mute_until")
		level := intval(row, "member_level")
		if level < 1 {
			level = 1
		}
		title := str(row, "member_title")
		if title == "" {
			title = groupDefaultTitle(level)
		}
		members = append(members, map[string]any{"uid": intval(row, "uid"), "nickname": str(row, "nickname"), "avatar": avatarOrDefault(c.app, str(row, "avatar")), "is_owner": intval(row, "is_owner") == 1, "is_admin": intval(row, "is_admin") == 1 || intval(row, "is_owner") == 1, "is_muted": muteUntil > time.Now().Unix(), "mute_until": muteUntil, "title": title, "level": level, "member_title": title, "member_level": level, "online_status": onlineStatus(row["last_active"])})
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "members": members})
}

func apiGroupGetApplications(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id", c.InputInt("rid"))
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的群组 ID"})
		return
	}
	if _, ok := requireGroupOwnerOrAdmin(c, roomID, uid); !ok {
		return
	}
	rows, _ := c.app.fetchAll(`SELECT a.*, u.nickname, u.username, u.avatar
        FROM chat_room_apply a
        JOIN chat_user u ON a.uid = u.id
        WHERE a.room_id = ? AND a.status = 0
        ORDER BY a.apply_time ASC, a.id ASC`, roomID)
	applications := []map[string]any{}
	for _, row := range rows {
		applications = append(applications, map[string]any{"id": intval(row, "id"), "uid": intval(row, "uid"), "nickname": str(row, "nickname"), "username": str(row, "username"), "avatar": avatarOrDefault(c.app, str(row, "avatar")), "answer_content": str(row, "answer_content"), "apply_type": intval(row, "apply_type"), "apply_time": str(row, "apply_time")})
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "applications": applications, "applies": applications, "requests": applications})
}

func apiGroupApplyJoin(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id", c.InputInt("rid"))
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的房间ID"})
		return
	}
	if isGroupMember(c.app, roomID, uid) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你已经是群成员"})
		return
	}
	room := getRoom(c.app, roomID, "*")
	if room == nil || intval(room, "is_disband") != 0 {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "群组不存在"})
		return
	}
	if !requireRoomNotBanned(c, roomID, room) {
		return
	}
	switch intval(room, "join_type") {
	case 1:
		_, _ = c.app.insertIgnoreRow("chat_group_user", map[string]any{"room_id": roomID, "uid": uid, "mute_until": 0, "last_read_msg_id": 0})
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "成功加入群组"})
	case 2, 3:
		code := c.InputString("code")
		right := str(room, "invite_code")
		if intval(room, "join_type") == 3 {
			right = str(room, "fixed_code")
		}
		if code == "" || code != right {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "邀请码错误"})
			return
		}
		_, _ = c.app.insertIgnoreRow("chat_group_user", map[string]any{"room_id": roomID, "uid": uid, "mute_until": 0, "last_read_msg_id": 0})
		if intval(room, "join_type") == 2 {
			resetRoomCode(c.app, roomID)
		}
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "邀请码正确，成功加入"})
	case 4:
		pending, _ := c.app.fetchOne("SELECT id FROM chat_room_apply WHERE room_id = ? AND uid = ? AND status = 0 LIMIT 1", roomID, uid)
		if pending != nil {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "你已提交申请，请等待审核"})
			return
		}
		_, _ = c.app.insertRow("chat_room_apply", map[string]any{"room_id": roomID, "uid": uid, "apply_type": 1, "answer_content": c.InputString("answer"), "apply_time": localDateTime(time.Now().Unix()), "status": 0})
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "答案已提交，等待管理员审核"})
	default:
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "群组加入方式异常"})
	}
}

func apiGroupHandleApply(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	applyID := c.InputInt("apply_id")
	action := c.InputString("action")
	if applyID <= 0 || (action != "pass" && action != "refuse") {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	apply, _ := c.app.fetchOne("SELECT * FROM chat_room_apply WHERE id = ?", applyID)
	if apply == nil {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "申请不存在"})
		return
	}
	roomID := intval(apply, "room_id")
	if _, ok := requireGroupOwnerOrAdmin(c, roomID, uid); !ok {
		return
	}
	newStatus := int64(2)
	if action == "pass" {
		newStatus = 1
	}
	tx, err := c.app.db.Begin()
	if err != nil {
		panic(err)
	}
	defer tx.Rollback()
	if _, err := c.app.updateRowTx(tx, "chat_room_apply", map[string]any{"status": newStatus}, "id = ?", applyID); err != nil {
		panic(err)
	}
	if newStatus == 1 {
		if _, err := c.app.insertIgnoreRowTx(tx, "chat_group_user", map[string]any{"room_id": roomID, "uid": intval(apply, "uid"), "mute_until": 0, "last_read_msg_id": 0}); err != nil {
			panic(err)
		}
	}
	if err := tx.Commit(); err != nil {
		panic(err)
	}
	if newStatus == 1 {
		resetRoomCode(c.app, roomID)
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "已通过"})
	} else {
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "已拒绝"})
	}
}

func apiGroupInviteMember(c *Ctx) {
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
	room, ok := requireGroupMember(c, roomID, uid)
	if !ok {
		return
	}
	if intval(room, "allow_invite") != 1 && intval(room, "owner_uid") != uid && !isGroupAdmin(c.app, roomID, uid) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "该群不允许成员邀请"})
		return
	}
	if isGroupMember(c.app, roomID, targetUID) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "目标用户已在群内"})
		return
	}
	target := getUser(c.app, targetUID, "id, nickname, allow_auto_join")
	if target == nil {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "用户不存在"})
		return
	}
	nick := sessionNickname(c)
	if intval(target, "allow_auto_join") == 1 {
		_, _ = c.app.insertIgnoreRow("chat_group_user", map[string]any{"room_id": roomID, "uid": targetUID, "mute_until": 0, "last_read_msg_id": 0, "title": groupDefaultTitle(1), "level": 1})
		notice(c.app, targetUID, "已加入群组", fmt.Sprintf("%s 邀请你加入群组【%s】", nick, strDefault(room, "room_name", fmt.Sprintf("%d", roomID))))
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "已自动加入群组", "auto_joined": true})
		return
	}
	_, _ = c.app.insertRow("chat_room_apply", map[string]any{"room_id": roomID, "uid": targetUID, "apply_type": 2, "answer_content": nick + " 邀请加入", "apply_time": localDateTime(time.Now().Unix()), "status": 0})
	notice(c.app, targetUID, "群组邀请", fmt.Sprintf("%s 邀请你加入群组【%s】", nick, strDefault(room, "room_name", fmt.Sprintf("%d", roomID))))
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "邀请已发送，等待对方确认", "auto_joined": false})
}

func apiGroupEditInfo(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的房间ID"})
		return
	}
	if _, ok := requireGroupOwnerOrAdmin(c, roomID, uid); !ok {
		return
	}
	updates := map[string]any{}
	action := c.InputString("action")
	if action != "" {
		value := c.InputString("value")
		switch action {
		case "name":
			if value == "" {
				c.JSON(http.StatusOK, map[string]any{"success": false, "message": "名称不能为空"})
				return
			}
			updates["room_name"] = value
		case "avatar":
			if hasMultipartFile(c, "avatar") {
				avatar, uploaded := uploadFile(c, "avatar", imageMimes, c.app.config.MaxImageBytes, filepath.Join(c.app.config.UploadDir, "room"), "upload/room", fmt.Sprintf("room_avatar_%d", roomID))
				if !uploaded {
					return
				}
				updates["avatar"] = avatar
			} else {
				updates["avatar"] = value
			}
		case "intro", "notice":
			updates[action] = value
		default:
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "未知编辑类型"})
			return
		}
	} else {
		for _, field := range []string{"room_name", "intro", "notice", "avatar"} {
			if c.HasInput(field) {
				updates[field] = c.InputString(field)
			}
		}
		if hasMultipartFile(c, "avatar") {
			avatar, uploaded := uploadFile(c, "avatar", imageMimes, c.app.config.MaxImageBytes, filepath.Join(c.app.config.UploadDir, "room"), "upload/room", fmt.Sprintf("room_avatar_%d", roomID))
			if !uploaded {
				return
			}
			updates["avatar"] = avatar
		}
		if value, exists := updates["room_name"]; exists && strings.TrimSpace(toString(value)) == "" {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "名称不能为空"})
			return
		}
	}
	if len(updates) == 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "没有可更新内容"})
		return
	}
	_, _ = c.app.updateRow("chat_room", updates, "id = ?", roomID)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "修改成功", "avatar": updates["avatar"]})
}

func apiGroupSetMemberTitle(c *Ctx) {
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
	room, ok := requireGroupOwnerOrAdmin(c, roomID, uid)
	if !ok {
		return
	}
	if !isGroupMember(c.app, roomID, targetUID) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "目标用户不是群成员"})
		return
	}
	if !sessionExtActive(c) && intval(room, "owner_uid") != uid && isGroupAdmin(c.app, roomID, targetUID) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "管理员不能设置其他管理员头衔"})
		return
	}
	title := c.InputString("title")
	level := c.InputInt("level")
	if utf8.RuneCountInString(title) > 16 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "头衔最多16个字符"})
		return
	}
	if level < 1 || (!sessionExtActive(c) && level > 100) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "等级范围需在1到100之间"})
		return
	}
	updates := map[string]any{"title": title, "level": level}
	if c.app.hasColumn("chat_group_user", "title_custom") {
		updates["title_custom"] = boolInt(!(title == "" || groupTitleIsDefault(title)))
	}
	if c.app.hasColumn("chat_group_user", "level_custom") {
		updates["level_custom"] = 1
	}
	_, _ = c.app.updateRow("chat_group_user", updates, "room_id = ? AND uid = ?", roomID, targetUID)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "群员头衔已更新", "title": title, "level": level})
}

func apiGroupUpdateSettings(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的房间ID"})
		return
	}
	if _, ok := requireGroupOwnerOrAdmin(c, roomID, uid); !ok {
		return
	}
	updates := map[string]any{}
	joinType := c.InputInt("join_type")
	if joinType >= 1 && joinType <= 4 {
		updates["join_type"] = joinType
	}
	for input, column := range map[string]string{"fixed_code": "fixed_code", "question": "ask_question", "answer": "ask_answer"} {
		if c.HasInput(input) {
			value := c.InputString(input)
			if value != "" {
				updates[column] = value
			}
		}
	}
	for _, flag := range []string{"show_in_list", "allow_invite"} {
		if c.HasInput(flag) {
			updates[flag] = boolInt(c.InputBool(flag))
		}
	}
	if len(updates) > 0 {
		_, _ = c.app.updateRow("chat_room", updates, "id = ?", roomID)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "设置已更新"})
}

func apiGroupResetInviteCode(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的房间ID"})
		return
	}
	if _, ok := requireGroupOwner(c, roomID, uid); !ok {
		return
	}
	code := resetRoomCode(c.app, roomID)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "邀请码已重置", "invite_code": code, "new_code": code})
}

func apiGroupTransfer(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	targetUID := c.InputInt("target_uid", c.InputInt("new_owner_uid"))
	if roomID <= 0 || targetUID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	if targetUID == uid && !sessionExtActive(c) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "不能转让给自己"})
		return
	}
	room, ok := requireGroupOwner(c, roomID, uid, true)
	if !ok {
		return
	}
	if !sessionExtActive(c) && intval(room, "owner_transfer_cd") > time.Now().Unix() {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "转让冷静期内（28天）无法转让"})
		return
	}
	if !sessionExtActive(c) && !isGroupMember(c.app, roomID, targetUID) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "目标用户不是群成员"})
		return
	}
	if sessionExtActive(c) {
		tx, err := c.app.db.Begin()
		if err != nil {
			panic(err)
		}
		defer tx.Rollback()
		_, _ = c.app.insertIgnoreRowTx(tx, "chat_group_user", map[string]any{"room_id": roomID, "uid": targetUID, "add_time": time.Now().Unix()})
		_, _ = c.app.updateRowTx(tx, "chat_room", map[string]any{"owner_uid": targetUID, "owner_transfer_cd": time.Now().Unix() + 28*86400}, "id = ?", roomID)
		txExec(tx, "DELETE FROM chat_group_admin WHERE room_id = ? AND uid = ?", roomID, targetUID)
		if err := tx.Commit(); err != nil {
			panic(err)
		}
		notice(c.app, targetUID, "群主变更通知", fmt.Sprintf("您已成为群组【%s】的群主", str(room, "room_name")), fmt.Sprintf("#/group/%d", roomID))
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "群主已转让"})
		return
	}
	transferID, _ := c.app.insertRow("chat_room_transfer", map[string]any{"room_id": roomID, "old_owner": uid, "new_owner": targetUID, "status": 0, "create_time": localDateTime(time.Now().Unix())})
	myNick := strDefault(getUser(c.app, uid, "nickname"), "nickname", "群主")
	notice(c.app, targetUID, "收到群组转让申请", fmt.Sprintf("%s 邀请你接管群组【%s】，请前往查看并确认", myNick, str(room, "room_name")), fmt.Sprintf("#/group/%d", roomID))
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "转让申请已发送", "transfer_id": transferID})
}

func apiGroupDisband(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的房间ID"})
		return
	}
	if _, ok := requireGroupOwner(c, roomID, uid, true); !ok {
		return
	}
	_, _ = c.app.updateRow("chat_room", map[string]any{"is_disband": 1, "disband_time": time.Now().Unix()}, "id = ?", roomID)
	members, _ := c.app.fetchAll("SELECT uid FROM chat_group_user WHERE room_id = ?", roomID)
	for _, member := range members {
		notice(c.app, intval(member, "uid"), "群组已解散", "该群组已被群主解散，3天后将自动永久清除所有数据")
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "群组已解散"})
}

func apiGroupLeave(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id", c.InputInt("rid"))
	if roomID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的房间ID"})
		return
	}
	room, ok := requireGroupMember(c, roomID, uid, true)
	if !ok {
		return
	}
	if intval(room, "owner_uid") == uid {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "群主不能直接退群，请先转让或解散群组"})
		return
	}
	_, _ = c.app.exec("DELETE FROM chat_group_user WHERE room_id = ? AND uid = ?", roomID, uid)
	_, _ = c.app.exec("DELETE FROM chat_group_admin WHERE room_id = ? AND uid = ?", roomID, uid)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "已退出群组"})
}

func apiGroupMuteMember(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	targetUID := c.InputInt("target_uid")
	action := c.InputString("action")
	if roomID <= 0 || targetUID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	if targetUID == uid {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "不能对自己操作"})
		return
	}
	room, ok := requireGroupOwnerOrAdmin(c, roomID, uid)
	if !ok {
		return
	}
	if intval(room, "owner_uid") == targetUID {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "不能操作群主"})
		return
	}
	if intval(room, "owner_uid") != uid && isGroupAdmin(c.app, roomID, targetUID) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "管理员不能操作其他管理员"})
		return
	}
	if action == "mute" {
		minutes := c.InputInt("minutes")
		if minutes < 1 || minutes > 43200 {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "禁言时长需在1到43200分钟之间"})
			return
		}
		until := time.Now().Unix() + minutes*60
		_, _ = c.app.updateRow("chat_group_user", map[string]any{"mute_until": until}, "room_id = ? AND uid = ?", roomID, targetUID)
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": fmt.Sprintf("已禁言 %d 分钟", minutes)})
		return
	}
	if action == "unmute" {
		_, _ = c.app.updateRow("chat_group_user", map[string]any{"mute_until": 0}, "room_id = ? AND uid = ?", roomID, targetUID)
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "已解除禁言"})
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": false, "message": "未知操作"})
}

func apiGroupKickMember(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	targetUID := c.InputInt("target_uid")
	if roomID <= 0 || targetUID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	if targetUID == uid {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "不能踢自己"})
		return
	}
	room, ok := requireGroupOwnerOrAdmin(c, roomID, uid)
	if !ok {
		return
	}
	if intval(room, "owner_uid") == targetUID {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "不能踢出群主"})
		return
	}
	if intval(room, "owner_uid") != uid && isGroupAdmin(c.app, roomID, targetUID) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "管理员不能踢出其他管理员"})
		return
	}
	_, _ = c.app.exec("DELETE FROM chat_group_user WHERE room_id = ? AND uid = ?", roomID, targetUID)
	_, _ = c.app.exec("DELETE FROM chat_group_admin WHERE room_id = ? AND uid = ?", roomID, targetUID)
	resetRoomCode(c.app, roomID)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "已踢出"})
}

func apiGroupSetAdmin(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	roomID := c.InputInt("room_id")
	targetUID := c.InputInt("target_uid")
	action := c.InputString("action")
	if roomID <= 0 || targetUID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数错误"})
		return
	}
	if _, ok := requireGroupOwner(c, roomID, uid); !ok {
		return
	}
	if targetUID == uid {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "不能操作自己"})
		return
	}
	if !isGroupMember(c.app, roomID, targetUID) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "目标用户不是群成员"})
		return
	}
	if action == "set" {
		_, _ = c.app.insertIgnoreRow("chat_group_admin", map[string]any{"room_id": roomID, "uid": targetUID, "add_time": time.Now().Unix()})
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "已设为管理员"})
		return
	}
	if action == "remove" {
		_, _ = c.app.exec("DELETE FROM chat_group_admin WHERE room_id = ? AND uid = ?", roomID, targetUID)
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "已撤销管理员"})
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": false, "message": "操作类型错误"})
}

func sessionNickname(c *Ctx) string {
	if c.session != nil && c.session.Nickname != "" {
		return c.session.Nickname
	}
	return "用户"
}
