// Copyright (c) Chemsource Studio. All rights reserved.
// Contact: swcsstudio@126.com

package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"fmt"
	"log"
	"math/rand"
	"net"
	"net/http"
	"net/mail"
	"net/smtp"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"golang.org/x/crypto/bcrypt"
)

func apiAuthLogin(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	username := c.InputString("username")
	pwd := c.InputString("pwd")
	platform := normalizePlatform(c.InputString("platform"))
	if username == "" || pwd == "" || platform == "" {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请填写账号、密码和客户端标识"})
		return
	}
	user, err := c.app.fetchOne("SELECT * FROM chat_user WHERE username = ?", username)
	if err != nil || user == nil || !isPasswordValid(user, pwd) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "账号或密码错误"})
		return
	}
	uid := intval(user, "id")
	if ban := checkUserBan(c.app, uid); ban != nil {
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "账号已封禁", "ban_info": ban})
		return
	}
	if c.session != nil && c.session.SID != "" {
		_, _ = c.app.exec("DELETE FROM csac_sessions WHERE sid = ?", c.session.SID)
	}
	c.session = &Session{SID: randomSessionID(), UID: uid, Nickname: str(user, "nickname"), Platform: platform, ExpiresAt: time.Now().Unix() + c.app.config.SessionLifetimeSeconds, dirty: true}
	updateUserPlatform(c.app, uid, platform)
	touchUser(c, uid)
	needGuide := intval(user, "is_first_login") == 1
	if needGuide {
		_, _ = c.app.updateRow("chat_user", map[string]any{"is_first_login": 0}, "id = ?", uid)
	}
	needsEmail := c.app.config.RequireExistingUserEmailVerification && strings.TrimSpace(str(user, "email")) == ""
	c.JSON(http.StatusOK, map[string]any{
		"success": true, "message": "登录成功", "need_guide": needGuide, "needs_email_verification": needsEmail, "platform": platform,
		"user": map[string]any{"uid": uid, "nickname": str(user, "nickname"), "platform": platform},
	})
}

func apiAuthSendEmailBindCode(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requirePendingEmailUser(c)
	if !ok {
		return
	}
	email := normalizeRegisterEmail(c.InputString("email"))
	if email == "" {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请输入有效的邮箱地址"})
		return
	}
	row, _ := c.app.fetchOne("SELECT id FROM chat_user WHERE email = ? AND id <> ? LIMIT 1", email, uid)
	if row != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "该邮箱已被注册"})
		return
	}
	sendRegisterCodeCommon(c, email, true)
}

func apiAuthVerifyEmailBindCode(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requirePendingEmailUser(c)
	if !ok {
		return
	}
	email := normalizeRegisterEmail(c.InputString("email"))
	code := c.InputString("email_code")
	if email == "" || code == "" {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请填写邮箱和验证码"})
		return
	}
	row, _ := c.app.fetchOne("SELECT id FROM chat_user WHERE email = ? AND id <> ? LIMIT 1", email, uid)
	if row != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "该邮箱已被注册"})
		return
	}
	codeID, ok := verifiedRegisterEmailCodeID(c, email, code)
	if !ok {
		return
	}
	tx, err := c.app.db.Begin()
	if err != nil {
		panic(err)
	}
	defer tx.Rollback()
	used := txExec(tx, "UPDATE register_email_codes SET used_at = ? WHERE id = ? AND used_at = 0", time.Now().Unix(), codeID)
	if used != 1 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "验证码已失效，请重新获取"})
		return
	}
	if _, err := c.app.updateRowTx(tx, "chat_user", map[string]any{"email": email}, "id = ?", uid); err != nil {
		panic(err)
	}
	if err := tx.Commit(); err != nil {
		panic(err)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "邮箱验证已完成"})
}

