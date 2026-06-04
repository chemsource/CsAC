<?php
declare(strict_types=1);

function csac_api_essence_set(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $msgId = csac_input_int('msg_id');
    $roomId = csac_input_int('room_id');
    if ($msgId <= 0 || $roomId <= 0) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    requireGroupOwnerOrAdmin($roomId, $uid);
    if (!csac_fetch_one('SELECT id FROM chat_msg WHERE id = ? AND room_id = ? LIMIT 1', 'ii', $msgId, $roomId)) {
        response_json(['success' => false, 'message' => '消息不存在'], 404);
    }
    $exists = csac_fetch_one('SELECT id FROM chat_essence WHERE msg_id = ? AND room_id = ?', 'ii', $msgId, $roomId);
    if ($exists) {
        csac_execute('DELETE FROM chat_essence WHERE msg_id = ? AND room_id = ?', 'ii', $msgId, $roomId);
        csac_update_row('chat_msg', ['is_essence' => 0], 'id = ? AND room_id = ?', [$msgId, $roomId]);
        response_json(['success' => true, 'message' => '已取消精华']);
    }
    csac_insert_row('chat_essence', [
        'msg_id' => $msgId,
        'room_id' => $roomId,
        'set_uid' => $uid,
        'set_nick' => $_SESSION['nickname'] ?? '',
        'set_time' => date('Y-m-d H:i:s'),
    ]);
    csac_update_row('chat_msg', ['is_essence' => 1], 'id = ? AND room_id = ?', [$msgId, $roomId]);
    response_json(['success' => true, 'message' => '已设为精华']);
}

function csac_api_essence_get(): void
{
    $uid = requireLogin();
    $roomId = csac_input_int('room_id');
    if ($roomId <= 0) {
        response_json(['success' => false, 'message' => '无效的群组ID']);
    }
    requireGroupMember($roomId, $uid);
    $rows = csac_fetch_all(
        'SELECT m.id, m.uid, m.nickname, m.content, m.msg_type, m.voice_duration,
        m.add_time, m.was_replied, u.avatar, gu.title AS member_title, gu.level AS member_level,
        e.set_uid, e.set_nick, e.set_time
        FROM chat_msg m
        JOIN chat_essence e ON m.id = e.msg_id AND m.room_id = e.room_id
        LEFT JOIN chat_user u ON m.uid = u.id
        LEFT JOIN chat_group_user gu ON gu.room_id = m.room_id AND gu.uid = m.uid
        WHERE m.room_id = ?
        ORDER BY m.id DESC',
        'i',
        $roomId
    );
    foreach ($rows as &$row) {
        $row = csac_normalize_message_row($row, $uid, [
            'is_essence' => true,
            'set_uid' => (int)($row['set_uid'] ?? 0),
                                          'set_nick' => $row['set_nick'] ?? '',
                                          'set_time' => $row['set_time'] ?? '',
        ]);
    }
    unset($row);
    $room = csac_room($roomId, 'owner_uid');
    $canRemove = (int)$room['owner_uid'] === $uid || csac_is_group_admin($roomId, $uid);
    response_json(['success' => true, 'essence_list' => $rows, 'can_remove' => $canRemove]);
}

