// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC Open Platform (ACOP) Version 1.0.0.260614-r1

package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// ===== 开发者认证 =====

func (app *ACOP) apiDevRegister(ctx *ACOPCtx) {
	email := ctx.param("email")
	pwd := ctx.param("pwd")
	devName := ctx.param("dev_name")
	code := ctx.param("code")
	csacUsername := ctx.param("csac_username")
	csacPassword := ctx.param("csac_password")
	if email == "" || pwd == "" || devName == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "请填写完整信息"})
		return
	}
	if csacUsername == "" || csacPassword == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "请填写CsAC账号信息"})
		return
	}
	if code == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "请输入邮箱验证码"})
		return
	}
	// 验证验证码
	if !app.codeStore.Verify(email, code) {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "验证码错误或已过期"})
		return
	}
	// 验证CsAC账号
	csacUID, err := app.verifyCsacAccount(csacUsername, csacPassword)
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "CsAC账号验证失败: " + err.Error()})
		return
	}
	// 检查CsAC账号是否已绑定其他开发者
	existingBind, _ := app.fetchOne("SELECT id FROM open_dev_accounts WHERE uid = ?", csacUID)
	if existingBind != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "该CsAC账号已绑定其他开发者"})
		return
	}
	if len(pwd) < 6 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "密码至少6位"})
		return
	}
	// 检查邮箱是否已注册
	existing, _ := app.fetchOne("SELECT id FROM open_dev_accounts WHERE email = ?", email)
	if existing != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "该邮箱已注册"})
		return
	}
	// 密码加密
	hashedPwd, err := hashPasswordBcrypt(pwd)
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "注册失败"})
		return
	}
	// 生成API Key
	apiKey := generateSecureToken(32)
	devID, err := app.insertRow("open_dev_accounts", map[string]any{
		"uid":        csacUID,
		"email":      email,
		"pwd":        hashedPwd,
		"dev_name":   devName,
		"api_key":    apiKey,
		"status":     1,
		"created_at": time.Now().Unix(),
	})
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "注册失败"})
		return
	}
	ctx.setSession(devID)
	ctx.JSON(http.StatusOK, map[string]any{
		"success": true,
		"message": "注册成功",
		"data": map[string]any{
			"dev_id":   devID,
			"api_key":  apiKey,
			"dev_name": devName,
		},
	})
}

func (app *ACOP) apiDevLogin(ctx *ACOPCtx) {
	email := ctx.param("email")
	pwd := ctx.param("pwd")
	if email == "" || pwd == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "请填写邮箱和密码"})
		return
	}
	dev, err := app.fetchOne("SELECT id, pwd, dev_name, status, uid FROM open_dev_accounts WHERE email = ?", email)
	if err != nil || dev == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "邮箱或密码错误"})
		return
	}
	if intval(dev, "status") != 1 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "账号已被封禁"})
		return
	}
	if !checkPasswordBcrypt(pwd, str(dev, "pwd")) {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "邮箱或密码错误"})
		return
	}
	// 检查关联的CsAC账号是否被封禁
	csacUID := intval(dev, "uid")
	if csacUID > 0 {
		csacUser, _ := app.fetchOne("SELECT ban_until FROM chat_user WHERE id = ?", csacUID)
		if csacUser != nil && intval(csacUser, "ban_until") > time.Now().Unix() {
			ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "关联的CsAC账号已被封禁"})
			return
		}
	}
	ctx.setSession(intval(dev, "id"))
	ctx.JSON(http.StatusOK, map[string]any{
		"success": true,
		"message": "登录成功",
		"data": map[string]any{
			"dev_id":   intval(dev, "id"),
			"dev_name": str(dev, "dev_name"),
		},
	})
}

func (app *ACOP) apiDevLogout(ctx *ACOPCtx) {
	ctx.clearSession()
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "已退出登录"})
}

// apiDevSendCode 发送邮箱验证码
func (app *ACOP) apiDevSendCode(ctx *ACOPCtx) {
	email := ctx.param("email")
	purpose := ctx.param("purpose") // "register" 或 "login"
	if email == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "请输入邮箱"})
		return
	}
	// 邮箱格式校验
	if !strings.Contains(email, "@") || !strings.Contains(email, ".") {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "邮箱格式不正确"})
		return
	}

	if purpose == "register" {
		// 注册时检查邮箱是否已存在
		existing, _ := app.fetchOne("SELECT id FROM open_dev_accounts WHERE email = ?", email)
		if existing != nil {
			ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "该邮箱已注册"})
			return
		}
	} else if purpose == "login" {
		// 登录时检查邮箱是否存在
		existing, _ := app.fetchOne("SELECT id, status FROM open_dev_accounts WHERE email = ?", email)
		if existing == nil {
			ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "该邮箱未注册"})
			return
		}
		if intval(existing, "status") != 1 {
			ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "账号已被封禁"})
			return
		}
	}

	// 生成6位数字验证码
	code := generateCode(6)
	app.codeStore.Set(email, code, 10*time.Minute)

	// 发送邮件
	subject := "CsAC 开放平台验证码"
	body := fmt.Sprintf("您的验证码是: %s\n\n验证码10分钟内有效，请勿泄露给他人。\n\n如非本人操作，请忽略此邮件。", code)

	go func() {
		if err := app.sendEmail(email, subject, body); err != nil {
			log.Printf("ACOP: 发送验证码邮件失败 to=%s err=%v", email, err)
		}
	}()

	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "验证码已发送"})
}

// apiDevLoginByCode 验证码登录
func (app *ACOP) apiDevLoginByCode(ctx *ACOPCtx) {
	email := ctx.param("email")
	code := ctx.param("code")
	if email == "" || code == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "请填写邮箱和验证码"})
		return
	}
	// 验证验证码
	if !app.codeStore.Verify(email, code) {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "验证码错误或已过期"})
		return
	}
	// 查找用户
	dev, err := app.fetchOne("SELECT id, dev_name, status, uid FROM open_dev_accounts WHERE email = ?", email)
	if err != nil || dev == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "该邮箱未注册"})
		return
	}
	if intval(dev, "status") != 1 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "账号已被封禁"})
		return
	}
	// 检查关联的CsAC账号是否被封禁
	csacUID := intval(dev, "uid")
	if csacUID > 0 {
		csacUser, _ := app.fetchOne("SELECT ban_until FROM chat_user WHERE id = ?", csacUID)
		if csacUser != nil && intval(csacUser, "ban_until") > time.Now().Unix() {
			ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "关联的CsAC账号已被封禁"})
			return
		}
	}
	ctx.setSession(intval(dev, "id"))
	ctx.JSON(http.StatusOK, map[string]any{
		"success": true,
		"message": "登录成功",
		"data": map[string]any{
			"dev_id":   intval(dev, "id"),
			"dev_name": str(dev, "dev_name"),
		},
	})
}

func (app *ACOP) apiDevGetInfo(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	dev, err := app.fetchOne("SELECT id, email, dev_name, api_key, status, created_at FROM open_dev_accounts WHERE id = ?", devID)
	if err != nil || dev == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "开发者不存在"})
		return
	}
	ctx.JSON(http.StatusOK, map[string]any{
		"success": true,
		"data": map[string]any{
			"dev_id":     intval(dev, "id"),
			"email":      str(dev, "email"),
			"dev_name":   str(dev, "dev_name"),
			"api_key":    str(dev, "api_key"),
			"status":     intval(dev, "status"),
			"created_at": intval(dev, "created_at"),
		},
	})
}

// ===== Bot管理 =====

func (app *ACOP) apiBotCreate(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	botName := ctx.param("bot_name")
	botDesc := ctx.param("bot_desc")
	if botName == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "请填写Bot名称"})
		return
	}
	// 检查开发者Bot数量限制（每个开发者最多10个Bot）
	var count int
	app.db.QueryRow("SELECT COUNT(*) FROM bot_accounts WHERE dev_id = ?", devID).Scan(&count)
	if count >= 10 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "每个开发者最多创建10个Bot"})
		return
	}
	// 在chat_user中创建Bot用户
	username := fmt.Sprintf("bot_%d_%s", devID, generateSecureToken(6))
	nickname := botName
	uid, err := app.insertRow("chat_user", map[string]any{
		"username":              username,
		"nickname":              nickname,
		"pwd":                   generateSecureToken(32), // 随机密码，Bot不通过密码登录
		"email":                 nil,
		"add_time":              time.Now().Unix(),
		"avatar":                "default.png",
		"is_first_login":        0,
		"last_active":           time.Now().Unix(),
		"platform":              "bot",
		"allow_auto_join":       0,
		"pat_action":            "拍了拍",
		"hide_conv":             "",
		"status":                1,
		"delete_time":           0,
		"restore_token":         "",
		"restore_token_expires": 0,
		"ban_until":             0,
		"ban_reason":            "",
		"is_bot":                1,
	})
	if err != nil {
		log.Printf("ACOP: create bot chat_user failed dev_id=%d username=%s err=%v", devID, username, err)
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "创建Bot用户失败"})
		return
	}
	// 生成Bot Token
	botToken := generateSecureToken(48)
	botID, err := app.insertRow("bot_accounts", map[string]any{
		"uid":        uid,
		"dev_id":     devID,
		"bot_token":  botToken,
		"bot_name":   botName,
		"bot_desc":   botDesc,
		"status":     1,
		"can_notify": 0,
		"can_http":   0,
		"online":     0,
		"created_at": time.Now().Unix(),
	})
	if err != nil {
		log.Printf("ACOP: create bot account failed dev_id=%d uid=%d err=%v", devID, uid, err)
		_, _ = app.exec("DELETE FROM chat_user WHERE id = ? AND is_bot = 1", uid)
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "创建Bot失败"})
		return
	}
	ctx.JSON(http.StatusOK, map[string]any{
		"success": true,
		"message": "Bot创建成功",
		"data": map[string]any{
			"bot_id":    botID,
			"uid":       uid,
			"bot_name":  botName,
			"bot_token": botToken,
		},
	})
}

