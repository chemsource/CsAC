// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC ServerBot Framework Version 1.0.0.260614-r1
// 脚本引擎 - 执行器 & 内置方法

package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ScriptValue 脚本运行时值
type ScriptValue struct {
	Type    string // "null", "number", "string", "bool", "map", "array"
	NumVal  int64
	StrVal  string
	BoolVal bool
	MapVal  map[string]*ScriptValue
	ArrVal  []*ScriptValue
}

var (
	svNull  = &ScriptValue{Type: "null"}
	svTrue  = &ScriptValue{Type: "bool", BoolVal: true}
	svFalse = &ScriptValue{Type: "bool", BoolVal: false}
)

// 控制流信号
type flowSignal int

const (
	flowNone flowSignal = iota
	flowBreak
	flowContinue
	flowReturn
)

func newNumVal(n int64) *ScriptValue  { return &ScriptValue{Type: "number", NumVal: n} }
func newStrVal(s string) *ScriptValue { return &ScriptValue{Type: "string", StrVal: s} }
func newBoolVal(b bool) *ScriptValue {
	if b {
		return svTrue
	}
	return svFalse
}
func newMapVal(m map[string]*ScriptValue) *ScriptValue {
	return &ScriptValue{Type: "map", MapVal: m}
}
func newArrVal(items []*ScriptValue) *ScriptValue {
	return &ScriptValue{Type: "array", ArrVal: items}
}

func (sv *ScriptValue) String() string {
	switch sv.Type {
	case "null":
		return "null"
	case "number":
		return fmt.Sprintf("%d", sv.NumVal)
	case "string":
		return sv.StrVal
	case "bool":
		return fmt.Sprintf("%t", sv.BoolVal)
	case "map":
		return fmt.Sprintf("%v", sv.MapVal)
	case "array":
		return fmt.Sprintf("%v", sv.ArrVal)
	default:
		return "undefined"
	}
}

func (sv *ScriptValue) IsTruthy() bool {
	switch sv.Type {
	case "null":
		return false
	case "number":
		return sv.NumVal != 0
	case "string":
		return sv.StrVal != ""
	case "bool":
		return sv.BoolVal
	case "map":
		return sv.MapVal != nil
	case "array":
		return len(sv.ArrVal) > 0
	default:
		return false
	}
}

func (sv *ScriptValue) ToInt64() int64 {
	switch sv.Type {
	case "number":
		return sv.NumVal
	case "string":
		n, _ := strconv.ParseInt(strings.TrimSpace(sv.StrVal), 10, 64)
		return n
	case "bool":
		if sv.BoolVal {
			return 1
		}
		return 0
	default:
		return 0
	}
}

// ScriptRuntime 脚本运行时
type ScriptRuntime struct {
	fw        *BotFramework
	botID     int64
	botUID    int64
	vars      map[string]*ScriptValue
	handlers  map[string]*EventHandler // 事件类型 -> 处理器
	logBuf    []string
	retVal    *ScriptValue // return 值暂存
	stepCount int64        // 执行步数计数（超时控制）
	// 事件上下文：在事件回调执行期间可用
	currentEvent map[string]*ScriptValue
	// 互斥锁：确保同一Bot的事件处理器串行执行，避免并发状态竞争
	execMu sync.Mutex
}

const maxSteps int64 = 100000 // 单次事件回调最大执行步数

// EventHandler 事件处理器
type EventHandler struct {
	Params []string
	Body   *Node
}

// NewScriptRuntime 创建脚本运行时
func NewScriptRuntime(fw *BotFramework, botID, botUID int64) *ScriptRuntime {
	return &ScriptRuntime{
		fw:       fw,
		botID:    botID,
		botUID:   botUID,
		vars:     make(map[string]*ScriptValue),
		handlers: make(map[string]*EventHandler),
		logBuf:   make([]string, 0),
	}
}

// Compile 编译脚本，注册事件处理器
func (rt *ScriptRuntime) Compile(script string) error {
	lexer := NewLexer(script)
	tokens := lexer.Tokenize()
	parser := NewParser(tokens)
	ast, errors := parser.Parse()
	if len(errors) > 0 {
		return fmt.Errorf("脚本编译错误: %s", strings.Join(errors, "; "))
	}

	// 遍历AST，注册事件处理器
	for _, child := range ast.Children {
		if child.Kind == NodeOnEvent {
			rt.registerEventHandler(child)
		}
	}
	return nil
}

func (rt *ScriptRuntime) registerEventHandler(node *Node) {
	if len(node.Children) == 0 {
		return
	}
	// 最后一个child是block，前面的是参数名
	blockIdx := len(node.Children) - 1
	params := make([]string, 0, blockIdx)
	for i := 0; i < blockIdx; i++ {
		params = append(params, node.Children[i].Token.Literal)
	}
	body := node.Children[blockIdx]
	rt.handlers[node.EventType] = &EventHandler{
		Params: params,
		Body:   body,
	}
}

// DispatchEvent 分发事件到对应的处理器
func (rt *ScriptRuntime) DispatchEvent(eventType string, eventData map[string]any) {
	handler, ok := rt.handlers[eventType]
	if !ok {
		return
	}

	// 加锁，确保同一Bot的事件处理器串行执行
	rt.execMu.Lock()
	defer rt.execMu.Unlock()

	// 清空变量，设置事件参数
	rt.vars = make(map[string]*ScriptValue)
	rt.stepCount = 0
	rt.logBuf = make([]string, 0)
	for i, param := range handler.Params {
		if i < len(handler.Params) {
			rt.vars[param] = mapToScriptValue(eventData)
		}
	}
	// 特殊处理：第一个参数通常是event对象
	if len(handler.Params) > 0 {
		rt.vars[handler.Params[0]] = mapToScriptValue(eventData)
	}

	// 设置事件上下文（供 getMsgId() 等方法访问）
	rt.currentEvent = make(map[string]*ScriptValue)
	for k, v := range eventData {
		rt.currentEvent[k] = anyToScriptValue(v)
	}

	// 执行处理器body
	rt.execBlock(handler.Body)

	// 清除事件上下文
	rt.currentEvent = nil
}

