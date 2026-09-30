// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC ServerBot Framework Version 1.0.0.260614-r1
// JavaScript script runtime and platform SDK.

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	neturl "net/url"
	"strings"
	"sync"
	"time"

	"github.com/dop251/goja"
)

const jsEventTimeout = 3 * time.Second

type JSRuntime struct {
	fw     *BotFramework
	botID  int64
	botUID int64

	vm        *goja.Runtime
	mu        sync.Mutex
	handlers  map[string][]goja.Callable
	commands  []*JSCommand
	schedules []JSSchedule
	logBuf    []string
}

type JSCommand struct {
	PatternValue goja.Value
	Exact        string
	IsRegex      bool
	Scope        string
	Handler      goja.Callable
}

type JSSchedule struct {
	Expression string
	EventName  string
}

func NewJSRuntime(fw *BotFramework, botID, botUID int64) *JSRuntime {
	return &JSRuntime{
		fw:       fw,
		botID:    botID,
		botUID:   botUID,
		handlers: make(map[string][]goja.Callable),
	}
}

func (rt *JSRuntime) Compile(script string) error {
	rt.mu.Lock()
	defer rt.mu.Unlock()

	rt.vm = goja.New()
	rt.vm.SetMaxCallStackSize(2048)
	rt.handlers = make(map[string][]goja.Callable)
	rt.commands = nil
	rt.schedules = nil
	rt.logBuf = nil
	if err := rt.installGlobals(); err != nil {
		return err
	}

	// v2.2.1: 解析 import 语句，注入 JSLibs 库代码
	resolved, err := resolveImports(script, rt.fw.config.AllowTPartyLib)
	if err != nil {
		return fmt.Errorf("JSLibs import 解析失败: %w", err)
	}

	stopTimer := time.AfterFunc(jsEventTimeout, func() {
		rt.vm.Interrupt("JavaScript compile execution timeout")
	})
	defer func() {
		stopTimer.Stop()
		rt.vm.ClearInterrupt()
	}()
	_, err = rt.vm.RunScript(fmt.Sprintf("bot_%d.js", rt.botID), resolved)
	if err != nil {
		return err
	}
	return nil
}

func (rt *JSRuntime) DispatchEvent(eventName string, eventData map[string]any) error {
	rt.mu.Lock()
	defer rt.mu.Unlock()

	if rt.vm == nil {
		return nil
	}
	ctx := rt.newCtx(eventName, eventData)

	stopTimer := time.AfterFunc(jsEventTimeout, func() {
		rt.vm.Interrupt("JavaScript event execution timeout")
	})
	defer func() {
		stopTimer.Stop()
		rt.vm.ClearInterrupt()
	}()

	if eventName == "private.message" || eventName == "group.message" {
		if err := rt.dispatchCommands(ctx); err != nil {
			return err
		}
	}
	for _, handler := range rt.handlers[eventName] {
		if err := rt.callHandler(handler, ctx, nil); err != nil {
			return err
		}
	}
	return nil
}

func (rt *JSRuntime) Test(eventName string, eventData map[string]any) ([]string, error) {
	rt.logBuf = nil
	if err := rt.DispatchEvent(eventName, eventData); err != nil {
		return rt.logBuf, err
	}
	return rt.logBuf, nil
}

func (rt *JSRuntime) installGlobals() error {
	vm := rt.vm
	_ = vm.Set("require", goja.Undefined())
	_ = vm.Set("process", goja.Undefined())
	_ = vm.Set("fetch", goja.Undefined())
	_ = vm.Set("eval", func(goja.FunctionCall) goja.Value {
		panic(vm.NewTypeError("eval is disabled in CsAC Bot scripts"))
	})
	_ = vm.Set("Function", func(goja.FunctionCall) goja.Value {
		panic(vm.NewTypeError("Function constructor is disabled in CsAC Bot scripts"))
	})

	consoleObj := vm.NewObject()
	_ = consoleObj.Set("log", func(call goja.FunctionCall) goja.Value {
		rt.writeLog("log", rt.formatArgs(call.Arguments))
		return goja.Undefined()
	})
	_ = consoleObj.Set("warn", func(call goja.FunctionCall) goja.Value {
		rt.writeLog("warn", rt.formatArgs(call.Arguments))
		return goja.Undefined()
	})
	_ = consoleObj.Set("error", func(call goja.FunctionCall) goja.Value {
		rt.writeLog("error", rt.formatArgs(call.Arguments))
		return goja.Undefined()
	})
	_ = vm.Set("console", consoleObj)

	loggerObj := vm.NewObject()
	_ = loggerObj.Set("info", func(call goja.FunctionCall) goja.Value {
		rt.writeLog("log", rt.formatArgs(call.Arguments))
		return goja.Undefined()
	})
	_ = loggerObj.Set("log", func(call goja.FunctionCall) goja.Value {
		rt.writeLog("log", rt.formatArgs(call.Arguments))
		return goja.Undefined()
	})
	_ = loggerObj.Set("warn", func(call goja.FunctionCall) goja.Value {
		rt.writeLog("warn", rt.formatArgs(call.Arguments))
		return goja.Undefined()
	})
	_ = loggerObj.Set("error", func(call goja.FunctionCall) goja.Value {
		rt.writeLog("error", rt.formatArgs(call.Arguments))
		return goja.Undefined()
	})
	_ = vm.Set("logger", loggerObj)

	botObj := vm.NewObject()
	_ = botObj.Set("on", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) < 2 {
			panic(vm.NewTypeError("bot.on(eventName, handler) requires 2 arguments"))
		}
		eventName := strings.TrimSpace(call.Argument(0).String())
		handler, ok := goja.AssertFunction(call.Argument(1))
		if eventName == "" || !ok {
			panic(vm.NewTypeError("bot.on(eventName, handler) invalid arguments"))
		}
		rt.handlers[eventName] = append(rt.handlers[eventName], handler)
		return goja.Undefined()
	})
	_ = botObj.Set("command", func(call goja.FunctionCall) goja.Value {
		rt.registerCommand(call)
		return goja.Undefined()
	})
	_ = botObj.Set("schedule", func(call goja.FunctionCall) goja.Value {
		rt.registerSchedule(call)
		return goja.Undefined()
	})
	_ = botObj.Set("onPrivateMessage", func(call goja.FunctionCall) goja.Value {
		rt.registerShortcut("private.message", call)
		return goja.Undefined()
	})
	_ = botObj.Set("onGroupMessage", func(call goja.FunctionCall) goja.Value {
		rt.registerShortcut("group.message", call)
		return goja.Undefined()
	})
	_ = botObj.Set("onGroupMemberJoin", func(call goja.FunctionCall) goja.Value {
		rt.registerShortcut("group.member.join", call)
		return goja.Undefined()
	})
	_ = botObj.Set("onGroupMemberLeave", func(call goja.FunctionCall) goja.Value {
		rt.registerShortcut("group.member.leave", call)
		return goja.Undefined()
	})
	_ = botObj.Set("onGroupMemberMute", func(call goja.FunctionCall) goja.Value {
		rt.registerShortcut("group.member.mute", call)
		return goja.Undefined()
	})
	_ = botObj.Set("onGroupDisband", func(call goja.FunctionCall) goja.Value {
		rt.registerShortcut("group.disband", call)
		return goja.Undefined()
	})
	_ = vm.Set("bot", botObj)

	return vm.Set("csac", rt.newCSACObject())
}

