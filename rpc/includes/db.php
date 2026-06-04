<?php
declare(strict_types=1);

function csac_db(): mysqli
{
    global $conn;
    if ($conn instanceof mysqli) {
        return $conn;
    }
    if (!class_exists('mysqli') || !function_exists('mysqli_report')) {
        throw new RuntimeException('PHP mysqli 扩展未启用');
    }
    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
    $conn = new mysqli(CSAC_DB_HOST, CSAC_DB_USER, CSAC_DB_PASS, CSAC_DB_NAME);
    $conn->set_charset('utf8mb4');
    csac_ensure_schema();
    return $conn;
}

function csac_ensure_schema(): void
{
    static $ensured = false;
    if ($ensured) {
        return;
    }
    $ensured = true;

    if (csac_schema_marker_valid()) {
        return;
    }

    $ok = true;
    $ok = csac_ensure_column('chat_user', 'allow_auto_join', 'TINYINT(1) NOT NULL DEFAULT 1') && $ok;
    $ok = csac_ensure_column('chat_user', 'pat_action', "VARCHAR(32) NOT NULL DEFAULT '拍了拍'") && $ok;
    $ok = csac_ensure_column('chat_user', 'platform', "VARCHAR(100) NOT NULL DEFAULT 'none'") && $ok;
    $ok = csac_ensure_column('chat_user', 'email', 'VARCHAR(255) NULL DEFAULT NULL') && $ok;
    $ok = csac_ensure_column('chat_room', 'avatar', "VARCHAR(255) NOT NULL DEFAULT ''") && $ok;
    $ok = csac_ensure_column('chat_room', 'is_disband', 'TINYINT(1) NOT NULL DEFAULT 0') && $ok;
    $ok = csac_ensure_column('chat_room', 'disband_time', 'INT NOT NULL DEFAULT 0') && $ok;
    $ok = csac_ensure_column('chat_msg', 'msg_type', 'TINYINT NOT NULL DEFAULT 1') && $ok;
    $ok = csac_ensure_column('chat_msg', 'voice_duration', 'INT NOT NULL DEFAULT 0') && $ok;
    $ok = csac_ensure_column('chat_msg', 'reply_to', 'INT NULL DEFAULT NULL') && $ok;
    $ok = csac_ensure_column('chat_msg', 'mention_uids', "VARCHAR(255) NOT NULL DEFAULT ''") && $ok;
    $ok = csac_ensure_column('chat_msg', 'was_replied', 'TINYINT NOT NULL DEFAULT 0') && $ok;
    $ok = csac_ensure_column('private_msg', 'reply_to', 'INT NULL DEFAULT NULL') && $ok;
    $ok = csac_ensure_column('chat_group_user', 'mute_until', 'INT NOT NULL DEFAULT 0') && $ok;
    $ok = csac_ensure_column('chat_group_user', 'last_read_msg_id', 'INT NOT NULL DEFAULT 0') && $ok;
    $ok = csac_ensure_column('chat_group_user', 'title', "VARCHAR(32) NOT NULL DEFAULT '青铜'") && $ok;
    $ok = csac_ensure_column('chat_group_user', 'level', 'INT NOT NULL DEFAULT 1') && $ok;
    $ok = csac_ensure_column_type('chat_group_user', 'level', 'int') && $ok;
    $ok = csac_ensure_column('chat_group_user', 'title_custom', 'TINYINT(1) NOT NULL DEFAULT 0') && $ok;
    $ok = csac_ensure_column('chat_group_user', 'level_custom', 'TINYINT(1) NOT NULL DEFAULT 0') && $ok;

    csac_ensure_index('chat_msg', 'idx_csac_chat_msg_room_id_id', ['room_id', 'id']);
    csac_ensure_index('chat_msg', 'idx_csac_chat_msg_room_uid_time', ['room_id', 'uid', 'add_time']);
    csac_ensure_index('chat_msg', 'idx_csac_chat_msg_reply_to', ['reply_to']);
    csac_ensure_index('private_msg', 'idx_csac_private_msg_read', ['to_uid', 'is_read', 'type', 'from_uid']);
    csac_ensure_index('private_msg', 'idx_csac_private_msg_from_pair', ['from_uid', 'to_uid', 'type', 'id']);
    csac_ensure_index('private_msg', 'idx_csac_private_msg_to_pair', ['to_uid', 'from_uid', 'type', 'id']);
    csac_ensure_index('chat_user_notice', 'idx_csac_notice_uid_read_time', ['uid', 'is_read', 'add_time']);
    csac_ensure_index('friend_request', 'idx_csac_friend_req_to_status', ['to_uid', 'status', 'from_uid']);
    csac_ensure_index('friend_request', 'idx_csac_friend_req_from_to_status', ['from_uid', 'to_uid', 'status']);
    csac_ensure_index('chat_group_user', 'idx_csac_group_user_uid_room', ['uid', 'room_id']);
    csac_ensure_index('chat_group_user', 'idx_csac_group_user_room_uid_read', ['room_id', 'uid', 'last_read_msg_id']);
    csac_ensure_index('friend_relation', 'idx_csac_friend_rel_uid1_status', ['uid1', 'status']);
    csac_ensure_index('friend_relation', 'idx_csac_friend_rel_uid2_status', ['uid2', 'status']);
    csac_ensure_index('chat_essence', 'idx_csac_essence_room_msg', ['room_id', 'msg_id']);
    csac_ensure_index('chat_group_admin', 'idx_csac_group_admin_room_uid', ['room_id', 'uid']);
    csac_ensure_index('admin_tokens', 'idx_csac_admin_tokens_token_expiry', ['token', 'expires_at', 'used']);
    csac_ensure_table(
        'register_email_codes',
        "CREATE TABLE IF NOT EXISTS `register_email_codes` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `email` VARCHAR(255) NOT NULL,
            `code_hash` VARCHAR(255) NOT NULL,
            `ip_hash` CHAR(64) NOT NULL DEFAULT '',
            `attempts` TINYINT UNSIGNED NOT NULL DEFAULT 0,
            `used_at` INT NOT NULL DEFAULT 0,
            `expires_at` INT NOT NULL,
            `created_at` INT NOT NULL,
            PRIMARY KEY (`id`),
            INDEX `idx_csac_register_email_created` (`email`, `created_at`),
            INDEX `idx_csac_register_ip_created` (`ip_hash`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );
    csac_ensure_unique_index('chat_user', 'uniq_csac_chat_user_email', ['email']);

    if ($ok) {
        csac_touch_schema_marker();
    }
}

function csac_ensure_table(string $table, string $sql): bool
{
    if (!preg_match('/^[A-Za-z0-9_]+$/', $table)) {
        return false;
    }
    try {
        csac_db()->query($sql);
        unset($GLOBALS['CSAC_TABLE_COLUMNS'][$table]);
        return true;
    } catch (Throwable $e) {
        csac_log_error($e);
        return false;
    }
}

function csac_ensure_unique_index(string $table, string $indexName, array $columns): bool
{
    if (!preg_match('/^[A-Za-z0-9_]+$/', $table) || !preg_match('/^[A-Za-z0-9_]+$/', $indexName) || !$columns) {
        return true;
    }
    foreach ($columns as $column) {
        if (!is_string($column) || !preg_match('/^[A-Za-z0-9_]+$/', $column) || !csac_has_column($table, $column)) {
            return true;
        }
    }
    $safeTable = str_replace('`', '', $table);
    $existing = csac_fetch_one('SHOW INDEX FROM `' . $safeTable . '` WHERE Key_name = ?', 's', $indexName);
    if ($existing) {
        return true;
    }
    try {
        csac_db()->query('ALTER TABLE `' . $safeTable . '` ADD UNIQUE INDEX `' . $indexName . '` (`' . implode('`, `', $columns) . '`)');
    } catch (Throwable $e) {
        csac_log_error($e);
    }
    return true;
}

function csac_schema_marker_path(): string
{
    return sys_get_temp_dir() . '/csac_schema_' . md5(CSAC_DB_HOST . '|' . CSAC_DB_NAME . '|' . __FILE__) . '.json';
}

function csac_schema_marker_valid(): bool
{
    $path = csac_schema_marker_path();
    if (!is_file($path)) {
        return false;
    }
    $raw = @file_get_contents($path);
    if (!is_string($raw) || $raw === '') {
        return false;
    }
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        return false;
    }
    $fileMtime = (int)(@filemtime(__FILE__) ?: 0);
    return (int)($data['version'] ?? 0) === CSAC_SCHEMA_VERSION
        && (int)($data['file_mtime'] ?? 0) === $fileMtime
        && (int)($data['checked_at'] ?? 0) > time() - CSAC_SCHEMA_CHECK_TTL;
}