func mapToScriptValue(m map[string]any) *ScriptValue {
	result := make(map[string]*ScriptValue)
	for k, v := range m {
		result[k] = anyToScriptValue(v)
	}
	return newMapVal(result)
}

func anyToScriptValue(v any) *ScriptValue {
	if v == nil {
		return svNull
	}
	switch val := v.(type) {
	case int:
		return newNumVal(int64(val))
	case int64:
		return newNumVal(val)
	case float64:
		return newNumVal(int64(val))
	case string:
		return newStrVal(val)
	case bool:
		return newBoolVal(val)
	case map[string]any:
		return mapToScriptValue(val)
	case []any:
		items := make([]*ScriptValue, len(val))
		for i, item := range val {
			items[i] = anyToScriptValue(item)
		}
		return newArrVal(items)
	default:
		return newStrVal(fmt.Sprintf("%v", v))
	}
}

// ===== 执行器 =====

func (rt *ScriptRuntime) execBlock(node *Node) flowSignal {
	if node == nil || node.Kind != NodeBlock {
		return flowNone
	}
	for _, child := range node.Children {
		sig := rt.execNode(child)
		if sig != flowNone {
			return sig
		}
	}
	return flowNone
}

func (rt *ScriptRuntime) execNode(node *Node) flowSignal {
	if node == nil {
		return flowNone
	}
	rt.stepCount++
	if rt.stepCount > maxSteps {
		rt.logBuf = append(rt.logBuf, "ERROR: 脚本执行超时（超过最大步数限制）")
		return flowReturn
	}

	switch node.Kind {
	case NodeBlock:
		return rt.execBlock(node)

	case NodeAssign:
		name := node.Children[0].Token.Literal
		val := rt.evalExpr(node.Children[1])
		rt.vars[name] = val
		return flowNone

	case NodeIf:
		cond := rt.evalExpr(node.Children[0])
		if cond.IsTruthy() {
			return rt.execBlock(node.Children[1])
		} else if node.ElseBlock != nil {
			return rt.execBlock(node.ElseBlock)
		}
		return flowNone

	case NodeReturn:
		if len(node.Children) > 0 {
			rt.retVal = rt.evalExpr(node.Children[0])
		} else {
			rt.retVal = svNull
		}
		return flowReturn

	case NodeFor:
		// init
		rt.execNode(node.Children[0])
		for {
			// condition
			cond := rt.evalExpr(node.Children[1])
			if !cond.IsTruthy() {
				break
			}
			// body
			sig := rt.execBlock(node.Children[3])
			if sig == flowBreak {
				break
			}
			if sig == flowReturn {
				return flowReturn
			}
			// step (continue also executes step)
			rt.execNode(node.Children[2])
		}
		return flowNone

	case NodeWhile:
		for {
			cond := rt.evalExpr(node.Children[0])
			if !cond.IsTruthy() {
				break
			}
			sig := rt.execBlock(node.Children[1])
			if sig == flowBreak {
				break
			}
			if sig == flowReturn {
				return flowReturn
			}
		}
		return flowNone

	case NodeBreak:
		return flowBreak

	case NodeContinue:
		return flowContinue

	case NodeCall:
		rt.evalCall(node)
		return flowNone

	default:
		// 表达式语句
		rt.evalExpr(node)
		return flowNone
	}
}

func (rt *ScriptRuntime) evalExpr(node *Node) *ScriptValue {
	switch node.Kind {
	case NodeNumberLit:
		n, _ := strconv.ParseInt(node.Value, 10, 64)
		return newNumVal(n)

	case NodeStringLit:
		return newStrVal(node.Value)

	case NodeBoolLit:
		return newBoolVal(node.Value == "true")

	case NodeNullLit:
		return svNull

	case NodeIdentifier:
		if val, ok := rt.vars[node.Token.Literal]; ok {
			return val
		}
		return svNull

	case NodeDotAccess:
		obj := rt.evalExpr(node.Children[0])
		if obj.Type == "map" && obj.MapVal != nil {
			if val, ok := obj.MapVal[node.Token.Literal]; ok {
				return val
			}
		}
		return svNull

	case NodeArrayLit:
		items := make([]*ScriptValue, 0, len(node.Children))
		for _, child := range node.Children {
			items = append(items, rt.evalExpr(child))
		}
		return newArrVal(items)

	case NodeIndexAccess:
		obj := rt.evalExpr(node.Children[0])
		idx := rt.evalExpr(node.Children[1])
		if obj.Type == "array" && obj.ArrVal != nil {
			i := idx.ToInt64()
			if i >= 0 && i < int64(len(obj.ArrVal)) {
				return obj.ArrVal[i]
			}
		}
		if obj.Type == "map" && obj.MapVal != nil {
			key := idx.String()
			if val, ok := obj.MapVal[key]; ok {
				return val
			}
		}
		return svNull

	case NodeBinary:
		return rt.evalBinary(node)

	case NodeUnary:
		operand := rt.evalExpr(node.Children[0])
		if node.Op == "!" {
			return newBoolVal(!operand.IsTruthy())
		}
		if node.Op == "-" {
			return newNumVal(-operand.ToInt64())
		}
		return svNull

	case NodeCall:
		return rt.evalCall(node)

	default:
		return svNull
	}
}