func apiAuthSendRegisterCode(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	if !c.app.config.RequireRegisterEmailVerification {
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "邮箱验证未启用"})
		return
	}
	email := normalizeRegisterEmail(c.InputString("email"))
	if email == "" {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请输入有效的邮箱地址"})
		return
	}
	row, _ := c.app.fetchOne("SELECT id FROM chat_user WHERE email = ? LIMIT 1", email)
	if row != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "该邮箱已被注册"})
		return
	}
	sendRegisterCodeCommon(c, email, false)
}

func sendRegisterCodeCommon(c *Ctx, email string, bind bool) {
	now := time.Now().Unix()
	ipHash := registerEmailIPHash(c)
	cooldownSince := now - registerEmailResendSeconds
	recentEmail, _ := c.app.fetchOne("SELECT id FROM register_email_codes WHERE email = ? AND created_at > ? LIMIT 1", email, cooldownSince)
	recentIP, _ := c.app.fetchOne("SELECT id FROM register_email_codes WHERE ip_hash = ? AND created_at > ? LIMIT 1", ipHash, cooldownSince)
	if recentEmail != nil || recentIP != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "验证码发送过于频繁，请稍后再试"})
		return
	}
	hourSince := now - 3600
	emailCount, _ := c.app.fetchOne("SELECT COUNT(*) AS c FROM register_email_codes WHERE email = ? AND created_at > ?", email, hourSince)
	ipCount, _ := c.app.fetchOne("SELECT COUNT(*) AS c FROM register_email_codes WHERE ip_hash = ? AND created_at > ?", ipHash, hourSince)
	if intval(emailCount, "c") >= registerEmailMaxSendsPerHour || intval(ipCount, "c") >= registerEmailMaxSendsPerHour {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "验证码发送次数过多，请稍后再试"})
		return
	}
	code := fmt.Sprintf("%06d", rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000)+100000)
	hash, err := bcrypt.GenerateFromPassword([]byte(code), bcrypt.DefaultCost)
	if err != nil {
		panic(err)
	}
	codeID, err := c.app.insertRow("register_email_codes", map[string]any{"email": email, "code_hash": string(hash), "ip_hash": ipHash, "attempts": 0, "used_at": 0, "expires_at": now + registerEmailCodeTTL, "created_at": now})
	if err != nil {
		panic(err)
	}
	if err := sendRegisterEmailCode(c.app, email, code); err != nil {
		log.Printf("send register email code to %s failed: %v", email, err)
		_, _ = c.app.exec("DELETE FROM register_email_codes WHERE id = ?", codeID)
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "验证码邮件发送失败，请稍后再试"})
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "验证码已发送，请查收邮箱", "expires_in": registerEmailCodeTTL, "resend_after": registerEmailResendSeconds})
}