function csac_touch_schema_marker(): void
{
    @file_put_contents(csac_schema_marker_path(), json_encode([
        'version' => CSAC_SCHEMA_VERSION,
        'file_mtime' => (int)(@filemtime(__FILE__) ?: 0),
        'checked_at' => time(),
    ], JSON_UNESCAPED_SLASHES), LOCK_EX);
}

function csac_ensure_column_type(string $table, string $column, string $typePrefix): bool
{
    $safeTable = str_replace('`', '', $table);
    $safeColumn = str_replace('`', '', $column);
    $row = csac_fetch_one('SHOW COLUMNS FROM `' . $safeTable . '` WHERE Field = ?', 's', $safeColumn);
    $type = strtolower((string)($row['Type'] ?? ''));
    if ($type === '' || str_starts_with($type, strtolower($typePrefix))) {
        return true;
    }
    try {
        csac_db()->query("ALTER TABLE `{$safeTable}` MODIFY COLUMN `{$safeColumn}` INT NOT NULL DEFAULT 1");
        unset($GLOBALS['CSAC_TABLE_COLUMNS'][$table]);
        return true;
    } catch (Throwable $e) {
        csac_log_error($e);
        return false;
    }
}

function csac_ensure_column(string $table, string $column, string $definition): bool
{
    global $CSAC_TABLE_COLUMNS;
    if (csac_has_column($table, $column)) {
        return true;
    }
    $safeTable = str_replace('`', '', $table);
    $safeColumn = str_replace('`', '', $column);
    try {
        csac_db()->query("ALTER TABLE `{$safeTable}` ADD COLUMN `{$safeColumn}` {$definition}");
        unset($CSAC_TABLE_COLUMNS[$table]);
        return true;
    } catch (Throwable $e) {
        unset($CSAC_TABLE_COLUMNS[$table]);
        csac_log_error($e);
        return false;
    }
}