func (rt *ScriptRuntime) evalBinary(node *Node) *ScriptValue {
	// 短路求值：&& 和 || 不预先计算右侧
	switch node.Op {
	case "&&":
		left := rt.evalExpr(node.Children[0])
		if !left.IsTruthy() {
			return svFalse
		}
		right := rt.evalExpr(node.Children[1])
		return newBoolVal(right.IsTruthy())
	case "||":
		left := rt.evalExpr(node.Children[0])
		if left.IsTruthy() {
			return svTrue
		}
		right := rt.evalExpr(node.Children[1])
		return newBoolVal(right.IsTruthy())
	}

	left := rt.evalExpr(node.Children[0])
	right := rt.evalExpr(node.Children[1])

	switch node.Op {
	case "==":
		return newBoolVal(rt.valuesEqual(left, right))
	case "!=":
		return newBoolVal(!rt.valuesEqual(left, right))
	case "<":
		return newBoolVal(left.ToInt64() < right.ToInt64())
	case ">":
		return newBoolVal(left.ToInt64() > right.ToInt64())
	case "<=":
		return newBoolVal(left.ToInt64() <= right.ToInt64())
	case ">=":
		return newBoolVal(left.ToInt64() >= right.ToInt64())
	case "+":
		if left.Type == "string" || right.Type == "string" {
			return newStrVal(left.String() + right.String())
		}
		return newNumVal(left.ToInt64() + right.ToInt64())
	case "-":
		return newNumVal(left.ToInt64() - right.ToInt64())
	case "*":
		return newNumVal(left.ToInt64() * right.ToInt64())
	case "/":
		r := right.ToInt64()
		if r == 0 {
			return newNumVal(0)
		}
		return newNumVal(left.ToInt64() / r)
	case "%":
		r := right.ToInt64()
		if r == 0 {
			return newNumVal(0)
		}
		return newNumVal(left.ToInt64() % r)
	default:
		return svNull
	}
}

func (rt *ScriptRuntime) valuesEqual(a, b *ScriptValue) bool {
	if a.Type != b.Type {
		// 尝试数字比较
		if a.Type == "number" || b.Type == "number" {
			return a.ToInt64() == b.ToInt64()
		}
		return false
	}
	switch a.Type {
	case "null":
		return true
	case "number":
		return a.NumVal == b.NumVal
	case "string":
		return a.StrVal == b.StrVal
	case "bool":
		return a.BoolVal == b.BoolVal
	default:
		return false
	}
}

// ===== 内置方法调用 =====

func (rt *ScriptRuntime) evalCall(node *Node) *ScriptValue {
	name := node.Token.Literal
	args := make([]*ScriptValue, len(node.Children))
	for i, child := range node.Children {
		args[i] = rt.evalExpr(child)
	}

	switch name {
	// ===== 群聊方法 =====
	case "sendGroupMsg":
		return rt.builtinSendGroupMsg(args)
	case "replyGroupMsg":
		return rt.builtinReplyGroupMsg(args)
	case "recallGroupMsg":
		return rt.builtinRecallGroupMsg(args)
	case "setGroupEssence":
		return rt.builtinSetGroupEssence(args)
	case "unsetGroupEssence":
		return rt.builtinUnsetGroupEssence(args)
	case "muteGroupMember":
		return rt.builtinMuteGroupMember(args)
	case "unmuteGroupMember":
		return rt.builtinUnmuteGroupMember(args)

	// ===== 私聊方法 =====
	case "sendPrivateMsg":
		return rt.builtinSendPrivateMsg(args)
	case "replyPrivateMsg":
		return rt.builtinReplyPrivateMsg(args)
	case "recallPrivateMsg":
		return rt.builtinRecallPrivateMsg(args)

	// ===== 通知方法 =====
	case "sendNotice":
		return rt.builtinSendNotice(args)

	// ===== 信息查询方法 =====
	case "getUserInfo":
		return rt.builtinGetUserInfo(args)
	case "getGroupInfo":
		return rt.builtinGetGroupInfo(args)
	case "getGroupMemberCount":
		return rt.builtinGetGroupMemberCount(args)
	case "isGroupMember":
		return rt.builtinIsGroupMember(args)
	case "getGroupAdminPermissions":
		return rt.builtinGetGroupAdminPms(args)
	case "inGroup":
		return rt.builtinInGroup(args)
	case "getBotGroups":
		return rt.builtinGetBotGroups(args)
	case "getBotFriends":
		return rt.builtinGetBotFriends(args)

	// ===== 辅助方法 =====
	case "log":
		msg := fmt.Sprintf("%v", args)
		if len(args) == 1 {
			msg = args[0].String()
		}
		rt.logBuf = append(rt.logBuf, msg)
		rt.writeBotLog("log", msg)
		log.Printf("[BotScript:%d] LOG: %s", rt.botID, msg)
		return svNull

	case "err":
		msg := fmt.Sprintf("%v", args)
		if len(args) == 1 {
			msg = args[0].String()
		}
		rt.logBuf = append(rt.logBuf, "ERROR: "+msg)
		rt.writeBotLog("error", msg)
		log.Printf("[BotScript:%d] ERROR: %s", rt.botID, msg)
		return svNull

	case "contains":
		if len(args) >= 2 && args[0].Type == "string" && args[1].Type == "string" {
			return newBoolVal(strings.Contains(args[0].StrVal, args[1].StrVal))
		}
		return svFalse

	case "startsWith":
		if len(args) >= 2 && args[0].Type == "string" && args[1].Type == "string" {
			return newBoolVal(strings.HasPrefix(args[0].StrVal, args[1].StrVal))
		}
		return svFalse

	case "endsWith":
		if len(args) >= 2 && args[0].Type == "string" && args[1].Type == "string" {
			return newBoolVal(strings.HasSuffix(args[0].StrVal, args[1].StrVal))
		}
		return svFalse

	case "len":
		if len(args) >= 1 {
			switch args[0].Type {
			case "string":
				return newNumVal(int64(len(args[0].StrVal)))
			case "array":
				return newNumVal(int64(len(args[0].ArrVal)))
			case "map":
				return newNumVal(int64(len(args[0].MapVal)))
			}
		}
		return newNumVal(0)

	case "toString":
		if len(args) >= 1 {
			return newStrVal(args[0].String())
		}
		return newStrVal("")

	case "toNumber":
		if len(args) >= 1 {
			return newNumVal(args[0].ToInt64())
		}
		return newNumVal(0)

	case "now":
		return newNumVal(time.Now().Unix())

	// ===== 字符串增强方法 =====
	case "split":
		if len(args) < 2 {
			return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: split(str, sep)")})
		}
		parts := strings.Split(args[0].String(), args[1].String())
		items := make([]*ScriptValue, len(parts))
		for i, p := range parts {
			items[i] = newStrVal(p)
		}
		return newArrVal(items)
	case "replace":
		if len(args) < 3 {
			return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: replace(str, old, new)")})
		}
		return newStrVal(strings.ReplaceAll(args[0].String(), args[1].String(), args[2].String()))
	case "trim":
		if len(args) < 1 {
			return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: trim(str)")})
		}
		return newStrVal(strings.TrimSpace(args[0].String()))
	case "substring":
		if len(args) < 3 {
			return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: substring(str, start, end)")})
		}
		s := args[0].String()
		start := int(args[1].ToInt64())
		end := int(args[2].ToInt64())
		if start < 0 {
			start = 0
		}
		if end > len(s) {
			end = len(s)
		}
		if start >= end {
			return newStrVal("")
		}
		return newStrVal(s[start:end])
	case "indexOf":
		if len(args) < 2 {
			return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: indexOf(str, sub)")})
		}
		return newNumVal(int64(strings.Index(args[0].String(), args[1].String())))
	case "matchKeyword":
		// matchKeyword(content, keywords) - 多关键词匹配
		// keywords 可以是数组 ["hello", "hi"] 或逗号分隔字符串 "hello,hi"
		// 返回匹配到的第一个关键词，未匹配返回空字符串
		if len(args) < 2 {
			return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: matchKeyword(content, keywords)")})
		}
		content := args[0].String()
		var keywords []string
		if args[1].Type == "array" {
			for _, item := range args[1].ArrVal {
				keywords = append(keywords, item.String())
			}
		} else {
			keywords = strings.Split(args[1].String(), ",")
		}
		for _, kw := range keywords {
			kw = strings.TrimSpace(kw)
			if kw != "" && strings.Contains(content, kw) {
				return newStrVal(kw)
			}
		}
		return newStrVal("")
	case "matchRegex":
		// matchRegex(content, pattern) - 正则匹配
		// 返回匹配到的字符串，未匹配返回空字符串
		if len(args) < 2 {
			return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: matchRegex(content, pattern)")})
		}
		matched, err := regexp.MatchString(args[1].String(), args[0].String())
		if err != nil {
			return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("正则表达式无效: " + err.Error())})
		}
		return newBoolVal(matched)
	case "push":
		if len(args) < 2 || args[0].Type != "array" {
			return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数无效: push(arr, item)")})
		}
		args[0].ArrVal = append(args[0].ArrVal, args[1])
		return newNumVal(int64(len(args[0].ArrVal)))
	case "size":
		if len(args) < 1 {
			return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: size(arr)")})
		}
		if args[0].Type == "array" {
			return newNumVal(int64(len(args[0].ArrVal)))
		}
		if args[0].Type == "map" {
			return newNumVal(int64(len(args[0].MapVal)))
		}
		if args[0].Type == "string" {
			return newNumVal(int64(len(args[0].StrVal)))
		}
		return newNumVal(0)

	// ===== 事件上下文方法 =====
	case "getMsgId":
		return rt.ctxGet("msg_id")
	case "getMsgSender":
		v := rt.ctxGet("uid")
		if v == svNull {
			v = rt.ctxGet("from_uid")
		}
		return v
	case "getMsgContent":
		return rt.ctxGet("content")
	case "getMsgType":
		return rt.ctxGet("msg_type")
	case "getMsgImageUrls":
		return rt.ctxGet("image_urls")
	case "getMsgReplyTo":
		v := rt.ctxGet("reply_to")
		if v == svNull {
			return newNumVal(0)
		}
		return v
	case "getMsgTimestamp":
		return rt.ctxGet("timestamp")

	// ===== 事件上下文扩展 =====
	case "getEventRoomId":
		return rt.ctxGet("room_id")

	// ===== 基础方法 =====
	case "getBotId":
		return newNumVal(rt.botID)
	case "getBotUid":
		return newNumVal(rt.botUID)

	// ===== 补充操作方法 =====
	case "sendGroupImage":
		return rt.builtinSendGroupImage(args)
	case "sendPvtImage":
		return rt.builtinSendPvtImage(args)
	case "leaveGroup":
		return rt.builtinLeaveGroup(args)

	// ===== 外部服务方法 =====
	case "httpGet":
		return rt.builtinHttpGet(args)
	case "httpPost":
		return rt.builtinHttpPost(args)

	// ===== 定时任务 =====
	case "cron":
		return rt.builtinCron(args)

	default:
		log.Printf("[BotScript:%d] 未知方法: %s", rt.botID, name)
		return svNull
	}
}