func (app *ACOP) apiBotList(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	bots, err := app.fetchAll(
		"SELECT ba.id, ba.uid, ba.bot_name, ba.bot_desc, ba.bot_avatar, ba.status, ba.can_notify, ba.can_http, ba.online, ba.last_online, ba.created_at, cu.nickname "+
			"FROM bot_accounts ba LEFT JOIN chat_user cu ON ba.uid = cu.id WHERE ba.dev_id = ? ORDER BY ba.id DESC", devID)
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	list := make([]map[string]any, 0, len(bots))
	for _, bot := range bots {
		list = append(list, map[string]any{
			"bot_id":      intval(bot, "id"),
			"uid":         intval(bot, "uid"),
			"bot_name":    str(bot, "bot_name"),
			"bot_desc":    str(bot, "bot_desc"),
			"bot_avatar":  str(bot, "bot_avatar"),
			"status":      intval(bot, "status"),
			"can_notify":  intval(bot, "can_notify"),
			"can_http":    intval(bot, "can_http"),
			"online":      intval(bot, "online"),
			"last_online": intval(bot, "last_online"),
			"created_at":  intval(bot, "created_at"),
			"nickname":    str(bot, "nickname"),
		})
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "data": list})
}

func (app *ACOP) apiBotGetInfo(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	botID, _ := strconv.ParseInt(strings.TrimSpace(ctx.r.FormValue("bot_id")), 10, 64)
	if botID <= 0 {
		botID = ctx.paramInt("bot_id")
	}
	if botID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少bot_id"})
		return
	}
	bot, err := app.fetchOne(
		"SELECT ba.*, cu.nickname FROM bot_accounts ba JOIN chat_user cu ON ba.uid = cu.id WHERE ba.id = ? AND ba.dev_id = ?",
		botID, devID)
	if err != nil || bot == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "Bot不存在"})
		return
	}
	ctx.JSON(http.StatusOK, map[string]any{
		"success": true,
		"data": map[string]any{
			"bot_id":      intval(bot, "id"),
			"uid":         intval(bot, "uid"),
			"bot_name":    str(bot, "bot_name"),
			"bot_desc":    str(bot, "bot_desc"),
			"bot_avatar":  str(bot, "bot_avatar"),
			"bot_token":   str(bot, "bot_token"),
			"status":      intval(bot, "status"),
			"can_notify":  intval(bot, "can_notify"),
			"can_http":    intval(bot, "can_http"),
			"online":      intval(bot, "online"),
			"last_online": intval(bot, "last_online"),
			"created_at":  intval(bot, "created_at"),
			"nickname":    str(bot, "nickname"),
		},
	})
}

func (app *ACOP) apiBotUpdate(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	botID := ctx.paramInt("bot_id")
	botName := ctx.param("bot_name")
	botDesc := ctx.param("bot_desc")
	rawBotAvatar, hasBotAvatar := ctx.params["bot_avatar"]
	if botID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少bot_id"})
		return
	}
	// 验证Bot属于该开发者
	bot, _ := app.fetchOne("SELECT id, uid, bot_name FROM bot_accounts WHERE id = ? AND dev_id = ?", botID, devID)
	if bot == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "Bot不存在"})
		return
	}
	updates := map[string]any{}
	if botName != "" {
		updates["bot_name"] = botName
		// 同步更新chat_user的nickname
		_, _ = app.updateRow("chat_user", map[string]any{"nickname": botName}, "id = (SELECT uid FROM bot_accounts WHERE id = ?)", botID)
	}
	if botDesc != "" {
		updates["bot_desc"] = botDesc
	}
	if hasBotAvatar {
		botAvatar := strings.TrimSpace(fmt.Sprint(rawBotAvatar))
		if len(botAvatar) > 255 {
			ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "头像地址不能超过255个字符"})
			return
		}
		updates["bot_avatar"] = botAvatar
		chatAvatar := botAvatar
		if chatAvatar == "" {
			chatAvatar = "default.png"
		}
		_, _ = app.updateRow("chat_user", map[string]any{"avatar": chatAvatar}, "id = ?", intval(bot, "uid"))
	}
	if len(updates) > 0 {
		_, _ = app.updateRow("bot_accounts", updates, "id = ? AND dev_id = ?", botID, devID)
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "更新成功"})
}

func (app *ACOP) apiBotUploadAvatar(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	botID := ctx.paramInt("bot_id")
	if botID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少bot_id"})
		return
	}
	bot, _ := app.fetchOne("SELECT id, uid FROM bot_accounts WHERE id = ? AND dev_id = ?", botID, devID)
	if bot == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "Bot不存在"})
		return
	}
	file, header, err := ctx.r.FormFile("avatar")
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "请选择头像文件"})
		return
	}
	defer file.Close()
	if header.Size > 5<<20 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "头像不能超过5MB"})
		return
	}
	buf := make([]byte, 512)
	n, readErr := file.Read(buf)
	if readErr != nil && readErr != io.EOF {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "读取头像失败"})
		return
	}
	mime := http.DetectContentType(buf[:n])
	ext := avatarExt(mime, header.Filename)
	if ext == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "只支持 png、jpg、gif、webp 头像"})
		return
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "读取头像失败"})
		return
	}
	dir := filepath.Join(app.config.UploadDir, "bot")
	if err := os.MkdirAll(dir, 0775); err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "头像目录不可用"})
		return
	}
	name := fmt.Sprintf("bot_avatar_%d_%s_%d.%s", botID, generateSecureToken(8), time.Now().Unix(), ext)
	dest := filepath.Join(dir, name)
	out, err := os.OpenFile(dest, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0664)
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "头像保存失败"})
		return
	}
	if _, err := io.Copy(out, file); err != nil {
		out.Close()
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "头像保存失败"})
		return
	}
	if err := out.Close(); err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "头像保存失败"})
		return
	}
	avatar := "upload/bot/" + name
	if _, err := app.updateRow("bot_accounts", map[string]any{"bot_avatar": avatar}, "id = ? AND dev_id = ?", botID, devID); err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "头像更新失败"})
		return
	}
	_, _ = app.updateRow("chat_user", map[string]any{"avatar": avatar}, "id = ?", intval(bot, "uid"))
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "头像已更新", "avatar": avatar})
}

func (app *ACOP) apiBotResetToken(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	botID := ctx.paramInt("bot_id")
	if botID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少bot_id"})
		return
	}
	bot, _ := app.fetchOne("SELECT id, uid, bot_name FROM bot_accounts WHERE id = ? AND dev_id = ?", botID, devID)
	if bot == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "Bot不存在"})
		return
	}
	newToken := generateSecureToken(48)
	_, _ = app.updateRow("bot_accounts", map[string]any{"bot_token": newToken}, "id = ? AND dev_id = ?", botID, devID)
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "Token已重置", "bot_token": newToken})
}

func (app *ACOP) apiBotDelete(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	botID := ctx.paramInt("bot_id")
	if botID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少bot_id"})
		return
	}
	bot, _ := app.fetchOne("SELECT id, uid FROM bot_accounts WHERE id = ? AND dev_id = ?", botID, devID)
	if bot == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "Bot不存在"})
		return
	}
	uid := intval(bot, "uid")
	// 删除Bot相关数据
	_, _ = app.exec("DELETE FROM bot_scripts WHERE bot_id = ?", botID)
	_, _ = app.exec("DELETE FROM bot_logs WHERE bot_id = ?", botID)
	_, _ = app.exec("DELETE FROM bot_perm_requests WHERE bot_id = ?", botID)
	_, _ = app.updateRow("bot_accounts", map[string]any{"status": 0, "online": 0}, "id = ?", botID)
	// 删除Bot用户（软删除：设置status=3）
	_, _ = app.updateRow("chat_user", map[string]any{"status": 3}, "id = ?", uid)
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "Bot已删除"})
}

// ===== 脚本管理 =====

func (app *ACOP) apiScriptCreate(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	botID := ctx.paramInt("bot_id")
	scriptName := ctx.param("script_name")
	scriptContent := ctx.param("script_content")
	if botID <= 0 || scriptName == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少bot_id或script_name"})
		return
	}
	// 验证Bot属于该开发者
	bot, _ := app.fetchOne("SELECT id FROM bot_accounts WHERE id = ? AND dev_id = ?", botID, devID)
	if bot == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "Bot不存在"})
		return
	}
	now := time.Now().Unix()
	scriptID, err := app.insertRow("bot_scripts", map[string]any{
		"bot_id":         botID,
		"script_name":    scriptName,
		"script_content": scriptContent,
		"enabled":        0, // 新建脚本默认禁用
		"version":        1,
		"created_at":     now,
		"updated_at":     now,
	})
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "创建脚本失败"})
		return
	}
	app.notifyServerBotReload(int64(botID))
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "脚本创建成功", "script_id": scriptID})
}

func (app *ACOP) apiScriptList(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	botID := ctx.paramInt("bot_id")
	if botID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少bot_id"})
		return
	}
	// 验证Bot属于该开发者
	bot, _ := app.fetchOne("SELECT id FROM bot_accounts WHERE id = ? AND dev_id = ?", botID, devID)
	if bot == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "Bot不存在"})
		return
	}
	scripts, err := app.fetchAll("SELECT id, bot_id, script_name, enabled, version, created_at, updated_at FROM bot_scripts WHERE bot_id = ? ORDER BY id DESC", botID)
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	list := make([]map[string]any, 0, len(scripts))
	for _, s := range scripts {
		list = append(list, map[string]any{
			"script_id":   intval(s, "id"),
			"bot_id":      intval(s, "bot_id"),
			"script_name": str(s, "script_name"),
			"enabled":     intval(s, "enabled"),
			"version":     intval(s, "version"),
			"created_at":  intval(s, "created_at"),
			"updated_at":  intval(s, "updated_at"),
		})
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "data": list})
}