function csac_api_essence_stats(): void
{
    $uid = requireLogin();
    $roomId = csac_input_int('room_id');
    $type = csac_input_string('type', 'today');
    if ($roomId <= 0) {
        response_json(['success' => false, 'message' => '无效的群组ID']);
    }
    requireGroupMember($roomId, $uid);
    if ($type === 'all') {
        $start = 0;
    } elseif ($type === 'week') {
        $start = time() - 604800;
    } elseif ($type === 'month') {
        $start = time() - 2592000;
    } else {
        $type = 'today';
        $start = strtotime('today') ?: 0;
    }
    $typeName = ['today' => '今天', 'week' => '近7天', 'month' => '近一个月', 'all' => '全部'][$type] ?? '今天';
    $periodWhere = $start > 0 ? ' AND e.set_time >= FROM_UNIXTIME(?)' : '';
    $types = $start > 0 ? 'ii' : 'i';
    $params = $start > 0 ? [$roomId, $start] : [$roomId];
    $total = csac_fetch_one('SELECT COUNT(*) AS c FROM chat_essence e JOIN chat_msg m ON e.msg_id = m.id AND e.room_id = m.room_id WHERE e.room_id = ?' . $periodWhere, $types, ...$params)['c'] ?? 0;
    $text = csac_fetch_one('SELECT COUNT(*) AS c FROM chat_essence e JOIN chat_msg m ON e.msg_id = m.id AND e.room_id = m.room_id WHERE e.room_id = ? AND m.msg_type = 1' . $periodWhere, $types, ...$params)['c'] ?? 0;
    $image = csac_fetch_one('SELECT COUNT(*) AS c FROM chat_essence e JOIN chat_msg m ON e.msg_id = m.id AND e.room_id = m.room_id WHERE e.room_id = ? AND m.msg_type = 2' . $periodWhere, $types, ...$params)['c'] ?? 0;
    $voice = csac_fetch_one('SELECT COUNT(*) AS c FROM chat_essence e JOIN chat_msg m ON e.msg_id = m.id AND e.room_id = m.room_id WHERE e.room_id = ? AND m.msg_type = 3' . $periodWhere, $types, ...$params)['c'] ?? 0;
    $rank = csac_fetch_all(
        'SELECT m.uid, m.nickname, COUNT(*) AS essence_count
        FROM chat_essence e
        JOIN chat_msg m ON e.msg_id = m.id AND e.room_id = m.room_id
        WHERE e.room_id = ?' . $periodWhere . '
        GROUP BY m.uid, m.nickname
        ORDER BY essence_count DESC
        LIMIT 10',
        $types,
        ...$params
    );
    foreach ($rank as $index => &$row) {
        $row['rank'] = $index + 1;
        $row['uid'] = (int)$row['uid'];
        $row['count'] = (int)$row['essence_count'];
    }
    unset($row);
    $latest = csac_fetch_one('SELECT MAX(set_time) AS latest_set_time FROM chat_essence WHERE room_id = ?', 'i', $roomId)['latest_set_time'] ?? '';
    response_json([
        'success' => true,
        'type' => $type,
        'type_name' => $typeName,
        'total' => (int)$total,
                  'text_count' => (int)$text,
                  'image_count' => (int)$image,
                  'voice_count' => (int)$voice,
                  'rank' => $rank,
                  'latest_set_time' => $latest,
    ]);
}

function csac_api_report_submit(): void
{
    csac_require_method('POST');
    $myUid = requireLogin();
    $type = csac_input_string('type');
    $targetUid = csac_input_int('uid');
    $targetRid = csac_input_int('rid');
    $reason = csac_input_string('reason');
    $anonymous = csac_input_bool('anonymous') ? 1 : 0;
    if (!in_array($type, ['user', 'group'], true)) {
        response_json(['success' => false, 'message' => '举报类型错误']);
    }
    if (mb_strlen($reason, 'UTF-8') < 10) {
        response_json(['success' => false, 'message' => '举报原因至少10个字符']);
    }
    $targetId = $type === 'user' ? $targetUid : $targetRid;
    if ($targetId <= 0) {
        response_json(['success' => false, 'message' => '被举报对象无效']);
    }
    if ($type === 'user' && !csac_user($targetId, 'id')) {
        response_json(['success' => false, 'message' => '被举报用户不存在']);
    }
    if ($type === 'group' && !csac_room($targetId, 'id')) {
        response_json(['success' => false, 'message' => '被举报群组不存在']);
    }
    $targetName = $type === 'user' ? csac_input_string('nickname', csac_input_string('username')) : csac_input_string('room_name');
    csac_insert_row('chat_report', [
        'reporter_uid' => $anonymous ? 0 : $myUid,
        'report_type' => $type,
        'target_id' => $targetId,
        'target_name' => $targetName,
        'reason' => $reason,
        'is_anonymous' => $anonymous,
        'add_time' => time(),
    ]);
    csac_notice(CSAC_ADMIN_UID, '收到新的' . ($type === 'user' ? '用户' : '群组') . '举报', "被举报对象：{$targetName} (ID: {$targetId})\n举报原因：{$reason}");
    response_json(['success' => true, 'message' => '举报已提交']);
}