// ===== 内置方法实现 =====

func (rt *ScriptRuntime) callAPI(action string, params map[string]any) map[string]any {
	// 直接调用BotFramework的内部方法，避免HTTP开销
	// 这里通过fw直接操作数据库
	return map[string]any{"success": false, "message": "internal call not implemented for " + action}
}

func (rt *ScriptRuntime) builtinSendGroupMsg(args []*ScriptValue) *ScriptValue {
	if len(args) < 2 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: sendGroupMsg(gid, content) 或 sendGroupMsg(event, content)")})
	}

	var gid int64
	var content string

	// 支持两种调用方式：
	// sendGroupMsg(event, content) - event是map，从中提取room_id
	// sendGroupMsg(gid, content) - gid是数字
	if args[0].Type == "map" && args[0].MapVal != nil {
		if v, ok := args[0].MapVal["room_id"]; ok {
			gid = v.ToInt64()
		}
		content = args[1].String()
	} else {
		gid = args[0].ToInt64()
		content = args[1].String()
	}

	if gid <= 0 || content == "" {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数无效")})
	}
	// 检查Bot是否在群内
	member, _ := rt.fw.fetchOne("SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?", gid, rt.botUID)
	if member == nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("InvalidMsg"), "message": newStrVal("Bot不在该群内")})
	}
	if muteUntil := intval(member, "mute_until"); muteUntil > time.Now().Unix() {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("InvalidMsg"), "message": newStrVal("Bot已被禁言")})
	}
	user, _ := rt.fw.fetchOne("SELECT nickname FROM chat_user WHERE id = ?", rt.botUID)
	nickname := str(user, "nickname")
	if nickname == "" {
		nickname = "Bot"
	}
	msgID, err := rt.fw.insertBotRow("chat_msg", map[string]any{
		"room_id": gid, "uid": rt.botUID, "nickname": nickname,
		"content": content, "msg_type": 1, "voice_duration": 0,
		"add_time": time.Now().UTC().Format("2006-01-02 15:04:05"),
		"reply_to": nil, "mention_uids": "", "was_replied": 0,
	})
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("发送失败")})
	}
	return newMapVal(map[string]*ScriptValue{"success": svTrue, "msg_id": newNumVal(msgID)})
}