function csac_ensure_index(string $table, string $indexName, array $columns): bool
{
    if (!preg_match('/^[A-Za-z0-9_]+$/', $table) || !preg_match('/^[A-Za-z0-9_]+$/', $indexName) || !$columns) {
        return true;
    }
    foreach ($columns as $column) {
        if (!is_string($column) || !preg_match('/^[A-Za-z0-9_]+$/', $column) || !csac_has_column($table, $column)) {
            return true;
        }
    }
    $safeTable = str_replace('`', '', $table);
    $existing = csac_fetch_one('SHOW INDEX FROM `' . $safeTable . '` WHERE Key_name = ?', 's', $indexName);
    if ($existing || csac_has_index_for_columns($table, $columns)) {
        return true;
    }
    try {
        csac_db()->query('ALTER TABLE `' . $safeTable . '` ADD INDEX `' . $indexName . '` (`' . implode('`, `', $columns) . '`)');
    } catch (Throwable $e) {
        csac_log_error($e);
    }
    return true;
}

function csac_has_index_for_columns(string $table, array $columns): bool
{
    $safeTable = str_replace('`', '', $table);
    $rows = csac_fetch_all('SHOW INDEX FROM `' . $safeTable . '`');
    $indexes = [];
    foreach ($rows as $row) {
        $name = (string)($row['Key_name'] ?? '');
        $seq = (int)($row['Seq_in_index'] ?? 0);
        $column = (string)($row['Column_name'] ?? '');
        if ($name === '' || $seq <= 0 || $column === '') {
            continue;
        }
        $indexes[$name][$seq] = $column;
    }
    foreach ($indexes as $indexColumns) {
        ksort($indexColumns);
        $ordered = array_values($indexColumns);
        if (array_slice($ordered, 0, count($columns)) === array_values($columns)) {
            return true;
        }
    }
    return false;
}


function csac_query(string $sql, string $types = '', ...$params): mysqli_stmt
{
    $stmt = csac_db()->prepare($sql);
    if ($types !== '') {
        $stmt->bind_param($types, ...$params);
    }
    $stmt->execute();
    return $stmt;
}

function csac_fetch_one(string $sql, string $types = '', ...$params): ?array
{
    $stmt = csac_query($sql, $types, ...$params);
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();
    return $row ?: null;
}

