// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC ServerBot Framework Version 1.0.0.260614-r1

package main

import (
	"database/sql"
	"fmt"
	"log"
	"regexp"
	"strings"
	"time"
)

var safeIdent = regexp.MustCompile(`^[A-Za-z0-9_]+$`)

// ensureSchema 确保Bot框架所需的数据库表和列存在
func (fw *BotFramework) ensureSchema() {
	// chat_user 新增 is_bot 列
	fw.ensureColumn("chat_user", "is_bot", "TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否为Bot账号：0=普通用户 1=Bot'")

	// 开发者账号表
	fw.ensureTable("open_dev_accounts", `CREATE TABLE IF NOT EXISTS open_dev_accounts (
		id INT NOT NULL AUTO_INCREMENT,
		email VARCHAR(255) NOT NULL,
		pwd VARCHAR(64) NOT NULL,
		dev_name VARCHAR(50) NOT NULL COMMENT '开发者名称',
		api_key VARCHAR(128) NOT NULL COMMENT '开发者API Key',
		status TINYINT NOT NULL DEFAULT 1 COMMENT '1=正常 0=封禁',
		allow_ajl_upload TINYINT NOT NULL DEFAULT 0 COMMENT '是否允许上传AJL库：0=不允许 1=允许',
		created_at INT NOT NULL,
		PRIMARY KEY (id),
		UNIQUE KEY uk_email (email),
		UNIQUE KEY uk_api_key (api_key)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	// v2.2.1: 开发者账号表添加 allow_ajl_upload 列（兼容旧数据库）
	fw.ensureColumn("open_dev_accounts", "allow_ajl_upload", "TINYINT NOT NULL DEFAULT 0 COMMENT '是否允许上传AJL库：0=不允许 1=允许'")

	// Bot账号表
	fw.ensureTable("bot_accounts", `CREATE TABLE IF NOT EXISTS bot_accounts (
		id INT NOT NULL AUTO_INCREMENT,
		uid INT NOT NULL COMMENT '关联chat_user.id',
		dev_id INT NOT NULL COMMENT '关联开发者ID',
		bot_token VARCHAR(128) NOT NULL COMMENT 'Bot认证Token',
		bot_name VARCHAR(50) NOT NULL COMMENT 'Bot名称',
		bot_desc VARCHAR(500) DEFAULT '' COMMENT 'Bot描述',
		bot_avatar VARCHAR(255) DEFAULT '' COMMENT 'Bot头像',
		status TINYINT NOT NULL DEFAULT 1 COMMENT '1=正常 0=禁用',
		can_notify TINYINT NOT NULL DEFAULT 0 COMMENT '是否允许发送通知',
		can_http TINYINT NOT NULL DEFAULT 0 COMMENT '是否允许HTTP请求',
		online TINYINT NOT NULL DEFAULT 0 COMMENT '是否在线',
		last_online INT NOT NULL DEFAULT 0 COMMENT '最后在线时间戳',
		created_at INT NOT NULL,
		PRIMARY KEY (id),
		UNIQUE KEY uk_bot_token (bot_token),
		INDEX idx_dev_id (dev_id),
		INDEX idx_uid (uid)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	// Bot脚本表
	fw.ensureTable("bot_scripts", `CREATE TABLE IF NOT EXISTS bot_scripts (
		id INT NOT NULL AUTO_INCREMENT,
		bot_id INT NOT NULL COMMENT '关联bot_accounts.id',
		script_name VARCHAR(100) NOT NULL COMMENT '脚本名称',
		script_content MEDIUMTEXT NOT NULL COMMENT '脚本内容',
		enabled TINYINT NOT NULL DEFAULT 1 COMMENT '1=启用 0=禁用',
		version INT NOT NULL DEFAULT 1 COMMENT '脚本版本号',
		created_at INT NOT NULL,
		updated_at INT NOT NULL,
		PRIMARY KEY (id),
		INDEX idx_bot_id (bot_id)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	// Bot运行日志表
	fw.ensureTable("bot_logs", `CREATE TABLE IF NOT EXISTS bot_logs (
		id INT NOT NULL AUTO_INCREMENT,
		bot_id INT NOT NULL,
		script_id INT NOT NULL DEFAULT 0,
		level ENUM('log','error','warn') NOT NULL DEFAULT 'log',
		content TEXT NOT NULL,
		created_at INT NOT NULL,
		PRIMARY KEY (id),
		INDEX idx_bot_created (bot_id, created_at),
		INDEX idx_bot_level (bot_id, level)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	// 权限申请表
	fw.ensureTable("bot_perm_requests", `CREATE TABLE IF NOT EXISTS bot_perm_requests (
		id INT NOT NULL AUTO_INCREMENT,
		bot_id INT NOT NULL,
		perm_type VARCHAR(50) NOT NULL COMMENT '权限类型：notify, http等',
		reason TEXT NOT NULL COMMENT '申请理由',
		status TINYINT NOT NULL DEFAULT 0 COMMENT '0=待审 1=通过 2=拒绝',
		admin_reply TEXT COMMENT '管理员回复',
		created_at INT NOT NULL,
		handled_at INT NOT NULL DEFAULT 0,
		PRIMARY KEY (id),
		INDEX idx_bot_id (bot_id),
		INDEX idx_status (status)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	// Bot JavaScript 私有键值存储表
	fw.ensureTable("bot_storage", `CREATE TABLE IF NOT EXISTS bot_storage (
		id INT NOT NULL AUTO_INCREMENT,
		bot_id INT NOT NULL,
		skey VARCHAR(128) NOT NULL,
		value MEDIUMTEXT NOT NULL,
		updated_at INT NOT NULL,
		PRIMARY KEY (id),
		UNIQUE KEY uk_bot_key (bot_id, skey),
		INDEX idx_bot_id (bot_id)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	// 清理过期日志（保留30天）
	_, _ = fw.db.Exec("DELETE FROM bot_logs WHERE created_at < ?", time.Now().Unix()-86400*30)

	// v2.2.1: AJL库审核表
	fw.ensureTable("bot_libs", `CREATE TABLE IF NOT EXISTS bot_libs (
		id INT NOT NULL AUTO_INCREMENT,
		name VARCHAR(100) NOT NULL COMMENT '库名',
		version VARCHAR(50) NOT NULL DEFAULT '1.0.0' COMMENT '版本号',
		content MEDIUMTEXT NOT NULL COMMENT 'JavaScript代码',
		signature VARCHAR(256) NOT NULL DEFAULT '' COMMENT '签名',
		author VARCHAR(100) NOT NULL DEFAULT '' COMMENT '作者',
		desc VARCHAR(500) NOT NULL DEFAULT '' COMMENT '描述',
		dev_id INT NOT NULL COMMENT '上传者开发者ID',
		status TINYINT NOT NULL DEFAULT 0 COMMENT '0=待审核 1=已通过 2=已拒绝',
		admin_note TEXT COMMENT '管理员备注',
		created_at INT NOT NULL,
		reviewed_at INT NOT NULL DEFAULT 0,
		PRIMARY KEY (id),
		INDEX idx_dev_id (dev_id),
		INDEX idx_status (status),
		UNIQUE KEY uk_name_version (name, version)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)

	// v2.3.0: 群命令配置表
	fw.ensureTable("group_commands", `CREATE TABLE IF NOT EXISTS group_commands (
		id INT NOT NULL AUTO_INCREMENT,
		room_id INT NOT NULL COMMENT '群ID',
		command VARCHAR(100) NOT NULL COMMENT '命令名',
		content TEXT NOT NULL COMMENT '命令对应的消息内容',
		created_by INT NOT NULL COMMENT '创建者UID',
		created_at INT NOT NULL,
		PRIMARY KEY (id),
		UNIQUE KEY uk_room_command (room_id, command),
		INDEX idx_room_id (room_id)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`)
}

func (fw *BotFramework) ensureTable(table, ddl string) {
	if _, err := fw.db.Exec(ddl); err != nil {
		log.Printf("ServerBot: ensure table %s failed: %v", table, err)
	}
}

func (fw *BotFramework) ensureColumn(table, column, definition string) {
	if !safeIdent.MatchString(table) || !safeIdent.MatchString(column) {
		return
	}
	if fw.hasColumn(table, column) {
		return
	}
	if _, err := fw.db.Exec(fmt.Sprintf("ALTER TABLE `%s` ADD COLUMN `%s` %s", table, column, definition)); err != nil {
		log.Printf("ServerBot: ensure column %s.%s failed: %v", table, column, err)
	}
}

func (fw *BotFramework) hasColumn(table, column string) bool {
	var count int
	err := fw.db.QueryRow(
		"SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?",
		table, column,
	).Scan(&count)
	return err == nil && count > 0
}

// fetchOne 查询单行
func (fw *BotFramework) fetchOne(query string, args ...any) (map[string]any, error) {
	rows, err := fw.fetchAll(query, args...)
	if err != nil || len(rows) == 0 {
		return nil, err
	}
	return rows[0], nil
}

// fetchAll 查询多行
func (fw *BotFramework) fetchAll(query string, args ...any) ([]map[string]any, error) {
	rows, err := fw.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cols, err := rows.Columns()
	if err != nil {
		return nil, err
	}
	result := make([]map[string]any, 0)
	for rows.Next() {
		values := make([]sql.NullString, len(cols))
		dest := make([]any, len(cols))
		for i := range values {
			dest[i] = &values[i]
		}
		if err := rows.Scan(dest...); err != nil {
			return nil, err
		}
		row := map[string]any{}
		for i, col := range cols {
			if values[i].Valid {
				row[col] = values[i].String
			} else {
				row[col] = nil
			}
		}
		result = append(result, row)
	}
	return result, rows.Err()
}

// exec 执行SQL
func (fw *BotFramework) exec(query string, args ...any) (int64, error) {
	res, err := fw.db.Exec(query, args...)
	if err != nil {
		return 0, err
	}
	affected, _ := res.RowsAffected()
	return affected, nil
}

// str 从行中获取字符串值
func str(row map[string]any, key string) string {
	if row == nil {
		return ""
	}
	v, ok := row[key]
	if !ok || v == nil {
		return ""
	}
	return strings.TrimSpace(fmt.Sprint(v))
}

// intval 从行中获取整数值
func intval(row map[string]any, key string) int64 {
	if row == nil {
		return 0
	}
	v, ok := row[key]
	if !ok || v == nil {
		return 0
	}
	s := strings.TrimSpace(fmt.Sprint(v))
	if s == "" {
		return 0
	}
	var n int64
	fmt.Sscanf(s, "%d", &n)
	return n
}