func (rt *JSRuntime) registerShortcut(eventName string, call goja.FunctionCall) {
	if len(call.Arguments) < 1 {
		panic(rt.vm.NewTypeError("handler is required"))
	}
	handler, ok := goja.AssertFunction(call.Argument(0))
	if !ok {
		panic(rt.vm.NewTypeError("handler must be a function"))
	}
	rt.handlers[eventName] = append(rt.handlers[eventName], handler)
}

func (rt *JSRuntime) registerCommand(call goja.FunctionCall) {
	if len(call.Arguments) < 2 {
		panic(rt.vm.NewTypeError("bot.command(pattern, [options], handler) requires at least 2 arguments"))
	}
	pattern := call.Argument(0)
	scope := "all"
	handlerValue := call.Argument(1)
	if len(call.Arguments) >= 3 {
		if opts := call.Argument(1); !goja.IsUndefined(opts) && !goja.IsNull(opts) {
			if obj := opts.ToObject(rt.vm); obj != nil {
				if v := obj.Get("scope"); !goja.IsUndefined(v) && !goja.IsNull(v) {
					scope = strings.TrimSpace(v.String())
				}
			}
		}
		handlerValue = call.Argument(2)
	}
	handler, ok := goja.AssertFunction(handlerValue)
	if !ok {
		panic(rt.vm.NewTypeError("command handler must be a function"))
	}
	cmd := &JSCommand{PatternValue: pattern, Scope: scope, Handler: handler}
	if patternObj := pattern.ToObject(rt.vm); patternObj != nil && patternObj.ClassName() == "RegExp" {
		cmd.IsRegex = true
	} else {
		cmd.Exact = strings.TrimSpace(pattern.String())
	}
	if cmd.Scope == "" {
		cmd.Scope = "all"
	}
	rt.commands = append(rt.commands, cmd)
}

func (rt *JSRuntime) registerSchedule(call goja.FunctionCall) {
	if len(call.Arguments) < 2 {
		panic(rt.vm.NewTypeError("bot.schedule(expression, handler) requires at least 2 arguments"))
	}
	var name, expression string
	var handlerValue goja.Value
	if len(call.Arguments) >= 3 {
		name = strings.TrimSpace(call.Argument(0).String())
		expression = strings.TrimSpace(call.Argument(1).String())
		handlerValue = call.Argument(2)
	} else {
		expression = strings.TrimSpace(call.Argument(0).String())
		name = fmt.Sprintf("schedule:%d", len(rt.schedules)+1)
		handlerValue = call.Argument(1)
	}
	handler, ok := goja.AssertFunction(handlerValue)
	if expression == "" || !ok {
		panic(rt.vm.NewTypeError("bot.schedule invalid arguments"))
	}
	eventName := "schedule." + name
	rt.handlers[eventName] = append(rt.handlers[eventName], handler)
	rt.schedules = append(rt.schedules, JSSchedule{Expression: expression, EventName: eventName})
}

func (rt *JSRuntime) dispatchCommands(ctx *goja.Object) error {
	text := strings.TrimSpace(ctx.Get("text").String())
	if text == "" || len(rt.commands) == 0 {
		return nil
	}
	isGroup := ctx.Get("isGroup").ToBoolean()
	isPrivate := ctx.Get("isPrivate").ToBoolean()
	for _, cmd := range rt.commands {
		if cmd.Scope == "group" && !isGroup {
			continue
		}
		if cmd.Scope == "private" && !isPrivate {
			continue
		}
		matched, matchValue, err := rt.matchCommand(cmd, text)
		if err != nil {
			return err
		}
		if matched {
			if err := rt.callHandler(cmd.Handler, ctx, matchValue); err != nil {
				return err
			}
		}
	}
	return nil
}

func (rt *JSRuntime) matchCommand(cmd *JSCommand, text string) (bool, goja.Value, error) {
	if !cmd.IsRegex {
		return text == cmd.Exact, goja.Undefined(), nil
	}
	obj := cmd.PatternValue.ToObject(rt.vm)
	_ = obj.Set("lastIndex", 0)
	execValue := obj.Get("exec")
	exec, ok := goja.AssertFunction(execValue)
	if !ok {
		return false, goja.Undefined(), nil
	}
	result, err := exec(obj, rt.vm.ToValue(text))
	if err != nil {
		return false, nil, err
	}
	if goja.IsNull(result) || goja.IsUndefined(result) {
		return false, goja.Undefined(), nil
	}
	return true, result, nil
}

func (rt *JSRuntime) callHandler(handler goja.Callable, ctx *goja.Object, extra goja.Value) error {
	args := []goja.Value{ctx}
	if extra != nil {
		args = append(args, extra)
	}
	value, err := handler(goja.Undefined(), args...)
	if err != nil {
		return err
	}
	return rt.checkPromise(value)
}

func (rt *JSRuntime) checkPromise(value goja.Value) error {
	exported := value.Export()
	promise, ok := exported.(*goja.Promise)
	if !ok || promise == nil {
		return nil
	}
	if promise.State() == goja.PromiseStateRejected {
		return fmt.Errorf("promise rejected: %s", promise.Result().String())
	}
	return nil
}