func apiAuthRegister(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	banNames := map[string]bool{"root": true, "admin": true, "administrator": true, "system": true, "guest": true, "客服": true, "管理": true, "管理员": true, "超级管理员": true, "官方": true, "站长": true, "后台": true}
	username := c.InputString("username")
	nickname := c.InputString("nickname")
	pwd := c.InputString("pwd")
	confirmPwd := c.InputString("confirm_pwd")
	email := normalizeRegisterEmail(c.InputString("email"))
	emailCode := c.InputString("email_code")
	if username == "" || nickname == "" || pwd == "" || confirmPwd == "" || (c.app.config.RequireRegisterEmailVerification && (email == "" || emailCode == "")) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请填写完整表单"})
		return
	}
	if c.app.config.RequireRegisterEmailVerification && email == "" {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请输入有效的邮箱地址"})
		return
	}
	if banNames[strings.ToLower(username)] || banNames[strings.ToLower(nickname)] {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "不允许使用管理员/系统保留账号昵称！"})
		return
	}
	if !regexp.MustCompile(`^[A-Za-z0-9_@.\-]{3,32}$`).MatchString(username) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "账号需为3-32位字母、数字或常用符号"})
		return
	}
	if utf8.RuneCountInString(nickname) > 16 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "昵称最多16个字符"})
		return
	}
	if pwd != confirmPwd {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "两次密码不一致"})
		return
	}
	if len(pwd) < 6 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "密码至少6位"})
		return
	}
	row, _ := c.app.fetchOne("SELECT id FROM chat_user WHERE username = ?", username)
	if row != nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "该登录账号已被注册"})
		return
	}
	if c.app.config.RequireRegisterEmailVerification {
		row, _ = c.app.fetchOne("SELECT id FROM chat_user WHERE email = ? LIMIT 1", email)
		if row != nil {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "该邮箱已被注册"})
			return
		}
	}
	codeID := int64(0)
	if c.app.config.RequireRegisterEmailVerification {
		var ok bool
		codeID, ok = verifiedRegisterEmailCodeID(c, email, emailCode)
		if !ok {
			return
		}
	}
	tx, err := c.app.db.Begin()
	if err != nil {
		panic(err)
	}
	defer tx.Rollback()
	if codeID > 0 {
		used := txExec(tx, "UPDATE register_email_codes SET used_at = ? WHERE id = ? AND used_at = 0", time.Now().Unix(), codeID)
		if used != 1 {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "验证码已失效，请重新获取"})
			return
		}
	}
	newUID, err := c.app.insertRowTx(tx, "chat_user", map[string]any{"username": username, "nickname": nickname, "email": nullableString(email), "pwd": hashPassword(pwd, username), "add_time": time.Now().Unix(), "avatar": c.app.config.DefaultAvatar, "is_first_login": 1, "last_active": time.Now().Unix()})
	if err != nil {
		panic(err)
	}
	if hasMultipartFile(c, "avatar") {
		if err := tx.Commit(); err != nil {
			panic(err)
		}
		avatar, ok := uploadFile(c, "avatar", imageMimes, c.app.config.MaxImageBytes, c.app.config.UploadDir, "upload", fmt.Sprintf("avatar_%d", newUID))
		if !ok {
			return
		}
		_, _ = c.app.updateRow("chat_user", map[string]any{"avatar": avatar}, "id = ?", newUID)
	} else {
		regDate := localDateTime(time.Now().Unix())
		_, _ = c.app.insertRowTx(tx, "chat_user_notice", map[string]any{"uid": newUID, "title": "欢迎使用 CsAC 在线聊天", "content": fmt.Sprintf("亲爱的%s：\n您好！\n感谢您使用Chemsource AtsukaCIT Chatting。\n\n使用指南：\n1. 登录后可创建群组，或通过群组编号、邀请码加入聊天室；\n2. 支持文字、图片、语音、好友和群组管理；\n3. 请文明交流，遇到问题可联系网站管理员。\n\nCsAC在线聊天网站管理员 admin\n%s", nickname, regDate), "is_read": 0, "add_time": localDateTime(time.Now().Unix())})
		if err := tx.Commit(); err != nil {
			panic(err)
		}
	}
	c.session = &Session{SID: randomSessionID(), UID: newUID, Nickname: nickname, ExpiresAt: time.Now().Unix() + c.app.config.SessionLifetimeSeconds, dirty: true}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "注册成功", "need_guide": true, "user": map[string]any{"uid": newUID, "nickname": nickname}})
}

func normalizeRegisterEmail(email string) string {
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" || len(email) > 255 {
		return ""
	}
	if _, err := mail.ParseAddress(email); err != nil {
		return ""
	}
	return email
}

func registerEmailIPHash(c *Ctx) string {
	ip := c.r.Header.Get("CF-Connecting-IP")
	if ip == "" {
		ip = c.r.Header.Get("X-Forwarded-For")
	}
	if ip == "" {
		ip, _, _ = net.SplitHostPort(c.r.RemoteAddr)
	}
	if strings.Contains(ip, ",") {
		ip = strings.TrimSpace(strings.Split(ip, ",")[0])
	}
	mac := hmac.New(sha256.New, []byte(c.app.config.CacheSalt))
	mac.Write([]byte(ip))
	return hex.EncodeToString(mac.Sum(nil))
}