func (app *ACOP) apiScriptGet(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	scriptID := ctx.paramInt("script_id")
	if scriptID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少script_id"})
		return
	}
	script, err := app.fetchOne(
		"SELECT bs.* FROM bot_scripts bs JOIN bot_accounts ba ON bs.bot_id = ba.id WHERE bs.id = ? AND ba.dev_id = ?",
		scriptID, devID)
	if err != nil || script == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "脚本不存在"})
		return
	}
	ctx.JSON(http.StatusOK, map[string]any{
		"success": true,
		"data": map[string]any{
			"script_id":      intval(script, "id"),
			"bot_id":         intval(script, "bot_id"),
			"script_name":    str(script, "script_name"),
			"script_content": str(script, "script_content"),
			"enabled":        intval(script, "enabled"),
			"version":        intval(script, "version"),
			"created_at":     intval(script, "created_at"),
			"updated_at":     intval(script, "updated_at"),
		},
	})
}

func (app *ACOP) apiScriptUpdate(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	scriptID := ctx.paramInt("script_id")
	scriptName := ctx.param("script_name")
	_ = ctx.param("script_content") // consumed via ctx.params below
	if scriptID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少script_id"})
		return
	}
	// 验证脚本属于该开发者
	script, _ := app.fetchOne(
		"SELECT bs.id, bs.bot_id, bs.version FROM bot_scripts bs JOIN bot_accounts ba ON bs.bot_id = ba.id WHERE bs.id = ? AND ba.dev_id = ?",
		scriptID, devID)
	if script == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "脚本不存在"})
		return
	}
	updates := map[string]any{
		"updated_at": time.Now().Unix(),
		"version":    intval(script, "version") + 1,
	}
	if scriptName != "" {
		updates["script_name"] = scriptName
	}
	// script_content 允许更新为空字符串（清空脚本）
	if rawScriptContent, ok := ctx.params["script_content"]; ok {
		updates["script_content"] = fmt.Sprint(rawScriptContent)
	}
	if _, err := app.updateRow("bot_scripts", updates, "id = ?", scriptID); err != nil {
		log.Printf("ACOP: update script failed script_id=%d err=%v", scriptID, err)
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "脚本更新失败"})
		return
	}
	// 通知ServerBot重载脚本
	app.notifyServerBotReload(intval(script, "bot_id"))
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "脚本已更新"})
}

func (app *ACOP) apiScriptDelete(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	scriptID := ctx.paramInt("script_id")
	if scriptID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少script_id"})
		return
	}
	// 验证脚本属于该开发者
	script, _ := app.fetchOne(
		"SELECT bs.id, bs.bot_id FROM bot_scripts bs JOIN bot_accounts ba ON bs.bot_id = ba.id WHERE bs.id = ? AND ba.dev_id = ?",
		scriptID, devID)
	if script == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "脚本不存在"})
		return
	}
	botID := intval(script, "bot_id")
	_, _ = app.exec("DELETE FROM bot_scripts WHERE id = ?", scriptID)
	app.notifyServerBotReload(botID)
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "脚本已删除"})
}

func (app *ACOP) apiScriptToggle(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	scriptID := ctx.paramInt("script_id")
	enabled := ctx.paramInt("enabled")
	if scriptID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少script_id"})
		return
	}
	script, _ := app.fetchOne(
		"SELECT bs.id, bs.bot_id FROM bot_scripts bs JOIN bot_accounts ba ON bs.bot_id = ba.id WHERE bs.id = ? AND ba.dev_id = ?",
		scriptID, devID)
	if script == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "脚本不存在"})
		return
	}
	_, _ = app.updateRow("bot_scripts", map[string]any{"enabled": enabled}, "id = ?", scriptID)
	app.notifyServerBotReload(intval(script, "bot_id"))
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "脚本状态已更新"})
}

func (app *ACOP) apiScriptTest(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	scriptID := ctx.paramInt("script_id")
	eventType := ctx.param("event_type")
	if scriptID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少script_id"})
		return
	}
	if eventType == "" {
		eventType = "group_message"
	}
	// 获取脚本内容和bot_id
	script, _ := app.fetchOne(
		"SELECT bs.id, bs.bot_id, bs.script_content FROM bot_scripts bs JOIN bot_accounts ba ON bs.bot_id = ba.id WHERE bs.id = ? AND ba.dev_id = ?",
		scriptID, devID)
	if script == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "脚本不存在"})
		return
	}
	botID := intval(script, "bot_id")
	// 获取Bot信息
	bot, _ := app.fetchOne("SELECT id, uid FROM bot_accounts WHERE id = ?", botID)
	if bot == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "Bot不存在"})
		return
	}
	// 构造测试事件数据
	eventData := ctx.params["event_data"]
	if eventData == nil {
		eventData = map[string]any{}
	}
	// 通知ServerBot执行测试
	if app.config.BotEndpoint == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "ServerBot端点未配置"})
		return
	}
	// 转发测试请求到ServerBot
	rawScriptContent, hasScriptContent := ctx.params["script_content"]
	scriptContentStr := fmt.Sprint(rawScriptContent)
	if !hasScriptContent {
		scriptContentStr = str(script, "script_content")
	}
	if strings.TrimSpace(scriptContentStr) == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "脚本内容为空"})
		return
	}
	testPayload, _ := json.Marshal(map[string]any{
		"bot_id":         botID,
		"script_id":      scriptID,
		"event_type":     eventType,
		"event_data":     eventData,
		"script_content": scriptContentStr,
	})
	url := app.config.BotEndpoint + "/bot/internal/test_script"
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(testPayload))
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "创建测试请求失败"})
		return
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Bot-Secret", app.config.BotSecret)
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "测试请求超时或ServerBot不可达"})
		return
	}
	defer resp.Body.Close()
	var result map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "解析测试结果失败"})
		return
	}
	ctx.JSON(http.StatusOK, result)
}

// ===== ACR/ACRG 上传 =====

func (app *ACOP) apiScriptUploadAcr(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	fileName := ctx.param("file_name")
	content := ctx.param("content")
	desc := ctx.param("desc")
	if fileName == "" || content == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少 file_name 或 content"})
		return
	}
	// 保存到开发者目录
	dir := filepath.Join(app.config.UploadDir, "acr", fmt.Sprintf("dev_%d", devID))
	if err := os.MkdirAll(dir, 0775); err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "保存目录不可用"})
		return
	}
	// 文件名安全处理
	safeName := strings.TrimSuffix(fileName, ".acr") + ".acr"
	dest := filepath.Join(dir, safeName)
	if err := os.WriteFile(dest, []byte(content), 0664); err != nil {
		log.Printf("ACOP: upload acr failed dev_id=%d file=%s err=%v", devID, safeName, err)
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件保存失败"})
		return
	}
	// 记录到审核表
	now := time.Now().Unix()
	uploadID, err := app.insertRow("acr_uploads", map[string]any{
		"dev_id":     devID,
		"file_name":  safeName,
		"file_type":  "acr",
		"content":    content,
		"desc":       desc,
		"status":     0,
		"created_at": now,
	})
	if err != nil {
		log.Printf("ACOP: insert acr_uploads failed dev_id=%d file=%s err=%v", devID, safeName, err)
	}
	// 通知管理员
	if uploadID > 0 && app.config.AdminUID > 0 {
		app.notifyAdminAcrUpload(uploadID, devID, safeName, "acr")
	}
	log.Printf("ACOP: acr uploaded dev_id=%d file=%s size=%d", devID, safeName, len(content))
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "ACR 上传成功，等待管理员审核", "file_name": safeName})
}

func (app *ACOP) apiScriptUploadAcrg(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	fileName := ctx.param("file_name")
	content := ctx.param("content")
	desc := ctx.param("desc")
	if fileName == "" || content == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少 file_name 或 content"})
		return
	}
	dir := filepath.Join(app.config.UploadDir, "acrg", fmt.Sprintf("dev_%d", devID))
	if err := os.MkdirAll(dir, 0775); err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "保存目录不可用"})
		return
	}
	safeName := strings.TrimSuffix(fileName, ".acrg") + ".acrg"
	dest := filepath.Join(dir, safeName)
	if err := os.WriteFile(dest, []byte(content), 0664); err != nil {
		log.Printf("ACOP: upload acrg failed dev_id=%d file=%s err=%v", devID, safeName, err)
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件保存失败"})
		return
	}
	// 记录到审核表
	now := time.Now().Unix()
	uploadID, err := app.insertRow("acr_uploads", map[string]any{
		"dev_id":     devID,
		"file_name":  safeName,
		"file_type":  "acrg",
		"content":    content,
		"desc":       desc,
		"status":     0,
		"created_at": now,
	})
	if err != nil {
		log.Printf("ACOP: insert acr_uploads failed dev_id=%d file=%s err=%v", devID, safeName, err)
	}
	if uploadID > 0 && app.config.AdminUID > 0 {
		app.notifyAdminAcrUpload(uploadID, devID, safeName, "acrg")
	}
	log.Printf("ACOP: acrg uploaded dev_id=%d file=%s size=%d", devID, safeName, len(content))
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "ACRG 上传成功，等待管理员审核", "file_name": safeName})
}

// ===== 日志 =====

