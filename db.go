// Copyright (c) Chemsource Studio. All rights reserved.
// Contact: swcsstudio@126.com

package main

import (
	"database/sql"
	"fmt"
	"log"
	"regexp"
	"sort"
	"strings"
	"time"
)

type Row map[string]any

var safeIdent = regexp.MustCompile(`^[A-Za-z0-9_]+$`)

type sqlRunner interface {
	Exec(query string, args ...any) (sql.Result, error)
	Query(query string, args ...any) (*sql.Rows, error)
	QueryRow(query string, args ...any) *sql.Row
}

func (a *App) fetchOne(query string, args ...any) (Row, error) {
	return fetchOne(a.db, query, args...)
}

func (a *App) fetchAll(query string, args ...any) ([]Row, error) {
	return fetchAll(a.db, query, args...)
}

func (a *App) exec(query string, args ...any) (int64, error) {
	res, err := a.db.Exec(query, args...)
	if err != nil {
		return 0, err
	}
	affected, _ := res.RowsAffected()
	return affected, nil
}

func fetchOne(q sqlRunner, query string, args ...any) (Row, error) {
	rows, err := fetchAll(q, query, args...)
	if err != nil || len(rows) == 0 {
		return nil, err
	}
	return rows[0], nil
}

func fetchAll(q sqlRunner, query string, args ...any) ([]Row, error) {
	rows, err := q.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cols, err := rows.Columns()
	if err != nil {
		return nil, err
	}
	result := []Row{}
	for rows.Next() {
		values := make([]sql.NullString, len(cols))
		dest := make([]any, len(cols))
		for i := range values {
			dest[i] = &values[i]
		}
		if err := rows.Scan(dest...); err != nil {
			return nil, err
		}
		row := Row{}
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

func (a *App) tableColumns(table string) map[string]bool {
	if !safeIdent.MatchString(table) {
		return map[string]bool{}
	}
	<-a.columnCacheMu
	if cached, ok := a.columnCache[table]; ok {
		a.columnCacheMu <- struct{}{}
		return cached
	}
	a.columnCacheMu <- struct{}{}

	rows, err := a.fetchAll("SHOW COLUMNS FROM `" + table + "`")
	columns := map[string]bool{}
	if err == nil {
		for _, row := range rows {
			field := str(row, "Field")
			if field != "" {
				columns[field] = true
			}
		}
	}

	<-a.columnCacheMu
	a.columnCache[table] = columns
	a.columnCacheMu <- struct{}{}
	return columns
}

func (a *App) hasColumn(table, column string) bool {
	return a.tableColumns(table)[column]
}

func (a *App) clearColumns(table string) {
	<-a.columnCacheMu
	delete(a.columnCache, table)
	a.columnCacheMu <- struct{}{}
}

func (a *App) insertRow(table string, data map[string]any) (int64, error) {
	return a.insertRowWith(a.db, table, data, false)
}

func (a *App) insertIgnoreRow(table string, data map[string]any) (int64, error) {
	return a.insertRowWith(a.db, table, data, true)
}

func (a *App) insertRowTx(tx *sql.Tx, table string, data map[string]any) (int64, error) {
	return a.insertRowWith(tx, table, data, false)
}

func (a *App) insertIgnoreRowTx(tx *sql.Tx, table string, data map[string]any) (int64, error) {
	return a.insertRowWith(tx, table, data, true)
}

func (a *App) insertRowWith(q sqlRunner, table string, data map[string]any, ignore bool) (int64, error) {
	if !safeIdent.MatchString(table) {
		return 0, fmt.Errorf("invalid table %q", table)
	}
	filtered := a.filterData(table, data)
	if len(filtered) == 0 {
		return 0, fmt.Errorf("no valid columns for insert: %s", table)
	}
	names := sortedKeys(filtered)
	placeholders := make([]string, len(names))
	args := make([]any, len(names))
	for i, name := range names {
		placeholders[i] = "?"
		args[i] = filtered[name]
	}
	verb := "INSERT INTO"
	if ignore {
		verb = "INSERT IGNORE INTO"
	}
	query := verb + " `" + table + "` (`" + strings.Join(names, "`, `") + "`) VALUES (" + strings.Join(placeholders, ", ") + ")"
	res, err := q.Exec(query, args...)
	if err != nil {
		return 0, err
	}
	if ignore {
		affected, _ := res.RowsAffected()
		return affected, nil
	}
	id, _ := res.LastInsertId()
	return id, nil
}

func (a *App) updateRow(table string, data map[string]any, where string, whereArgs ...any) (int64, error) {
	return a.updateRowWith(a.db, table, data, where, whereArgs...)
}

func (a *App) updateRowTx(tx *sql.Tx, table string, data map[string]any, where string, whereArgs ...any) (int64, error) {
	return a.updateRowWith(tx, table, data, where, whereArgs...)
}

func (a *App) updateRowWith(q sqlRunner, table string, data map[string]any, where string, whereArgs ...any) (int64, error) {
	if !safeIdent.MatchString(table) {
		return 0, fmt.Errorf("invalid table %q", table)
	}
	filtered := a.filterData(table, data)
	if len(filtered) == 0 {
		return 0, nil
	}
	names := sortedKeys(filtered)
	sets := make([]string, len(names))
	args := make([]any, 0, len(names)+len(whereArgs))
	for i, name := range names {
		sets[i] = "`" + name + "` = ?"
		args = append(args, filtered[name])
	}
	args = append(args, whereArgs...)
	res, err := q.Exec("UPDATE `"+table+"` SET "+strings.Join(sets, ", ")+" WHERE "+where, args...)
	if err != nil {
		return 0, err
	}
	affected, _ := res.RowsAffected()
	return affected, nil
}

func (a *App) filterData(table string, data map[string]any) map[string]any {
	columns := a.tableColumns(table)
	filtered := map[string]any{}
	for key, value := range data {
		if safeIdent.MatchString(key) && columns[key] {
			filtered[key] = value
		}
	}
	return filtered
}

func sortedKeys(m map[string]any) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func (a *App) ensureSchema() {
	a.ensureTable("csac_sessions", `CREATE TABLE IF NOT EXISTS csac_sessions (
        sid VARCHAR(128) NOT NULL PRIMARY KEY,
        uid BIGINT NOT NULL DEFAULT 0,
        nickname VARCHAR(255) NOT NULL DEFAULT '',
        platform VARCHAR(100) NOT NULL DEFAULT '',
        sx TINYINT(1) NOT NULL DEFAULT 0,
        se BIGINT NOT NULL DEFAULT 0,
        last_touch BIGINT NOT NULL DEFAULT 0,
        expires_at BIGINT NOT NULL,
        updated_at BIGINT NOT NULL,
        INDEX idx_csac_sessions_expires (expires_at),
        INDEX idx_csac_sessions_uid (uid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`)
	a.ensureTable("register_email_codes", `CREATE TABLE IF NOT EXISTS register_email_codes (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        email VARCHAR(255) NOT NULL,
        code_hash VARCHAR(255) NOT NULL,
        ip_hash CHAR(64) NOT NULL DEFAULT '',
        attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
        used_at INT NOT NULL DEFAULT 0,
        expires_at INT NOT NULL,
        created_at INT NOT NULL,
        PRIMARY KEY (id),
        INDEX idx_csac_register_email_created (email, created_at),
        INDEX idx_csac_register_ip_created (ip_hash, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`)

	columns := []struct{ table, column, def string }{
		{"chat_user", "allow_auto_join", "TINYINT(1) NOT NULL DEFAULT 1"},
		{"chat_user", "pat_action", "VARCHAR(32) NOT NULL DEFAULT '拍了拍'"},
		{"chat_user", "platform", "VARCHAR(100) NOT NULL DEFAULT 'none'"},
		{"chat_user", "email", "VARCHAR(255) NULL DEFAULT NULL"},
		{"chat_room", "avatar", "VARCHAR(255) NOT NULL DEFAULT ''"},
		{"chat_room", "is_disband", "TINYINT(1) NOT NULL DEFAULT 0"},
		{"chat_room", "disband_time", "INT NOT NULL DEFAULT 0"},
		{"chat_msg", "msg_type", "TINYINT NOT NULL DEFAULT 1"},
		{"chat_msg", "voice_duration", "INT NOT NULL DEFAULT 0"},
		{"chat_msg", "reply_to", "INT NULL DEFAULT NULL"},
		{"chat_msg", "mention_uids", "VARCHAR(255) NOT NULL DEFAULT ''"},
		{"chat_msg", "was_replied", "TINYINT NOT NULL DEFAULT 0"},
		{"private_msg", "reply_to", "INT NULL DEFAULT NULL"},
		{"chat_group_user", "mute_until", "INT NOT NULL DEFAULT 0"},
		{"chat_group_user", "last_read_msg_id", "INT NOT NULL DEFAULT 0"},
		{"chat_group_user", "title", "VARCHAR(32) NOT NULL DEFAULT '青铜'"},
		{"chat_group_user", "level", "INT NOT NULL DEFAULT 1"},
		{"chat_group_user", "title_custom", "TINYINT(1) NOT NULL DEFAULT 0"},
		{"chat_group_user", "level_custom", "TINYINT(1) NOT NULL DEFAULT 0"},
	}
	for _, col := range columns {
		a.ensureColumn(col.table, col.column, col.def)
	}
	a.ensureUTF8MB4()
	_, _ = a.exec("DELETE FROM csac_sessions WHERE expires_at < ?", time.Now().Unix())
}

func (a *App) ensureUTF8MB4() {
	for _, table := range []string{"chat_msg", "private_msg", "chat_user_notice", "chat_room", "chat_user", "emoji_list"} {
		if !safeIdent.MatchString(table) || len(a.tableColumns(table)) == 0 {
			continue
		}
		if _, err := a.db.Exec("ALTER TABLE `" + table + "` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"); err != nil {
			log.Printf("convert table %s to utf8mb4 failed: %v", table, err)
			continue
		}
		a.clearColumns(table)
	}
	for _, item := range []struct{ table, column string }{
		{"chat_msg", "content"},
		{"chat_msg", "nickname"},
		{"private_msg", "content"},
		{"chat_user_notice", "title"},
		{"chat_user_notice", "content"},
	} {
		if !a.hasColumn(item.table, item.column) {
			continue
		}
		col, err := a.fetchOne("SHOW COLUMNS FROM `"+item.table+"` WHERE Field = ?", item.column)
		if err != nil || col == nil {
			continue
		}
		colType := str(col, "Type")
		if colType == "" {
			continue
		}
		if _, err := a.db.Exec("ALTER TABLE `" + item.table + "` MODIFY `" + item.column + "` " + colType + " CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"); err != nil {
			log.Printf("convert column %s.%s to utf8mb4 failed: %v", item.table, item.column, err)
		}
	}
}

func (a *App) ensureTable(table, ddl string) {
	if _, err := a.db.Exec(ddl); err != nil {
		log.Printf("ensure table %s failed: %v", table, err)
		return
	}
	a.clearColumns(table)
}

func (a *App) ensureColumn(table, column, definition string) {
	if !safeIdent.MatchString(table) || !safeIdent.MatchString(column) {
		return
	}
	if a.hasColumn(table, column) {
		return
	}
	if _, err := a.db.Exec("ALTER TABLE `" + table + "` ADD COLUMN `" + column + "` " + definition); err != nil {
		log.Printf("ensure column %s.%s failed: %v", table, column, err)
		return
	}
	a.clearColumns(table)
}

func selectColumns(a *App, table, columns string) string {
	columns = strings.TrimSpace(columns)
	if columns == "" || columns == "*" {
		return "*"
	}
	available := a.tableColumns(table)
	parts := []string{}
	for _, col := range strings.Split(columns, ",") {
		name := strings.TrimSpace(col)
		if safeIdent.MatchString(name) && available[name] {
			parts = append(parts, "`"+name+"`")
		}
	}
	if len(parts) == 0 {
		return "*"
	}
	return strings.Join(parts, ", ")
}

func str(row Row, key string) string {
	if row == nil {
		return ""
	}
	return toString(row[key])
}

func strDefault(row Row, key, fallback string) string {
	value := str(row, key)
	if value == "" {
		return fallback
	}
	return value
}

func intval(row Row, key string) int64 {
	if row == nil {
		return 0
	}
	return toInt64Default(row[key], 0)
}

func boolval(row Row, key string) bool {
	return intval(row, key) != 0
}