func verifiedRegisterEmailCodeID(c *Ctx, email, code string) (int64, bool) {
	if email == "" || !regexp.MustCompile(`^\d{6}$`).MatchString(code) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "邮箱验证码错误"})
		return 0, false
	}
	row, _ := c.app.fetchOne("SELECT * FROM register_email_codes WHERE email = ? AND used_at = 0 ORDER BY id DESC LIMIT 1", email)
	if row == nil {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请先获取邮箱验证码"})
		return 0, false
	}
	if intval(row, "expires_at") < time.Now().Unix() {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "验证码已过期，请重新获取"})
		return 0, false
	}
	if intval(row, "attempts") >= registerEmailMaxAttempts {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "验证码错误次数过多，请重新获取"})
		return 0, false
	}
	if err := bcrypt.CompareHashAndPassword([]byte(str(row, "code_hash")), []byte(code)); err != nil {
		_, _ = c.app.exec("UPDATE register_email_codes SET attempts = attempts + 1 WHERE id = ?", intval(row, "id"))
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "邮箱验证码错误"})
		return 0, false
	}
	return intval(row, "id"), true
}

func sendRegisterEmailCode(a *App, email, code string) error {
	host := getenv("CSAC_SMTP_HOST", "")
	username := getenv("CSAC_SMTP_USERNAME", "")
	password := getenv("CSAC_SMTP_PASSWORD", "")
	fromEmail := getenv("CSAC_SMTP_FROM_EMAIL", "")
	if host == "" || username == "" || password == "" || fromEmail == "" {
		return fmt.Errorf("smtp config is incomplete")
	}
	port := getenv("CSAC_SMTP_PORT", "465")
	secure := strings.ToLower(getenv("CSAC_SMTP_SECURE", "ssl"))
	fromName := getenv("CSAC_SMTP_FROM_NAME", "CsAC")
	addr := net.JoinHostPort(host, port)
	subject := "CsAC 注册邮箱验证码"
	minutes := (registerEmailCodeTTL + 59) / 60
	body := fmt.Sprintf("你的 CsAC 注册验证码是：%s\n\n验证码 %d 分钟内有效，请勿转发给他人。\n如果不是你本人操作，请忽略这封邮件。", code, minutes)
	msg := []byte(fmt.Sprintf("From: %s <%s>\r\nTo: %s\r\nSubject: %s\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n%s", fromName, fromEmail, email, subject, body))
	auth := smtp.PlainAuth("", username, password, host)
	if secure == "ssl" || secure == "smtps" {
		conn, err := tls.Dial("tcp", addr, &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12})
		if err != nil {
			return err
		}
		client, err := smtp.NewClient(conn, host)
		if err != nil {
			return err
		}
		defer client.Close()
		if err := client.Auth(auth); err != nil {
			return err
		}
		if err := client.Mail(fromEmail); err != nil {
			return err
		}
		if err := client.Rcpt(email); err != nil {
			return err
		}
		w, err := client.Data()
		if err != nil {
			return err
		}
		if _, err := w.Write(msg); err != nil {
			return err
		}
		if err := w.Close(); err != nil {
			return err
		}
		return client.Quit()
	}
	return smtp.SendMail(addr, auth, fromEmail, []string{email}, msg)
}

func apiAuthLogout(c *Ctx) {
	uid := int64(0)
	if c.session != nil {
		uid = c.session.UID
	}
	if uid > 0 {
		updateUserPlatform(c.app, uid, "none")
	}
	c.destroySession()
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "已退出登录"})
}