func (rt *ScriptRuntime) builtinReplyGroupMsg(args []*ScriptValue) *ScriptValue {
	var gid, oriMsgID int64
	var content string

	if len(args) == 2 {
		// replyGroupMsg(event, content) - event是map
		if args[0].Type == "map" && args[0].MapVal != nil {
			if v, ok := args[0].MapVal["room_id"]; ok {
				gid = v.ToInt64()
			}
			if v, ok := args[0].MapVal["msg_id"]; ok {
				oriMsgID = v.ToInt64()
			}
			content = args[1].String()
		} else {
			return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数无效: replyGroupMsg(event, content) 或 replyGroupMsg(gid, oriMsgId, content)")})
		}
	} else if len(args) >= 3 {
		// replyGroupMsg(gid, oriMsgId, content)
		gid = args[0].ToInt64()
		oriMsgID = args[1].ToInt64()
		content = args[2].String()
	} else {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: replyGroupMsg(event, content)")})
	}
	if gid <= 0 || oriMsgID <= 0 || content == "" {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数无效")})
	}
	oriMsg, _ := rt.fw.fetchOne("SELECT id FROM chat_msg WHERE id = ? AND room_id = ?", oriMsgID, gid)
	if oriMsg == nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("InvalidMsg"), "message": newStrVal("原消息不存在")})
	}
	member, _ := rt.fw.fetchOne("SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?", gid, rt.botUID)
	if member == nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("InvalidMsg"), "message": newStrVal("Bot不在该群内")})
	}
	if muteUntil := intval(member, "mute_until"); muteUntil > time.Now().Unix() {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("InvalidMsg"), "message": newStrVal("Bot已被禁言")})
	}
	user, _ := rt.fw.fetchOne("SELECT nickname FROM chat_user WHERE id = ?", rt.botUID)
	nickname := str(user, "nickname")
	if nickname == "" {
		nickname = "Bot"
	}
	msgID, err := rt.fw.insertBotRow("chat_msg", map[string]any{
		"room_id": gid, "uid": rt.botUID, "nickname": nickname,
		"content": content, "msg_type": 1, "voice_duration": 0,
		"add_time": time.Now().UTC().Format("2006-01-02 15:04:05"),
		"reply_to": oriMsgID, "mention_uids": "", "was_replied": 0,
	})
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("发送失败")})
	}
	return newMapVal(map[string]*ScriptValue{"success": svTrue, "msg_id": newNumVal(msgID)})
}

func (rt *ScriptRuntime) builtinRecallGroupMsg(args []*ScriptValue) *ScriptValue {
	if len(args) < 2 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: recallGroupMsg(gid, msgId)")})
	}
	gid := args[0].ToInt64()
	msgID := args[1].ToInt64()
	if !rt.fw.isGroupAdminOrOwner(gid, rt.botUID) {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("HnPmsDenied"), "message": newStrVal("缺少管理员权限")})
	}
	_, err := rt.fw.exec("UPDATE chat_msg SET was_replied = 2 WHERE id = ? AND room_id = ?", msgID, gid)
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("撤回失败")})
	}
	return newMapVal(map[string]*ScriptValue{"success": svTrue, "message": newStrVal("撤回成功")})
}

func (rt *ScriptRuntime) builtinSetGroupEssence(args []*ScriptValue) *ScriptValue {
	if len(args) < 2 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足")})
	}
	gid, msgID := args[0].ToInt64(), args[1].ToInt64()
	if !rt.fw.isGroupAdminOrOwner(gid, rt.botUID) {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("HnPmsDenied")})
	}
	_, err := rt.fw.insertBotRow("chat_essence", map[string]any{
		"room_id": gid, "msg_id": msgID, "set_uid": rt.botUID, "set_nick": "Bot", "set_time": time.Now().UTC().Format("2006-01-02 15:04:05"),
	})
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("设置精华失败")})
	}
	return newMapVal(map[string]*ScriptValue{"success": svTrue})
}

func (rt *ScriptRuntime) builtinUnsetGroupEssence(args []*ScriptValue) *ScriptValue {
	if len(args) < 2 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足")})
	}
	gid, msgID := args[0].ToInt64(), args[1].ToInt64()
	if !rt.fw.isGroupAdminOrOwner(gid, rt.botUID) {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("HnPmsDenied")})
	}
	_, _ = rt.fw.exec("DELETE FROM chat_essence WHERE msg_id = ? AND room_id = ?", msgID, gid)
	return newMapVal(map[string]*ScriptValue{"success": svTrue})
}

func (rt *ScriptRuntime) builtinMuteGroupMember(args []*ScriptValue) *ScriptValue {
	if len(args) < 3 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: muteGroupMember(gid, uid, seconds)")})
	}
	gid, uid, seconds := args[0].ToInt64(), args[1].ToInt64(), args[2].ToInt64()
	if !rt.fw.isGroupAdminOrOwner(gid, rt.botUID) {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("HnPmsDenied")})
	}
	muteUntil := time.Now().Unix() + seconds
	_, err := rt.fw.exec("UPDATE chat_group_user SET mute_until = ? WHERE room_id = ? AND uid = ?", muteUntil, gid, uid)
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("禁言失败")})
	}
	return newMapVal(map[string]*ScriptValue{"success": svTrue, "mute_until": newNumVal(muteUntil)})
}

func (rt *ScriptRuntime) builtinUnmuteGroupMember(args []*ScriptValue) *ScriptValue {
	if len(args) < 2 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足")})
	}
	gid, uid := args[0].ToInt64(), args[1].ToInt64()
	if !rt.fw.isGroupAdminOrOwner(gid, rt.botUID) {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("HnPmsDenied")})
	}
	_, _ = rt.fw.exec("UPDATE chat_group_user SET mute_until = 0 WHERE room_id = ? AND uid = ?", gid, uid)
	return newMapVal(map[string]*ScriptValue{"success": svTrue})
}