func (app *ACOP) apiLogList(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	botID := ctx.paramInt("bot_id")
	level := ctx.param("level")
	limit := ctx.paramInt("limit")
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	if botID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少bot_id"})
		return
	}
	// 验证Bot属于该开发者
	bot, _ := app.fetchOne("SELECT id FROM bot_accounts WHERE id = ? AND dev_id = ?", botID, devID)
	if bot == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "Bot不存在"})
		return
	}
	query := "SELECT id, bot_id, script_id, level, content, created_at FROM bot_logs WHERE bot_id = ?"
	args := []any{botID}
	if level != "" && (level == "log" || level == "error" || level == "warn") {
		query += " AND level = ?"
		args = append(args, level)
	}
	query += " ORDER BY id DESC LIMIT ?"
	args = append(args, limit)
	logs, err := app.fetchAll(query, args...)
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	list := make([]map[string]any, 0, len(logs))
	for _, l := range logs {
		list = append(list, map[string]any{
			"id":         intval(l, "id"),
			"bot_id":     intval(l, "bot_id"),
			"script_id":  intval(l, "script_id"),
			"level":      str(l, "level"),
			"content":    str(l, "content"),
			"created_at": intval(l, "created_at"),
		})
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "data": list})
}

// ===== 权限申请 =====

func (app *ACOP) apiPermRequest(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	botID := ctx.paramInt("bot_id")
	permType := ctx.param("perm_type")
	reason := ctx.param("reason")
	if botID <= 0 || permType == "" || reason == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少参数"})
		return
	}
	// 验证权限类型
	if permType != "notify" && permType != "http" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "不支持的权限类型"})
		return
	}
	// 验证Bot属于该开发者
	bot, _ := app.fetchOne("SELECT id FROM bot_accounts WHERE id = ? AND dev_id = ?", botID, devID)
	if bot == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "Bot不存在"})
		return
	}
	// 检查是否已有待审核的申请
	existing, _ := app.fetchOne("SELECT id FROM bot_perm_requests WHERE bot_id = ? AND perm_type = ? AND status = 0", botID, permType)
	if existing != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "已有待审核的申请"})
		return
	}
	requestID, err := app.insertRow("bot_perm_requests", map[string]any{
		"bot_id":     botID,
		"perm_type":  permType,
		"reason":     reason,
		"status":     0,
		"created_at": time.Now().Unix(),
	})
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "申请失败"})
		return
	}
	if err := app.notifyAdminPermRequest(requestID, devID, bot, permType, reason); err != nil {
		log.Printf("ACOP: notify admin perm request failed request_id=%d err=%v", requestID, err)
		ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "申请已提交，但通知管理员失败"})
		return
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "申请已提交，已通知管理员"})
}

func (app *ACOP) apiPermList(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	botID := ctx.paramInt("bot_id")
	if botID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少bot_id"})
		return
	}
	bot, _ := app.fetchOne("SELECT id FROM bot_accounts WHERE id = ? AND dev_id = ?", botID, devID)
	if bot == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "Bot不存在"})
		return
	}
	requests, err := app.fetchAll("SELECT * FROM bot_perm_requests WHERE bot_id = ? ORDER BY id DESC", botID)
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	list := make([]map[string]any, 0, len(requests))
	for _, r := range requests {
		list = append(list, map[string]any{
			"id":          intval(r, "id"),
			"bot_id":      intval(r, "bot_id"),
			"perm_type":   str(r, "perm_type"),
			"reason":      str(r, "reason"),
			"status":      intval(r, "status"),
			"admin_reply": str(r, "admin_reply"),
			"created_at":  intval(r, "created_at"),
			"handled_at":  intval(r, "handled_at"),
		})
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "data": list})
}

func (app *ACOP) notifyAdminPermRequest(requestID, devID int64, bot map[string]any, permType, reason string) error {
	dev, _ := app.fetchOne("SELECT dev_name, email, uid FROM open_dev_accounts WHERE id = ?", devID)
	permLabel := map[string]string{
		"notify": "发送通知权限",
		"http":   "HTTP请求权限",
	}[permType]
	if permLabel == "" {
		permLabel = permType
	}
	devName := "未知开发者"
	devEmail := ""
	devUID := int64(0)
	if dev != nil {
		devName = str(dev, "dev_name")
		devEmail = str(dev, "email")
		devUID = intval(dev, "uid")
	}
	content := fmt.Sprintf(
		"ACOP 收到新的 Bot 权限申请，请及时审核。\n\n申请编号：%d\n权限类型：%s\nBot：%s (Bot ID: %d, UID: %d)\n开发者：%s (Dev ID: %d, CsAC UID: %d)\n邮箱：%s\n\n申请理由：\n%s",
		requestID,
		permLabel,
		str(bot, "bot_name"),
		intval(bot, "id"),
		intval(bot, "uid"),
		devName,
		devID,
		devUID,
		devEmail,
		reason,
	)
	_, err := app.insertRow("chat_user_notice", map[string]any{
		"uid":      app.config.AdminUID,
		"title":    "ACOP 权限申请待审核",
		"content":  content,
		"link":     "",
		"is_read":  0,
		"add_time": localDateTime(time.Now().Unix()),
	})
	return err
}

// ===== 管理员操作 =====

// apiAdminLogin 管理员独立登录（通过CsAC账号验证）
func (app *ACOP) apiAdminLogin(ctx *ACOPCtx) {
	username := ctx.param("csac_username")
	password := ctx.param("csac_password")
	if username == "" || password == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "请填写CsAC账号和密码"})
		return
	}
	user, err := app.fetchOne("SELECT id, pwd, ban_until FROM chat_user WHERE username = ?", username)
	if err != nil || user == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "账号不存在"})
		return
	}
	banUntil := intval(user, "ban_until")
	if banUntil > 0 && banUntil > time.Now().Unix() {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "账号已被封禁"})
		return
	}
	expectedPwd := hashCsacPassword(password, username)
	if str(user, "pwd") != expectedPwd {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "密码错误"})
		return
	}
	uid := intval(user, "id")
	// 校验uid是否是管理员
	if uid != app.config.AdminUID {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "非管理员账号"})
		return
	}
	// 设置acop_admin cookie
	http.SetCookie(ctx.w, &http.Cookie{
		Name:     "acop_admin",
		Value:    fmt.Sprintf("admin_%d", uid),
		Path:     "/",
		MaxAge:   86400 * 7,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "管理员登录成功"})
}

// apiAdminLogout 退出管理员会话
func (app *ACOP) apiAdminLogout(ctx *ACOPCtx) {
	http.SetCookie(ctx.w, &http.Cookie{
		Name:     "acop_admin",
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		HttpOnly: true,
	})
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "已退出管理员会话"})
}

// apiAdminCheck 检查当前会话是否有管理员权限
func (app *ACOP) apiAdminCheck(ctx *ACOPCtx) {
	isAdmin := false
	if cookie, err := ctx.r.Cookie("acop_admin"); err == nil && cookie.Value == fmt.Sprintf("admin_%d", app.config.AdminUID) {
		isAdmin = true
	}
	if !isAdmin && ctx.devID > 0 {
		dev, err := app.fetchOne("SELECT uid, status FROM open_dev_accounts WHERE id = ?", ctx.devID)
		if err == nil && dev != nil && intval(dev, "uid") == app.config.AdminUID && intval(dev, "status") == 1 {
			isAdmin = true
		}
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "is_admin": isAdmin})
}

func (app *ACOP) apiAdminPermHandle(ctx *ACOPCtx) {
	if !ctx.requireAdmin() {
		return
	}
	requestID := ctx.paramInt("request_id")
	action := ctx.param("action") // approve / reject
	adminReply := ctx.param("admin_reply")
	if requestID <= 0 || action == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少参数"})
		return
	}
	req, _ := app.fetchOne("SELECT id, bot_id, perm_type, reason FROM bot_perm_requests WHERE id = ? AND status = 0", requestID)
	if req == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "申请不存在或已处理"})
		return
	}
	status := int64(2) // 拒绝
	if action == "approve" {
		status = 1
		// 更新Bot权限
		botID := intval(req, "bot_id")
		permType := str(req, "perm_type")
		switch permType {
		case "notify":
			_, _ = app.updateRow("bot_accounts", map[string]any{"can_notify": 1}, "id = ?", botID)
		case "http":
			_, _ = app.updateRow("bot_accounts", map[string]any{"can_http": 1}, "id = ?", botID)
		}
	}
	_, _ = app.updateRow("bot_perm_requests", map[string]any{
		"status":      status,
		"admin_reply": adminReply,
		"handled_at":  time.Now().Unix(),
	}, "id = ?", requestID)

	// 发送通知给开发者的聊天账号
	app.sendDevNotice(requestID, status, str(req, "perm_type"), adminReply)

	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "已处理"})
}

// apiAdminPermPending 管理员查看所有待处理的权限申请
func (app *ACOP) apiAdminPermPending(ctx *ACOPCtx) {
	if !ctx.requireAdmin() {
		return
	}
	rows, err := app.fetchAll(
		"SELECT pr.id, pr.bot_id, pr.perm_type, pr.reason, pr.status, pr.created_at, " +
			"COALESCE(ba.bot_name, '(已删除)') AS bot_name, COALESCE(ba.uid, 0) AS bot_uid, " +
			"COALESCE(od.dev_name, '(已删除)') AS dev_name, COALESCE(od.email, '') AS email, COALESCE(od.uid, 0) AS dev_csac_uid " +
			"FROM bot_perm_requests pr " +
			"LEFT JOIN bot_accounts ba ON pr.bot_id = ba.id " +
			"LEFT JOIN open_dev_accounts od ON ba.dev_id = od.id " +
			"WHERE pr.status = 0 ORDER BY pr.created_at ASC")
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	result := make([]map[string]any, 0, len(rows))
	for _, r := range rows {
		result = append(result, map[string]any{
			"id":           intval(r, "id"),
			"bot_id":       intval(r, "bot_id"),
			"bot_name":     str(r, "bot_name"),
			"bot_uid":      intval(r, "bot_uid"),
			"perm_type":    str(r, "perm_type"),
			"reason":       str(r, "reason"),
			"dev_name":     str(r, "dev_name"),
			"email":        str(r, "email"),
			"dev_csac_uid": intval(r, "dev_csac_uid"),
			"created_at":   localDateTime(intval(r, "created_at")),
		})
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "data": result})
}

