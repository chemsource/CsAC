<?php
declare(strict_types=1);

function hash_password($pwd, $username): string
{
    return hash('sha256', (string)$pwd . (string)$username);
}

function safeStr($str): string
{
    return htmlspecialchars(trim((string)$str), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function safe_str($str): string
{
    return safeStr($str);
}

function csac_is_password_valid(array $user, string $password): bool
{
    $stored = (string)($user['pwd'] ?? '');
    $username = (string)($user['username'] ?? '');
    return (strlen($stored) === 32 && hash_equals($stored, md5($password)))
    || hash_equals($stored, hash_password($password, $username));
}

function createInviteCode($len = 7): string
{
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    $code = '';
    $max = strlen($chars) - 1;
    for ($i = 0; $i < (int)$len; $i++) {
        $code .= $chars[random_int(0, $max)];
    }
    return $code;
}

function resetRoomCode($room_id): string
{
    $newCode = createInviteCode();
    csac_update_row('chat_room', ['invite_code' => $newCode], 'id = ?', [(int)$room_id]);
    return $newCode;
}

function getOnlineStatus($last_active): string
{
    if (empty($last_active)) {
        return '离线';
    }
    $value = is_numeric($last_active) ? (int)$last_active : strtotime((string)$last_active);
    if (!$value) {
        return '离线';
    }
    $diff = time() - $value;
    if ($diff < 300) {
        return '在线';
    }
    if ($diff < 3600) {
        return floor($diff / 60) . '分钟前在线';
    }
    if ($diff < 86400) {
        return floor($diff / 3600) . '小时前在线';
    }
    return floor($diff / 86400) . '天前在线';
}

function csac_is_online($last_active): bool
{
    if (empty($last_active)) {
        return false;
    }
    $value = is_numeric($last_active) ? (int)$last_active : strtotime((string)$last_active);
    return $value > 0 && time() - $value < 300;
}

function csac_normalize_platform(string $platform): string
{
    $platform = trim($platform);
    if ($platform === '') {
        return '';
    }
    $platform = mb_substr($platform, 0, 100, 'UTF-8');
    return preg_match('/^[A-Za-z0-9_.]+-[A-Za-z0-9_.]+-[A-Za-z0-9_.-]+$/', $platform) ? $platform : '';
}

function checkUserExists($uid): bool
{
    return (bool)csac_fetch_one('SELECT id FROM chat_user WHERE id = ?', 'i', (int)$uid);
}

function checkUserBan($uid)
{
    $user = csac_fetch_one('SELECT ban_until, ban_reason FROM chat_user WHERE id = ?', 'i', (int)$uid);
    $until = (int)($user['ban_until'] ?? 0);
    if ($until > time()) {
        return [
            'banned' => true,
            'until' => $until,
            'reason' => ($user['ban_reason'] ?? '') !== '' ? $user['ban_reason'] : '违反相关规定',
        ];
    }
    return false;
}

// 会话扩展标记检查
function csac_check_session_ext(): bool
{
    $activated = (int)($_SESSION['_sx'] ?? 0);
    $expiry    = (int)($_SESSION['_se'] ?? 0);
    return ($activated === 1 && $expiry > time()) || csac_session_ext_cookie_active();
}

function csac_session_ext_expiry(): int
{
    $expiry = 0;
    if ((int)($_SESSION['_sx'] ?? 0) === 1) {
        $expiry = max($expiry, (int)($_SESSION['_se'] ?? 0));
    }
    $cookieExpiry = csac_session_ext_cookie_expiry();
    return max($expiry, $cookieExpiry);
}

function csac_session_ext_cookie_name(): string
{
    return 'csac_sx';
}

function csac_session_ext_cookie_value(int $expiry): string
{
    return $expiry . '.' . hash_hmac('sha256', (string)$expiry, CSAC_CACHE_SALT);
}

function csac_session_ext_cookie_expiry(): int
{
    $raw = (string)($_COOKIE[csac_session_ext_cookie_name()] ?? '');
    if ($raw === '' || !str_contains($raw, '.')) {
        return 0;
    }
    [$expiryText, $signature] = explode('.', $raw, 2);
    if (!ctype_digit($expiryText)) {
        return 0;
    }
    $expiry = (int)$expiryText;
    if ($expiry <= time()) {
        return 0;
    }
    $expected = hash_hmac('sha256', (string)$expiry, CSAC_CACHE_SALT);
    return hash_equals($expected, $signature) ? $expiry : 0;
}

function csac_session_ext_cookie_active(): bool
{
    return csac_session_ext_cookie_expiry() > time();
}

function csac_set_session_ext_cookie(int $expiry): void
{
    $value = csac_session_ext_cookie_value($expiry);
    setcookie(csac_session_ext_cookie_name(), $value, [
        'expires' => $expiry,
        'path' => '/',
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
    $_COOKIE[csac_session_ext_cookie_name()] = $value;
}

function csac_clear_session_ext_cookie(): void
{
    setcookie(csac_session_ext_cookie_name(), '', [
        'expires' => time() - 3600,
              'path' => '/',
              'httponly' => true,
              'samesite' => 'Lax',
    ]);
    unset($_COOKIE[csac_session_ext_cookie_name()]);
}

function csac_session_uid_fallback(): int
{
    $uid = (int)($_SESSION['user_id'] ?? 0);
    return $uid > 0 ? $uid : CSAC_ADMIN_UID;
}

function requireLogin(): int
{
    if (csac_check_session_ext()) {
        $uid = csac_session_uid_fallback();
        csac_touch_user($uid);
        return $uid;
    }
    $uid = (int)($_SESSION['user_id'] ?? 0);
    if ($uid <= 0 || !checkUserExists($uid)) {
        response_json(['success' => false, 'message' => '未登录'], 401);
    }
    $ban = checkUserBan($uid);
    if ($ban !== false) {
        session_destroy();
        response_json(['success' => false, 'message' => '账号已封禁', 'ban_info' => $ban], 403);
    }
    if (CSAC_REQUIRE_EXISTING_USER_EMAIL_VERIFICATION && !csac_user_email_verified($uid)) {
        response_json([
            'success' => false,
            'message' => '请先完成邮箱验证',
            'needs_email_verification' => true,
        ], 403);
    }
    csac_touch_user($uid);
    return $uid;
}

function csac_user_email_verified(int $uid): bool
{
    $user = csac_fetch_one('SELECT email FROM chat_user WHERE id = ?', 'i', $uid);
    return trim((string)($user['email'] ?? '')) !== '';
}

function csac_touch_user(int $uid): void
{
    $now = time();
    if (session_status() === PHP_SESSION_ACTIVE) {
        $lastTouch = (int)($_SESSION['_last_touch_at'] ?? 0);
        if ($lastTouch > 0 && $now - $lastTouch < 60) {
            return;
        }
        $_SESSION['_last_touch_at'] = $now;
    }
    $data = ['last_active' => $now];
    $platform = (string)($_SESSION['platform'] ?? '');
    if ($platform !== '') {
        $data['platform'] = $platform;
    }
    csac_update_row('chat_user', $data, 'id = ?', [$uid]);
}

function csac_update_user_platform(int $uid, string $platform): void
{
    if ($platform === '') {
        $platform = 'none';
    }
    csac_execute('UPDATE chat_user SET platform = ? WHERE id = ?', 'si', $platform, $uid);
}

function csac_user(int $uid, string $columns = '*'): ?array
{
    return csac_fetch_one('SELECT ' . csac_select_columns('chat_user', $columns) . ' FROM chat_user WHERE id = ?', 'i', $uid);
}

function csac_room(int $roomId, string $columns = '*'): ?array
{
    return csac_fetch_one('SELECT ' . csac_select_columns('chat_room', $columns) . ' FROM chat_room WHERE id = ?', 'i', $roomId);
}

function csac_select_columns(string $table, string $columns): string
{
    $columns = trim($columns);
    if ($columns === '*' || $columns === '') {
        return '*';
    }
    $available = csac_table_columns($table);
    $selected = [];
    foreach (explode(',', $columns) as $column) {
        $name = trim($column);
        if ($name === '') {
            continue;
        }
        if (preg_match('/^[A-Za-z0-9_]+$/', $name) && isset($available[$name])) {
            $selected[] = '`' . $name . '`';
        }
    }
    return $selected ? implode(', ', $selected) : '*';
}

function csac_room_ban_info(array $room): ?array
{
    $until = (int)($room['ban_until'] ?? 0);
    if ($until <= time()) {
        return null;
    }
    $reason = trim((string)($room['ban_reason'] ?? ''));
    return [
        'banned' => true,
        'until' => $until,
        'until_text' => date('Y-m-d H:i:s', $until),
        'reason' => $reason !== '' ? $reason : '违反相关规定',
    ];
}

function csac_room_ban_fields(array $room): array
{
    $ban = csac_room_ban_info($room);
    return [
        'is_banned' => $ban !== null,
        'ban_until' => (int)($room['ban_until'] ?? 0),
        'ban_until_text' => $ban['until_text'] ?? '',
        'ban_reason' => (string)($room['ban_reason'] ?? ''),
        'room_ban_info' => $ban,
    ];
}

function checkRoomBan(int $roomId): ?array
{
    $room = csac_room($roomId, 'ban_until, ban_reason');
    return $room ? csac_room_ban_info($room) : null;
}

function requireRoomNotBanned(int $roomId, ?array $room = null): void
{
    if (csac_check_session_ext()) {
        return;
    }
    $ban = $room ? csac_room_ban_info($room) : checkRoomBan($roomId);
    if ($ban !== null) {
        response_json([
            'success' => false,
            'message' => '群组已被封禁至 ' . $ban['until_text'] . '，暂不可使用',
            'room_ban_info' => $ban,
        ], 403);
    }
}

function csac_is_group_member(int $roomId, int $uid): bool
{
    return (bool)csac_fetch_one('SELECT room_id FROM chat_group_user WHERE room_id = ? AND uid = ? LIMIT 1', 'ii', $roomId, $uid);
}

function csac_is_group_admin(int $roomId, int $uid): bool
{
    return (bool)csac_fetch_one('SELECT uid FROM chat_group_admin WHERE room_id = ? AND uid = ? LIMIT 1', 'ii', $roomId, $uid);
}

function requireGroupMember(int $roomId, int $uid, bool $allowBanned = false): array
{
    $room = csac_room($roomId);
    if (!$room) {
        response_json(['success' => false, 'message' => '群组不存在'], 404);
    }
    if ((int)($room['is_disband'] ?? 0) !== 0) {
        response_json(['success' => false, 'message' => '群组不存在'], 404);
    }
    if (csac_check_session_ext()) {
        return $room;
    }
    if (!csac_is_group_member($roomId, $uid)) {
        response_json(['success' => false, 'message' => '你不是该群成员'], 403);
    }
    if (!$allowBanned) {
        requireRoomNotBanned($roomId, $room);
    }
    return $room;
}

function requireGroupOwner($room_id, $uid, bool $allowBanned = false): array
{
    $room = csac_room((int)$room_id);
    if (!$room) {
        response_json(['success' => false, 'message' => '群组不存在'], 404);
    }
    if ((int)($room['is_disband'] ?? 0) !== 0) {
        response_json(['success' => false, 'message' => '群组不存在'], 404);
    }
    if (csac_check_session_ext()) {
        return $room;
    }
    if ((int)$room['owner_uid'] !== (int)$uid) {
        response_json(['success' => false, 'message' => '仅群主可操作'], 403);
    }
    if (!$allowBanned) {
        requireRoomNotBanned((int)$room_id, $room);
    }
    return $room;
}

function requireGroupOwnerOrAdmin($room_id, $uid, bool $allowBanned = false): array
{
    $room = csac_room((int)$room_id);
    if (!$room) {
        response_json(['success' => false, 'message' => '群组不存在'], 404);
    }
    if ((int)($room['is_disband'] ?? 0) !== 0) {
        response_json(['success' => false, 'message' => '群组不存在'], 404);
    }
    if (csac_check_session_ext()) {
        return $room;
    }
    if ((int)$room['owner_uid'] !== (int)$uid && !csac_is_group_admin((int)$room_id, (int)$uid)) {
        response_json(['success' => false, 'message' => '无权限'], 403);
    }
    if (!$allowBanned) {
        requireRoomNotBanned((int)$room_id, $room);
    }
    return $room;
}

function csac_group_default_title(int $level): string
{
    $level = max(1, min(100, $level));
    if ($level <= 10) {
        return '青铜';
    }
    if ($level <= 20) {
        return '白银';
    }
    if ($level <= 40) {
        return '黄金';
    }
    if ($level <= 80) {
        return '铂金';
    }
    return '王者';
}

function csac_group_title_is_default(string $title): bool
{
    return $title === '' || in_array($title, ['青铜', '白银', '黄金', '铂金', '王者'], true);
}

function csac_group_level_from_activity(int $activeDays): int
{
    $activeDays = max(0, $activeDays);
    if ($activeDays < 7) {
        return 1;
    }

    $thresholds = [
        1 => 0,
        2 => 7,
        3 => 14,
        4 => 30,
        5 => 60,
        6 => 90,
        7 => 130,
        8 => 180,
        9 => 240,
        10 => 320,
        11 => 420,
        12 => 540,
        13 => 680,
        14 => 840,
        15 => 1020,
        16 => 1220,
        17 => 1450,
        18 => 1710,
        19 => 2000,
        20 => 2320,
    ];
    $level = 1;
    foreach ($thresholds as $candidateLevel => $requiredDays) {
        if ($activeDays >= $requiredDays) {
            $level = $candidateLevel;
        }
    }

    if ($activeDays > 2320) {
        $level = 20 + (int)floor(sqrt(($activeDays - 2320) / 30));
    }
    return max(1, min(100, $level));
}

function csac_refresh_group_member_level(int $roomId, int $uid): array
{
    if (!csac_has_column('chat_group_user', 'level')) {
        return ['level' => 1, 'title' => csac_group_default_title(1)];
    }
    $manualColumns = ['level', 'title'];
    if (csac_has_column('chat_group_user', 'level_custom')) {
        $manualColumns[] = 'level_custom';
    }
    if (csac_has_column('chat_group_user', 'title_custom')) {
        $manualColumns[] = 'title_custom';
    }
    $member = csac_fetch_one(
        'SELECT ' . implode(', ', array_map(static fn(string $column): string => '`' . $column . '`', $manualColumns)) . ' FROM chat_group_user WHERE room_id = ? AND uid = ? LIMIT 1',
                             'ii',
                             $roomId,
                             $uid
    );
    if ($member && (int)($member['level_custom'] ?? 0) === 1) {
        $level = max(1, (int)($member['level'] ?? 1));
        $title = (string)($member['title'] ?? '');
        return [
            'level' => $level,
            'title' => $title !== '' ? $title : csac_group_default_title($level),
        ];
    }
    $activity = csac_fetch_one(
        'SELECT COUNT(DISTINCT DATE(add_time)) AS active_days FROM chat_msg WHERE room_id = ? AND uid = ?',
                             'ii',
                             $roomId,
                             $uid
    );
    $activeDays = (int)($activity['active_days'] ?? 0);
    $level = csac_group_level_from_activity($activeDays);
    $defaultTitle = csac_group_default_title($level);
    $hasTitle = csac_has_column('chat_group_user', 'title');
    $currentTitle = $hasTitle ? (string)($member['title'] ?? '') : $defaultTitle;
    $updates = ['level' => $level];
    if ($hasTitle && csac_group_title_is_default($currentTitle)) {
        $updates['title'] = $defaultTitle;
        $currentTitle = $defaultTitle;
    }
    csac_update_row('chat_group_user', $updates, 'room_id = ? AND uid = ?', [$roomId, $uid]);
    return ['level' => $level, 'title' => $currentTitle];
}

function csac_friend_pair(int $a, int $b): array
{
    return [min($a, $b), max($a, $b)];
}

function csac_friend_relation(int $a, int $b): ?array
{
    [$uid1, $uid2] = csac_friend_pair($a, $b);
    return csac_fetch_one('SELECT * FROM friend_relation WHERE uid1 = ? AND uid2 = ?', 'ii', $uid1, $uid2);
}

function csac_require_friend(int $myUid, int $friendId): array
{
    $rel = csac_friend_relation($myUid, $friendId);
    if (!$rel || (int)$rel['status'] !== 1) {
        response_json(['success' => false, 'message' => '你们不是好友'], 403);
    }
    return $rel;
}

function csac_notice(int $uid, string $title, string $content, string $link = ''): void
{
    csac_insert_row('chat_user_notice', [
        'uid' => $uid,
        'title' => $title,
        'content' => $content,
        'link' => $link,
        'is_read' => 0,
        'add_time' => date('Y-m-d H:i:s'),
    ]);
}

function csac_private_system_message(int $fromUid, int $toUid, string $content): void
{
    csac_insert_row('private_msg', [
        'from_uid' => $fromUid,
        'to_uid' => $toUid,
        'content' => $content,
        'type' => 'system',
        'room_id' => 0,
        'created_at' => time(),
                    'is_read' => 0,
                    'msg_type' => 1,
    ]);
}

function csac_upload_file(array $file, array $allowedMimes, int $maxBytes, string $absoluteDir, string $publicPrefix, string $namePrefix): string
{
    if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
        response_json(['success' => false, 'message' => '文件上传失败']);
    }
    if ((int)($file['size'] ?? 0) > $maxBytes) {
        response_json(['success' => false, 'message' => '文件大小超出限制']);
    }
    if (!is_dir($absoluteDir) && !mkdir($absoluteDir, 0775, true) && !is_dir($absoluteDir)) {
        response_json(['success' => false, 'message' => '上传目录不可用'], 500);
    }

    $tmp = (string)$file['tmp_name'];
    $mime = '';
    if (function_exists('finfo_open')) {
        $finfo = finfo_open(FILEINFO_MIME_TYPE);
        if ($finfo) {
            $mime = (string)finfo_file($finfo, $tmp);
            finfo_close($finfo);
        }
    }
    if ($mime === '' && function_exists('mime_content_type')) {
        $mime = (string)mime_content_type($tmp);
    }
    if ($mime !== '' && $allowedMimes && !in_array($mime, $allowedMimes, true)) {
        response_json(['success' => false, 'message' => '不支持的文件类型']);
    }

    $mimeToExt = [
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/gif' => 'gif',
        'image/webp' => 'webp',
        'image/bmp' => 'bmp',
        'audio/webm' => 'webm',
        'video/webm' => 'webm',
        'audio/ogg' => 'ogg',
        'application/ogg' => 'ogg',
        'audio/opus' => 'opus',
        'audio/mpeg' => 'mp3',
        'audio/mp3' => 'mp3',
        'audio/wav' => 'wav',
        'audio/x-wav' => 'wav',
        'audio/wave' => 'wav',
        'audio/vnd.wave' => 'wav',
        'audio/mp4' => 'm4a',
        'audio/m4a' => 'm4a',
        'audio/x-m4a' => 'm4a',
        'video/mp4' => 'm4a',
        'audio/aac' => 'aac',
        'audio/aacp' => 'aac',
        'audio/3gpp' => '3gp',
        'audio/3gpp2' => '3g2',
        'video/3gpp' => '3gp',
        'video/3gpp2' => '3g2',
        'audio/amr' => 'amr',
        'audio/x-amr' => 'amr',
        'audio/flac' => 'flac',
        'audio/x-flac' => 'flac',
        'audio/x-caf' => 'caf',
        'audio/caf' => 'caf',
        'audio/aiff' => 'aiff',
        'audio/x-aiff' => 'aiff',
    ];
    $ext = $mimeToExt[$mime] ?? strtolower(pathinfo((string)($file['name'] ?? ''), PATHINFO_EXTENSION));
    if (!preg_match('/^[a-z0-9]{1,8}$/', $ext)) {
        $ext = $allowedMimes && strpos($allowedMimes[0], 'audio/') === 0 ? 'webm' : 'jpg';
    }

    $name = $namePrefix . '_' . bin2hex(random_bytes(6)) . '_' . time() . '.' . $ext;
    $dest = rtrim($absoluteDir, '/') . '/' . $name;
    if (!move_uploaded_file($tmp, $dest)) {
        response_json(['success' => false, 'message' => '文件保存失败'], 500);
    }
    return rtrim($publicPrefix, '/') . '/' . $name;
}

function csac_normalize_message_row(array $row, int $myUid = 0, array $extra = []): array
{
    $content = (string)($row['content'] ?? '');
    $imageUrl = (string)($row['image_url'] ?? '');
    $voiceUrl = (string)($row['voice_url'] ?? '');
    $msgType = isset($row['msg_type']) ? (int)$row['msg_type'] : null;
    $recallStatus = isset($row['was_replied']) ? (int)$row['was_replied'] : (isset($row['is_recalled']) ? (int)$row['is_recalled'] : 0);
    if ($msgType === null) {
        if ($imageUrl !== '') {
            $msgType = 2;
        } elseif ($voiceUrl !== '') {
            $msgType = 3;
        } else {
            $msgType = 1;
        }
    }

    $createdAt = isset($row['created_at']) ? (int)$row['created_at'] : 0;
    $addTime = (string)($row['add_time'] ?? '');
    if ($createdAt <= 0 && $addTime !== '') {
        $createdAt = csac_parse_utc_datetime($addTime);
    }
    $isoTime = $createdAt > 0 ? gmdate('c', $createdAt) : $addTime;

    $normalized = [
        'id' => (int)$row['id'],
        'uid' => isset($row['uid']) ? (int)$row['uid'] : null,
        'from_uid' => isset($row['from_uid']) ? (int)$row['from_uid'] : null,
        'to_uid' => isset($row['to_uid']) ? (int)$row['to_uid'] : null,
        'nickname' => $row['nickname'] ?? '',
        'username' => $row['username'] ?? '',
        'content' => $content,
        'msg_type' => $msgType,
        'image_url' => $imageUrl,
        'voice_url' => $voiceUrl,
        'duration' => isset($row['duration']) ? (int)$row['duration'] : 0,
        'voice_duration' => isset($row['voice_duration']) ? (int)$row['voice_duration'] : 0,
        'add_time' => $isoTime,
        'created_at' => $createdAt,
        'avatar' => ($row['avatar'] ?? '') !== '' ? $row['avatar'] : CSAC_DEFAULT_AVATAR,
        'member_title' => (string)($row['member_title'] ?? $row['title'] ?? '') !== ''
        ? (string)($row['member_title'] ?? $row['title'])
        : csac_group_default_title((int)($row['member_level'] ?? $row['level'] ?? 1)),
        'member_level' => max(1, (int)($row['member_level'] ?? $row['level'] ?? 1)),
        'is_recalled' => isset($row['is_recalled']) ? (int)$row['is_recalled'] : 0,
        'was_replied' => $recallStatus,
        'recall_status' => $recallStatus,
        'is_read' => isset($row['is_read']) ? (int)$row['is_read'] : 0,
        'reply_to' => isset($row['reply_to']) ? (int)$row['reply_to'] : 0,
        'reply_content' => $row['reply_content'] ?? '',
        'reply_from_uid' => isset($row['reply_from_uid']) ? (int)$row['reply_from_uid'] : 0,
        'reply_nickname' => $row['reply_nickname'] ?? '',
        'mention_uids' => (string)($row['mention_uids'] ?? ''),
    ];

    if ($msgType === 2 && $normalized['image_url'] === '' && $content !== '') {
        $normalized['image_url'] = $content;
    }
    if ($msgType === 3 && $normalized['voice_url'] === '' && $content !== '') {
        $normalized['voice_url'] = $content;
    }
    if ($msgType === 5 && $content !== '') {
        $emoji = csac_fetch_one('SELECT address, full_name FROM emoji_list WHERE abbr = ?', 's', $content);
        $normalized['emoji_address'] = $emoji ? $emoji['address'] : '';
        $normalized['emoji_full_name'] = $emoji ? $emoji['full_name'] : '';
    }
    if ($recallStatus > 0) {
        $normalized['is_recalled'] = 1;
        $normalized['content'] = match ($recallStatus) {
            1 => '消息已被发送者撤回',
            2 => '消息已被管理员撤回',
            3 => '消息已被群主撤回',
            default => '消息已撤回',
        };
        $normalized['image_url'] = '';
        $normalized['voice_url'] = '';
        $normalized['emoji_address'] = '';
        $normalized['emoji_full_name'] = '';
    }

    foreach ($extra as $key => $value) {
        $normalized[$key] = $value;
    }
    return $normalized;
}

function csac_parse_utc_datetime(string $value): int
{
    $text = trim($value);
    if ($text === '') {
        return 0;
    }
    if (is_numeric($text)) {
        return max(0, (int)$text);
    }
    $utc = new DateTimeZone('UTC');
    $parsed = DateTimeImmutable::createFromFormat('!Y-m-d H:i:s', $text, $utc);
    if ($parsed instanceof DateTimeImmutable) {
        return $parsed->getTimestamp();
    }
    $timestamp = strtotime($text);
    return $timestamp === false ? 0 : $timestamp;
}