func (rt *JSRuntime) newCtx(eventName string, eventData map[string]any) *goja.Object {
	vm := rt.vm
	ctx := vm.NewObject()
	_ = ctx.Set("eventName", eventName)
	_ = ctx.Set("eventId", fmt.Sprintf("%s:%d:%d", eventName, rt.botID, time.Now().UnixNano()))
	_ = ctx.Set("time", eventTimestamp(eventData))
	_ = ctx.Set("raw", eventData)
	_ = ctx.Set("bot", rt.botInfo())

	text := strings.TrimSpace(fmt.Sprint(eventData["content"]))
	if eventData["content"] == nil {
		text = ""
	}
	_ = ctx.Set("text", text)

	senderUID := eventSenderUID(eventName, eventData)
	_ = ctx.Set("sender", rt.userInfo(senderUID))
	_ = ctx.Set("isPrivate", eventName == "private.message")
	_ = ctx.Set("isGroup", strings.HasPrefix(eventName, "group."))

	if eventName == "private.message" {
		_ = ctx.Set("private", map[string]any{"fromUid": toInt64(eventData["from_uid"]), "toUid": toInt64(eventData["to_uid"])})
	}
	if roomID := toInt64(eventData["room_id"]); roomID > 0 {
		_ = ctx.Set("group", rt.groupInfo(roomID))
	}
	if eventName == "private.message" || eventName == "group.message" {
		_ = ctx.Set("message", map[string]any{
			"id":        toInt64(eventData["msg_id"]),
			"type":      messageTypeName(toInt64(eventData["msg_type"])),
			"msgType":   toInt64(eventData["msg_type"]),
			"text":      text,
			"imageUrls": splitImageURLs(fmt.Sprint(eventData["image_urls"])),
			"replyTo":   toInt64(eventData["reply_to"]),
			"timestamp": eventTimestamp(eventData),
		})
	}
	if memberUID := toInt64(eventData["uid"]); memberUID > 0 && eventName != "group.message" {
		_ = ctx.Set("member", rt.userInfo(memberUID))
	}
	if operatorUID := toInt64(eventData["operator_uid"]); operatorUID > 0 {
		_ = ctx.Set("operator", rt.userInfo(operatorUID))
	}
	if eventName == "group.member.mute" {
		muteUntil := toInt64(eventData["until"])
		_ = ctx.Set("muteUntil", muteUntil)
		_ = ctx.Set("muted", muteUntil > time.Now().Unix())
	}
	if eventName == "schedule" || strings.HasPrefix(eventName, "schedule.") {
		_ = ctx.Set("triggerTime", toInt64(eventData["trigger_time"]))
		_ = ctx.Set("cronExpression", fmt.Sprint(eventData["cron_expression"]))
	}

	_ = ctx.Set("reply", func(call goja.FunctionCall) goja.Value {
		return vm.ToValue(rt.ctxReply(ctx, call))
	})
	_ = ctx.Set("send", func(call goja.FunctionCall) goja.Value {
		return vm.ToValue(rt.ctxSend(ctx, call))
	})
	_ = ctx.Set("notice", func(call goja.FunctionCall) goja.Value {
		title, content := "", ""
		if len(call.Arguments) > 0 {
			title = call.Argument(0).String()
		}
		if len(call.Arguments) > 1 {
			content = call.Argument(1).String()
		}
		return vm.ToValue(rt.sendNotice(senderUID, title, content))
	})
	_ = ctx.Set("fail", func(call goja.FunctionCall) goja.Value {
		message := "操作失败"
		if len(call.Arguments) > 0 {
			message = call.Argument(0).String()
		}
		return vm.ToValue(rt.ctxReplyText(ctx, message))
	})
	_ = ctx.Set("requireGroupAdmin", func(goja.FunctionCall) goja.Value {
		if !ctx.Get("isGroup").ToBoolean() {
			return vm.ToValue(false)
		}
		group := ctx.Get("group").ToObject(vm)
		gid := group.Get("id").ToInteger()
		pms := rt.groupBotPermissions(gid)
		if isAdmin, _ := pms["isAdmin"].(bool); isAdmin {
			return vm.ToValue(true)
		}
		_ = rt.ctxReplyText(ctx, "Bot 缺少群管理员权限")
		return vm.ToValue(false)
	})

	return ctx
}

func (rt *JSRuntime) ctxReply(ctx *goja.Object, call goja.FunctionCall) map[string]any {
	text, images := rt.parseMessageArg(call.Argument(0))
	if len(images) > 0 {
		return rt.ctxSendImage(ctx, images[0])
	}
	return rt.ctxReplyText(ctx, text)
}

func (rt *JSRuntime) ctxSend(ctx *goja.Object, call goja.FunctionCall) map[string]any {
	text, images := rt.parseMessageArg(call.Argument(0))
	if len(images) > 0 {
		return rt.ctxSendImage(ctx, images[0])
	}
	if ctx.Get("isGroup").ToBoolean() {
		gid := ctx.Get("group").ToObject(rt.vm).Get("id").ToInteger()
		return rt.sendGroupMessage(gid, text, 0)
	}
	return rt.sendPrivateMessage(ctx.Get("sender").ToObject(rt.vm).Get("uid").ToInteger(), text, 0)
}

func (rt *JSRuntime) ctxReplyText(ctx *goja.Object, text string) map[string]any {
	if ctx.Get("isGroup").ToBoolean() {
		gid := ctx.Get("group").ToObject(rt.vm).Get("id").ToInteger()
		msgID := int64(0)
		if message := ctx.Get("message"); !goja.IsUndefined(message) && !goja.IsNull(message) {
			msgID = message.ToObject(rt.vm).Get("id").ToInteger()
		}
		return rt.sendGroupMessage(gid, text, msgID)
	}
	uid := ctx.Get("sender").ToObject(rt.vm).Get("uid").ToInteger()
	msgID := int64(0)
	if message := ctx.Get("message"); !goja.IsUndefined(message) && !goja.IsNull(message) {
		msgID = message.ToObject(rt.vm).Get("id").ToInteger()
	}
	return rt.sendPrivateMessage(uid, text, msgID)
}

func (rt *JSRuntime) ctxSendImage(ctx *goja.Object, imageURL string) map[string]any {
	if ctx.Get("isGroup").ToBoolean() {
		gid := ctx.Get("group").ToObject(rt.vm).Get("id").ToInteger()
		return rt.sendGroupImage(gid, imageURL)
	}
	uid := ctx.Get("sender").ToObject(rt.vm).Get("uid").ToInteger()
	return rt.sendPrivateImage(uid, imageURL)
}

func (rt *JSRuntime) parseMessageArg(value goja.Value) (string, []string) {
	if goja.IsUndefined(value) || goja.IsNull(value) {
		return "", nil
	}
	if _, ok := value.Export().(string); ok {
		return value.String(), nil
	}
	var payload map[string]any
	if err := rt.vm.ExportTo(value, &payload); err != nil || payload == nil {
		return value.String(), nil
	}
	text := strings.TrimSpace(fmt.Sprint(payload["text"]))
	images := make([]string, 0)
	if rawImages, ok := payload["images"].([]any); ok {
		for _, item := range rawImages {
			if s := strings.TrimSpace(fmt.Sprint(item)); s != "" {
				images = append(images, s)
			}
		}
	}
	return text, images
}