// sendDevNotice 发送审核结果通知到开发者对应的聊天账号
func (app *ACOP) sendDevNotice(requestID, status int64, permType, adminReply string) {
	// 获取开发者的CsAC uid
	row, err := app.fetchOne(
		"SELECT od.uid, od.dev_name, ba.bot_name, pr.perm_type "+
			"FROM bot_perm_requests pr "+
			"JOIN bot_accounts ba ON pr.bot_id = ba.id "+
			"JOIN open_dev_accounts od ON ba.dev_id = od.id "+
			"WHERE pr.id = ?", requestID)
	if err != nil || row == nil {
		return
	}
	devUID := intval(row, "uid")
	if devUID <= 0 {
		return
	}
	permLabel := map[string]string{
		"notify": "发送通知权限",
		"http":   "HTTP请求权限",
	}[permType]
	if permLabel == "" {
		permLabel = permType
	}
	actionLabel := "已拒绝"
	if status == 1 {
		actionLabel = "已通过"
	}
	title := fmt.Sprintf("ACOP 权限申请%s", actionLabel)
	content := fmt.Sprintf(
		"您的 Bot「%s」的 %s 申请%s。\n申请编号：%d",
		str(row, "bot_name"),
		permLabel,
		actionLabel,
		requestID,
	)
	if adminReply != "" {
		content += fmt.Sprintf("\n管理员备注：%s", adminReply)
	}
	_, err = app.insertRow("chat_user_notice", map[string]any{
		"uid":      devUID,
		"title":    title,
		"content":  content,
		"link":     "",
		"is_read":  0,
		"add_time": localDateTime(time.Now().Unix()),
	})
	if err != nil {
		log.Printf("ACOP: send notice to uid=%d failed: %v", devUID, err)
	}
}

// ===== 管理员: ACR脚本审核 =====

// apiAdminAcrPending 管理员查看待审核的ACR上传
func (app *ACOP) apiAdminAcrPending(ctx *ACOPCtx) {
	if !ctx.requireAdmin() {
		return
	}
	rows, err := app.fetchAll(
		"SELECT au.id, au.dev_id, au.file_name, au.file_type, au.status, au.created_at, " +
			"COALESCE(od.dev_name, '(已删除)') AS dev_name, COALESCE(od.email, '') AS email, COALESCE(od.uid, 0) AS dev_csac_uid, " +
			"COALESCE(au.`desc`, '') AS `desc` " +
			"FROM acr_uploads au " +
			"LEFT JOIN open_dev_accounts od ON au.dev_id = od.id " +
			"WHERE au.status = 0 ORDER BY au.created_at ASC")
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	result := make([]map[string]any, 0, len(rows))
	for _, r := range rows {
		result = append(result, map[string]any{
			"id":           intval(r, "id"),
			"dev_id":       intval(r, "dev_id"),
			"dev_name":     str(r, "dev_name"),
			"email":        str(r, "email"),
			"dev_csac_uid": intval(r, "dev_csac_uid"),
			"file_name":    str(r, "file_name"),
			"file_type":    str(r, "file_type"),
			"desc":         str(r, "desc"),
			"created_at":   localDateTime(intval(r, "created_at")),
		})
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "data": result})
}

// apiAdminAcrRead 管理员读取ACR文件内容
func (app *ACOP) apiAdminAcrRead(ctx *ACOPCtx) {
	if !ctx.requireAdmin() {
		return
	}
	uploadID := ctx.paramInt("id")
	if uploadID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少id参数"})
		return
	}
	row, err := app.fetchOne("SELECT id, file_name, file_type, content, dev_id, status, COALESCE(`desc`, '') AS `desc` FROM acr_uploads WHERE id = ?", uploadID)
	if err != nil || row == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件不存在"})
		return
	}
	ctx.JSON(http.StatusOK, map[string]any{
		"success":   true,
		"id":        intval(row, "id"),
		"file_name": str(row, "file_name"),
		"file_type": str(row, "file_type"),
		"content":   str(row, "content"),
		"dev_id":    intval(row, "dev_id"),
		"status":    intval(row, "status"),
		"desc":      str(row, "desc"),
	})
}

// apiAdminAcrReview 管理员审核ACR上传
func (app *ACOP) apiAdminAcrReview(ctx *ACOPCtx) {
	if !ctx.requireAdmin() {
		return
	}
	uploadID := ctx.paramInt("id")
	action := ctx.param("action") // approve / reject
	adminNote := ctx.param("admin_note")
	log.Printf("[DIAG] apiAdminAcrReview 入口 uploadID=%d action=%s adminNote=%s", uploadID, action, adminNote)
	if uploadID <= 0 || (action != "approve" && action != "reject") {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数无效"})
		return
	}

	row, err := app.fetchOne("SELECT id, file_name, file_type, content, dev_id, status FROM acr_uploads WHERE id = ?", uploadID)
	if err != nil || row == nil {
		log.Printf("[DIAG] apiAdminAcrReview 未找到上传记录 uploadID=%d err=%v", uploadID, err)
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "上传记录不存在"})
		return
	}
	if intval(row, "status") != 0 {
		log.Printf("[DIAG] apiAdminAcrReview 已审核 status=%d", intval(row, "status"))
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "该上传已被审核"})
		return
	}

	devID := intval(row, "dev_id")
	fileName := str(row, "file_name")
	fileType := str(row, "file_type")
	content := str(row, "content")
	log.Printf("[DIAG] apiAdminAcrReview 审核数据 fileName=%s fileType=%s contentLen=%d BotEndpoint=%s BotSecretLen=%d",
		fileName, fileType, len(content), app.config.BotEndpoint, len(app.config.BotSecret))

	now := time.Now().Unix()
	status := int64(2)
	if action == "approve" {
		status = 1
	}

	_, err = app.updateRow("acr_uploads", map[string]any{
		"status":      status,
		"admin_note":  adminNote,
		"reviewed_at": now,
	}, "id = ?", uploadID)
	if err != nil {
		log.Printf("[DIAG] apiAdminAcrReview DB更新失败: %v", err)
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "审核失败"})
		return
	}

	// 审核通过：通知 ServerBot 签名并保存为 AJL 文件到 lib/ 目录
	if action == "approve" && content != "" {
		libName := fileName
		libName = strings.TrimSuffix(libName, ".acr")
		libName = strings.TrimSuffix(libName, ".acrg")
		if err := app.notifyServerBotAcrSave(libName, "1.0.0", content); err != nil {
			log.Printf("ACOP: 通知ServerBot保存ACR失败: %v", err)
			ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "审核已通过，但保存文件到ServerBot失败: " + err.Error()})
			return
		}
	}

	// 通知开发者
	app.sendDevAcrNotice(devID, uploadID, fileName, fileType, status, adminNote)

	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "ACR已审核通过并保存"})
}

// sendDevAcrNotice 发送ACR审核结果通知
func (app *ACOP) sendDevAcrNotice(devID, uploadID int64, fileName, fileType string, status int64, adminNote string) {
	// 获取开发者CsAC uid
	dev, err := app.fetchOne("SELECT uid, dev_name FROM open_dev_accounts WHERE id = ?", devID)
	if err != nil || dev == nil {
		return
	}
	devUID := intval(dev, "uid")
	if devUID <= 0 {
		return
	}
	typeLabel := "ACR"
	if fileType == "acrg" {
		typeLabel = "ACRG"
	}
	actionLabel := "已拒绝"
	if status == 1 {
		actionLabel = "已通过"
	}
	title := fmt.Sprintf("ACOP %s 脚本审核%s", typeLabel, actionLabel)
	content := fmt.Sprintf(
		"您上传的 %s 脚本「%s」审核%s。\n上传编号：%d",
		typeLabel,
		fileName,
		actionLabel,
		uploadID,
	)
	if adminNote != "" {
		content += fmt.Sprintf("\n管理员备注：%s", adminNote)
	}
	_, err = app.insertRow("chat_user_notice", map[string]any{
		"uid":      devUID,
		"title":    title,
		"content":  content,
		"link":     "",
		"is_read":  0,
		"add_time": localDateTime(time.Now().Unix()),
	})
	if err != nil {
		log.Printf("ACOP: send acr notice to uid=%d failed: %v", devUID, err)
	}
}

// notifyAdminAcrUpload 通知管理员有新的ACR上传待审核
func (app *ACOP) notifyAdminAcrUpload(uploadID, devID int64, fileName, fileType string) {
	dev, _ := app.fetchOne("SELECT dev_name, email FROM open_dev_accounts WHERE id = ?", devID)
	devName := "未知开发者"
	devEmail := ""
	if dev != nil {
		devName = str(dev, "dev_name")
		devEmail = str(dev, "email")
	}
	typeLabel := "ACR"
	if fileType == "acrg" {
		typeLabel = "ACRG"
	}
	content := fmt.Sprintf(
		"ACOP 收到新的 %s 脚本上传，请及时审核。\n\n上传编号：%d\n文件名：%s\n开发者：%s (Dev ID: %d)\n邮箱：%s",
		typeLabel,
		uploadID,
		fileName,
		devName,
		devID,
		devEmail,
	)
	_, err := app.insertRow("chat_user_notice", map[string]any{
		"uid":      app.config.AdminUID,
		"title":    fmt.Sprintf("ACOP %s 脚本待审核", typeLabel),
		"content":  content,
		"link":     "",
		"is_read":  0,
		"add_time": localDateTime(time.Now().Unix()),
	})
	if err != nil {
		log.Printf("ACOP: notify admin acr upload failed: %v", err)
	}
}

// ===== 用户: EMA小程序上传 =====

