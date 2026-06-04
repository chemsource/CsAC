<?php
declare(strict_types=1);

function csac_api_friend_send_request(): void
{
    csac_require_method('POST');
    $myUid = requireLogin();
    $toUid = csac_input_int('to_uid', csac_input_int('friend_id'));
    $content = csac_input_string('message', '请求添加你为好友');
    if ($toUid <= 0) {
        response_json(['success' => false, 'message' => '无效的用户ID']);
    }
    if ($toUid === $myUid) {
        response_json(['success' => false, 'message' => '不能添加自己为好友']);
    }
    $target = csac_user($toUid, 'id, nickname');
    if (!$target) {
        response_json(['success' => false, 'message' => '用户不存在'], 404);
    }

    [$uid1, $uid2] = csac_friend_pair($myUid, $toUid);
    $rel = csac_friend_relation($myUid, $toUid);
    if ($rel) {
        $status = (int)$rel['status'];
        if ($status === 1) {
            response_json(['success' => false, 'message' => '你们已经是好友了']);
        }
        if ($status === 0) {
            if ((int)($rel['from_uid'] ?? 0) === $myUid) {
                response_json(['success' => false, 'message' => '你已发送过好友请求，等待确认']);
            }
            response_json(['success' => false, 'message' => '对方已向你发送好友请求，请先处理']);
        }
        if ($status === 4) {
            response_json(['success' => false, 'message' => '存在拉黑关系，无法添加']);
        }
    }
    if (csac_fetch_one('SELECT id FROM friend_request WHERE from_uid = ? AND to_uid = ? AND status = 0 LIMIT 1', 'ii', $myUid, $toUid)) {
        response_json(['success' => false, 'message' => '你已发送过好友请求，等待确认']);
    }
    if (csac_fetch_one('SELECT id FROM friend_request WHERE from_uid = ? AND to_uid = ? AND status = 0 LIMIT 1', 'ii', $toUid, $myUid)) {
        response_json(['success' => false, 'message' => '对方已向你发送好友请求，请先处理']);
    }

    csac_begin();
    try {
        if ($rel) {
            csac_update_row('friend_relation', [
                'status' => 0,
                'from_uid' => $myUid,
                'delete_by' => null,
                'delete_time' => null,
                'update_time' => date('Y-m-d H:i:s'),
            ], 'uid1 = ? AND uid2 = ?', [$uid1, $uid2]);
        } else {
            csac_insert_row('friend_relation', [
                'uid1' => $uid1,
                'uid2' => $uid2,
                'status' => 0,
                'from_uid' => $myUid,
                'create_time' => date('Y-m-d H:i:s'),
                            'created_at' => date('Y-m-d H:i:s'),
                            'update_time' => date('Y-m-d H:i:s'),
            ]);
        }
        csac_insert_row('friend_request', [
            'from_uid' => $myUid,
            'to_uid' => $toUid,
            'type' => 1,
            'status' => 0,
            'content' => $content !== '' ? $content : '请求添加你为好友',
            'create_time' => date('Y-m-d H:i:s'),
        ]);
        csac_commit();
    } catch (Throwable $e) {
        csac_rollback();
        throw $e;
    }
    response_json(['success' => true, 'message' => '好友请求已发送']);
}

