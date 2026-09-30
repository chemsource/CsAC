// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC ServerBot Framework Version 1.0.0.260614-r1
// JavaScript script dispatcher.

package main

import (
	"fmt"
	"log"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ScriptManager manages JavaScript runtimes for all enabled Bot scripts.
type ScriptManager struct {
	fw       *BotFramework
	runtimes map[int64]*JSRuntime // botID -> runtime
	mu       sync.RWMutex

	cronEntries []*CronEntry
	cronMu      sync.RWMutex
	cronStop    chan struct{}
}

// CronEntry is a registered JavaScript bot.schedule task.
type CronEntry struct {
	BotID      int64
	Expression string
	EventName  string
	Spec       *CronSpec
}

// CronSpec is a parsed 5-field cron expression: minute hour day month week.
type CronSpec struct {
	Minute []int // 0-59
	Hour   []int // 0-23
	Day    []int // 1-31
	Month  []int // 1-12
	Week   []int // 0-6 (0=Sunday)
}

// NewScriptManager creates the JavaScript script manager.
func NewScriptManager(fw *BotFramework) *ScriptManager {
	sm := &ScriptManager{
		fw:          fw,
		runtimes:    make(map[int64]*JSRuntime),
		cronEntries: make([]*CronEntry, 0),
		cronStop:    make(chan struct{}),
	}
	sm.loadAllScripts()
	go sm.cronLoop()
	return sm
}

// loadAllScripts loads all enabled JavaScript scripts, grouped by Bot.
func (sm *ScriptManager) loadAllScripts() {
	scripts, err := sm.fw.fetchAll(
		"SELECT bs.id, bs.bot_id, bs.script_content, ba.uid FROM bot_scripts bs JOIN bot_accounts ba ON bs.bot_id = ba.id WHERE bs.enabled = 1 AND ba.status = 1 ORDER BY bs.bot_id ASC, bs.id ASC",
	)
	if err != nil {
		log.Printf("ScriptManager: 加载JS脚本失败: %v", err)
		return
	}

	type bundle struct {
		botUID  int64
		content strings.Builder
	}
	bundles := map[int64]*bundle{}
	for _, s := range scripts {
		botID := intval(s, "bot_id")
		botUID := intval(s, "uid")
		content := str(s, "script_content")
		if botID <= 0 || botUID <= 0 || strings.TrimSpace(content) == "" {
			continue
		}
		b := bundles[botID]
		if b == nil {
			b = &bundle{botUID: botUID}
			bundles[botID] = b
		}
		b.content.WriteString("\n// ---- script ")
		b.content.WriteString(str(s, "id"))
		b.content.WriteString(" ----\n")
		b.content.WriteString(content)
		b.content.WriteString("\n")
	}

	loaded := make(map[int64]*JSRuntime, len(bundles))
	sm.cronMu.Lock()
	sm.cronEntries = nil
	sm.cronMu.Unlock()
	for botID, b := range bundles {
		rt := NewJSRuntime(sm.fw, botID, b.botUID)
		if err := rt.Compile(b.content.String()); err != nil {
			log.Printf("ScriptManager: Bot[%d] JS脚本编译失败: %v", botID, err)
			continue
		}
		for _, schedule := range rt.schedules {
			if err := sm.RegisterCron(botID, schedule.Expression, schedule.EventName); err != nil {
				log.Printf("ScriptManager: Bot[%d] JS定时任务注册失败: %v", botID, err)
			}
		}
		loaded[botID] = rt
		log.Printf("ScriptManager: Bot[%d] JS脚本加载成功", botID)
	}

	sm.mu.Lock()
	sm.runtimes = loaded
	sm.mu.Unlock()
	log.Printf("ScriptManager: 共加载 %d 个JS脚本运行时", len(loaded))
}

// ReloadBot reloads enabled JavaScript scripts for a Bot.
func (sm *ScriptManager) ReloadBot(botID int64) {
	scripts, err := sm.fw.fetchAll(
		"SELECT bs.id, bs.script_content, ba.uid FROM bot_scripts bs JOIN bot_accounts ba ON bs.bot_id = ba.id WHERE bs.bot_id = ? AND bs.enabled = 1 AND ba.status = 1 ORDER BY bs.id ASC",
		botID,
	)
	if err != nil || len(scripts) == 0 {
		sm.UnloadBot(botID)
		return
	}

	botUID := intval(scripts[0], "uid")
	var allContent strings.Builder
	for _, s := range scripts {
		content := str(s, "script_content")
		if strings.TrimSpace(content) == "" {
			continue
		}
		allContent.WriteString("\n// ---- script ")
		allContent.WriteString(str(s, "id"))
		allContent.WriteString(" ----\n")
		allContent.WriteString(content)
		allContent.WriteString("\n")
	}
	if strings.TrimSpace(allContent.String()) == "" {
		sm.UnloadBot(botID)
		return
	}

	rt := NewJSRuntime(sm.fw, botID, botUID)
	if err := rt.Compile(allContent.String()); err != nil {
		log.Printf("ScriptManager: Bot[%d] JS脚本重载失败: %v", botID, err)
		return
	}
	sm.RemoveBotCrons(botID)
	for _, schedule := range rt.schedules {
		if err := sm.RegisterCron(botID, schedule.Expression, schedule.EventName); err != nil {
			log.Printf("ScriptManager: Bot[%d] JS定时任务注册失败: %v", botID, err)
		}
	}

	sm.mu.Lock()
	sm.runtimes[botID] = rt
	sm.mu.Unlock()
	log.Printf("ScriptManager: Bot[%d] JS脚本重载成功", botID)
}

// UnloadBot unloads a Bot runtime and removes its cron tasks.
func (sm *ScriptManager) UnloadBot(botID int64) {
	sm.mu.Lock()
	delete(sm.runtimes, botID)
	sm.mu.Unlock()
	sm.RemoveBotCrons(botID)
}

func (sm *ScriptManager) runtime(botID int64) *JSRuntime {
	sm.mu.RLock()
	defer sm.mu.RUnlock()
	return sm.runtimes[botID]
}

// DispatchGroupMsg dispatches a group message event to JavaScript runtimes.
func (sm *ScriptManager) DispatchGroupMsg(roomID, senderUID, msgID int64, content, nickname string, msgType, replyTo int64, imageUrls string, timestamp int64) {
	eventData := map[string]any{
		"room_id":    roomID,
		"uid":        senderUID,
		"msg_id":     msgID,
		"content":    content,
		"nickname":   nickname,
		"msg_type":   msgType,
		"reply_to":   replyTo,
		"image_urls": imageUrls,
		"timestamp":  timestamp,
	}

	sm.mu.RLock()
	runtimes := make(map[int64]*JSRuntime, len(sm.runtimes))
	for botID, rt := range sm.runtimes {
		runtimes[botID] = rt
	}
	sm.mu.RUnlock()

	for botID, rt := range runtimes {
		if rt.botUID == senderUID {
			continue
		}
		inGroup, _ := sm.fw.fetchOne("SELECT room_id FROM chat_group_user WHERE room_id = ? AND uid = ? LIMIT 1", roomID, rt.botUID)
		if inGroup == nil {
			continue
		}
		go sm.safeDispatch(botID, rt, "group.message", eventData)
	}
}

// DispatchPrivateMsg dispatches a private message event to the recipient Bot runtime.
func (sm *ScriptManager) DispatchPrivateMsg(fromUID, toUID, msgID int64, content string, msgType, replyTo int64, imageUrls string, timestamp int64) {
	eventData := map[string]any{
		"from_uid":   fromUID,
		"to_uid":     toUID,
		"msg_id":     msgID,
		"content":    content,
		"msg_type":   msgType,
		"reply_to":   replyTo,
		"image_urls": imageUrls,
		"timestamp":  timestamp,
	}

	sm.mu.RLock()
	runtimes := make(map[int64]*JSRuntime, len(sm.runtimes))
	for botID, rt := range sm.runtimes {
		runtimes[botID] = rt
	}
	sm.mu.RUnlock()

	for botID, rt := range runtimes {
		if rt.botUID != toUID {
			continue
		}
		if !sm.isFriend(fromUID, rt.botUID) {
			log.Printf("ScriptManager: Bot[%d] UID[%d] 与发送者 UID[%d] 非好友，跳过私聊事件", botID, rt.botUID, fromUID)
			continue
		}
		go sm.safeDispatch(botID, rt, "private.message", eventData)
	}
}

func (sm *ScriptManager) isFriend(uid1, uid2 int64) bool {
	a, b := uid1, uid2
	if a > b {
		a, b = b, a
	}
	row, _ := sm.fw.fetchOne("SELECT status FROM friend_relation WHERE uid1 = ? AND uid2 = ? AND status = 1 LIMIT 1", a, b)
	return row != nil
}

func (sm *ScriptManager) DispatchGroupMemberJoin(roomID, uid int64) {
	sm.dispatchGroupMemberEvent("group.member.join", roomID, uid, 0, 0)
}

func (sm *ScriptManager) DispatchGroupMemberLeave(roomID, uid int64) {
	sm.dispatchGroupMemberEvent("group.member.leave", roomID, uid, 0, 0)
}

func (sm *ScriptManager) DispatchGroupMemberMute(roomID, uid, operatorUID, until int64) {
	sm.dispatchGroupMemberEvent("group.member.mute", roomID, uid, operatorUID, until)
}

func (sm *ScriptManager) DispatchGroupDisband(roomID, operatorUID int64) {
	eventData := map[string]any{
		"room_id":      roomID,
		"operator_uid": operatorUID,
	}
	sm.dispatchGroupEvent("group.disband", roomID, 0, eventData)
}

func (sm *ScriptManager) dispatchGroupMemberEvent(eventName string, roomID, uid, operatorUID, until int64) {
	eventData := map[string]any{
		"room_id": roomID,
		"uid":     uid,
	}
	if operatorUID > 0 {
		eventData["operator_uid"] = operatorUID
	}
	if until > 0 || eventName == "group.member.mute" {
		eventData["until"] = until
	}
	sm.dispatchGroupEvent(eventName, roomID, uid, eventData)
}

func (sm *ScriptManager) dispatchGroupEvent(eventName string, roomID, skipUID int64, eventData map[string]any) {
	sm.mu.RLock()
	runtimes := make(map[int64]*JSRuntime, len(sm.runtimes))
	for botID, rt := range sm.runtimes {
		runtimes[botID] = rt
	}
	sm.mu.RUnlock()

	for botID, rt := range runtimes {
		if skipUID > 0 && rt.botUID == skipUID {
			continue
		}
		inGroup, _ := sm.fw.fetchOne("SELECT room_id FROM chat_group_user WHERE room_id = ? AND uid = ? LIMIT 1", roomID, rt.botUID)
		if inGroup == nil {
			continue
		}
		go sm.safeDispatch(botID, rt, eventName, eventData)
	}
}

func (sm *ScriptManager) safeDispatch(botID int64, rt *JSRuntime, eventName string, eventData map[string]any) {
	defer func() {
		if rec := recover(); rec != nil {
			log.Printf("ScriptManager: Bot[%d] JS脚本执行panic: %v", botID, rec)
		}
	}()
	if err := rt.DispatchEvent(eventName, eventData); err != nil {
		log.Printf("ScriptManager: Bot[%d] JS事件[%s]执行失败: %v", botID, eventName, err)
	}
}

// RegisterCron registers a JavaScript bot.schedule task.
func (sm *ScriptManager) RegisterCron(botID int64, expression, eventName string) error {
	spec, err := parseCronExpression(expression)
	if err != nil {
		return err
	}
	sm.cronMu.Lock()
	defer sm.cronMu.Unlock()
	for _, entry := range sm.cronEntries {
		if entry.BotID == botID && entry.Expression == expression && entry.EventName == eventName {
			entry.Spec = spec
			return nil
		}
	}
	sm.cronEntries = append(sm.cronEntries, &CronEntry{BotID: botID, Expression: expression, EventName: eventName, Spec: spec})
	log.Printf("ScriptManager: Bot[%d] 注册JS定时任务: %s -> %s", botID, expression, eventName)
	return nil
}

func (sm *ScriptManager) RemoveBotCrons(botID int64) {
	sm.cronMu.Lock()
	defer sm.cronMu.Unlock()
	filtered := make([]*CronEntry, 0, len(sm.cronEntries))
	for _, entry := range sm.cronEntries {
		if entry.BotID != botID {
			filtered = append(filtered, entry)
		}
	}
	sm.cronEntries = filtered
}

func (sm *ScriptManager) cronLoop() {
	now := time.Now()
	next := now.Truncate(time.Minute).Add(time.Minute)
	time.Sleep(next.Sub(now))

	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	sm.checkCronTriggers(next)

	for {
		select {
		case <-sm.cronStop:
			return
		case t := <-ticker.C:
			sm.checkCronTriggers(t)
		}
	}
}

func (sm *ScriptManager) checkCronTriggers(t time.Time) {
	sm.cronMu.RLock()
	entries := make([]*CronEntry, len(sm.cronEntries))
	copy(entries, sm.cronEntries)
	sm.cronMu.RUnlock()

	for _, entry := range entries {
		if !matchesCronSpec(entry.Spec, t) {
			continue
		}
		rt := sm.runtime(entry.BotID)
		if rt == nil {
			continue
		}
		eventData := map[string]any{
			"cron_expression": entry.Expression,
			"trigger_time":    t.Unix(),
		}
		go sm.safeDispatch(entry.BotID, rt, entry.EventName, eventData)
	}
}

func matchesCronSpec(spec *CronSpec, t time.Time) bool {
	return containsInt(spec.Minute, t.Minute()) &&
		containsInt(spec.Hour, t.Hour()) &&
		containsInt(spec.Day, t.Day()) &&
		containsInt(spec.Month, int(t.Month())) &&
		containsInt(spec.Week, int(t.Weekday()))
}

func containsInt(slice []int, val int) bool {
	for _, v := range slice {
		if v == val {
			return true
		}
	}
	return false
}

// parseCronExpression parses 5-field cron expressions: minute hour day month week.
func parseCronExpression(expr string) (*CronSpec, error) {
	fields := strings.Fields(expr)
	if len(fields) != 5 {
		return nil, fmt.Errorf("cron表达式需要5个字段，得到%d个: %s", len(fields), expr)
	}

	minute, err := parseCronField(fields[0], 0, 59)
	if err != nil {
		return nil, fmt.Errorf("分钟字段错误: %w", err)
	}
	hour, err := parseCronField(fields[1], 0, 23)
	if err != nil {
		return nil, fmt.Errorf("小时字段错误: %w", err)
	}
	day, err := parseCronField(fields[2], 1, 31)
	if err != nil {
		return nil, fmt.Errorf("日期字段错误: %w", err)
	}
	month, err := parseCronField(fields[3], 1, 12)
	if err != nil {
		return nil, fmt.Errorf("月份字段错误: %w", err)
	}
	week, err := parseCronField(fields[4], 0, 6)
	if err != nil {
		return nil, fmt.Errorf("星期字段错误: %w", err)
	}

	return &CronSpec{Minute: minute, Hour: hour, Day: day, Month: month, Week: week}, nil
}

func parseCronField(field string, min, max int) ([]int, error) {
	result := make(map[int]bool)
	parts := strings.Split(field, ",")
	for _, part := range parts {
		step := 1
		if idx := strings.Index(part, "/"); idx >= 0 {
			stepStr := part[idx+1:]
			parsedStep, err := strconv.Atoi(stepStr)
			if err != nil || parsedStep <= 0 {
				return nil, fmt.Errorf("无效步长: %s", stepStr)
			}
			step = parsedStep
			part = part[:idx]
		}

		var rangeMin, rangeMax int
		switch {
		case part == "*":
			rangeMin, rangeMax = min, max
		case strings.Contains(part, "-"):
			idx := strings.Index(part, "-")
			var err error
			rangeMin, err = strconv.Atoi(part[:idx])
			if err != nil {
				return nil, fmt.Errorf("无效范围: %s", part)
			}
			rangeMax, err = strconv.Atoi(part[idx+1:])
			if err != nil {
				return nil, fmt.Errorf("无效范围: %s", part)
			}
		default:
			val, err := strconv.Atoi(part)
			if err != nil {
				return nil, fmt.Errorf("无效值: %s", part)
			}
			rangeMin, rangeMax = val, val
		}

		for i := rangeMin; i <= rangeMax; i += step {
			if i >= min && i <= max {
				result[i] = true
			}
		}
	}
	values := make([]int, 0, len(result))
	for v := range result {
		values = append(values, v)
	}
	return values, nil
}