func (rt *ScriptRuntime) builtinSendPrivateMsg(args []*ScriptValue) *ScriptValue {
	if len(args) < 2 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: sendPrivateMsg(uid, content)")})
	}
	uid, content := args[0].ToInt64(), args[1].String()
	rel, _ := rt.fw.fetchOne("SELECT status FROM friend_relation WHERE (uid1 = ? AND uid2 = ?) OR (uid1 = ? AND uid2 = ?)",
		min64(rt.botUID, uid), max64(rt.botUID, uid), max64(rt.botUID, uid), min64(rt.botUID, uid))
	if rel == nil || intval(rel, "status") != 1 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("不是好友")})
	}
	msgID, err := rt.fw.insertBotRow("private_msg", map[string]any{
		"from_uid": rt.botUID, "to_uid": uid, "content": content,
		"type": "private", "room_id": 0, "created_at": time.Now().Unix(),
		"is_read": 0, "msg_type": 1, "is_recalled": 0, "reply_to": nil,
	})
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("发送失败")})
	}
	return newMapVal(map[string]*ScriptValue{"success": svTrue, "msg_id": newNumVal(msgID)})
}

func (rt *ScriptRuntime) builtinReplyPrivateMsg(args []*ScriptValue) *ScriptValue {
	var uid, oriMsgID int64
	var content string

	if len(args) == 2 {
		// replyPrivateMsg(event, content) - event是map
		if args[0].Type == "map" && args[0].MapVal != nil {
			if v, ok := args[0].MapVal["from_uid"]; ok {
				uid = v.ToInt64()
			}
			if v, ok := args[0].MapVal["msg_id"]; ok {
				oriMsgID = v.ToInt64()
			}
			content = args[1].String()
		} else {
			return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数无效: replyPrivateMsg(event, content) 或 replyPrivateMsg(uid, oriMsgId, content)")})
		}
	} else if len(args) >= 3 {
		// replyPrivateMsg(uid, oriMsgId, content)
		uid = args[0].ToInt64()
		oriMsgID = args[1].ToInt64()
		content = args[2].String()
	} else {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: replyPrivateMsg(event, content)")})
	}
	msgID, err := rt.fw.insertBotRow("private_msg", map[string]any{
		"from_uid": rt.botUID, "to_uid": uid, "content": content,
		"type": "private", "room_id": 0, "created_at": time.Now().Unix(),
		"is_read": 0, "msg_type": 1, "is_recalled": 0, "reply_to": oriMsgID,
	})
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("发送失败")})
	}
	return newMapVal(map[string]*ScriptValue{"success": svTrue, "msg_id": newNumVal(msgID)})
}

func (rt *ScriptRuntime) builtinRecallPrivateMsg(args []*ScriptValue) *ScriptValue {
	if len(args) < 2 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足")})
	}
	uid, msgID := args[0].ToInt64(), args[1].ToInt64()
	msg, _ := rt.fw.fetchOne("SELECT id FROM private_msg WHERE id = ? AND from_uid = ? AND to_uid = ? AND is_recalled = 0", msgID, rt.botUID, uid)
	if msg == nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("InvalidMsg"), "message": newStrVal("消息不存在")})
	}
	_, _ = rt.fw.exec("UPDATE private_msg SET is_recalled = 1 WHERE id = ?", msgID)
	return newMapVal(map[string]*ScriptValue{"success": svTrue})
}

func (rt *ScriptRuntime) builtinSendNotice(args []*ScriptValue) *ScriptValue {
	if len(args) < 3 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: sendNotice(uid, title, content)")})
	}
	uid, title, content := args[0].ToInt64(), args[1].String(), args[2].String()
	// 检查通知权限
	bot, _ := rt.fw.fetchOne("SELECT can_notify FROM bot_accounts WHERE id = ?", rt.botID)
	if bot == nil || intval(bot, "can_notify") != 1 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("NtcNAuth")})
	}
	_, err := rt.fw.insertBotRow("chat_user_notice", map[string]any{
		"uid": uid, "title": title, "content": content, "is_read": 0,
		"add_time": time.Now().UTC().Format("2006-01-02 15:04:05"),
	})
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("发送通知失败")})
	}
	return newMapVal(map[string]*ScriptValue{"success": svTrue})
}

func (rt *ScriptRuntime) builtinGetUserInfo(args []*ScriptValue) *ScriptValue {
	if len(args) < 1 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足")})
	}
	uid := args[0].ToInt64()
	user, _ := rt.fw.fetchOne("SELECT id, nickname, username, avatar, platform, last_active FROM chat_user WHERE id = ?", uid)
	if user == nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("InvalidMsg"), "message": newStrVal("用户不存在")})
	}
	return newMapVal(map[string]*ScriptValue{
		"success": svTrue, "uid": newNumVal(intval(user, "id")),
		"nickname": newStrVal(str(user, "nickname")), "username": newStrVal(str(user, "username")),
		"avatar": newStrVal(str(user, "avatar")), "platform": newStrVal(str(user, "platform")),
		"last_active": newNumVal(intval(user, "last_active")),
	})
}

func (rt *ScriptRuntime) builtinGetGroupInfo(args []*ScriptValue) *ScriptValue {
	if len(args) < 1 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足")})
	}
	gid := args[0].ToInt64()
	room, _ := rt.fw.fetchOne("SELECT id, room_name, owner_uid, avatar, is_disband FROM chat_room WHERE id = ?", gid)
	if room == nil || intval(room, "is_disband") != 0 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("InvalidMsg"), "message": newStrVal("群不存在")})
	}
	return newMapVal(map[string]*ScriptValue{
		"success": svTrue, "gid": newNumVal(intval(room, "id")),
		"room_name": newStrVal(str(room, "room_name")), "owner_uid": newNumVal(intval(room, "owner_uid")),
		"avatar": newStrVal(str(room, "avatar")),
	})
}