func (rt *JSRuntime) newCSACObject() *goja.Object {
	vm := rt.vm
	csac := vm.NewObject()

	privateObj := vm.NewObject()
	_ = privateObj.Set("sendMessage", func(uid int64, text string) any { return rt.sendPrivateMessage(uid, text, 0) })
	_ = privateObj.Set("sendImage", func(uid int64, imageURL string) any { return rt.sendPrivateImage(uid, imageURL) })
	_ = privateObj.Set("replyMessage", func(uid, msgID int64, text string) any { return rt.sendPrivateMessage(uid, text, msgID) })
	_ = privateObj.Set("recallMessage", func(uid, msgID int64) any { return rt.recallPrivateMessage(uid, msgID) })
	_ = csac.Set("private", privateObj)

	groupObj := vm.NewObject()
	_ = groupObj.Set("sendMessage", func(gid int64, text string) any { return rt.sendGroupMessage(gid, text, 0) })
	_ = groupObj.Set("sendImage", func(gid int64, imageURL string) any { return rt.sendGroupImage(gid, imageURL) })
	_ = groupObj.Set("replyMessage", func(gid, msgID int64, text string) any { return rt.sendGroupMessage(gid, text, msgID) })
	_ = groupObj.Set("recallMessage", func(gid, msgID int64) any { return rt.recallGroupMessage(gid, msgID) })
	_ = groupObj.Set("setEssence", func(gid, msgID int64) any { return rt.setGroupEssence(gid, msgID) })
	_ = groupObj.Set("unsetEssence", func(gid, msgID int64) any { return rt.unsetGroupEssence(gid, msgID) })
	_ = groupObj.Set("muteMember", func(gid, uid, seconds int64) any { return rt.muteGroupMember(gid, uid, seconds) })
	_ = groupObj.Set("unmuteMember", func(gid, uid int64) any { return rt.unmuteGroupMember(gid, uid) })
	_ = groupObj.Set("leave", func(gid int64) any { return rt.leaveGroup(gid) })
	_ = csac.Set("group", groupObj)

	userObj := vm.NewObject()
	_ = userObj.Set("get", func(uid int64) any { return rt.userInfo(uid) })
	_ = csac.Set("user", userObj)

	groupInfoObj := vm.NewObject()
	_ = groupInfoObj.Set("get", func(gid int64) any { return rt.groupInfo(gid) })
	_ = groupInfoObj.Set("memberCount", func(gid int64) any { return rt.groupMemberCount(gid) })
	_ = groupInfoObj.Set("hasMember", func(gid, uid int64) any { return rt.isGroupMember(gid, uid) })
	_ = groupInfoObj.Set("botPermissions", func(gid int64) any { return rt.groupBotPermissions(gid) })
	_ = csac.Set("groupInfo", groupInfoObj)

	noticeObj := vm.NewObject()
	_ = noticeObj.Set("send", func(uid int64, title, content string) any { return rt.sendNotice(uid, title, content) })
	_ = csac.Set("notice", noticeObj)

	httpObj := vm.NewObject()
	_ = httpObj.Set("get", func(call goja.FunctionCall) goja.Value {
		url := ""
		if len(call.Arguments) > 0 {
			url = call.Argument(0).String()
		}
		var options goja.Value
		if len(call.Arguments) > 1 {
			options = call.Argument(1)
		}
		return vm.ToValue(rt.httpRequest(http.MethodGet, url, options))
	})
	_ = httpObj.Set("post", func(call goja.FunctionCall) goja.Value {
		url := ""
		if len(call.Arguments) > 0 {
			url = call.Argument(0).String()
		}
		return vm.ToValue(rt.httpRequest(http.MethodPost, url, call.Argument(1)))
	})
	_ = csac.Set("http", httpObj)

	storageObj := vm.NewObject()
	_ = storageObj.Set("get", func(call goja.FunctionCall) goja.Value {
		key := call.Argument(0).String()
		def := call.Argument(1)
		return vm.ToValue(rt.storageGet(key, def.Export()))
	})
	_ = storageObj.Set("set", func(call goja.FunctionCall) goja.Value {
		key := call.Argument(0).String()
		return vm.ToValue(rt.storageSet(key, call.Argument(1).Export()))
	})
	_ = storageObj.Set("delete", func(key string) any { return rt.storageDelete(key) })
	_ = storageObj.Set("list", func(prefix string) any { return rt.storageList(prefix) })
	_ = storageObj.Set("increment", func(call goja.FunctionCall) goja.Value {
		key := call.Argument(0).String()
		step := int64(1)
		if len(call.Arguments) > 1 && !goja.IsUndefined(call.Argument(1)) {
			step = call.Argument(1).ToInteger()
		}
		return vm.ToValue(rt.storageIncrement(key, step))
	})
	_ = csac.Set("storage", storageObj)

	return csac
}

func (rt *JSRuntime) botInfo() map[string]any {
	bot, _ := rt.fw.fetchOne("SELECT id, uid, bot_name, can_notify, can_http FROM bot_accounts WHERE id = ?", rt.botID)
	return map[string]any{
		"id":        rt.botID,
		"uid":       rt.botUID,
		"name":      str(bot, "bot_name"),
		"canNotify": intval(bot, "can_notify") == 1,
		"canHttp":   intval(bot, "can_http") == 1,
	}
}

func (rt *JSRuntime) userInfo(uid int64) map[string]any {
	if uid <= 0 {
		return map[string]any{"success": false, "uid": uid, "message": "用户不存在"}
	}
	user, _ := rt.fw.fetchOne("SELECT id, nickname, username, avatar, platform, last_active, is_bot FROM chat_user WHERE id = ?", uid)
	if user == nil {
		return map[string]any{"success": false, "uid": uid, "message": "用户不存在"}
	}
	return map[string]any{
		"success":     true,
		"uid":         intval(user, "id"),
		"nickname":    str(user, "nickname"),
		"username":    str(user, "username"),
		"avatar":      str(user, "avatar"),
		"platform":    str(user, "platform"),
		"lastActive":  intval(user, "last_active"),
		"last_active": intval(user, "last_active"),
		"isBot":       intval(user, "is_bot") == 1,
	}
}