func apiUserGetInfo(c *Ctx) {
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	viewUID := c.InputInt("uid", myUID)
	if viewUID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的用户ID"})
		return
	}
	user := getUser(c.app, viewUID, "id, avatar, nickname, username, last_active, allow_auto_join, pat_action, platform")
	if user == nil {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "用户不存在"})
		return
	}
	isSelf := viewUID == myUID
	remark := ""
	isFriend, sent, received, blocked := false, false, false, false
	canAdd := !isSelf
	if !isSelf {
		rel := friendRelation(c.app, myUID, viewUID)
		if rel != nil {
			uid1, _ := friendPair(myUID, viewUID)
			status := intval(rel, "status")
			if myUID == uid1 {
				remark = str(rel, "remark1")
			} else {
				remark = str(rel, "remark2")
			}
			switch status {
			case 1:
				isFriend = true
				canAdd = false
			case 0:
				sent = intval(rel, "from_uid") == myUID
				received = !sent
				canAdd = false
			case 4:
				blocked = intval(rel, "delete_by") == myUID
				canAdd = false
			}
		}
		pendingOut, _ := c.app.fetchOne("SELECT id FROM friend_request WHERE from_uid = ? AND to_uid = ? AND status = 0 LIMIT 1", myUID, viewUID)
		pendingIn, _ := c.app.fetchOne("SELECT id FROM friend_request WHERE from_uid = ? AND to_uid = ? AND status = 0 LIMIT 1", viewUID, myUID)
		if pendingOut != nil {
			sent = true
			canAdd = false
		}
		if pendingIn != nil {
			received = true
			canAdd = false
		}
	}
	platform := "none"
	if isOnline(user["last_active"]) {
		platform = strDefault(user, "platform", "none")
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "user": map[string]any{
		"uid": viewUID, "username": str(user, "username"), "nickname": str(user, "nickname"), "avatar": avatarOrDefault(c.app, str(user, "avatar")), "last_active": user["last_active"],
		"online_status": onlineStatus(user["last_active"]), "platform": platform, "allow_auto_join": intval(user, "allow_auto_join"), "pat_action": strDefault(user, "pat_action", "拍了拍"),
		"is_self": isSelf, "remark": remark, "is_friend": isFriend, "friend_request_sent": sent, "friend_request_received": received, "is_blocked": blocked, "can_add_friend": canAdd,
	}})
}

func apiUserUpdateProfile(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	user := getUser(c.app, uid, "id, username, nickname, pwd, avatar, allow_auto_join, pat_action")
	if user == nil {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "用户不存在"})
		return
	}
	action := c.InputString("action")
	switch action {
	case "nickname":
		nickname := c.InputString("nickname")
		if nickname == "" {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "昵称不能为空"})
			return
		}
		if utf8.RuneCountInString(nickname) > 16 {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "昵称最多16个字符"})
			return
		}
		_, _ = c.app.updateRow("chat_user", map[string]any{"nickname": nickname}, "id = ?", uid)
		c.session.Nickname = nickname
		c.markSessionDirty()
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "昵称修改成功", "nickname": nickname})
	case "password":
		changePassword(c, uid, user, true)
	case "avatar":
		if !hasMultipartFile(c, "avatar") {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请选择图片"})
			return
		}
		avatar, ok := uploadFile(c, "avatar", imageMimes, c.app.config.MaxImageBytes, c.app.config.UploadDir, "upload", fmt.Sprintf("avatar_%d", uid))
		if !ok {
			return
		}
		_, _ = c.app.updateRow("chat_user", map[string]any{"avatar": avatar}, "id = ?", uid)
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "头像更换成功", "avatar": avatar})
	case "privacy":
		updates := map[string]any{}
		if c.HasInput("allow_auto_join") {
			updates["allow_auto_join"] = boolInt(c.InputBool("allow_auto_join"))
		}
		if len(updates) == 0 {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "没有可更新内容"})
			return
		}
		_, _ = c.app.updateRow("chat_user", updates, "id = ?", uid)
		resp := map[string]any{"success": true, "message": "设置已更新"}
		for k, v := range updates {
			resp[k] = v
		}
		c.JSON(http.StatusOK, resp)
	case "pat_action":
		patAction := c.InputString("pat_action", c.InputString("value", "拍了拍"))
		if patAction == "" {
			patAction = "拍了拍"
		}
		if utf8.RuneCountInString(patAction) > 16 {
			c.JSON(http.StatusOK, map[string]any{"success": false, "message": "拍一拍动作最多16个字符"})
			return
		}
		_, _ = c.app.updateRow("chat_user", map[string]any{"pat_action": patAction}, "id = ?", uid)
		c.JSON(http.StatusOK, map[string]any{"success": true, "message": "拍一拍动作已更新", "pat_action": patAction})
	default:
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "未知操作"})
	}
}