function csac_api_friend_handle_request(): void
{
    csac_require_method('POST');
    $myUid = requireLogin();
    $requestId = csac_input_int('request_id');
    $action = csac_input_string('action');
    if ($requestId <= 0 || !in_array($action, ['agree', 'refuse'], true)) {
        response_json(['success' => false, 'message' => '参数错误']);
    }

    $request = csac_fetch_one('SELECT * FROM friend_request WHERE id = ? AND to_uid = ? AND status = 0', 'ii', $requestId, $myUid);
    if (!$request) {
        response_json(['success' => false, 'message' => '请求不存在或已处理']);
    }
    $fromUid = (int)$request['from_uid'];
    [$uid1, $uid2] = csac_friend_pair($myUid, $fromUid);

    csac_begin();
    try {
        $status = $action === 'agree' ? 1 : 2;
        csac_execute('UPDATE friend_request SET status = ? WHERE id = ?', 'ii', $status, $requestId);
        if ($action === 'agree') {
            $rel = csac_friend_relation($myUid, $fromUid);
            if ($rel) {
                csac_update_row('friend_relation', [
                    'status' => 1,
                    'from_uid' => $fromUid,
                    'delete_by' => null,
                    'delete_time' => null,
                    'update_time' => date('Y-m-d H:i:s'),
                ], 'uid1 = ? AND uid2 = ?', [$uid1, $uid2]);
            } else {
                csac_insert_row('friend_relation', [
                    'uid1' => $uid1,
                    'uid2' => $uid2,
                    'status' => 1,
                    'from_uid' => $fromUid,
                    'create_time' => date('Y-m-d H:i:s'),
                                'update_time' => date('Y-m-d H:i:s'),
                ]);
            }
        }
        csac_commit();
    } catch (Throwable $e) {
        csac_rollback();
        throw $e;
    }
    response_json(['success' => true, 'message' => $action === 'agree' ? '已同意' : '已拒绝']);
}

function csac_api_friend_delete_friend(): void
{
    csac_friend_remove_common(2, '好友已删除', ' 删除了好友关系');
}

function csac_api_friend_block_friend(): void
{
    csac_friend_remove_common(4, '好友已拉黑', ' 已将你拉黑');
}

function csac_friend_remove_common(int $status, string $successMessage, string $noticeSuffix): void
{
    csac_require_method('POST');
    $myUid = requireLogin();
    $friendId = csac_input_int('friend_id');
    if ($friendId <= 0) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    csac_require_friend($myUid, $friendId);
    [$uid1, $uid2] = csac_friend_pair($myUid, $friendId);
    csac_update_row('friend_relation', [
        'status' => $status,
        'delete_time' => date('Y-m-d H:i:s'),
                    'delete_by' => $myUid,
                    'update_time' => date('Y-m-d H:i:s'),
    ], 'uid1 = ? AND uid2 = ?', [$uid1, $uid2]);
    csac_private_system_message($myUid, $friendId, ($_SESSION['nickname'] ?? '用户') . $noticeSuffix);
    response_json(['success' => true, 'message' => $successMessage]);
}

function csac_api_friend_recover_friend(): void
{
    csac_require_method('POST');
    $myUid = requireLogin();
    $friendId = csac_input_int('friend_id');
    $direct = csac_input_bool('direct');
    if ($friendId <= 0) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    $rel = csac_friend_relation($myUid, $friendId);
    if (!$rel) {
        response_json(['success' => false, 'message' => '你们还不是好友']);
    }
    [$uid1, $uid2] = csac_friend_pair($myUid, $friendId);
    $status = (int)$rel['status'];
    $deleteBy = (int)($rel['delete_by'] ?? 0);
    if ($direct) {
        if (!in_array($status, [2, 4], true) || $deleteBy !== $myUid) {
            response_json(['success' => false, 'message' => '当前状态无法直接恢复']);
        }
        csac_update_row('friend_relation', ['status' => 1, 'delete_time' => null, 'delete_by' => null, 'update_time' => date('Y-m-d H:i:s')], 'uid1 = ? AND uid2 = ?', [$uid1, $uid2]);
        response_json(['success' => true, 'message' => '好友关系已恢复']);
    }
    if (!in_array($status, [2, 3], true)) {
        response_json(['success' => false, 'message' => '当前状态无法申请恢复']);
    }
    if (!empty($rel['delete_time']) && strtotime((string)$rel['delete_time']) < time() - 259200) {
        response_json(['success' => false, 'message' => '删除已超过3天，无法恢复']);
    }
    $recent = csac_fetch_one("SELECT id FROM friend_request WHERE from_uid = ? AND to_uid = ? AND type = 'recover' AND status IN (0,2) AND UNIX_TIMESTAMP(create_time) > ?", 'iii', $myUid, $friendId, time() - 86400);
    if ($recent) {
        response_json(['success' => false, 'message' => '24小时内已发送过恢复请求']);
    }
    $message = csac_input_string('message', '希望恢复好友关系');
    csac_insert_row('friend_request', [
        'from_uid' => $myUid,
        'to_uid' => $friendId,
        'type' => 'recover',
        'status' => 0,
        'content' => $message,
        'create_time' => date('Y-m-d H:i:s'),
    ]);
    csac_private_system_message($myUid, $friendId, ($_SESSION['nickname'] ?? '用户') . ' 请求恢复好友关系');
    response_json(['success' => true, 'message' => '恢复请求已发送']);
}