function csac_fetch_all(string $sql, string $types = '', ...$params): array
{
    $stmt = csac_query($sql, $types, ...$params);
    $result = $stmt->get_result();
    $rows = [];
    while ($row = $result->fetch_assoc()) {
        $rows[] = $row;
    }
    $stmt->close();
    return $rows;
}

function csac_execute(string $sql, string $types = '', ...$params): int
{
    $stmt = csac_query($sql, $types, ...$params);
    $affected = $stmt->affected_rows;
    $stmt->close();
    return $affected;
}

function csac_insert_id(): int
{
    return (int)csac_db()->insert_id;
}

function csac_begin(): void
{
    csac_db()->begin_transaction();
}

function csac_commit(): void
{
    csac_db()->commit();
}

function csac_rollback(): void
{
    csac_db()->rollback();
}

function csac_table_columns(string $table): array
{
    global $CSAC_TABLE_COLUMNS;
    if (isset($CSAC_TABLE_COLUMNS[$table])) {
        return $CSAC_TABLE_COLUMNS[$table];
    }
    try {
        $rows = csac_fetch_all('SHOW COLUMNS FROM `' . str_replace('`', '', $table) . '`');
        $CSAC_TABLE_COLUMNS[$table] = array_fill_keys(array_column($rows, 'Field'), true);
    } catch (Throwable) {
        $CSAC_TABLE_COLUMNS[$table] = [];
    }
    return $CSAC_TABLE_COLUMNS[$table];
}

function csac_has_column(string $table, string $column): bool
{
    $columns = csac_table_columns($table);
    return isset($columns[$column]);
}

function csac_insert_row(string $table, array $data): int
{
    $columns = csac_table_columns($table);
    $filtered = [];
    foreach ($data as $key => $value) {
        if (isset($columns[$key])) {
            $filtered[$key] = $value;
        }
    }
    if (!$filtered) {
        throw new RuntimeException('No valid columns for insert: ' . $table);
    }

    $names = array_keys($filtered);
    $placeholders = implode(', ', array_fill(0, count($names), '?'));
    $sql = 'INSERT INTO `' . str_replace('`', '', $table) . '` (`' . implode('`, `', $names) . '`) VALUES (' . $placeholders . ')';
    csac_query_dynamic($sql, array_values($filtered))->close();
    return csac_insert_id();
}

function csac_insert_ignore_row(string $table, array $data): int
{
    $columns = csac_table_columns($table);
    $filtered = [];
    foreach ($data as $key => $value) {
        if (isset($columns[$key])) {
            $filtered[$key] = $value;
        }
    }
    if (!$filtered) {
        throw new RuntimeException('No valid columns for insert: ' . $table);
    }

    $names = array_keys($filtered);
    $placeholders = implode(', ', array_fill(0, count($names), '?'));
    $sql = 'INSERT IGNORE INTO `' . str_replace('`', '', $table) . '` (`' . implode('`, `', $names) . '`) VALUES (' . $placeholders . ')';
    $stmt = csac_query_dynamic($sql, array_values($filtered));
    $affected = $stmt->affected_rows;
    $stmt->close();
    return $affected;
}

function csac_update_row(string $table, array $data, string $where, array $whereParams = []): int
{
    $columns = csac_table_columns($table);
    $filtered = [];
    foreach ($data as $key => $value) {
        if (isset($columns[$key])) {
            $filtered[$key] = $value;
        }
    }
    if (!$filtered) {
        return 0;
    }

    $sets = [];
    foreach (array_keys($filtered) as $name) {
        $sets[] = '`' . $name . '` = ?';
    }
    $sql = 'UPDATE `' . str_replace('`', '', $table) . '` SET ' . implode(', ', $sets) . ' WHERE ' . $where;
    $stmt = csac_query_dynamic($sql, array_merge(array_values($filtered), $whereParams));
    $affected = $stmt->affected_rows;
    $stmt->close();
    return $affected;
}

function csac_query_dynamic(string $sql, array $params = []): mysqli_stmt
{
    $stmt = csac_db()->prepare($sql);
    if ($params) {
        $types = '';
        foreach ($params as $value) {
            if (is_int($value)) {
                $types .= 'i';
            } elseif (is_float($value)) {
                $types .= 'd';
            } else {
                $types .= 's';
            }
        }
        $stmt->bind_param($types, ...$params);
    }
    $stmt->execute();
    return $stmt;
}