func changePassword(c *Ctx, uid int64, user Row, requireOld bool) {
	oldPwd := c.InputString("old_password")
	newPwd := c.InputString("new_password")
	confirmPwd := c.InputString("confirm_password")
	if (requireOld && oldPwd == "") || newPwd == "" || confirmPwd == "" {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请填写完整"})
		return
	}
	if requireOld && !isPasswordValid(user, oldPwd) {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "原密码错误"})
		return
	}
	if len(newPwd) < 6 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "新密码至少6位"})
		return
	}
	if newPwd != confirmPwd {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "两次输入的密码不一致"})
		return
	}
	_, _ = c.app.updateRow("chat_user", map[string]any{"pwd": hashPassword(newPwd, str(user, "username")), "last_active": time.Now().Unix()}, "id = ?", uid)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "密码修改成功"})
}

func apiUserUpgradePassword(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	user := getUser(c.app, uid, "id, username, pwd")
	if user == nil {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "用户不存在"})
		return
	}
	changePassword(c, uid, user, false)
}

func apiUserDeleteAccount(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	rooms, _ := c.app.fetchAll("SELECT id FROM chat_room WHERE owner_uid = ?", uid)
	tx, err := c.app.db.Begin()
	if err != nil {
		panic(err)
	}
	defer tx.Rollback()
	for _, room := range rooms {
		rid := intval(room, "id")
		txExec(tx, "DELETE FROM chat_group_user WHERE room_id = ?", rid)
		txExec(tx, "DELETE FROM chat_group_admin WHERE room_id = ?", rid)
		txExec(tx, "DELETE FROM chat_msg WHERE room_id = ?", rid)
		txExec(tx, "DELETE FROM chat_essence WHERE room_id = ?", rid)
		txExec(tx, "DELETE FROM chat_room_apply WHERE room_id = ?", rid)
		txExec(tx, "DELETE FROM chat_room WHERE id = ?", rid)
	}
	for _, sqlText := range []string{"DELETE FROM chat_group_user WHERE uid = ?", "DELETE FROM chat_group_admin WHERE uid = ?", "DELETE FROM chat_msg WHERE uid = ?", "DELETE FROM chat_essence WHERE set_uid = ?", "DELETE FROM chat_user_notice WHERE uid = ?", "DELETE FROM chat_user WHERE id = ?"} {
		txExec(tx, sqlText, uid)
	}
	txExec(tx, "DELETE FROM friend_request WHERE from_uid = ? OR to_uid = ?", uid, uid)
	txExec(tx, "DELETE FROM private_msg WHERE from_uid = ? OR to_uid = ?", uid, uid)
	if err := tx.Commit(); err != nil {
		panic(err)
	}
	c.destroySession()
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "账号已注销"})
}