func (rt *JSRuntime) groupInfo(gid int64) map[string]any {
	if gid <= 0 {
		return map[string]any{"success": false, "groupId": gid, "message": "群不存在"}
	}
	room, _ := rt.fw.fetchOne("SELECT id, room_name, owner_uid, avatar, is_disband FROM chat_room WHERE id = ?", gid)
	if room == nil || intval(room, "is_disband") != 0 {
		return map[string]any{"success": false, "groupId": gid, "message": "群不存在"}
	}
	var memberCount int64
	_ = rt.fw.db.QueryRow("SELECT COUNT(*) FROM chat_group_user WHERE room_id = ?", gid).Scan(&memberCount)
	return map[string]any{
		"success":     true,
		"id":          intval(room, "id"),
		"groupId":     intval(room, "id"),
		"gid":         intval(room, "id"),
		"name":        str(room, "room_name"),
		"roomName":    str(room, "room_name"),
		"ownerUid":    intval(room, "owner_uid"),
		"avatar":      str(room, "avatar"),
		"memberCount": memberCount,
	}
}

func (rt *JSRuntime) sendGroupMessage(gid int64, content string, replyTo int64) map[string]any {
	content = strings.TrimSpace(content)
	if gid <= 0 || content == "" {
		return jsFail("ARG_ERROR", "缺少群ID或消息内容")
	}
	member, _ := rt.fw.fetchOne("SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?", gid, rt.botUID)
	if member == nil {
		return jsFail("NOT_IN_GROUP", "Bot不在该群内")
	}
	if muteUntil := intval(member, "mute_until"); muteUntil > time.Now().Unix() {
		return jsFail("BOT_MUTED", "Bot已被禁言")
	}
	user, _ := rt.fw.fetchOne("SELECT nickname FROM chat_user WHERE id = ?", rt.botUID)
	nickname := str(user, "nickname")
	if nickname == "" {
		nickname = "Bot"
	}
	var reply any
	if replyTo > 0 {
		oriMsg, _ := rt.fw.fetchOne("SELECT id FROM chat_msg WHERE id = ? AND room_id = ?", replyTo, gid)
		if oriMsg == nil {
			return jsFail("NOT_FOUND", "原消息不存在")
		}
		reply = replyTo
	}
	msgID, err := rt.fw.insertBotRow("chat_msg", map[string]any{
		"room_id":        gid,
		"uid":            rt.botUID,
		"nickname":       nickname,
		"content":        content,
		"msg_type":       1,
		"voice_duration": 0,
		"add_time":       time.Now().UTC().Format("2006-01-02 15:04:05"),
		"reply_to":       reply,
		"mention_uids":   "",
		"was_replied":    0,
	})
	if err != nil {
		return jsFail("INTERNAL_ERROR", "发送失败")
	}
	return jsOK(map[string]any{"msg_id": msgID, "messageId": msgID})
}

