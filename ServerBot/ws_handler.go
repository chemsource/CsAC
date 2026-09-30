// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC ServerBot Framework Version 1.0.0.260614-r1

package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

// handleBotWebSocket 处理Bot的WebSocket连接
func (fw *BotFramework) handleBotWebSocket(w http.ResponseWriter, r *http.Request) {
	// 从查询参数获取Bot Token
	token := strings.TrimSpace(r.URL.Query().Get("token"))
	if token == "" {
		http.Error(w, `{"success":false,"message":"缺少token参数"}`, http.StatusUnauthorized)
		return
	}

	// 验证Token，获取Bot信息
	bot, err := fw.authenticateBot(token)
	if err != nil {
		log.Printf("ServerBot: authentication failed for token %s...: %v", token[:min(8, len(token))], err)
		http.Error(w, `{"success":false,"message":"认证失败"}`, http.StatusUnauthorized)
		return
	}

	// 检查Bot状态
	if intval(bot, "status") != 1 {
		http.Error(w, `{"success":false,"message":"Bot已被禁用"}`, http.StatusForbidden)
		return
	}

	// 升级为WebSocket连接
	conn, err := fw.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("ServerBot: websocket upgrade failed: %v", err)
		return
	}

	botConn := &BotConn{
		BotID:     intval(bot, "id"),
		UID:       intval(bot, "uid"),
		DevID:     intval(bot, "dev_id"),
		BotName:   str(bot, "bot_name"),
		CanNotify: intval(bot, "can_notify") == 1,
		CanHTTP:   intval(bot, "can_http") == 1,
		Conn:      conn,
		Send:      make(chan []byte, 256),
	}

	// 注册Bot
	fw.RegisterBot(botConn)

	// 发送hello消息
	_ = botConn.SendJSON(map[string]any{
		"type":        "hello",
		"bot_id":      botConn.BotID,
		"uid":         botConn.UID,
		"bot_name":    botConn.BotName,
		"can_notify":  botConn.CanNotify,
		"can_http":    botConn.CanHTTP,
		"server_time": time.Now().Unix(),
	})

	// 启动写协程
	go fw.writePump(botConn)

	// 读循环
	fw.readPump(botConn)
}

// authenticateBot 验证Bot Token并返回Bot信息
func (fw *BotFramework) authenticateBot(token string) (map[string]any, error) {
	bot, err := fw.fetchOne(
		"SELECT ba.id, ba.uid, ba.dev_id, ba.bot_name, ba.status, ba.can_notify, ba.can_http, cu.nickname, cu.ban_until "+
			"FROM bot_accounts ba JOIN chat_user cu ON ba.uid = cu.id "+
			"WHERE ba.bot_token = ? LIMIT 1", token,
	)
	if err != nil {
		return nil, err
	}
	if bot == nil {
		return nil, errBotNotFound
	}
	// 检查关联用户是否被封禁
	if banUntil := intval(bot, "ban_until"); banUntil > time.Now().Unix() {
		return nil, errBotBanned
	}
	return bot, nil
}

// readPump 从Bot读取消息
func (fw *BotFramework) readPump(bot *BotConn) {
	defer func() {
		fw.UnregisterBot(bot.BotID)
		bot.Conn.Close()
	}()

	bot.Conn.SetReadLimit(65536)
	bot.Conn.SetReadDeadline(time.Now().Add(120 * time.Second))
	bot.Conn.SetPongHandler(func(string) error {
		bot.Conn.SetReadDeadline(time.Now().Add(120 * time.Second))
		return nil
	})

	for {
		_, message, err := bot.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				log.Printf("ServerBot: Bot [%s] read error: %v", bot.BotName, err)
			}
			return
		}

		var data map[string]any
		if err := json.Unmarshal(message, &data); err != nil {
			continue
		}

		fw.handleBotMessage(bot, data)
	}
}

// writePump 向Bot写入消息
func (fw *BotFramework) writePump(bot *BotConn) {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		bot.Conn.Close()
	}()

	for {
		select {
		case message, ok := <-bot.Send:
			bot.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				_ = bot.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := bot.Conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
		case <-ticker.C:
			bot.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := bot.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// handleBotMessage 处理Bot发来的消息
func (fw *BotFramework) handleBotMessage(bot *BotConn, data map[string]any) {
	msgType, _ := data["type"].(string)

	switch msgType {
	case "ping":
		_ = bot.SendJSON(map[string]any{"type": "pong", "server_time": time.Now().Unix()})

	case "subscribe":
		// Bot订阅事件（群消息/私聊消息）
		// 格式: {"type": "subscribe", "events": ["group_msg", "private_msg"]}
		events, _ := data["events"].([]any)
		eventList := make([]string, 0, len(events))
		for _, e := range events {
			if s, ok := e.(string); ok {
				eventList = append(eventList, s)
			}
		}
		_ = bot.SendJSON(map[string]any{
			"type":        "subscribed",
			"events":      eventList,
			"server_time": time.Now().Unix(),
		})
		log.Printf("ServerBot: Bot [%s] subscribed to events: %v", bot.BotName, eventList)

	case "unsubscribe":
		_ = bot.SendJSON(map[string]any{
			"type":        "unsubscribed",
			"server_time": time.Now().Unix(),
		})

	default:
		// 未知消息类型，忽略
		log.Printf("ServerBot: Bot [%s] sent unknown message type: %s", bot.BotName, msgType)
	}
}

// 错误定义
var (
	errBotNotFound = &botError{message: "Bot not found"}
	errBotBanned   = &botError{message: "Bot user is banned"}
)

type botError struct {
	message string
}

func (e *botError) Error() string {
	return e.message
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