func (rt *ScriptRuntime) builtinGetGroupMemberCount(args []*ScriptValue) *ScriptValue {
	if len(args) < 1 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足")})
	}
	gid := args[0].ToInt64()
	var count int64
	_ = rt.fw.db.QueryRow("SELECT COUNT(*) FROM chat_group_user WHERE room_id = ?", gid).Scan(&count)
	return newMapVal(map[string]*ScriptValue{"success": svTrue, "count": newNumVal(count)})
}

func (rt *ScriptRuntime) builtinIsGroupMember(args []*ScriptValue) *ScriptValue {
	if len(args) < 2 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足")})
	}
	gid, uid := args[0].ToInt64(), args[1].ToInt64()
	row, _ := rt.fw.fetchOne("SELECT room_id FROM chat_group_user WHERE room_id = ? AND uid = ? LIMIT 1", gid, uid)
	return newBoolVal(row != nil)
}

func (rt *ScriptRuntime) builtinGetGroupAdminPms(args []*ScriptValue) *ScriptValue {
	if len(args) < 1 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足")})
	}
	gid := args[0].ToInt64()
	row, _ := rt.fw.fetchOne("SELECT uid FROM chat_group_admin WHERE room_id = ? AND uid = ? LIMIT 1", gid, rt.botUID)
	isAdmin := row != nil
	room, _ := rt.fw.fetchOne("SELECT owner_uid FROM chat_room WHERE id = ? AND is_disband = 0", gid)
	isOwner := room != nil && intval(room, "owner_uid") == rt.botUID
	return newMapVal(map[string]*ScriptValue{
		"success": svTrue, "is_admin": newBoolVal(isAdmin || isOwner), "is_owner": newBoolVal(isOwner),
	})
}

func (rt *ScriptRuntime) builtinInGroup(args []*ScriptValue) *ScriptValue {
	if len(args) < 1 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足")})
	}
	gid := args[0].ToInt64()
	row, _ := rt.fw.fetchOne("SELECT room_id FROM chat_group_user WHERE room_id = ? AND uid = ? LIMIT 1", gid, rt.botUID)
	return newBoolVal(row != nil)
}

// builtinGetBotGroups 获取Bot所在的所有群组列表
// 返回: {success: true, groups: [{room_id, room_name, owner_uid, avatar}, ...]}
func (rt *ScriptRuntime) builtinGetBotGroups(args []*ScriptValue) *ScriptValue {
	rows, err := rt.fw.db.Query(
		"SELECT r.id, r.room_name, r.owner_uid, r.avatar FROM chat_group_user gu JOIN chat_room r ON gu.room_id = r.id WHERE gu.uid = ? AND r.is_disband = 0",
		rt.botUID)
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("DBErr"), "message": newStrVal("查询失败")})
	}
	defer rows.Close()

	var groups []*ScriptValue
	for rows.Next() {
		var id, ownerUID int64
		var roomName, avatar string
		if err := rows.Scan(&id, &roomName, &ownerUID, &avatar); err != nil {
			continue
		}
		groups = append(groups, newMapVal(map[string]*ScriptValue{
			"room_id":   newNumVal(id),
			"room_name": newStrVal(roomName),
			"owner_uid": newNumVal(ownerUID),
			"avatar":    newStrVal(avatar),
		}))
	}
	if groups == nil {
		groups = []*ScriptValue{}
	}
	return newMapVal(map[string]*ScriptValue{
		"success": svTrue,
		"groups":  newArrVal(groups),
	})
}

// builtinGetBotFriends 获取Bot的所有好友列表
// 返回: {success: true, friends: [{uid, nickname, username, avatar}, ...]}
func (rt *ScriptRuntime) builtinGetBotFriends(args []*ScriptValue) *ScriptValue {
	rows, err := rt.fw.db.Query(
		"SELECT u.id, u.nickname, u.username, u.avatar FROM friend_relation fr JOIN chat_user u ON (CASE WHEN fr.uid1 = ? THEN fr.uid2 ELSE fr.uid1 END) = u.id WHERE (fr.uid1 = ? OR fr.uid2 = ?) AND fr.status = 1",
		rt.botUID, rt.botUID, rt.botUID)
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("DBErr"), "message": newStrVal("查询失败")})
	}
	defer rows.Close()

	var friends []*ScriptValue
	for rows.Next() {
		var id int64
		var nickname, username, avatar string
		if err := rows.Scan(&id, &nickname, &username, &avatar); err != nil {
			continue
		}
		friends = append(friends, newMapVal(map[string]*ScriptValue{
			"uid":      newNumVal(id),
			"nickname": newStrVal(nickname),
			"username": newStrVal(username),
			"avatar":   newStrVal(avatar),
		}))
	}
	if friends == nil {
		friends = []*ScriptValue{}
	}
	return newMapVal(map[string]*ScriptValue{
		"success": svTrue,
		"friends": newArrVal(friends),
	})
}

func (rt *ScriptRuntime) writeBotLog(level, content string) {
	_, _ = rt.fw.insertBotRow("bot_logs", map[string]any{
		"bot_id":     rt.botID,
		"level":      level,
		"content":    content,
		"created_at": time.Now().Unix(),
	})
}

// ===== 辅助函数（min64/max64 已在 api_handler.go 中定义）=====

// ctxGet 从事件上下文中获取字段值
func (rt *ScriptRuntime) ctxGet(key string) *ScriptValue {
	if rt.currentEvent == nil {
		return svNull
	}
	if val, ok := rt.currentEvent[key]; ok {
		return val
	}
	return svNull
}

// ===== 事件上下文方法实现 =====

// ===== 补充操作方法实现 =====