// apiScriptUploadEma 用户上传EMA小程序包（不签名，待管理员审核）
func (app *ACOP) apiScriptUploadEma(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	fileName := ctx.param("file_name")
	content := ctx.param("content")
	desc := ctx.param("desc")
	if fileName == "" || content == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少 file_name 或 content"})
		return
	}
	if len(content) > 10*1024*1024 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "EMA包体过大（上限10MB）"})
		return
	}

	// 保存 .ema 文件到本地
	dir := filepath.Join(app.config.UploadDir, "ema", fmt.Sprintf("dev_%d", devID))
	os.MkdirAll(dir, 0755)
	safeName := strings.TrimSuffix(fileName, ".ema") + ".ema"
	dest := filepath.Join(dir, fmt.Sprintf("%d_%s", time.Now().UnixNano(), safeName))
	if err := os.WriteFile(dest, []byte(content), 0644); err != nil {
		log.Printf("ACOP: upload ema failed dev_id=%d file=%s err=%v", devID, safeName, err)
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件保存失败"})
		return
	}

	// 记录到审核表
	now := time.Now().Unix()
	uploadID, err := app.insertRow("ema_uploads", map[string]any{
		"dev_id":     devID,
		"file_name":  safeName,
		"file_path":  dest,
		"file_size":  int64(len(content)),
		"desc":       desc,
		"status":     0,
		"created_at": now,
	})
	if err != nil {
		log.Printf("ACOP: insert ema_uploads failed dev_id=%d file=%s err=%v", devID, safeName, err)
	}
	if uploadID > 0 && app.config.AdminUID > 0 {
		app.notifyAdminEmaUpload(uploadID, devID, safeName)
	}
	log.Printf("ACOP: ema uploaded dev_id=%d file=%s size=%d", devID, safeName, len(content))
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "EMA 已提交审核", "file_name": safeName})
}

// ===== 管理员: EMA审核 =====

func (app *ACOP) apiAdminEmaPending(ctx *ACOPCtx) {
	if !ctx.requireAdmin() {
		return
	}
	rows, err := app.fetchAll(
		"SELECT eu.id, eu.dev_id, eu.file_name, eu.file_size, eu.status, eu.created_at, " +
			"COALESCE(od.dev_name, '(已删除)') AS dev_name, COALESCE(od.email, '') AS email, COALESCE(od.uid, 0) AS dev_csac_uid, " +
			"COALESCE(eu.`desc`, '') AS `desc` " +
			"FROM ema_uploads eu " +
			"LEFT JOIN open_dev_accounts od ON eu.dev_id = od.id " +
			"WHERE eu.status = 0 " +
			"ORDER BY eu.created_at ASC")
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	result := make([]map[string]any, 0, len(rows))
	for _, r := range rows {
		result = append(result, map[string]any{
			"id":           intval(r, "id"),
			"dev_id":       intval(r, "dev_id"),
			"dev_name":     str(r, "dev_name"),
			"email":        str(r, "email"),
			"dev_csac_uid": intval(r, "dev_csac_uid"),
			"file_name":    str(r, "file_name"),
			"file_size":    intval(r, "file_size"),
			"desc":         str(r, "desc"),
			"status":       intval(r, "status"),
			"created_at":   localDateTime(intval(r, "created_at")),
		})
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "data": result})
}

func (app *ACOP) apiAdminEmaRead(ctx *ACOPCtx) {
	if !ctx.requireAdmin() {
		return
	}
	uploadID := ctx.paramInt("id")
	if uploadID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少id参数"})
		return
	}
	row, err := app.fetchOne("SELECT id, file_name, file_path, dev_id, status, COALESCE(`desc`, '') AS `desc` FROM ema_uploads WHERE id = ?", uploadID)
	if err != nil || row == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "文件不存在"})
		return
	}
	filePath := str(row, "file_path")
	data, err := os.ReadFile(filePath)
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "读取失败"})
		return
	}
	ctx.JSON(http.StatusOK, map[string]any{
		"success":   true,
		"id":        intval(row, "id"),
		"file_name": str(row, "file_name"),
		"content":   string(data),
		"dev_id":    intval(row, "dev_id"),
		"status":    intval(row, "status"),
		"desc":      str(row, "desc"),
	})
}

func (app *ACOP) apiAdminEmaReview(ctx *ACOPCtx) {
	if !ctx.requireAdmin() {
		return
	}
	uploadID := ctx.paramInt("id")
	action := ctx.param("action")
	adminNote := ctx.param("admin_note")
	if uploadID <= 0 || (action != "approve" && action != "reject") {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数无效"})
		return
	}

	row, err := app.fetchOne("SELECT id, file_name, file_path, dev_id, status FROM ema_uploads WHERE id = ?", uploadID)
	if err != nil || row == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "上传记录不存在"})
		return
	}
	if intval(row, "status") != 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "该上传已被审核"})
		return
	}

	status := 2
	if action == "approve" {
		status = 1
		// 审核通过：通知 eMApps 签名保存
		go app.callEmAppsApprove(
			intval(row, "id"),
			str(row, "file_name"),
			str(row, "file_path"),
		)
	}

	// 更新状态
	_, err = app.exec("UPDATE ema_uploads SET status = ?, admin_note = ?, reviewed_at = ? WHERE id = ?",
		status, adminNote, time.Now().Unix(), uploadID)
	if err != nil {
		log.Printf("ACOP: update ema review failed: %v", err)
	}

	// 通知开发者
	devID := intval(row, "dev_id")
	if devID > 0 {
		dev, _ := app.fetchOne("SELECT uid FROM open_dev_accounts WHERE id = ?", devID)
		if dev != nil && intval(dev, "uid") > 0 {
			actionLabel := "已拒绝"
			if status == 1 {
				actionLabel = "已通过"
			}
			title := fmt.Sprintf("EMA小程序审核%s", actionLabel)
			emailContent := fmt.Sprintf(
				"您上传的EMA小程序「%s」审核%s。\n上传编号：%d",
				str(row, "file_name"), actionLabel, uploadID,
			)
			if adminNote != "" {
				emailContent += fmt.Sprintf("\n管理员备注：%s", adminNote)
			}
			app.insertRow("chat_user_notice", map[string]any{
				"uid":      intval(dev, "uid"),
				"title":    title,
				"content":  emailContent,
				"link":     "",
				"is_read":  0,
				"add_time": localDateTime(time.Now().Unix()),
			})
		}
	}

	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "操作成功"})
}

// notifyAdminEmaUpload 通知管理员有新的EMA上传
func (app *ACOP) notifyAdminEmaUpload(uploadID, devID int64, fileName string) {
	dev, _ := app.fetchOne("SELECT dev_name FROM open_dev_accounts WHERE id = ?", devID)
	devName := "未知开发者"
	if dev != nil {
		devName = str(dev, "dev_name")
	}
	app.insertRow("chat_user_notice", map[string]any{
		"uid":      1,
		"title":    "有新的EMA小程序待审核",
		"content":  fmt.Sprintf("开发者 %s 上传了EMA小程序「%s」，编号 #%d，请及时审核。", devName, fileName, uploadID),
		"link":     "/admin/ema",
		"is_read":  0,
		"add_time": localDateTime(time.Now().Unix()),
	})
}

// callEmAppsApprove 通知 eMApps 服务对 EMA 进行签名保存
func (app *ACOP) callEmAppsApprove(uploadID int64, fileName, filePath string) {
	content, err := os.ReadFile(filePath)
	if err != nil {
		log.Printf("[DIAG] ACOP callEmAppsApprove 读取文件失败: path=%s err=%v", filePath, err)
		return
	}
	emAppsURL := os.Getenv("EMAPPS_URL")
	if emAppsURL == "" {
		emAppsURL = "http://csac-emapps:8090"
	}
	botSecret := os.Getenv("CSAC_BOT_SECRET")
	if botSecret == "" {
		botSecret = os.Getenv("ACOP_BOT_SECRET") // 兼容旧 env 名称
	}
	log.Printf("[DIAG] ACOP callEmAppsApprove 开始: uploadID=%d url=%s/%s botSecretLen=%d contentLen=%d",
		uploadID, emAppsURL, "emapps/internal/approve", len(botSecret), len(content))

	reqBody, _ := json.Marshal(map[string]string{
		"file_name": fileName,
		"content":   string(content),
		"source_id": fmt.Sprintf("acop_%d", uploadID),
	})
	req, err := http.NewRequest("POST", emAppsURL+"/emapps/internal/approve", bytes.NewReader(reqBody))
	if err != nil {
		log.Printf("[DIAG] ACOP callEmAppsApprove 创建请求失败: %v", err)
		return
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Bot-Secret", botSecret)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Printf("[DIAG] ACOP callEmAppsApprove HTTP调用失败: %v", err)
		return
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
	log.Printf("[DIAG] ACOP callEmAppsApprove 完成: uploadID=%d httpStatus=%d resp=%s", uploadID, resp.StatusCode, string(respBody))
}

func (app *ACOP) apiAdminBotList(ctx *ACOPCtx) {
	if !ctx.requireAdmin() {
		return
	}
	bots, err := app.fetchAll(
		"SELECT ba.id, ba.uid, ba.dev_id, ba.bot_name, ba.bot_desc, ba.bot_avatar, ba.status, ba.can_notify, ba.can_http, ba.online, ba.last_online, ba.created_at, " +
			"da.dev_name, da.email FROM bot_accounts ba JOIN open_dev_accounts da ON ba.dev_id = da.id ORDER BY ba.id DESC")
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	requestsByBot := map[int64][]map[string]any{}
	if len(bots) > 0 {
		ids := make([]string, 0, len(bots))
		args := make([]any, 0, len(bots))
		for _, b := range bots {
			ids = append(ids, "?")
			args = append(args, intval(b, "id"))
		}
		requests, err := app.fetchAll(
			"SELECT id, bot_id, perm_type, reason, status, admin_reply, created_at, handled_at FROM bot_perm_requests WHERE bot_id IN ("+
				strings.Join(ids, ",")+
				") ORDER BY status ASC, id DESC",
			args...,
		)
		if err == nil {
			for _, r := range requests {
				botID := intval(r, "bot_id")
				requestsByBot[botID] = append(requestsByBot[botID], map[string]any{
					"request_id":  intval(r, "id"),
					"bot_id":      botID,
					"perm_type":   str(r, "perm_type"),
					"reason":      str(r, "reason"),
					"status":      intval(r, "status"),
					"admin_reply": str(r, "admin_reply"),
					"created_at":  localDateTime(intval(r, "created_at")),
					"handled_at":  localDateTime(intval(r, "handled_at")),
				})
			}
		}
	}
	list := make([]map[string]any, 0, len(bots))
	for _, b := range bots {
		botID := intval(b, "id")
		list = append(list, map[string]any{
			"bot_id":              botID,
			"uid":                 intval(b, "uid"),
			"dev_id":              intval(b, "dev_id"),
			"bot_name":            str(b, "bot_name"),
			"bot_desc":            str(b, "bot_desc"),
			"bot_avatar":          str(b, "bot_avatar"),
			"status":              intval(b, "status"),
			"can_notify":          intval(b, "can_notify"),
			"can_http":            intval(b, "can_http"),
			"online":              intval(b, "online"),
			"last_online":         intval(b, "last_online"),
			"created_at":          intval(b, "created_at"),
			"dev_name":            str(b, "dev_name"),
			"email":               str(b, "email"),
			"permission_requests": requestsByBot[botID],
		})
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "data": list})
}

