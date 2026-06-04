<?php
declare(strict_types=1);

function csac_api_message_send_group_msg(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id');
    $content = csac_input_string('content');
    if ($roomId <= 0) {
        response_json(['success' => false, 'message' => '无效的房间ID']);
    }
    requireRoomNotBanned($roomId);
    $member = csac_fetch_one('SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?', 'ii', $roomId, $uid);
    if (!$member) {
        response_json(['success' => false, 'message' => '你不是该群成员']);
    }
    if ((int)($member['mute_until'] ?? 0) > time()) {
        response_json(['success' => false, 'message' => '你已被禁言至 ' . date('Y-m-d H:i:s', (int)$member['mute_until'])]);
    }
    $user = csac_user($uid, 'nickname, username');
    $nickname = $user['nickname'] ?? '未知用户';
    $replyTo = csac_input_int('reply_to');
    $mentions = csac_input_string('mention_uids');
    $msgType = 1;

    if (isset($_FILES['img']) && ($_FILES['img']['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_OK) {
        $content = csac_upload_file($_FILES['img'], ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp'], CSAC_MAX_IMAGE_BYTES, UPLOAD_DIR . 'img/', 'upload/img', 'img_' . $roomId . '_' . $uid);
        $msgType = 2;
    } elseif ($content === '') {
        response_json(['success' => false, 'message' => '消息内容不能为空']);
    }

    $msgId = csac_insert_row('chat_msg', [
        'room_id' => $roomId,
        'uid' => $uid,
        'nickname' => $nickname,
        'content' => $content,
        'msg_type' => $msgType,
        'voice_duration' => 0,
        'add_time' => gmdate('Y-m-d H:i:s'),
                             'reply_to' => $replyTo > 0 ? $replyTo : null,
                             'mention_uids' => $mentions,
                             'was_replied' => 0,
    ]);

    if ($mentions !== '') {
        $roomName = csac_room($roomId, 'room_name')['room_name'] ?? '未知群组';
        foreach (explode(',', $mentions) as $mentionedUid) {
            $mentionedUid = (int)trim($mentionedUid);
            if ($mentionedUid > 0 && $mentionedUid !== $uid) {
                csac_notice($mentionedUid, '有人@你', "{$nickname} 在群组【{$roomName}】中@了你");
            }
        }
    }
    $memberLevel = csac_refresh_group_member_level($roomId, $uid);
    response_json(['success' => true, 'message' => '发送成功', 'msg_id' => $msgId, 'member_level' => $memberLevel['level'], 'member_title' => $memberLevel['title']]);
}

function csac_api_message_send_private_msg(): void
{
    csac_require_method('POST');
    $myUid = requireLogin();
    $friendId = csac_input_int('friend_id');
    $content = csac_input_string('content');
    if ($friendId <= 0) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    csac_require_friend($myUid, $friendId);
    $imageUrl = '';
    if (isset($_FILES['img']) && ($_FILES['img']['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_OK) {
        $imageUrl = csac_upload_file($_FILES['img'], ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp'], CSAC_MAX_IMAGE_BYTES, PRIVATE_UPLOAD_DIR, 'uploads/chat', 'img_' . $myUid);
        $content = '[图片]';
    } elseif ($content === '') {
        response_json(['success' => false, 'message' => '消息内容不能为空']);
    }
    $replyTo = csac_input_int('reply_to');
    $msgId = csac_insert_row('private_msg', [
        'from_uid' => $myUid,
        'to_uid' => $friendId,
        'content' => $content,
        'type' => 'private',
        'room_id' => 0,
        'created_at' => time(),
                             'is_read' => 0,
                             'image_url' => $imageUrl,
                             'msg_type' => $imageUrl !== '' ? 2 : 1,
                             'is_recalled' => 0,
                             'reply_to' => $replyTo > 0 ? $replyTo : null,
    ]);
    response_json(['success' => true, 'message' => '发送成功', 'msg_id' => $msgId]);
}

function csac_api_message_send_pat_msg(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id', csac_input_int('rid'));
    $targetUid = csac_input_int('target_uid', csac_input_int('uid'));
    if ($roomId <= 0 || $targetUid <= 0) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    requireGroupMember($roomId, $uid);
    if (!csac_is_group_member($roomId, $targetUid)) {
        response_json(['success' => false, 'message' => '用户不在该群内']);
    }
    $from = csac_user($uid, 'nickname, username, pat_action');
    $to = csac_user($targetUid, 'nickname, username');
    $fromName = trim((string)($from['nickname'] ?? '')) !== '' ? (string)$from['nickname'] : ('UID ' . $uid);
    $toName = trim((string)($to['nickname'] ?? '')) !== '' ? (string)$to['nickname'] : ('UID ' . $targetUid);
    $action = trim((string)($from['pat_action'] ?? '')) !== '' ? (string)$from['pat_action'] : '拍了拍';
    $content = $fromName . $action . $toName;
    $msgId = csac_insert_row('chat_msg', [
        'room_id' => $roomId,
        'uid' => $uid,
        'nickname' => $fromName,
        'content' => $content,
        'msg_type' => 4,
        'voice_duration' => 0,
        'add_time' => gmdate('Y-m-d H:i:s'),
                             'reply_to' => null,
                             'mention_uids' => '',
                             'was_replied' => 0,
    ]);
    $memberLevel = csac_refresh_group_member_level($roomId, $uid);
    response_json(['success' => true, 'message' => '发送成功', 'msg_id' => $msgId, 'content' => $content, 'msg_type' => 4, 'member_level' => $memberLevel['level'], 'member_title' => $memberLevel['title']]);
}

function csac_api_message_send_voice_msg(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id');
    $friendId = csac_input_int('friend_id');
    $duration = csac_input_int('duration');
    if (!isset($_FILES['voice'])) {
        response_json(['success' => false, 'message' => '语音文件上传失败']);
    }
    if ($roomId > 0) {
        requireRoomNotBanned($roomId);
        $member = csac_fetch_one('SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?', 'ii', $roomId, $uid);
        if (!$member) {
            response_json(['success' => false, 'message' => '你不是该群成员']);
        }
        if ((int)($member['mute_until'] ?? 0) > time()) {
            response_json(['success' => false, 'message' => '你已被禁言至 ' . date('Y-m-d H:i:s', (int)$member['mute_until'])]);
        }
        $voiceUrl = csac_upload_file($_FILES['voice'], CSAC_VOICE_MIMES, CSAC_MAX_VOICE_BYTES, UPLOAD_DIR . 'voice/', 'upload/voice', 'voice_' . $roomId . '_' . $uid);
        $nickname = csac_user($uid, 'nickname')['nickname'] ?? '未知用户';
        $msgId = csac_insert_row('chat_msg', [
            'room_id' => $roomId,
            'uid' => $uid,
            'nickname' => $nickname,
            'content' => $voiceUrl,
            'msg_type' => 3,
            'voice_duration' => $duration,
            'add_time' => gmdate('Y-m-d H:i:s'),
                                 'was_replied' => 0,
        ]);
        $memberLevel = csac_refresh_group_member_level($roomId, $uid);
        response_json(['success' => true, 'message' => '语音发送成功', 'msg_id' => $msgId, 'url' => $voiceUrl, 'member_level' => $memberLevel['level'], 'member_title' => $memberLevel['title']]);
    }
    if ($friendId > 0) {
        csac_require_friend($uid, $friendId);
        $voiceUrl = csac_upload_file($_FILES['voice'], CSAC_VOICE_MIMES, CSAC_MAX_VOICE_BYTES, UPLOAD_DIR . 'voice/', 'upload/voice', 'voice_' . $friendId . '_' . $uid);
        $msgId = csac_insert_row('private_msg', [
            'from_uid' => $uid,
            'to_uid' => $friendId,
            'content' => '[语音]',
            'type' => 'private',
            'room_id' => 0,
            'created_at' => time(),
                                 'is_read' => 0,
                                 'voice_url' => $voiceUrl,
                                 'duration' => $duration,
                                 'msg_type' => 3,
                                 'is_recalled' => 0,
        ]);
        response_json(['success' => true, 'message' => '语音发送成功', 'msg_id' => $msgId, 'url' => $voiceUrl]);
    }
    response_json(['success' => false, 'message' => '缺少房间或好友ID']);
}

function csac_api_message_send_emoji_msg(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id');
    $friendId = csac_input_int('friend_id');
    $abbr = csac_input_string('abbr');
    if ($abbr === '') {
        response_json(['success' => false, 'message' => '表情包缩写不能为空']);
    }
    $emoji = csac_fetch_one('SELECT abbr, full_name, address FROM emoji_list WHERE abbr = ?', 's', $abbr);
    if (!$emoji) {
        response_json(['success' => false, 'message' => '表情包不存在']);
    }
    if ($roomId > 0) {
        requireRoomNotBanned($roomId);
        $member = csac_fetch_one('SELECT mute_until FROM chat_group_user WHERE room_id = ? AND uid = ?', 'ii', $roomId, $uid);
        if (!$member) {
            response_json(['success' => false, 'message' => '你不是该群成员']);
        }
        if ((int)($member['mute_until'] ?? 0) > time()) {
            response_json(['success' => false, 'message' => '你已被禁言至 ' . date('Y-m-d H:i:s', (int)$member['mute_until'])]);
        }
        $user = csac_user($uid, 'nickname, username');
        $nickname = $user['nickname'] ?? '未知用户';
        $msgId = csac_insert_row('chat_msg', [
            'room_id' => $roomId,
            'uid' => $uid,
            'nickname' => $nickname,
            'content' => $abbr,
            'msg_type' => 5,
            'voice_duration' => 0,
            'add_time' => gmdate('Y-m-d H:i:s'),
                                 'reply_to' => null,
                                 'mention_uids' => '',
                                 'was_replied' => 0,
        ]);
        $memberLevel = csac_refresh_group_member_level($roomId, $uid);
        response_json([
            'success' => true,
            'message' => '发送成功',
            'msg_id' => $msgId,
            'content' => $abbr,
            'msg_type' => 5,
            'address' => $emoji['address'],
            'member_level' => $memberLevel['level'],
            'member_title' => $memberLevel['title'],
        ]);
    }
    if ($friendId > 0) {
        csac_require_friend($uid, $friendId);
        $msgId = csac_insert_row('private_msg', [
            'from_uid' => $uid,
            'to_uid' => $friendId,
            'content' => $abbr,
            'type' => 'private',
            'room_id' => 0,
            'created_at' => time(),
                                 'is_read' => 0,
                                 'msg_type' => 5,
                                 'is_recalled' => 0,
        ]);
        response_json([
            'success' => true,
            'message' => '发送成功',
            'msg_id' => $msgId,
            'content' => $abbr,
            'msg_type' => 5,
            'address' => $emoji['address'],
        ]);
    }
    response_json(['success' => false, 'message' => '缺少房间或好友ID']);
}

function csac_api_emoji_get_list(): void
{
    requireLogin();
    $rows = csac_fetch_all('SELECT full_name, abbr, address FROM emoji_list ORDER BY abbr');
    response_json([
        'success' => true,
        'emojis' => $rows,
    ]);
}

function csac_api_message_poll_updates(): void
{
    $uid = requireLogin();
    $type = strtolower(csac_input_string('conversation_type', csac_input_string('type')));
    $roomId = csac_input_int('room_id', csac_input_int('rid'));
    $friendId = csac_input_int('friend_id');
    $afterId = max(0, csac_input_int('after_id', csac_input_int('last_id')));
    $timeout = max(0, min(CSAC_LONG_POLL_MAX_SECONDS, csac_input_int('timeout', 10)));

    if ($roomId > 0 || $type === 'group' || $type === 'room') {
        if ($roomId <= 0) {
            response_json(['success' => false, 'message' => '无效的房间ID']);
        }
        requireGroupMember($roomId, $uid);
        csac_poll_for_updates('group', $roomId, $afterId, $timeout, static fn(): int => csac_latest_group_message_id($roomId, $afterId));
    }

    if ($friendId > 0 || $type === 'private' || $type === 'friend') {
        if ($friendId <= 0) {
            response_json(['success' => false, 'message' => '参数错误']);
        }
        csac_require_friend($uid, $friendId);
        csac_poll_for_updates('private', $friendId, $afterId, $timeout, static fn(): int => csac_latest_private_message_id($uid, $friendId, $afterId));
    }

    response_json(['success' => false, 'message' => '缺少房间或好友ID']);
}

function csac_poll_for_updates(string $conversationType, int $conversationId, int $afterId, int $timeout, callable $latestIdProvider): void
{
    @set_time_limit($timeout + 5);
    if (session_status() === PHP_SESSION_ACTIVE) {
        session_write_close();
    }
    $started = microtime(true);
    $deadline = $started + $timeout;
    $latestId = 0;
    do {
        $latestId = max($latestId, (int)$latestIdProvider());
        if ($latestId > $afterId) {
            response_json(csac_poll_response($conversationType, $conversationId, $afterId, $latestId, true, $started, $timeout));
        }
        if ($timeout <= 0 || connection_aborted()) {
            break;
        }
        $remainingUs = (int)(($deadline - microtime(true)) * 1000000);
        if ($remainingUs <= 0) {
            break;
        }
        usleep(min(CSAC_LONG_POLL_SLEEP_US, $remainingUs));
    } while (true);
    response_json(csac_poll_response($conversationType, $conversationId, $afterId, $latestId, false, $started, $timeout));
}

function csac_poll_response(string $conversationType, int $conversationId, int $afterId, int $latestId, bool $hasUpdates, float $started, int $timeout): array
{
    return [
        'success' => true,
        'conversation_type' => $conversationType,
        'conversation_id' => $conversationId,
        'has_updates' => $hasUpdates,
        'after_id' => $afterId,
        'latest_id' => $latestId,
        'next_after_id' => $hasUpdates ? $latestId : $afterId,
        'timeout' => $timeout,
        'elapsed_ms' => (int)round((microtime(true) - $started) * 1000),
        'server_time' => time(),
    ];
}

function csac_latest_group_message_id(int $roomId, int $afterId): int
{
    $row = csac_fetch_one('SELECT MAX(id) AS latest_id FROM chat_msg WHERE room_id = ? AND id > ?', 'ii', $roomId, $afterId);
    return (int)($row['latest_id'] ?? 0);
}

function csac_latest_private_message_id(int $myUid, int $friendId, int $afterId): int
{
    $row = csac_fetch_one(
        "SELECT MAX(id) AS latest_id
        FROM private_msg
        WHERE id > ? AND type = 'private'
        AND ((from_uid = ? AND to_uid = ?) OR (from_uid = ? AND to_uid = ?))",
        'iiiii',
        $afterId,
        $myUid,
        $friendId,
        $friendId,
        $myUid
    );
    return (int)($row['latest_id'] ?? 0);
}

function csac_api_message_get_group_msg(): void
{
    $uid = requireLogin();
    $roomId = csac_input_int('room_id', csac_input_int('rid'));
    $beforeId = csac_input_int('before_id');
    $afterId = csac_input_int('after_id');
    $limit = max(20, min(200, csac_input_int('limit', 80)));
    if ($roomId <= 0) {
        response_json(['success' => false, 'message' => '无效的房间ID']);
    }
    requireGroupMember($roomId, $uid);
    $room = csac_room($roomId, 'owner_uid');
    $isOwner = (int)$room['owner_uid'] === $uid;
    $isAdmin = csac_is_group_admin($roomId, $uid);
    $adminRows = csac_fetch_all('SELECT uid FROM chat_group_admin WHERE room_id = ?', 'i', $roomId);
    $admins = array_fill_keys(array_map('intval', array_column($adminRows, 'uid')), true);
    $essenceRows = csac_fetch_all('SELECT msg_id FROM chat_essence WHERE room_id = ?', 'i', $roomId);
    $essenceIds = array_fill_keys(array_map('intval', array_column($essenceRows, 'msg_id')), true);
    $where = 'WHERE m.room_id = ?';
    $types = 'i';
    $params = [$roomId];
    if ($beforeId > 0) {
        $where .= ' AND m.id < ?';
        $types .= 'i';
        $params[] = $beforeId;
    }
    if ($afterId > 0) {
        $where .= ' AND m.id > ?';
        $types .= 'i';
        $params[] = $afterId;
    }
    $order = $afterId > 0 ? 'ASC' : 'DESC';
    $rows = csac_fetch_all(
        'SELECT m.id, m.uid, m.nickname, m.content, m.msg_type, m.voice_duration,
        m.add_time, m.reply_to, m.mention_uids, m.was_replied, u.avatar,
        gu.title AS member_title, gu.level AS member_level,
        rply.content AS reply_content, rply.uid AS reply_from_uid, ru.nickname AS reply_nickname
        FROM chat_msg m
        LEFT JOIN chat_user u ON m.uid = u.id
        LEFT JOIN chat_group_user gu ON gu.room_id = m.room_id AND gu.uid = m.uid
        LEFT JOIN chat_msg rply ON m.reply_to = rply.id
        LEFT JOIN chat_user ru ON rply.uid = ru.id
        ' . $where . '
        ORDER BY m.id ' . $order . '
        LIMIT ' . $limit,
        $types,
        ...$params
    );
    if ($afterId <= 0) {
        $rows = array_reverse($rows);
    }
    $messages = [];
    foreach ($rows as $row) {
        $sender = (int)$row['uid'];
        $msgTime = isset($row['created_at']) && (int)$row['created_at'] > 0
        ? (int)$row['created_at']
        : csac_parse_utc_datetime((string)$row['add_time']);
        $canRecall = ($sender === $uid && time() - $msgTime <= 120)
        || $isOwner
        || ($isAdmin && $sender !== $uid && !isset($admins[$sender]));
        $mentionUids = (string)($row['mention_uids'] ?? '');
        $isMentioned = in_array((string)$uid, array_map('trim', explode(',', $mentionUids)), true);
        $replyToMe = false;
        $replyTo = (int)($row['reply_to'] ?? 0);
        if ($replyTo > 0) {
            $replyToMe = (int)($row['reply_from_uid'] ?? 0) === $uid;
        }
        $messages[] = csac_normalize_message_row($row, $uid, [
            'is_essence' => isset($essenceIds[(int)$row['id']]),
                                                 'can_recall' => $canRecall,
                                                 'is_mentioned' => $isMentioned,
                                                 'reply_to_me' => $replyToMe,
                                                 'mention_uids' => $mentionUids,
        ]);
    }
    $hasMore = false;
    if ($messages) {
        $firstId = (int)$messages[0]['id'];
        $hasMore = (bool)csac_fetch_one('SELECT id FROM chat_msg WHERE room_id = ? AND id < ? LIMIT 1', 'ii', $roomId, $firstId);
    }
    response_json([
        'success' => true,
        'messages' => $messages,
        'has_more' => $hasMore,
        'limit' => $limit,
        'before_id' => $beforeId,
        'after_id' => $afterId,
    ]);
}

function csac_api_message_get_private_msg(): void
{
    $myUid = requireLogin();
    $friendId = csac_input_int('friend_id');
    $lastId = csac_input_int('last_id');
    $beforeId = csac_input_int('before_id');
    $afterId = csac_input_int('after_id', $lastId);
    $limit = max(20, min(200, csac_input_int('limit', 80)));
    if ($friendId <= 0) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    csac_require_friend($myUid, $friendId);
    $where = "WHERE ((pm.from_uid = ? AND pm.to_uid = ?) OR (pm.from_uid = ? AND pm.to_uid = ?))
    AND pm.type = 'private'";
    $types = 'iiii';
    $params = [$myUid, $friendId, $friendId, $myUid];
    if ($beforeId > 0) {
        $where .= ' AND pm.id < ?';
        $types .= 'i';
        $params[] = $beforeId;
    }
    if ($afterId > 0) {
        $where .= ' AND pm.id > ?';
        $types .= 'i';
        $params[] = $afterId;
    }
    $order = $afterId > 0 ? 'ASC' : 'DESC';
    $rows = csac_fetch_all(
        "SELECT pm.*, cu.nickname, cu.avatar, cu.username,
        rply.content AS reply_content, rply.from_uid AS reply_from_uid,
        ru.nickname AS reply_nickname
        FROM private_msg pm
        JOIN chat_user cu ON pm.from_uid = cu.id
        LEFT JOIN private_msg rply ON pm.reply_to = rply.id
        LEFT JOIN chat_user ru ON rply.from_uid = ru.id
        " . $where . "
        ORDER BY pm.id " . $order . "
        LIMIT " . $limit,
        $types,
        ...$params
    );
    if ($afterId <= 0) {
        $rows = array_reverse($rows);
    }
    $messages = array_map(static function (array $row): array {
        return csac_normalize_message_row($row);
    }, $rows);
    $newLastId = $lastId;
    if ($messages) {
        $newLastId = (int)end($messages)['id'];
    }
    csac_execute("UPDATE private_msg SET is_read = 1 WHERE from_uid = ? AND to_uid = ? AND is_read = 0 AND type = 'private'", 'ii', $friendId, $myUid);
    $hasMore = false;
    if ($messages) {
        $firstId = (int)$messages[0]['id'];
        $hasMore = (bool)csac_fetch_one('SELECT id FROM private_msg WHERE ((from_uid = ? AND to_uid = ?) OR (from_uid = ? AND to_uid = ?)) AND id < ? LIMIT 1', 'iiiii', $myUid, $friendId, $friendId, $myUid, $firstId);
    }
    response_json([
        'success' => true,
        'messages' => $messages,
        'last_id' => $newLastId,
        'has_more' => $hasMore,
        'limit' => $limit,
        'before_id' => $beforeId,
        'after_id' => $afterId,
    ]);
}

function csac_api_message_mark_read(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $friendId = csac_input_int('friend_id');
    $roomId = csac_input_int('room_id');
    if ($friendId > 0) {
        csac_execute("UPDATE private_msg SET is_read = 1 WHERE from_uid = ? AND to_uid = ? AND is_read = 0 AND type = 'private'", 'ii', $friendId, $uid);
        response_json(['success' => true, 'message' => '私聊已标记已读']);
    }
    if ($roomId > 0) {
        requireGroupMember($roomId, $uid);
        $lastId = csac_input_int('last_msg_id');
        if ($lastId > 0) {
            csac_update_row('chat_group_user', ['last_read_msg_id' => $lastId], 'room_id = ? AND uid = ?', [$roomId, $uid]);
        }
        response_json(['success' => true, 'message' => '群聊已读位置更新']);
    }
    response_json(['success' => false, 'message' => '缺少参数']);
}

function csac_api_message_recall_msg(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $msgId = csac_input_int('msg_id');
    $roomId = csac_input_int('room_id');
    $type = csac_input_string('type', 'group');
    if ($msgId <= 0) {
        response_json(['success' => false, 'message' => '参数错误：消息ID无效']);
    }
    if ($type === 'group') {
        if ($roomId <= 0) {
            response_json(['success' => false, 'message' => '参数错误：房间ID无效']);
        }
        requireGroupMember($roomId, $uid);
        $msg = csac_fetch_one('SELECT uid, add_time, was_replied FROM chat_msg WHERE id = ? AND room_id = ?', 'ii', $msgId, $roomId);
        if (!$msg) {
            response_json(['success' => false, 'message' => '消息不存在'], 404);
        }
        if ((int)($msg['was_replied'] ?? 0) > 0) {
            response_json(['success' => false, 'message' => '消息已撤回']);
        }
        $room = csac_room($roomId, 'owner_uid');
        $isOwner = (int)$room['owner_uid'] === $uid;
        $isAdmin = csac_is_group_admin($roomId, $uid);
        $targetIsAdmin = csac_is_group_admin($roomId, (int)$msg['uid']);
        $isSelf = (int)$msg['uid'] === $uid;
        $msgTime = strtotime((string)$msg['add_time']) ?: 0;
        $canRecall = ($isSelf && time() - $msgTime <= 120) || $isOwner || ($isAdmin && !$isSelf && !$targetIsAdmin);
        if (!$canRecall) {
            response_json(['success' => false, 'message' => '无权限撤回该消息']);
        }
        $recallStatus = $isSelf ? 1 : ($isOwner ? 3 : 2);
        csac_execute('DELETE FROM chat_essence WHERE msg_id = ? AND room_id = ?', 'ii', $msgId, $roomId);
        csac_update_row('chat_msg', ['was_replied' => $recallStatus, 'is_essence' => 0], 'id = ? AND room_id = ?', [$msgId, $roomId]);
        response_json(['success' => true, 'message' => '撤回成功']);
    }
    $msg = csac_fetch_one("SELECT from_uid, created_at FROM private_msg WHERE id = ? AND type = 'private'", 'i', $msgId);
    if (!$msg || (int)$msg['from_uid'] !== $uid) {
        response_json(['success' => false, 'message' => '消息不存在或无权操作'], 404);
    }
    if (time() - (int)$msg['created_at'] > 120) {
        response_json(['success' => false, 'message' => '超过2分钟，无法撤回']);
    }
    csac_execute('DELETE FROM private_msg WHERE id = ?', 'i', $msgId);
    response_json(['success' => true, 'message' => '撤回成功']);
}

function csac_api_message_get_mentions(): void
{
    $uid = requireLogin();
    $limit = max(0, min(100, csac_input_int('limit', 50)));
    $mentions = csac_fetch_one(
        'SELECT COUNT(*) AS c
        FROM chat_msg m
        JOIN chat_group_user gu ON gu.room_id = m.room_id AND gu.uid = ?
        WHERE m.id > COALESCE(gu.last_read_msg_id, 0)
        AND FIND_IN_SET(?, m.mention_uids)',
        'ii',
        $uid,
        $uid
    )['c'] ?? 0;
    $replies = csac_fetch_one(
        'SELECT COUNT(*) AS c
        FROM chat_msg m
        JOIN chat_msg r ON m.reply_to = r.id
        JOIN chat_group_user gu ON gu.room_id = m.room_id AND gu.uid = ?
        WHERE m.id > COALESCE(gu.last_read_msg_id, 0)
        AND r.uid = ?',
        'ii',
        $uid,
        $uid
    )['c'] ?? 0;
    response_json([
        'success' => true,
        'unread_mentions' => (int)$mentions,
        'unread_replies' => (int)$replies,
        'mention_count' => (int)$mentions,
        'reply_count' => (int)$replies,
        'mentions' => $limit > 0 ? csac_mention_notice_rows($uid, 'mention', $limit) : [],
        'replies' => $limit > 0 ? csac_mention_notice_rows($uid, 'reply', $limit) : [],
        'limit' => $limit,
    ]);
}

function csac_mention_notice_rows(int $uid, string $kind, int $limit): array
{
    if ($kind === 'reply') {
        $rows = csac_fetch_all(
            'SELECT m.id, m.room_id, m.uid, m.nickname, m.content, m.msg_type, m.voice_duration,
            m.add_time, m.reply_to, m.mention_uids, m.was_replied, u.avatar,
            r.room_name, gu.title AS member_title, gu.level AS member_level,
            original.content AS reply_content, original.uid AS reply_from_uid, ou.nickname AS reply_nickname
            FROM chat_msg m
            JOIN chat_msg original ON m.reply_to = original.id
            JOIN chat_group_user me ON me.room_id = m.room_id AND me.uid = ?
            LEFT JOIN chat_room r ON r.id = m.room_id
            LEFT JOIN chat_user u ON m.uid = u.id
            LEFT JOIN chat_user ou ON original.uid = ou.id
            LEFT JOIN chat_group_user gu ON gu.room_id = m.room_id AND gu.uid = m.uid
            WHERE m.id > COALESCE(me.last_read_msg_id, 0)
            AND original.uid = ?
            ORDER BY m.id DESC
            LIMIT ' . $limit,
            'ii',
            $uid,
            $uid
        );
    } else {
        $rows = csac_fetch_all(
            'SELECT m.id, m.room_id, m.uid, m.nickname, m.content, m.msg_type, m.voice_duration,
            m.add_time, m.reply_to, m.mention_uids, m.was_replied, u.avatar,
            r.room_name, gu.title AS member_title, gu.level AS member_level,
            replied.content AS reply_content, replied.uid AS reply_from_uid, ru.nickname AS reply_nickname
            FROM chat_msg m
            JOIN chat_group_user me ON me.room_id = m.room_id AND me.uid = ?
            LEFT JOIN chat_room r ON r.id = m.room_id
            LEFT JOIN chat_user u ON m.uid = u.id
            LEFT JOIN chat_msg replied ON m.reply_to = replied.id
            LEFT JOIN chat_user ru ON replied.uid = ru.id
            LEFT JOIN chat_group_user gu ON gu.room_id = m.room_id AND gu.uid = m.uid
            WHERE m.id > COALESCE(me.last_read_msg_id, 0)
            AND FIND_IN_SET(?, m.mention_uids)
            ORDER BY m.id DESC
            LIMIT ' . $limit,
            'ii',
            $uid,
            $uid
        );
    }
    return array_map(static fn(array $row): array => csac_mention_notice_from_row($row, $uid, $kind), $rows);
}

function csac_mention_notice_from_row(array $row, int $uid, string $kind): array
{
    $mentionUids = (string)($row['mention_uids'] ?? '');
    $message = csac_normalize_message_row($row, $uid, [
        'is_mentioned' => in_array((string)$uid, array_map('trim', explode(',', $mentionUids)), true),
        'reply_to_me' => $kind === 'reply',
        'mention_uids' => $mentionUids,
    ]);
    return [
        'id' => (int)$row['id'],
        'notice_id' => (int)$row['id'],
        'kind' => $kind,
        'notice_type' => $kind,
        'conversation_type' => 'group',
        'room_id' => (int)$row['room_id'],
        'room_name' => (string)($row['room_name'] ?? ''),
        'title' => $kind === 'reply' ? 'Reply to me' : '@ me',
        'is_read' => 0,
        'message' => $message,
    ] + $message;
}