func (rt *ScriptRuntime) builtinSendGroupImage(args []*ScriptValue) *ScriptValue {
	if len(args) < 2 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: sendGroupImage(gid, url)")})
	}
	gid := args[0].ToInt64()
	imageURL := args[1].String()
	if gid <= 0 || imageURL == "" {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数无效")})
	}
	// 检查Bot是否在群内
	member, _ := rt.fw.fetchOne("SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?", gid, rt.botUID)
	if member == nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("Bot不在该群内")})
	}
	if muteUntil := intval(member, "mute_until"); muteUntil > time.Now().Unix() {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("Bot已被禁言")})
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
		"msg_type":       2, // 图片消息
		"voice_duration": 0,
		"add_time":       time.Now().UTC().Format("2006-01-02 15:04:05"),
		"reply_to":       nil,
		"mention_uids":   "",
		"was_replied":    0,
	})
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("发送图片失败")})
	}
	return newMapVal(map[string]*ScriptValue{"success": svTrue, "msg_id": newNumVal(msgID)})
}

func (rt *ScriptRuntime) builtinSendPvtImage(args []*ScriptValue) *ScriptValue {
	if len(args) < 2 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: sendPvtImage(uid, url)")})
	}
	uid := args[0].ToInt64()
	imageURL := args[1].String()
	if uid <= 0 || imageURL == "" {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数无效")})
	}
	// 检查好友关系
	rel, _ := rt.fw.fetchOne("SELECT status FROM friend_relation WHERE (uid1 = ? AND uid2 = ?) OR (uid1 = ? AND uid2 = ?)",
		min64(rt.botUID, uid), max64(rt.botUID, uid), max64(rt.botUID, uid), min64(rt.botUID, uid))
	if rel == nil || intval(rel, "status") != 1 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("不是好友")})
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
		"msg_type":    2, // 图片消息
		"is_recalled": 0,
		"reply_to":    nil,
	})
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("发送图片失败")})
	}
	return newMapVal(map[string]*ScriptValue{"success": svTrue, "msg_id": newNumVal(msgID)})
}

func (rt *ScriptRuntime) builtinLeaveGroup(args []*ScriptValue) *ScriptValue {
	if len(args) < 1 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: leaveGroup(gid)")})
	}
	gid := args[0].ToInt64()
	if gid <= 0 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数无效")})
	}
	// 检查Bot是否在群内
	member, _ := rt.fw.fetchOne("SELECT room_id FROM chat_group_user WHERE room_id = ? AND uid = ?", gid, rt.botUID)
	if member == nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("Bot不在该群内")})
	}
	// 删除群成员记录
	_, err := rt.fw.exec("DELETE FROM chat_group_user WHERE room_id = ? AND uid = ?", gid, rt.botUID)
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("退群失败")})
	}
	// 如果Bot是群主，需要特殊处理（转让或解散）
	room, _ := rt.fw.fetchOne("SELECT owner_uid FROM chat_room WHERE id = ? AND is_disband = 0", gid)
	if room != nil && intval(room, "owner_uid") == rt.botUID {
		// Bot是群主，解散群聊
		_, _ = rt.fw.exec("UPDATE chat_room SET is_disband = 1 WHERE id = ?", gid)
		_, _ = rt.fw.exec("DELETE FROM chat_group_user WHERE room_id = ?", gid)
	}
	return newMapVal(map[string]*ScriptValue{"success": svTrue, "message": newStrVal("已退群")})
}

// ===== 外部服务方法实现 =====

func (rt *ScriptRuntime) builtinHttpGet(args []*ScriptValue) *ScriptValue {
	if len(args) < 1 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: httpGet(url)")})
	}
	url := args[0].String()
	if url == "" {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("URL不能为空")})
	}
	// 检查Bot是否有HTTP权限
	botInfo, _ := rt.fw.fetchOne("SELECT can_http FROM bot_accounts WHERE id = ?", rt.botID)
	if botInfo == nil || intval(botInfo, "can_http") != 1 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("HnPmsDenied"), "message": newStrVal("未获得HTTP请求权限")})
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("请求失败: " + err.Error())})
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("读取响应失败")})
	}
	return newMapVal(map[string]*ScriptValue{
		"success":      svTrue,
		"status":       newNumVal(int64(resp.StatusCode)),
		"body":         newStrVal(string(body)),
		"content_type": newStrVal(resp.Header.Get("Content-Type")),
	})
}

func (rt *ScriptRuntime) builtinHttpPost(args []*ScriptValue) *ScriptValue {
	if len(args) < 2 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: httpPost(url, body, contentType)")})
	}
	url := args[0].String()
	bodyStr := args[1].String()
	contentType := "application/json"
	if len(args) >= 3 && args[2].String() != "" {
		contentType = args[2].String()
	}
	if url == "" {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("URL不能为空")})
	}
	// 检查Bot是否有HTTP权限
	botInfo, _ := rt.fw.fetchOne("SELECT can_http FROM bot_accounts WHERE id = ?", rt.botID)
	if botInfo == nil || intval(botInfo, "can_http") != 1 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("HnPmsDenied"), "message": newStrVal("未获得HTTP请求权限")})
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Post(url, contentType, strings.NewReader(bodyStr))
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("请求失败: " + err.Error())})
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("读取响应失败")})
	}
	return newMapVal(map[string]*ScriptValue{
		"success":      svTrue,
		"status":       newNumVal(int64(resp.StatusCode)),
		"body":         newStrVal(string(body)),
		"content_type": newStrVal(resp.Header.Get("Content-Type")),
	})
}

// ===== 定时任务方法实现 =====

func (rt *ScriptRuntime) builtinCron(args []*ScriptValue) *ScriptValue {
	if len(args) < 2 {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数不足: cron(expression, handlerName)")})
	}
	expression := args[0].String()
	handlerName := args[1].String()
	if expression == "" || handlerName == "" {
		return newMapVal(map[string]*ScriptValue{"success": svFalse, "error": newStrVal("ArgErr"), "message": newStrVal("参数无效")})
	}
	// 注册cron任务到ScriptManager
	if rt.fw.scriptMgr != nil {
		err := rt.fw.scriptMgr.RegisterCron(rt.botID, expression, handlerName)
		if err != nil {
			return newMapVal(map[string]*ScriptValue{"success": svFalse, "message": newStrVal("注册定时任务失败: " + err.Error())})
		}
	}
	return newMapVal(map[string]*ScriptValue{"success": svTrue, "message": newStrVal("定时任务已注册")})
}