function csac_api_friend_update_remark(): void
{
    csac_require_method('POST');
    $myUid = requireLogin();
    $friendId = csac_input_int('friend_id');
    $remark = csac_input_string('remark');
    if ($friendId <= 0) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    csac_require_friend($myUid, $friendId);
    [$uid1, $uid2] = csac_friend_pair($myUid, $friendId);
    $field = $myUid === $uid1 ? 'remark1' : 'remark2';
    csac_update_row('friend_relation', [$field => $remark, 'update_time' => date('Y-m-d H:i:s')], 'uid1 = ? AND uid2 = ?', [$uid1, $uid2]);
    response_json(['success' => true, 'message' => '备注已更新']);
}

function csac_api_friend_get_common_groups(): void
{
    $myUid = requireLogin();
    $friendId = csac_input_int('friend_id');
    if ($friendId <= 0) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    $rows = csac_fetch_all(
        'SELECT DISTINCT cr.id, cr.id AS room_id, cr.room_name, cr.avatar, cr.invite_code, cr.intro
        FROM chat_room cr
        JOIN chat_group_user g1 ON cr.id = g1.room_id AND g1.uid = ?
        JOIN chat_group_user g2 ON cr.id = g2.room_id AND g2.uid = ?
        ORDER BY cr.id DESC',
        'ii',
        $myUid,
        $friendId
    );
    response_json(['success' => true, 'groups' => $rows]);
}

function csac_api_friend_get_deleted_notices(): void
{
    $myUid = requireLogin();
    $rows = csac_fetch_all(
        "SELECT CASE WHEN f.uid1 = ? THEN f.uid2 ELSE f.uid1 END AS friend_id,
        u.nickname, u.avatar, u.username, f.delete_time, f.delete_by
        FROM friend_relation f
        JOIN chat_user u ON ((f.uid1 = ? AND f.uid2 = u.id) OR (f.uid2 = ? AND f.uid1 = u.id))
    WHERE f.status = 2 AND f.delete_time > DATE_SUB(NOW(), INTERVAL 3 DAY)
    ORDER BY f.delete_time DESC",
    'iii',
    $myUid,
    $myUid,
    $myUid
    );
    response_json(['success' => true, 'notices' => $rows]);
}

function csac_api_friend_get_friend_requests(): void
{
    $myUid = requireLogin();
    $rows = csac_fetch_all(
        'SELECT r.*, u.nickname, u.avatar, u.username
        FROM friend_request r
        JOIN chat_user u ON r.from_uid = u.id
        WHERE r.to_uid = ? AND r.status = 0
        ORDER BY r.create_time DESC',
        'i',
        $myUid
    );
    foreach ($rows as &$row) {
        $row['id'] = (int)$row['id'];
        $row['from_uid'] = (int)$row['from_uid'];
        $row['to_uid'] = (int)$row['to_uid'];
    }
    unset($row);
    response_json(['success' => true, 'requests' => $rows]);
}