func apiUserGetFriends(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	rows, err := c.app.fetchAll(`SELECT
        CASE WHEN f.uid1 = ? THEN f.uid2 ELSE f.uid1 END AS friend_id,
        CASE WHEN f.uid1 = ? THEN f.remark1 ELSE f.remark2 END AS remark,
        u.nickname, u.avatar, u.username, u.last_active,
        COALESCE(pm.unread, 0) AS unread_count
        FROM friend_relation f
        JOIN chat_user u ON ((f.uid1 = ? AND f.uid2 = u.id) OR (f.uid2 = ? AND f.uid1 = u.id))
        LEFT JOIN (
            SELECT from_uid, COUNT(*) AS unread
            FROM private_msg
            WHERE to_uid = ? AND is_read = 0 AND type = 'private'
            GROUP BY from_uid
        ) pm ON pm.from_uid = CASE WHEN f.uid1 = ? THEN f.uid2 ELSE f.uid1 END
        WHERE f.status = 1 AND (f.uid1 = ? OR f.uid2 = ?)
        ORDER BY COALESCE(f.update_time, f.create_time) DESC, f.uid1 DESC`, uid, uid, uid, uid, uid, uid, uid, uid)
	if err != nil {
		panic(err)
	}
	friends := []map[string]any{}
	for _, row := range rows {
		remark := str(row, "remark")
		display := str(row, "nickname")
		if remark != "" {
			display = remark
		}
		friends = append(friends, map[string]any{"friend_id": intval(row, "friend_id"), "nickname": str(row, "nickname"), "avatar": avatarOrDefault(c.app, str(row, "avatar")), "username": str(row, "username"), "last_active": row["last_active"], "online_status": onlineStatus(row["last_active"]), "remark": remark, "display_name": display, "unread_count": intval(row, "unread_count")})
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "friends": friends})
}

func apiUserGetGroups(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	rows, err := c.app.fetchAll(`SELECT
        r.*,
        COALESCE(NULLIF(u.nickname, ''), CONCAT('UID ', r.owner_uid)) AS owner_name,
        COALESCE(member.member_count, 0) AS member_count,
        COALESCE(unread.cnt, 0) AS unread_count
        FROM chat_room r
        JOIN chat_group_user g ON r.id = g.room_id AND g.uid = ?
        LEFT JOIN chat_user u ON u.id = r.owner_uid
        LEFT JOIN (
            SELECT room_id, COUNT(DISTINCT uid) AS member_count
            FROM (
                SELECT id AS room_id, owner_uid AS uid FROM chat_room WHERE owner_uid > 0
                UNION ALL SELECT room_id, uid FROM chat_group_user
            ) member_source GROUP BY room_id
        ) member ON member.room_id = r.id
        LEFT JOIN (
            SELECT m.room_id, COUNT(*) AS cnt
            FROM chat_msg m
            JOIN chat_group_user gu ON gu.room_id = m.room_id AND gu.uid = ?
            WHERE m.id > COALESCE(gu.last_read_msg_id, 0)
            GROUP BY m.room_id
        ) unread ON r.id = unread.room_id
        WHERE COALESCE(r.is_disband, 0) = 0
        ORDER BY r.id ASC`, uid, uid)
	if err != nil {
		panic(err)
	}
	groups := []map[string]any{}
	for _, row := range rows {
		g := map[string]any{"room_id": intval(row, "id"), "id": intval(row, "id"), "room_name": str(row, "room_name"), "avatar": str(row, "avatar"), "intro": str(row, "intro"), "invite_code": str(row, "invite_code"), "join_type": intval(row, "join_type"), "owner_uid": intval(row, "owner_uid"), "owner_name": strDefault(row, "owner_name", "未知"), "member_count": intval(row, "member_count"), "unread_count": intval(row, "unread_count")}
		for k, v := range roomBanFields(row) {
			g[k] = v
		}
		groups = append(groups, g)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "群组加载成功", "count": len(groups), "groups": groups})
}

func apiUserGetNotifications(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	system, _ := c.app.fetchOne("SELECT COUNT(*) AS c FROM chat_user_notice WHERE uid = ? AND is_read = 0", uid)
	requests, _ := c.app.fetchOne("SELECT COUNT(*) AS c FROM friend_request WHERE to_uid = ? AND status = 0", uid)
	deleted, _ := c.app.fetchOne("SELECT COUNT(*) AS c FROM friend_relation WHERE (uid1 = ? OR uid2 = ?) AND status = 2 AND delete_time > DATE_SUB(NOW(), INTERVAL 3 DAY)", uid, uid)
	total := intval(system, "c") + intval(requests, "c") + intval(deleted, "c")
	c.JSON(http.StatusOK, map[string]any{"success": true, "system_notice_unread": intval(system, "c"), "friend_request_unread": intval(requests, "c"), "deleted_friend_notices": intval(deleted, "c"), "total_unread": total})
}