// ===== 辅助函数 =====

func localDateTime(ts int64) string {
	return time.Unix(ts, 0).Format("2006-01-02 15:04:05")
}

func avatarExt(mime, filename string) string {
	switch strings.ToLower(mime) {
	case "image/png":
		return "png"
	case "image/jpeg":
		return "jpg"
	case "image/gif":
		return "gif"
	case "image/webp":
		return "webp"
	}
	switch strings.ToLower(strings.TrimPrefix(filepath.Ext(filename), ".")) {
	case "png", "jpg", "jpeg", "gif", "webp":
		if strings.EqualFold(filepath.Ext(filename), ".jpeg") {
			return "jpg"
		}
		return strings.ToLower(strings.TrimPrefix(filepath.Ext(filename), "."))
	}
	return ""
}

// ===== v2.2.1: JSLibs 库管理 API =====

// apiLibUpload 开发者上传AJL库
func (app *ACOP) apiLibUpload(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	// 检查开发者是否有上传权限
	dev, _ := app.fetchOne("SELECT id, allow_ajl_upload, status FROM open_dev_accounts WHERE id = ?", devID)
	if dev == nil || intval(dev, "status") != 1 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "账号状态异常"})
		return
	}
	if intval(dev, "allow_ajl_upload") != 1 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "未获得AJL库上传权限，请联系管理员申请"})
		return
	}

	name := ctx.param("name")
	version := ctx.param("version")
	content := ctx.param("content")
	author := ctx.param("author")
	desc := ctx.param("desc")

	name = strings.TrimSpace(name)
	content = strings.TrimSpace(content)
	if name == "" || content == "" {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "库名和内容不能为空"})
		return
	}
	if version == "" {
		version = "1.0.0"
	}
	if !regexp.MustCompile(`^[a-zA-Z][a-zA-Z0-9_-]{0,49}$`).MatchString(name) {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "库名格式无效：需以字母开头，仅允许字母数字下划线连字符，最长50字符"})
		return
	}
	if len(content) > 512*1024 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "库内容超过512KB限制"})
		return
	}

	// 检查是否已存在同名同版本
	existing, _ := app.fetchOne("SELECT id, status FROM bot_libs WHERE name = ? AND version = ?", name, version)
	if existing != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "该库版本已存在"})
		return
	}

	now := time.Now().Unix()
	_, err := app.insertRow("bot_libs", map[string]any{
		"name":       name,
		"version":    version,
		"content":    content,
		"signature":  "", // 签名由ServerBot审核通过后生成
		"author":     author,
		"desc":       desc,
		"dev_id":     devID,
		"status":     0,
		"created_at": now,
	})
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "上传失败"})
		return
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "库已提交，等待管理员审核"})
}

// apiLibMyLibs 开发者查看自己上传的库
func (app *ACOP) apiLibMyLibs(ctx *ACOPCtx) {
	devID, ok := ctx.requireLogin()
	if !ok {
		return
	}
	rows, err := app.fetchAll("SELECT id, name, version, author, `desc`, status, admin_note, created_at, reviewed_at FROM bot_libs WHERE dev_id = ? ORDER BY created_at DESC", devID)
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	statusMap := map[int64]string{0: "pending", 1: "approved", 2: "rejected"}
	result := make([]map[string]any, 0, len(rows))
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
			"created_at":  localDateTime(intval(row, "created_at")),
			"reviewed_at": localDateTime(intval(row, "reviewed_at")),
		})
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "libs": result})
}

// apiLibList 获取已通过审核的库列表（公开）
func (app *ACOP) apiLibList(ctx *ACOPCtx) {
	rows, err := app.fetchAll("SELECT name, version, author, `desc` FROM bot_libs WHERE status = 1 ORDER BY name ASC")
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	result := make([]map[string]any, 0, len(rows))
	for _, row := range rows {
		result = append(result, map[string]any{
			"name":    str(row, "name"),
			"version": str(row, "version"),
			"author":  str(row, "author"),
			"desc":    str(row, "desc"),
		})
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "libs": result})
}

// apiAdminLibPending 管理员查看待审核库列表
func (app *ACOP) apiAdminLibPending(ctx *ACOPCtx) {
	if !ctx.requireAdmin() {
		return
	}
	rows, err := app.fetchAll(
		"SELECT l.id, l.name, l.version, l.author, l.`desc`, l.content, l.dev_id, l.created_at, d.dev_name " +
			"FROM bot_libs l JOIN open_dev_accounts d ON l.dev_id = d.id WHERE l.status = 0 ORDER BY l.created_at ASC")
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "查询失败"})
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
			"content":    str(row, "content"),
			"dev_id":     intval(row, "dev_id"),
			"dev_name":   str(row, "dev_name"),
			"created_at": localDateTime(intval(row, "created_at")),
		})
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "libs": result})
}

// apiAdminLibReview 管理员审核库
func (app *ACOP) apiAdminLibReview(ctx *ACOPCtx) {
	if !ctx.requireAdmin() {
		return
	}
	libID := ctx.paramInt("id")
	action := ctx.param("action") // approve / reject
	adminNote := ctx.param("admin_note")
	if libID <= 0 || (action != "approve" && action != "reject") {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "参数无效"})
		return
	}

	lib, _ := app.fetchOne("SELECT id, name, version, content, status FROM bot_libs WHERE id = ?", libID)
	if lib == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "库不存在"})
		return
	}
	if intval(lib, "status") != 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "该库已被审核"})
		return
	}

	now := time.Now().Unix()
	if action == "approve" {
		// 更新审核状态
		_, err := app.updateRow("bot_libs", map[string]any{
			"status":      1,
			"reviewed_at": now,
			"admin_note":  adminNote,
		}, "id = ?", libID)
		if err != nil {
			ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "审核失败"})
			return
		}
		// 通知ServerBot签名保存库到磁盘
		if err := app.notifyServerBotLibApprove(libID, str(lib, "name"), str(lib, "version"), str(lib, "content")); err != nil {
			log.Printf("ACOP: 通知ServerBot保存库失败: %v", err)
			ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "审核已通过，但保存库文件到ServerBot失败: " + err.Error()})
			return
		}
		ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "库已审核通过并保存"})
	} else {
		_, err := app.updateRow("bot_libs", map[string]any{
			"status":      2,
			"reviewed_at": now,
			"admin_note":  adminNote,
		}, "id = ?", libID)
		if err != nil {
			ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "审核失败"})
			return
		}
		ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "库已拒绝"})
	}
}

// apiAdminLibSetUploadPerm 管理员设置开发者的AJL上传权限
func (app *ACOP) apiAdminLibSetUploadPerm(ctx *ACOPCtx) {
	if !ctx.requireAdmin() {
		return
	}
	devID := ctx.paramInt("dev_id")
	allow := ctx.paramInt("allow") // 0 or 1
	if devID <= 0 {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "dev_id无效"})
		return
	}
	dev, _ := app.fetchOne("SELECT id FROM open_dev_accounts WHERE id = ?", devID)
	if dev == nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "开发者不存在"})
		return
	}
	_, err := app.updateRow("open_dev_accounts", map[string]any{"allow_ajl_upload": allow}, "id = ?", devID)
	if err != nil {
		ctx.JSON(http.StatusOK, map[string]any{"success": false, "message": "更新失败"})
		return
	}
	ctx.JSON(http.StatusOK, map[string]any{"success": true, "message": "权限已更新"})
}

// notifyServerBotLibApprove 同步保存库到 ServerBot lib/ 目录，返回error
func (app *ACOP) notifyServerBotLibApprove(libID int64, name, version, content string) error {
	log.Printf("[DIAG] notifyServerBotLibApprove 调用 name=%s version=%s contentLen=%d", name, version, len(content))
	return app.saveToServerBotLib(name, version, content, libID)
}

// notifyServerBotAcrSave 同步将ACR脚本签名保存为AJL文件到ServerBot lib/，返回error
func (app *ACOP) notifyServerBotAcrSave(name, version, content string) error {
	log.Printf("[DIAG] notifyServerBotAcrSave 入口 name=%s version=%s contentLen=%d", name, version, len(content))
	return app.saveToServerBotLib(name, version, content, 0)
}