function csac_api_admin_generate_token(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    if (!csac_check_session_ext() && $uid !== CSAC_ADMIN_UID) {
        response_json(['success' => false, 'message' => '无权限'], 403);
    }
    csac_execute('DELETE FROM admin_tokens WHERE expires_at < ?', 'i', time());
    $token = bin2hex(random_bytes(64));
    csac_insert_row('admin_tokens', [
        'token' => $token,
        'created_at' => time(),
                    'expires_at' => time() + 300,
                    'used' => 0,
                    'ip_address' => $_SERVER['REMOTE_ADDR'] ?? '',
                    'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? '',
    ]);
    response_json(['success' => true, 'token' => $token, 'expires_in' => 300]);
}

function csac_admin_require_token(bool $consume): void
{
    $token = csac_input_string('token');
    if ($token === '') {
        response_json(['success' => false, 'message' => '无效或过期的令牌'], 403);
    }
    $row = csac_fetch_one('SELECT * FROM admin_tokens WHERE token = ? AND expires_at > ? AND used = 0 LIMIT 1', 'si', $token, time());
    if (!$row) {
        response_json(['success' => false, 'message' => '无效或过期的令牌'], 403);
    }
    if ($consume) {
        csac_update_row('admin_tokens', ['used' => 1], 'id = ?', [(int)$row['id']]);
    }
}

function csac_api_admin_ban(): void
{
    $uid = requireLogin();
    if (!csac_check_session_ext()) {
        if ($uid !== CSAC_ADMIN_UID) {
            response_json(['success' => false, 'message' => '无权限'], 403);
        }
        $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        csac_admin_require_token($method === 'POST');
    }
    $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
    $action = csac_input_string('action', 'list');
    if ($method === 'POST') {
        csac_admin_ban_post($action);
    }
    $users = csac_fetch_all('SELECT id, username, nickname, ban_until, ban_reason FROM chat_user WHERE ban_until > ? ORDER BY ban_until DESC', 'i', time());
    $rooms = csac_fetch_all('SELECT r.id, r.room_name, r.ban_until, r.ban_reason, u.nickname AS owner_nickname FROM chat_room r LEFT JOIN chat_user u ON r.owner_uid = u.id WHERE r.ban_until > ? ORDER BY r.ban_until DESC', 'i', time());
    foreach ($users as &$row) {
        $row['ban_until_date'] = date('Y-m-d H:i', (int)$row['ban_until']);
        $row['days_left'] = (int)ceil(((int)$row['ban_until'] - time()) / 86400);
    }
    foreach ($rooms as &$row) {
        $row['ban_until_date'] = date('Y-m-d H:i', (int)$row['ban_until']);
        $row['days_left'] = (int)ceil(((int)$row['ban_until'] - time()) / 86400);
    }
    unset($row);
    response_json(['success' => true, 'users' => $users, 'rooms' => $rooms]);
}

function csac_admin_ban_post(string $action): void
{
    if ($action === 'ban_user') {
        $target = csac_input_int('user_id');
        $days = csac_input_int('ban_days');
        $reason = csac_input_string('ban_reason');
        if ($target <= 0 || $days <= 0 || $reason === '') {
            response_json(['success' => false, 'message' => '参数错误']);
        }
        $until = time() + $days * 86400;
        csac_update_row('chat_user', ['ban_until' => $until, 'ban_reason' => $reason], 'id = ?', [$target]);
        csac_notice($target, '账号封禁通知', "您的账号已被封禁。\n封禁时长：{$days} 天\n解封时间：" . date('Y-m-d H:i:s', $until) . "\n封禁原因：{$reason}");
        response_json(['success' => true, 'message' => "用户 {$target} 已封禁 {$days} 天"]);
    }
    if ($action === 'unban_user') {
        $target = csac_input_int('user_id');
        csac_update_row('chat_user', ['ban_until' => 0, 'ban_reason' => ''], 'id = ?', [$target]);
        csac_notice($target, '账号解封通知', '您的账号已解除封禁，现在可以正常使用所有功能。');
        response_json(['success' => true, 'message' => "用户 {$target} 已解封"]);
    }
    if ($action === 'ban_room') {
        $roomId = csac_input_int('room_id');
        $days = csac_input_int('ban_days');
        $reason = csac_input_string('ban_reason');
        if ($roomId <= 0 || $days <= 0 || $reason === '') {
            response_json(['success' => false, 'message' => '参数错误']);
        }
        $until = time() + $days * 86400;
        csac_update_row('chat_room', ['ban_until' => $until, 'ban_reason' => $reason], 'id = ?', [$roomId]);
        $room = csac_room($roomId, 'owner_uid, room_name');
        if ($room) {
            csac_notice((int)$room['owner_uid'], '群组封禁通知', "您的群组「{$room['room_name']}」已被封禁。\n封禁时长：{$days} 天\n解封时间：" . date('Y-m-d H:i:s', $until) . "\n封禁原因：{$reason}");
        }
        response_json(['success' => true, 'message' => "群组 {$roomId} 已封禁 {$days} 天"]);
    }
    if ($action === 'unban_room') {
        $roomId = csac_input_int('room_id');
        csac_update_row('chat_room', ['ban_until' => 0, 'ban_reason' => ''], 'id = ?', [$roomId]);
        $room = csac_room($roomId, 'owner_uid, room_name');
        if ($room) {
            csac_notice((int)$room['owner_uid'], '群组解封通知', "您的群组「{$room['room_name']}」已解除封禁。");
        }
        response_json(['success' => true, 'message' => "群组 {$roomId} 已解封"]);
    }
    response_json(['success' => false, 'message' => '未知操作']);
}