func apiUserGetNoticeList(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	rows, _ := c.app.fetchAll("SELECT * FROM chat_user_notice WHERE uid = ? ORDER BY add_time DESC", uid)
	notices := []map[string]any{}
	for _, row := range rows {
		link := str(row, "link")
		notices = append(notices, map[string]any{"id": intval(row, "id"), "title": str(row, "title"), "content": str(row, "content"), "add_time": str(row, "add_time"), "is_read": intval(row, "is_read"), "link": link, "route": noticeRoute(link)})
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "notices": notices})
}

func apiUserMarkNoticeRead(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	if c.InputBool("read_all") {
		_, _ = c.app.exec("UPDATE chat_user_notice SET is_read = 1 WHERE uid = ? AND is_read = 0", uid)
	} else if noticeID := c.InputInt("notice_id"); noticeID > 0 {
		_, _ = c.app.exec("UPDATE chat_user_notice SET is_read = 1 WHERE id = ? AND uid = ? AND is_read = 0", noticeID, uid)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "已标记已读"})
}

func apiUserGetCreatedGroups(c *Ctx) {
	uid, ok := requireLogin(c)
	if !ok {
		return
	}
	viewUID := c.InputInt("uid", uid)
	publicOnly := ""
	if viewUID != uid {
		publicOnly = " AND r.show_in_list = 1"
	}
	rows, err := c.app.fetchAll(`SELECT
        r.*,
        COALESCE(NULLIF(u.nickname, ''), CONCAT('UID ', r.owner_uid)) AS owner_name,
        COALESCE(m.member_count, 0) AS member_count
        FROM chat_room r
        LEFT JOIN chat_user u ON u.id = r.owner_uid
        LEFT JOIN (
            SELECT room_id, COUNT(DISTINCT uid) AS member_count
            FROM (
                SELECT id AS room_id, owner_uid AS uid FROM chat_room WHERE owner_uid > 0
                UNION ALL SELECT room_id, uid FROM chat_group_user
            ) member_source GROUP BY room_id
        ) m ON m.room_id = r.id
        WHERE r.owner_uid = ?`+publicOnly+` ORDER BY r.id DESC`, viewUID)
	if err != nil {
		panic(err)
	}
	canManage := viewUID == uid
	groups := []map[string]any{}
	for _, row := range rows {
		inviteCode := ""
		fixedCode := ""
		if canManage {
			inviteCode = str(row, "invite_code")
			fixedCode = str(row, "fixed_code")
		}
		g := map[string]any{"id": intval(row, "id"), "room_id": intval(row, "id"), "room_name": strDefault(row, "room_name", fmt.Sprintf("群组 %d", intval(row, "id"))), "avatar": str(row, "avatar"), "intro": str(row, "intro"), "notice": str(row, "notice"), "invite_code": inviteCode, "join_type": intval(row, "join_type"), "owner_uid": intval(row, "owner_uid"), "owner_name": strDefault(row, "owner_name", "未知"), "member_count": intval(row, "member_count"), "show_in_list": intval(row, "show_in_list"), "allow_invite": intval(row, "allow_invite"), "ask_question": str(row, "ask_question"), "fixed_code": fixedCode}
		for k, v := range roomBanFields(row) {
			g[k] = v
		}
		groups = append(groups, g)
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "groups": groups})
}

func nullableString(v string) any {
	if v == "" {
		return nil
	}
	return v
}

func hasMultipartFile(c *Ctx, field string) bool {
	if err := c.r.ParseMultipartForm(c.app.config.MaxVoiceBytes + 1024*1024); err != nil {
		return false
	}
	if c.r.MultipartForm == nil || c.r.MultipartForm.File == nil {
		return false
	}
	files := c.r.MultipartForm.File[field]
	return len(files) > 0 && files[0] != nil && files[0].Size >= 0
}
