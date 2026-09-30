// Copyright (c) Chemsource Studio. All rights reserved.
// Backend Version 2.2.0.260614-r1

package main

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"
)

// BotEventForwarder 负责将主服务器的事件转发到ServerBot框架
type BotEventForwarder struct {
	botEndpoint string // ServerBot的事件接收端点，如 http://serverbot:8081/bot/internal/event
	secret      string // 内部通信密钥
	client      *http.Client
	enabled     bool
	queue       chan map[string]any
	wg          sync.WaitGroup
}

var botForwarder *BotEventForwarder

func initBotForwarder(endpoint, secret string) {
	if endpoint == "" {
		botForwarder = &BotEventForwarder{enabled: false}
		log.Println("[BotForwarder] 未配置ServerBot端点，事件转发已禁用")
		return
	}
	fw := &BotEventForwarder{
		botEndpoint: endpoint,
		secret:      secret,
		client: &http.Client{
			Timeout: 5 * time.Second,
		},
		enabled: true,
		queue:   make(chan map[string]any, 1024),
	}
	botForwarder = fw
	// 启动异步发送协程
	fw.wg.Add(1)
	go fw.sendLoop()
	log.Printf("[BotForwarder] 已启用，端点: %s", endpoint)
}

func (fw *BotEventForwarder) sendLoop() {
	defer fw.wg.Done()
	for evt := range fw.queue {
		fw.doSend(evt)
	}
}

func (fw *BotEventForwarder) doSend(evt map[string]any) {
	data, err := json.Marshal(evt)
	if err != nil {
		log.Printf("[BotForwarder] JSON编码失败: %v", err)
		return
	}
	req, err := http.NewRequest(http.MethodPost, fw.botEndpoint, bytes.NewReader(data))
	if err != nil {
		log.Printf("[BotForwarder] 创建请求失败: %v", err)
		return
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Bot-Secret", fw.secret)
	resp, err := fw.client.Do(req)
	if err != nil {
		log.Printf("[BotForwarder] 发送事件失败: %v", err)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		log.Printf("[BotForwarder] ServerBot返回非200状态: %d", resp.StatusCode)
	}
}

// pushBotEvent 异步推送事件到ServerBot
func pushBotEvent(eventType string, payload map[string]any) {
	if botForwarder == nil || !botForwarder.enabled {
		return
	}
	evt := map[string]any{
		"event":     eventType,
		"payload":   payload,
		"timestamp": time.Now().Unix(),
	}
	select {
	case botForwarder.queue <- evt:
	default:
		log.Printf("[BotForwarder] 事件队列已满，丢弃事件: %s", eventType)
	}
}