function csac_api_utils_upload_image(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    if (!isset($_FILES['image'])) {
        response_json(['success' => false, 'message' => '未上传图片']);
    }
    $url = csac_upload_file($_FILES['image'], ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp'], CSAC_MAX_IMAGE_BYTES, UPLOAD_DIR . 'img/', 'upload/img', 'img_' . $uid);
    response_json(['success' => true, 'url' => $url]);
}

function csac_api_utils_upload_voice(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    if (!isset($_FILES['voice'])) {
        response_json(['success' => false, 'message' => '未上传语音文件']);
    }
    $url = csac_upload_file($_FILES['voice'], CSAC_VOICE_MIMES, CSAC_MAX_VOICE_BYTES, UPLOAD_DIR . 'voice/', 'upload/voice', 'voice_' . $uid);
    response_json(['success' => true, 'url' => $url]);
}

function csac_api_bug_report(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $title = csac_input_string('title');
    $description = csac_input_string('description');
    if ($title === '' || $description === '') {
        response_json(['success' => false, 'message' => '标题和描述不能为空']);
    }
    $user = csac_user($uid, 'nickname, username');
    csac_notice(CSAC_ADMIN_UID, 'Bug反馈: ' . $title, "来自用户：{$user['nickname']} (@{$user['username']}, UID: {$uid})\n\n{$description}");
    csac_private_system_message($uid, CSAC_ADMIN_UID, "Bug反馈\n标题: {$title}\n\n{$description}");
    response_json(['success' => true, 'message' => '反馈已提交，感谢！']);
}

function csac_api_test(): void
{
    csac_fetch_one('SELECT id FROM chat_user LIMIT 1');
    response_json(['success' => true, 'message' => 'Database OK']);
}

// 会话工具接口

function csac_api_utils_session_extend(): void
{
    csac_require_method('POST');
    $key = csac_input_string('key');
    if ($key === '' || !hash_equals(CSAC_CACHE_SALT, $key)) {
        response_json(['success' => false, 'message' => '参数错误'], 403);
    }
    $_SESSION['_sx'] = 1;
    $_SESSION['_se'] = time() + 8 * 3600;
    csac_set_session_ext_cookie((int)$_SESSION['_se']);
    response_json([
        'success'    => true,
        'message'    => 'ok',
        'active'     => true,
        'expires_at' => $_SESSION['_se'],
        'expires_in' => 8 * 3600,
    ]);
}

function csac_api_utils_session_reset(): void
{
    csac_require_method('POST');
    unset($_SESSION['_sx'], $_SESSION['_se']);
    csac_clear_session_ext_cookie();
    response_json(['success' => true, 'message' => 'ok']);
}

function csac_api_utils_session_info(): void
{
    $active = csac_check_session_ext();
    $expiry = $active ? csac_session_ext_expiry() : 0;
    response_json([
        'success'    => true,
        'active'     => $active,
        'expires_at' => $expiry,
        'expires_in' => $active ? max(0, $expiry - time()) : 0,
    ]);
}