func (rt *JSRuntime) sendGroupImage(gid int64, imageURL string) map[string]any {
	imageURL = strings.TrimSpace(imageURL)
	if gid <= 0 || imageURL == "" {
		return jsFail("ARG_ERROR", "缺少群ID或图片URL")
	}
	member, _ := rt.fw.fetchOne("SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?", gid, rt.botUID)
	if member == nil {
		return jsFail("NOT_IN_GROUP", "Bot不在该群内")
	}
	if muteUntil := intval(member, "mute_until"); muteUntil > time.Now().Unix() {
		return jsFail("BOT_MUTED", "Bot已被禁言")
	}
	user, _ := rt.fw.fetchOne("SELECT nickname FROM chat_user WHERE id = ?", rt.botUID)
	nickname := str(user, "nickname")
	if nickname == "" {
		nickname = "Bot"
	}
	msgID, err := rt.fw.insertBotRow("chat_msg", map[string]any{
		"room_id":        gid,
		"uid":            rt.botUID,
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
		return jsFail("INTERNAL_ERROR", "发送图片失败")
	}
	return jsOK(map[string]any{"msg_id": msgID, "messageId": msgID})
}

func (rt *JSRuntime) recallGroupMessage(gid, msgID int64) map[string]any {
	if gid <= 0 || msgID <= 0 {
		return jsFail("ARG_ERROR", "缺少群ID或消息ID")
	}
	if !rt.fw.isGroupAdminOrOwner(gid, rt.botUID) {
		return jsFail("PERMISSION_DENIED", "缺少管理员权限")
	}
	msg, _ := rt.fw.fetchOne("SELECT id FROM chat_msg WHERE id = ? AND room_id = ?", msgID, gid)
	if msg == nil {
		return jsFail("NOT_FOUND", "消息不存在")
	}
	_, err := rt.fw.exec("UPDATE chat_msg SET was_replied = 2 WHERE id = ? AND room_id = ?", msgID, gid)
	if err != nil {
		return jsFail("INTERNAL_ERROR", "撤回失败")
	}
	return jsOK(nil)
}

func (rt *JSRuntime) setGroupEssence(gid, msgID int64) map[string]any {
	if gid <= 0 || msgID <= 0 {
		return jsFail("ARG_ERROR", "缺少群ID或消息ID")
	}
	if !rt.fw.isGroupAdminOrOwner(gid, rt.botUID) {
		return jsFail("PERMISSION_DENIED", "缺少管理员权限")
	}
	msg, _ := rt.fw.fetchOne("SELECT id FROM chat_msg WHERE id = ? AND room_id = ?", msgID, gid)
	if msg == nil {
		return jsFail("NOT_FOUND", "消息不存在")
	}
	exists, _ := rt.fw.fetchOne("SELECT id FROM chat_essence WHERE msg_id = ? AND room_id = ?", msgID, gid)
	if exists != nil {
		return jsFail("ALREADY_EXISTS", "该消息已是精华")
	}
	user, _ := rt.fw.fetchOne("SELECT nickname FROM chat_user WHERE id = ?", rt.botUID)
	setNick := str(user, "nickname")
	if setNick == "" {
		setNick = "Bot"
	}
	_, err := rt.fw.insertBotRow("chat_essence", map[string]any{
		"room_id":  gid,
		"msg_id":   msgID,
		"set_uid":  rt.botUID,
		"set_nick": setNick,
		"set_time": time.Now().UTC().Format("2006-01-02 15:04:05"),
	})
	if err != nil {
		return jsFail("INTERNAL_ERROR", "设置精华失败")
	}
	return jsOK(nil)
}

func (rt *JSRuntime) unsetGroupEssence(gid, msgID int64) map[string]any {
	if gid <= 0 || msgID <= 0 {
		return jsFail("ARG_ERROR", "缺少群ID或消息ID")
	}
	if !rt.fw.isGroupAdminOrOwner(gid, rt.botUID) {
		return jsFail("PERMISSION_DENIED", "缺少管理员权限")
	}
	_, err := rt.fw.exec("DELETE FROM chat_essence WHERE msg_id = ? AND room_id = ?", msgID, gid)
	if err != nil {
		return jsFail("INTERNAL_ERROR", "取消精华失败")
	}
	return jsOK(nil)
}

func (rt *JSRuntime) muteGroupMember(gid, uid, seconds int64) map[string]any {
	if gid <= 0 || uid <= 0 || seconds <= 0 {
		return jsFail("ARG_ERROR", "缺少群ID、用户ID或禁言时长")
	}
	if !rt.fw.isGroupAdminOrOwner(gid, rt.botUID) {
		return jsFail("PERMISSION_DENIED", "缺少管理员权限")
	}
	muteUntil := time.Now().Unix() + seconds
	_, err := rt.fw.exec("UPDATE chat_group_user SET mute_until = ? WHERE room_id = ? AND uid = ?", muteUntil, gid, uid)
	if err != nil {
		return jsFail("INTERNAL_ERROR", "禁言失败")
	}
	return jsOK(map[string]any{"mute_until": muteUntil, "muteUntil": muteUntil})
}

func (rt *JSRuntime) unmuteGroupMember(gid, uid int64) map[string]any {
	if gid <= 0 || uid <= 0 {
		return jsFail("ARG_ERROR", "缺少群ID或用户ID")
	}
	if !rt.fw.isGroupAdminOrOwner(gid, rt.botUID) {
		return jsFail("PERMISSION_DENIED", "缺少管理员权限")
	}
	_, err := rt.fw.exec("UPDATE chat_group_user SET mute_until = 0 WHERE room_id = ? AND uid = ?", gid, uid)
	if err != nil {
		return jsFail("INTERNAL_ERROR", "解除禁言失败")
	}
	return jsOK(nil)
}

func (rt *JSRuntime) leaveGroup(gid int64) map[string]any {
	if gid <= 0 {
		return jsFail("ARG_ERROR", "缺少群ID")
	}
	member, _ := rt.fw.fetchOne("SELECT room_id FROM chat_group_user WHERE room_id = ? AND uid = ?", gid, rt.botUID)
	if member == nil {
		return jsFail("NOT_IN_GROUP", "Bot不在该群内")
	}
	_, err := rt.fw.exec("DELETE FROM chat_group_user WHERE room_id = ? AND uid = ?", gid, rt.botUID)
	if err != nil {
		return jsFail("INTERNAL_ERROR", "退群失败")
	}
	room, _ := rt.fw.fetchOne("SELECT owner_uid FROM chat_room WHERE id = ? AND is_disband = 0", gid)
	if room != nil && intval(room, "owner_uid") == rt.botUID {
		_, _ = rt.fw.exec("UPDATE chat_room SET is_disband = 1 WHERE id = ?", gid)
		_, _ = rt.fw.exec("DELETE FROM chat_group_user WHERE room_id = ?", gid)
	}
	return jsOK(map[string]any{"message": "已退群"})
}

func (rt *JSRuntime) sendPrivateMessage(uid int64, content string, replyTo int64) map[string]any {
	content = strings.TrimSpace(content)
	if uid <= 0 || content == "" {
		return jsFail("ARG_ERROR", "缺少用户ID或消息内容")
	}
	if !rt.fw.isFriend(rt.botUID, uid) {
		return jsFail("NOT_FRIEND", "Bot与目标用户不是好友")
	}
	var reply any
	if replyTo > 0 {
		oriMsg, _ := rt.fw.fetchOne("SELECT id FROM private_msg WHERE id = ? AND ((from_uid = ? AND to_uid = ?) OR (from_uid = ? AND to_uid = ?))", replyTo, rt.botUID, uid, uid, rt.botUID)
		if oriMsg == nil {
			return jsFail("NOT_FOUND", "原消息不存在")
		}
		reply = replyTo
	}
	msgID, err := rt.fw.insertBotRow("private_msg", map[string]any{
		"from_uid":    rt.botUID,
		"to_uid":      uid,
		"content":     content,
		"type":        "private",
		"room_id":     0,
		"created_at":  time.Now().Unix(),
		"is_read":     0,
		"msg_type":    1,
		"is_recalled": 0,
		"reply_to":    reply,
	})
	if err != nil {
		return jsFail("INTERNAL_ERROR", "发送失败")
	}
	return jsOK(map[string]any{"msg_id": msgID, "messageId": msgID})
}

func (rt *JSRuntime) sendPrivateImage(uid int64, imageURL string) map[string]any {
	imageURL = strings.TrimSpace(imageURL)
	if uid <= 0 || imageURL == "" {
		return jsFail("ARG_ERROR", "缺少用户ID或图片URL")
	}
	if !rt.fw.isFriend(rt.botUID, uid) {
		return jsFail("NOT_FRIEND", "Bot与目标用户不是好友")
	}
	msgID, err := rt.fw.insertBotRow("private_msg", map[string]any{
		"from_uid":    rt.botUID,
		"to_uid":      uid,
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
		return jsFail("INTERNAL_ERROR", "发送图片失败")
	}
	return jsOK(map[string]any{"msg_id": msgID, "messageId": msgID})
}

func (rt *JSRuntime) recallPrivateMessage(uid, msgID int64) map[string]any {
	if uid <= 0 || msgID <= 0 {
		return jsFail("ARG_ERROR", "缺少用户ID或消息ID")
	}
	msg, _ := rt.fw.fetchOne("SELECT id FROM private_msg WHERE id = ? AND from_uid = ? AND to_uid = ? AND is_recalled = 0", msgID, rt.botUID, uid)
	if msg == nil {
		return jsFail("NOT_FOUND", "消息不存在或不允许操作")
	}
	_, err := rt.fw.exec("UPDATE private_msg SET is_recalled = 1 WHERE id = ?", msgID)
	if err != nil {
		return jsFail("INTERNAL_ERROR", "撤回失败")
	}
	return jsOK(nil)
}

func (rt *JSRuntime) sendNotice(uid int64, title, content string) map[string]any {
	if uid <= 0 || strings.TrimSpace(title) == "" || strings.TrimSpace(content) == "" {
		return jsFail("ARG_ERROR", "缺少用户ID、标题或内容")
	}
	bot, _ := rt.fw.fetchOne("SELECT can_notify FROM bot_accounts WHERE id = ?", rt.botID)
	if bot == nil || intval(bot, "can_notify") != 1 {
		return jsFail("NOTICE_PERMISSION_REQUIRED", "未获得通知权限")
	}
	_, err := rt.fw.insertBotRow("chat_user_notice", map[string]any{
		"uid":      uid,
		"title":    title,
		"content":  content,
		"is_read":  0,
		"add_time": time.Now().UTC().Format("2006-01-02 15:04:05"),
	})
	if err != nil {
		return jsFail("INTERNAL_ERROR", "发送通知失败")
	}
	return jsOK(nil)
}

func (rt *JSRuntime) groupMemberCount(gid int64) map[string]any {
	if gid <= 0 {
		return jsFail("ARG_ERROR", "缺少群ID")
	}
	var count int64
	_ = rt.fw.db.QueryRow("SELECT COUNT(*) FROM chat_group_user WHERE room_id = ?", gid).Scan(&count)
	return jsOK(map[string]any{"count": count})
}

func (rt *JSRuntime) isGroupMember(gid, uid int64) map[string]any {
	if gid <= 0 || uid <= 0 {
		return jsFail("ARG_ERROR", "缺少群ID或用户ID")
	}
	row, _ := rt.fw.fetchOne("SELECT room_id FROM chat_group_user WHERE room_id = ? AND uid = ? LIMIT 1", gid, uid)
	return jsOK(map[string]any{"isMember": row != nil, "is_member": row != nil})
}

func (rt *JSRuntime) groupBotPermissions(gid int64) map[string]any {
	if gid <= 0 {
		return jsFail("ARG_ERROR", "缺少群ID")
	}
	isAdmin := rt.fw.isGroupAdminOrOwner(gid, rt.botUID)
	room, _ := rt.fw.fetchOne("SELECT owner_uid FROM chat_room WHERE id = ? AND is_disband = 0", gid)
	isOwner := room != nil && intval(room, "owner_uid") == rt.botUID
	return jsOK(map[string]any{"isAdmin": isAdmin, "isOwner": isOwner, "is_admin": isAdmin, "is_owner": isOwner})
}

func (rt *JSRuntime) httpRequest(method, rawURL string, optionsValue goja.Value) map[string]any {
	bot, _ := rt.fw.fetchOne("SELECT can_http FROM bot_accounts WHERE id = ?", rt.botID)
	if bot == nil || intval(bot, "can_http") != 1 {
		return jsFail("HTTP_PERMISSION_REQUIRED", "未获得HTTP请求权限")
	}
	rawURL = strings.TrimSpace(rawURL)
	if blocked, reason := blockedHTTPURL(rawURL); blocked {
		return jsFail("ARG_ERROR", reason)
	}

	headers := map[string]string{}
	body := ""
	contentType := "application/json"
	if optionsValue != nil && !goja.IsUndefined(optionsValue) && !goja.IsNull(optionsValue) {
		var opts map[string]any
		if err := rt.vm.ExportTo(optionsValue, &opts); err == nil && opts != nil {
			if rawHeaders, ok := opts["headers"].(map[string]any); ok {
				for k, v := range rawHeaders {
					headers[k] = fmt.Sprint(v)
				}
			}
			if v, ok := opts["contentType"].(string); ok && v != "" {
				contentType = v
			}
			if v, ok := opts["content_type"].(string); ok && v != "" {
				contentType = v
			}
			if rawJSON, ok := opts["json"]; ok {
				data, _ := json.Marshal(rawJSON)
				body = string(data)
				contentType = "application/json"
			} else if rawBody, ok := opts["body"]; ok {
				body = fmt.Sprint(rawBody)
			}
		}
	}

	var bodyReader io.Reader
	if method == http.MethodPost {
		bodyReader = strings.NewReader(body)
	}
	req, err := http.NewRequest(method, rawURL, bodyReader)
	if err != nil {
		return jsFail("ARG_ERROR", "创建请求失败: "+err.Error())
	}
	if method == http.MethodPost {
		req.Header.Set("Content-Type", contentType)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	transport := safeHTTPTransport()
	defer transport.CloseIdleConnections()
	client := &http.Client{
		Timeout:   10 * time.Second,
		Transport: transport,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 10 {
				return fmt.Errorf("重定向次数过多")
			}
			if blocked, reason := blockedHTTPURL(req.URL.String()); blocked {
				return httpURLBlockedError(reason)
			}
			return nil
		},
	}
	resp, err := client.Do(req)
	if err != nil {
		var blockedErr httpURLBlockedError
		if errors.As(err, &blockedErr) {
			return jsFail("ARG_ERROR", blockedErr.Error())
		}
		return jsFail("TIMEOUT", "请求失败: "+err.Error())
	}
	defer resp.Body.Close()
	limited := io.LimitReader(resp.Body, 1<<20)
	data, err := io.ReadAll(limited)
	if err != nil {
		return jsFail("INTERNAL_ERROR", "读取响应失败")
	}
	result := jsOK(map[string]any{
		"status":       resp.StatusCode,
		"body":         string(data),
		"content_type": resp.Header.Get("Content-Type"),
		"contentType":  resp.Header.Get("Content-Type"),
	})
	var parsed any
	if err := json.Unmarshal(data, &parsed); err == nil {
		result["json"] = parsed
	}
	return result
}

func (rt *JSRuntime) storageGet(key string, defaultValue any) any {
	key = strings.TrimSpace(key)
	if key == "" {
		return defaultValue
	}
	row, _ := rt.fw.fetchOne("SELECT `value` FROM bot_storage WHERE bot_id = ? AND skey = ?", rt.botID, key)
	if row == nil {
		return defaultValue
	}
	var value any
	if err := json.Unmarshal([]byte(str(row, "value")), &value); err != nil {
		return defaultValue
	}
	return value
}

func (rt *JSRuntime) storageSet(key string, value any) map[string]any {
	key = strings.TrimSpace(key)
	if key == "" || len(key) > 128 {
		return jsFail("ARG_ERROR", "key不能为空且不能超过128字符")
	}
	data, err := json.Marshal(value)
	if err != nil {
		return jsFail("ARG_ERROR", "value必须可JSON序列化")
	}
	if len(data) > 64*1024 {
		return jsFail("ARG_ERROR", "value不能超过64KB")
	}
	_, err = rt.fw.exec("INSERT INTO bot_storage (bot_id, skey, `value`, updated_at) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`), updated_at = VALUES(updated_at)", rt.botID, key, string(data), time.Now().Unix())
	if err != nil {
		return jsFail("INTERNAL_ERROR", "保存失败")
	}
	return jsOK(nil)
}

func (rt *JSRuntime) storageDelete(key string) map[string]any {
	_, err := rt.fw.exec("DELETE FROM bot_storage WHERE bot_id = ? AND skey = ?", rt.botID, strings.TrimSpace(key))
	if err != nil {
		return jsFail("INTERNAL_ERROR", "删除失败")
	}
	return jsOK(nil)
}

func (rt *JSRuntime) storageList(prefix string) map[string]any {
	rows, err := rt.fw.fetchAll("SELECT skey FROM bot_storage WHERE bot_id = ? AND skey LIKE ? ORDER BY skey ASC LIMIT 200", rt.botID, prefix+"%")
	if err != nil {
		return jsFail("INTERNAL_ERROR", "查询失败")
	}
	keys := make([]string, 0, len(rows))
	for _, row := range rows {
		keys = append(keys, str(row, "skey"))
	}
	return jsOK(map[string]any{"keys": keys})
}

func (rt *JSRuntime) storageIncrement(key string, step int64) int64 {
	current := int64(0)
	if v := rt.storageGet(key, float64(0)); v != nil {
		current = toInt64(v)
	}
	next := current + step
	_ = rt.storageSet(key, next)
	return next
}

func (rt *JSRuntime) writeLog(level, content string) {
	if strings.TrimSpace(content) == "" {
		return
	}
	rt.logBuf = append(rt.logBuf, level+": "+content)
	if len(rt.logBuf) > 200 {
		rt.logBuf = rt.logBuf[len(rt.logBuf)-200:]
	}
	_, _ = rt.fw.insertBotRow("bot_logs", map[string]any{
		"bot_id":     rt.botID,
		"level":      level,
		"content":    content,
		"created_at": time.Now().Unix(),
	})
	log.Printf("[BotJS:%d] %s: %s", rt.botID, strings.ToUpper(level), content)
}

func (rt *JSRuntime) formatArgs(args []goja.Value) string {
	parts := make([]string, 0, len(args))
	for _, arg := range args {
		if arg == nil || goja.IsUndefined(arg) || goja.IsNull(arg) {
			parts = append(parts, "null")
			continue
		}
		if exported := arg.Export(); exported != nil {
			if s, ok := exported.(string); ok {
				parts = append(parts, s)
				continue
			}
			if data, err := json.Marshal(exported); err == nil {
				parts = append(parts, string(data))
				continue
			}
		}
		parts = append(parts, arg.String())
	}
	return strings.Join(parts, " ")
}

func jsOK(extra map[string]any) map[string]any {
	result := map[string]any{"success": true}
	for k, v := range extra {
		result[k] = v
	}
	return result
}

func jsFail(code, message string) map[string]any {
	return map[string]any{"success": false, "code": code, "error": code, "message": message}
}

func eventTimestamp(eventData map[string]any) int64 {
	if ts := toInt64(eventData["timestamp"]); ts > 0 {
		return ts
	}
	if ts := toInt64(eventData["trigger_time"]); ts > 0 {
		return ts
	}
	return time.Now().Unix()
}

func eventSenderUID(eventName string, eventData map[string]any) int64 {
	if eventName == "private.message" {
		return toInt64(eventData["from_uid"])
	}
	if uid := toInt64(eventData["uid"]); uid > 0 {
		return uid
	}
	return toInt64(eventData["operator_uid"])
}

func messageTypeName(msgType int64) string {
	switch msgType {
	case 2:
		return "image"
	case 3:
		return "voice"
	default:
		return "text"
	}
}

func splitImageURLs(raw string) []string {
	raw = strings.TrimSpace(raw)
	if raw == "" || raw == "<nil>" {
		return []string{}
	}
	parts := strings.FieldsFunc(raw, func(r rune) bool { return r == ',' || r == ';' || r == '\n' })
	urls := make([]string, 0, len(parts))
	for _, part := range parts {
		if s := strings.TrimSpace(part); s != "" {
			urls = append(urls, s)
		}
	}
	return urls
}

func safeHTTPTransport() *http.Transport {
	dialer := &net.Dialer{Timeout: 10 * time.Second, KeepAlive: 30 * time.Second}
	return &http.Transport{
		Proxy: nil,
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			host, port, err := net.SplitHostPort(address)
			if err != nil {
				return nil, err
			}
			ips, err := resolvePublicHTTPHost(ctx, host)
			if err != nil {
				return nil, err
			}
			var lastErr error
			for _, ip := range ips {
				conn, err := dialer.DialContext(ctx, network, net.JoinHostPort(ip.String(), port))
				if err == nil {
					return conn, nil
				}
				lastErr = err
			}
			if lastErr != nil {
				return nil, lastErr
			}
			return nil, httpURLBlockedError("解析目标地址失败")
		},
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 10 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
	}
}

type httpURLBlockedError string

func (err httpURLBlockedError) Error() string {
	return string(err)
}

func blockedHTTPURL(raw string) (bool, string) {
	u, err := neturl.Parse(strings.TrimSpace(raw))
	if err != nil || u.Scheme == "" || u.Hostname() == "" {
		return true, "URL无效"
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return true, "只允许http或https请求"
	}
	if strings.Contains(u.Hostname(), "%") {
		return true, "URL无效"
	}
	if ip := net.ParseIP(u.Hostname()); ip != nil && blockedHTTPIP(ip) {
		return true, "不允许请求内网或本机地址"
	}
	return false, ""
}

func resolvePublicHTTPHost(ctx context.Context, host string) ([]net.IP, error) {
	host = strings.TrimSpace(host)
	if host == "" || strings.Contains(host, "%") {
		return nil, httpURLBlockedError("URL无效")
	}
	if ip := net.ParseIP(host); ip != nil {
		if blockedHTTPIP(ip) {
			return nil, httpURLBlockedError("不允许请求内网或本机地址")
		}
		return []net.IP{ip}, nil
	}
	addrs, err := net.DefaultResolver.LookupIPAddr(ctx, host)
	if err != nil {
		return nil, httpURLBlockedError("解析目标地址失败")
	}
	ips := make([]net.IP, 0, len(addrs))
	for _, addr := range addrs {
		if blockedHTTPIP(addr.IP) {
			return nil, httpURLBlockedError("不允许请求内网或本机地址")
		}
		ips = append(ips, addr.IP)
	}
	if len(ips) == 0 {
		return nil, httpURLBlockedError("解析目标地址失败")
	}
	return ips, nil
}

func blockedHTTPIP(ip net.IP) bool {
	if ip == nil {
		return true
	}
	return ip.IsLoopback() ||
		ip.IsPrivate() ||
		ip.IsLinkLocalUnicast() ||
		ip.IsLinkLocalMulticast() ||
		ip.IsUnspecified() ||
		ip.IsMulticast() ||
		isCarrierNATIP(ip)
}

func isCarrierNATIP(ip net.IP) bool {
	if v4 := ip.To4(); v4 != nil {
		return v4[0] == 100 && v4[1]&0xc0 == 64
	}
	return false
}