// saveToServerBotLib 保存库文件到 ServerBot 的 lib/ 目录
// 策略：
//   - 若设置了 ACOP_LIB_DIR 环境变量 → 直接写入磁盘 + 通知 ServerBot 重载
//   - 否则（Docker 等容器化部署）→ 通过 HTTP /bot/internal/lib/approve 让 ServerBot 自行保存
func (app *ACOP) saveToServerBotLib(name, version, content string, libID int64) error {
	log.Printf("[DIAG] saveToServerBotLib 开始 name=%s libID=%d BotEndpoint=%q LibDir=%q",
		name, libID, app.config.BotEndpoint, app.config.LibDir)

	// 策略1：ACOP_LIB_DIR 明确设置 → 直接写磁盘（同机/共享卷部署）
	if app.config.LibDir != "" {
		log.Printf("[DIAG] saveToServerBotLib 使用直接写入模式 libDir=%s", app.config.LibDir)
		if err := app.writeLibFileDirect(name, version, content); err != nil {
			return fmt.Errorf("直接写入失败: %w", err)
		}
		// 通知 ServerBot 重载
		if err := app.notifyServerBotReloadLib(); err != nil {
			log.Printf("[DIAG] saveToServerBotLib 写入成功但reload失败: %v", err)
		}
		log.Printf("[DIAG] saveToServerBotLib 直接写入完成")
		return nil
	}

	// 策略2：未设置 ACOP_LIB_DIR → HTTP 通知 ServerBot 自签名保存（Docker 等容器化部署）
	if app.config.BotEndpoint == "" {
		return fmt.Errorf("未配置 ACOP_LIB_DIR 且未配置 BotEndpoint，无法保存库文件。请设置 ACOP_LIB_DIR 或 ACOP_BOTAPI_URL")
	}

	url := app.config.BotEndpoint + "/bot/internal/lib/approve"
	log.Printf("[DIAG] saveToServerBotLib 使用HTTP模式 url=%s", url)

	data, _ := json.Marshal(map[string]any{
		"id":      libID,
		"name":    name,
		"version": version,
		"content": content,
	})
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("创建HTTP请求失败: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Bot-Secret", app.config.BotSecret)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		log.Printf("[DIAG] saveToServerBotLib HTTP请求失败 url=%s err=%v", url, err)
		return fmt.Errorf("连接ServerBot失败: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode != http.StatusOK {
		log.Printf("[DIAG] saveToServerBotLib HTTP返回错误 status=%d body=%s", resp.StatusCode, string(body))
		return fmt.Errorf("ServerBot返回 %d: %s", resp.StatusCode, string(body))
	}

	log.Printf("[DIAG] saveToServerBotLib HTTP保存成功 name=%s", name)
	return nil
}

// writeLibFileDirect 直接签名并写入 AJL 文件到 ServerBot 的 lib/ 目录
func (app *ACOP) writeLibFileDirect(name, version, content string) error {
	// 确定 lib 目录：优先 ACOP_LIB_DIR 环境变量，否则 ../ServerBot/lib 相对路径
	var libDir string
	if app.config.LibDir != "" {
		libDir = app.config.LibDir
	} else {
		exePath, _ := os.Executable()
		exeDir := filepath.Dir(exePath)
		libDir = filepath.Join(exeDir, "..", "ServerBot", "lib")
	}
	log.Printf("[DIAG] writeLibFileDirect 开始 name=%s version=%s contentLen=%d libDir=%s exeDir=%s",
		name, version, len(content), libDir, filepath.Dir(func() string { p, _ := os.Executable(); return p }()))

	// 生成签名（使用与ServerBot相同的算法和密钥）
	ajl := map[string]string{
		"name":    name,
		"version": version,
		"content": content,
	}
	signature := acopGenerateAJLSignature(name, version, content, app.config.BotSecret)
	ajl["signature"] = signature
	log.Printf("[DIAG] writeLibFileDirect 签名完成 signatureLen=%d", len(signature))

	data, err := json.MarshalIndent(ajl, "", "  ")
	if err != nil {
		log.Printf("[DIAG] writeLibFileDirect JSON序列化失败: %v", err)
		return fmt.Errorf("序列化AJL失败: %w", err)
	}
	log.Printf("[DIAG] writeLibFileDirect JSON大小=%d bytes", len(data))

	if err := os.MkdirAll(libDir, 0775); err != nil {
		log.Printf("[DIAG] writeLibFileDirect MkdirAll失败 libDir=%s err=%v", libDir, err)
		return fmt.Errorf("创建目录 %s 失败: %w", libDir, err)
	}
	log.Printf("[DIAG] writeLibFileDirect MkdirAll成功 libDir=%s", libDir)

	filename := strings.ToLower(name) + ".ajl"
	dest := filepath.Join(libDir, filename)
	log.Printf("[DIAG] writeLibFileDirect 目标文件=%s", dest)
	if err := os.WriteFile(dest, data, 0664); err != nil {
		log.Printf("[DIAG] writeLibFileDirect WriteFile失败 dest=%s err=%v", dest, err)
		return fmt.Errorf("写入 %s 失败: %w", dest, err)
	}

	log.Printf("[DIAG] writeLibFileDirect 写入成功! 文件=%s 大小=%d 签名=%s...", dest, len(data), signature[:16])
	return nil
}

// notifyServerBotReloadLib 通知ServerBot重新加载lib目录
func (app *ACOP) notifyServerBotReloadLib() error {
	if app.config.BotEndpoint == "" {
		return fmt.Errorf("BotEndpoint未配置")
	}

	url := app.config.BotEndpoint + "/bot/internal/lib/reload"
	req, err := http.NewRequest(http.MethodPost, url, nil)
	if err != nil {
		return fmt.Errorf("创建重载请求失败: %w", err)
	}
	req.Header.Set("X-Bot-Secret", app.config.BotSecret)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("重载请求网络错误: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("重载返回 %d: %s", resp.StatusCode, string(body))
	}

	log.Printf("ACOP: 已通知ServerBot重载lib目录")
	return nil
}

// ==== AJL 签名函数（与 ServerBot/jslibs.go 完全一致）====

var acopAJLSignPepper = []byte("CsAC-AJL-Sign-v2.2.1-pepper-x9K3mQ7rT")

func acopDeriveSignKey(key string) []byte {
	salted := append([]byte(key), acopAJLSignPepper...)
	mac := hmac.New(sha256.New, salted)
	mac.Write([]byte(key))
	result := mac.Sum(nil)
	for i := 0; i < 999; i++ {
		mac = hmac.New(sha256.New, salted)
		mac.Write(result)
		result = mac.Sum(nil)
	}
	return result
}

func acopGenerateAJLSignature(name, version, content, key string) string {
	derivedKey := acopDeriveSignKey(key)
	mac := hmac.New(sha512.New, derivedKey)
	mac.Write([]byte(name + "\x00" + version + "\x00" + content))
	return hex.EncodeToString(mac.Sum(nil))
}

// apiDiagTestSave 诊断端点：测试保存流程
func (app *ACOP) apiDiagTestSave(ctx *ACOPCtx) {
	testName := ctx.param("name")
	testContent := ctx.param("content")
	mode := ctx.param("mode") // "direct" | "http" | "" (both)
	if testName == "" {
		testName = "diag_test"
	}
	if testContent == "" {
		testContent = "// DIAG test content\nconsole.log('test');"
	}

	status := map[string]any{
		"botEndpoint":    app.config.BotEndpoint,
		"botSecretLen":   len(app.config.BotSecret),
		"libDirEnv":      app.config.LibDir,
		"testName":       testName,
		"testContentLen": len(testContent),
		"strategy": func() string {
			if app.config.LibDir != "" {
				return "direct"
			} else {
				return "http"
			}
		}(),
	}

	// 测试完整保存流程（使用当前策略）
	fullErr := app.saveToServerBotLib(testName+"_full", "1.0.0", testContent, 0)
	status["saveLib_full"] = func() string {
		if fullErr != nil {
			return "FAIL: " + fullErr.Error()
		}
		return "OK"
	}()

	// 如果指定了 mode=direct，单独测试直接写入
	if mode == "direct" || mode == "" {
		directErr := app.writeLibFileDirect(testName, "1.0.0", testContent)
		status["writeLibFileDirect"] = func() string {
			if directErr != nil {
				return "FAIL: " + directErr.Error()
			}
			return "OK"
		}()
	}

	// 如果指定了 mode=http 或默认，测试 HTTP approve
	if mode == "http" || mode == "" {
		if app.config.BotEndpoint != "" {
			url := app.config.BotEndpoint + "/bot/internal/lib/approve"
			status["approveUrl"] = url
			data, _ := json.Marshal(map[string]any{
				"id":      0,
				"name":    testName + "_http",
				"version": "1.0.0",
				"content": testContent,
			})
			req, _ := http.NewRequest(http.MethodPost, url, bytes.NewReader(data))
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("X-Bot-Secret", app.config.BotSecret)
			client := &http.Client{Timeout: 10 * time.Second}
			resp, err := client.Do(req)
			if err != nil {
				status["httpApprove"] = "FAIL: " + err.Error()
			} else {
				defer resp.Body.Close()
				body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
				if resp.StatusCode == http.StatusOK {
					status["httpApprove"] = "OK"
				} else {
					status["httpApprove"] = fmt.Sprintf("FAIL status=%d body=%s", resp.StatusCode, string(body))
				}
			}
		} else {
			status["httpApprove"] = "SKIP (BotEndpoint未配置)"
		}

		// HTTP reload
		if app.config.BotEndpoint != "" {
			reloadErr := app.notifyServerBotReloadLib()
			status["reloadLib"] = func() string {
				if reloadErr != nil {
					return "FAIL: " + reloadErr.Error()
				}
				return "OK"
			}()
		} else {
			status["reloadLib"] = "SKIP (BotEndpoint未配置)"
		}
	}

	status["success"] = fullErr == nil
	log.Printf("[DIAG] apiDiagTestSave: %+v", status)
	ctx.JSON(http.StatusOK, status)
}

func generateSecureToken(length int) string {
	buf := make([]byte, (length+1)/2)
	if _, err := rand.Read(buf); err != nil {
		return strings.ReplaceAll(fmt.Sprintf("%d_%d", time.Now().UnixNano(), length), "-", "")
	}
	return hex.EncodeToString(buf)[:length]
}
