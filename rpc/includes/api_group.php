<?php
declare(strict_types=1);

function csac_api_group_create(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $name = csac_input_string('room_name');
    if ($name === '') {
        response_json(['success' => false, 'message' => '群组名称不能为空']);
    }
    if (mb_strlen($name, 'UTF-8') > 32) {
        response_json(['success' => false, 'message' => '群组名称最多32个字符']);
    }
    $code = createInviteCode();
    csac_begin();
    try {
        $rid = csac_insert_row('chat_room', [
            'room_name' => $name,
            'owner_uid' => $uid,
            'intro' => '',
            'notice' => '',
            'invite_code' => $code,
            'join_type' => 1,
            'show_in_list' => 0,
            'allow_invite' => 1,
            'is_disband' => 0,
            'avatar' => '',
        ]);
        csac_insert_ignore_row('chat_group_user', ['room_id' => $rid, 'uid' => $uid, 'mute_until' => 0, 'last_read_msg_id' => 0]);
        csac_commit();
    } catch (Throwable $e) {
        csac_rollback();
        throw $e;
    }
    response_json(['success' => true, 'message' => '群组创建成功', 'room_id' => $rid, 'id' => $rid, 'invite_code' => $code]);
}

function csac_api_group_get_public_list(): void
{
    requireLogin();
    $rows = csac_fetch_all(
        "SELECT
        r.id,
        r.id AS room_id,
        r.room_name,
        r.avatar,
        r.intro,
        r.join_type,
        r.owner_uid,
        r.ban_until,
        r.ban_reason,
        COALESCE(NULLIF(u.nickname, ''), CONCAT('UID ', r.owner_uid)) AS owner_name,
                           COALESCE(m.member_count, 0) AS member_count
                           FROM chat_room r
                           LEFT JOIN chat_user u ON u.id = r.owner_uid
                           LEFT JOIN (
                               SELECT room_id, COUNT(DISTINCT uid) AS member_count
                               FROM (
                                   SELECT id AS room_id, owner_uid AS uid
                                   FROM chat_room
                                   WHERE owner_uid > 0
                                   UNION ALL
                                   SELECT room_id, uid
                                   FROM chat_group_user
    ) member_source
    GROUP BY room_id
    ) m ON m.room_id = r.id
    WHERE r.show_in_list = 1
    ORDER BY r.id DESC"
    );
    foreach ($rows as &$row) {
        $row['id'] = (int)$row['id'];
        $row['room_id'] = (int)$row['room_id'];
        $row['join_type'] = (int)($row['join_type'] ?? 1);
        $row['owner_uid'] = (int)($row['owner_uid'] ?? 0);
        $row['owner_name'] = (string)($row['owner_name'] ?? '未知');
        $row['member_count'] = (int)($row['member_count'] ?? 0);
        $row['intro'] = (string)($row['intro'] ?? '');
        $row['avatar'] = (string)($row['avatar'] ?? '');
        $row['room_name'] = (string)($row['room_name'] ?? ('群组 ' . $row['room_id']));
        $row = array_merge($row, csac_room_ban_fields($row));
    }
    unset($row);
    response_json([
        'success' => true,
        'message' => '公开群组加载成功',
        'count' => count($rows),
                  'groups' => $rows,
    ]);
}

function csac_api_group_get_group_view_info(): void
{
    $uid = requireLogin();
    $rid = csac_input_int('rid', csac_input_int('room_id'));
    if ($rid <= 0) {
        response_json(['success' => false, 'message' => '无效的群ID']);
    }
    $room = csac_fetch_one(
        'SELECT cr.*, cu.nickname AS owner_name
        FROM chat_room cr
        LEFT JOIN chat_user cu ON cr.owner_uid = cu.id
        WHERE cr.id = ?',
        'i',
        $rid
    );
    if (!$room) {
        response_json(['success' => false, 'message' => '群组不存在'], 404);
    }
    $isInGroup = csac_is_group_member($rid, $uid);
    $hasApply = (bool)csac_fetch_one('SELECT id FROM chat_room_apply WHERE room_id = ? AND uid = ? AND status = 0 LIMIT 1', 'ii', $rid, $uid);
    $isOwner = (int)$room['owner_uid'] === $uid;
    $isAdmin = csac_is_group_admin($rid, $uid);
    $allowInvite = (int)($room['allow_invite'] ?? 1);
    $roomPayload = [
        'id' => (int)$room['id'],
        'room_id' => (int)$room['id'],
        'room_name' => $room['room_name'],
        'avatar' => (string)($room['avatar'] ?? ''),
        'intro' => $room['intro'] ?? '',
        'notice' => $room['notice'] ?? '',
        'invite_code' => $room['invite_code'] ?? '',
        'join_type' => (int)($room['join_type'] ?? 1),
        'owner_uid' => (int)$room['owner_uid'],
        'owner_name' => $room['owner_name'] ?? '未知',
        'ask_question' => $room['ask_question'] ?? '',
        'fixed_code' => $room['fixed_code'] ?? '',
        'show_in_list' => (int)($room['show_in_list'] ?? 1),
        'allow_invite' => $allowInvite,
    ];
    response_json([
        'success' => true,
        'room' => array_merge($roomPayload, csac_room_ban_fields($room)),
                  'is_in_group' => $isInGroup,
                  'has_apply' => $hasApply,
                  'is_owner' => $isOwner,
                  'is_admin' => $isOwner || $isAdmin,
                  'can_view_invite' => $isOwner || $isAdmin || $allowInvite === 1,
    ]);
}

function csac_api_group_get_members(): void
{
    $uid = requireLogin();
    $roomId = csac_input_int('room_id', csac_input_int('rid'));
    if ($roomId <= 0) {
        response_json(['success' => false, 'message' => '无效的群ID']);
    }
    requireGroupMember($roomId, $uid);
    $room = csac_room($roomId, 'owner_uid');
    $ownerUid = (int)$room['owner_uid'];
    $rows = csac_fetch_all(
        "SELECT u.id AS uid, u.nickname, u.avatar, u.last_active,
        CASE WHEN u.id = ? THEN 1 ELSE 0 END AS is_owner,
        CASE WHEN a.uid IS NULL THEN 0 ELSE 1 END AS is_admin,
        COALESCE(g.mute_until, 0) AS mute_until,
                           COALESCE(g.title, '') AS member_title,
                           COALESCE(g.level, 0) AS member_level
                           FROM chat_group_user g
                           JOIN chat_user u ON g.uid = u.id
                           LEFT JOIN chat_group_admin a ON a.room_id = g.room_id AND a.uid = g.uid
                           WHERE g.room_id = ?
                           ORDER BY is_owner DESC, is_admin DESC, u.nickname ASC",
                           'ii',
                           $ownerUid,
                           $roomId
    );
    $members = array_map(static function (array $row): array {
        $muteUntil = (int)($row['mute_until'] ?? 0);
        return [
            'uid' => (int)$row['uid'],
                         'nickname' => $row['nickname'] ?? '',
                         'avatar' => ($row['avatar'] ?? '') !== '' ? $row['avatar'] : CSAC_DEFAULT_AVATAR,
                         'is_owner' => (int)$row['is_owner'] === 1,
                         'is_admin' => (int)$row['is_admin'] === 1 || (int)$row['is_owner'] === 1,
                         'is_muted' => $muteUntil > time(),
                         'mute_until' => $muteUntil,
                         'title' => (string)($row['member_title'] ?? '') !== '' ? (string)$row['member_title'] : csac_group_default_title((int)($row['member_level'] ?? 1)),
                         'level' => max(1, (int)($row['member_level'] ?? 1)),
                         'member_title' => (string)($row['member_title'] ?? '') !== '' ? (string)$row['member_title'] : csac_group_default_title((int)($row['member_level'] ?? 1)),
                         'member_level' => max(1, (int)($row['member_level'] ?? 1)),
                         'online_status' => getOnlineStatus($row['last_active'] ?? ''),
        ];
    }, $rows);
    response_json(['success' => true, 'members' => $members]);
}

function csac_api_group_get_applications(): void
{
    $uid = requireLogin();
    $roomId = csac_input_int('room_id', csac_input_int('rid'));
    if ($roomId <= 0) {
        response_json(['success' => false, 'message' => '无效的群组 ID']);
    }
    requireGroupOwnerOrAdmin($roomId, $uid);
    $rows = csac_fetch_all(
        'SELECT a.*, u.nickname, u.username, u.avatar
        FROM chat_room_apply a
        JOIN chat_user u ON a.uid = u.id
        WHERE a.room_id = ? AND a.status = 0
        ORDER BY a.apply_time ASC, a.id ASC',
        'i',
        $roomId
    );
    $applications = array_map(static function (array $row): array {
        return [
            'id' => (int)$row['id'],
                              'uid' => (int)$row['uid'],
                              'nickname' => $row['nickname'] ?? '',
                              'username' => $row['username'] ?? '',
                              'avatar' => ($row['avatar'] ?? '') !== '' ? $row['avatar'] : CSAC_DEFAULT_AVATAR,
                              'answer_content' => $row['answer_content'] ?? '',
                              'apply_type' => (int)($row['apply_type'] ?? 1),
                              'apply_time' => $row['apply_time'] ?? '',
        ];
    }, $rows);
    response_json(['success' => true, 'applications' => $applications, 'applies' => $applications, 'requests' => $applications]);
}

function csac_api_group_apply_join(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id', csac_input_int('rid'));
    if ($roomId <= 0) {
        response_json(['success' => false, 'message' => '无效的房间ID']);
    }
    if (csac_is_group_member($roomId, $uid)) {
        response_json(['success' => false, 'message' => '你已经是群成员']);
    }
    $room = csac_room($roomId);
    if (!$room || (int)($room['is_disband'] ?? 0) !== 0) {
        response_json(['success' => false, 'message' => '群组不存在'], 404);
    }
    requireRoomNotBanned($roomId, $room);
    $joinType = (int)($room['join_type'] ?? 1);
    if ($joinType === 1) {
        csac_insert_ignore_row('chat_group_user', ['room_id' => $roomId, 'uid' => $uid, 'mute_until' => 0, 'last_read_msg_id' => 0]);
        response_json(['success' => true, 'message' => '成功加入群组']);
    }
    if ($joinType === 2 || $joinType === 3) {
        $code = csac_input_string('code');
        $rightCode = $joinType === 2 ? (string)($room['invite_code'] ?? '') : (string)($room['fixed_code'] ?? '');
        if ($code === '' || !hash_equals($rightCode, $code)) {
            response_json(['success' => false, 'message' => '邀请码错误']);
        }
        csac_insert_ignore_row('chat_group_user', ['room_id' => $roomId, 'uid' => $uid, 'mute_until' => 0, 'last_read_msg_id' => 0]);
        if ($joinType === 2) {
            resetRoomCode($roomId);
        }
        response_json(['success' => true, 'message' => '邀请码正确，成功加入']);
    }
    if ($joinType === 4) {
        if (csac_fetch_one('SELECT id FROM chat_room_apply WHERE room_id = ? AND uid = ? AND status = 0 LIMIT 1', 'ii', $roomId, $uid)) {
            response_json(['success' => false, 'message' => '你已提交申请，请等待审核']);
        }
        csac_insert_row('chat_room_apply', [
            'room_id' => $roomId,
            'uid' => $uid,
            'apply_type' => 1,
            'answer_content' => csac_input_string('answer'),
                        'apply_time' => date('Y-m-d H:i:s'),
                        'status' => 0,
        ]);
        response_json(['success' => true, 'message' => '答案已提交，等待管理员审核']);
    }
    response_json(['success' => false, 'message' => '群组加入方式异常']);
}

function csac_api_group_handle_apply(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $applyId = csac_input_int('apply_id');
    $action = csac_input_string('action');
    if ($applyId <= 0 || !in_array($action, ['pass', 'refuse'], true)) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    $apply = csac_fetch_one('SELECT * FROM chat_room_apply WHERE id = ?', 'i', $applyId);
    if (!$apply) {
        response_json(['success' => false, 'message' => '申请不存在'], 404);
    }
    $roomId = (int)$apply['room_id'];
    requireGroupOwnerOrAdmin($roomId, $uid);
    $newStatus = $action === 'pass' ? 1 : 2;
    csac_begin();
    try {
        csac_update_row('chat_room_apply', ['status' => $newStatus], 'id = ?', [$applyId]);
        if ($newStatus === 1) {
            csac_insert_ignore_row('chat_group_user', ['room_id' => $roomId, 'uid' => (int)$apply['uid'], 'mute_until' => 0, 'last_read_msg_id' => 0]);
            resetRoomCode($roomId);
        }
        csac_commit();
    } catch (Throwable $e) {
        csac_rollback();
        throw $e;
    }
    response_json(['success' => true, 'message' => $newStatus === 1 ? '已通过' : '已拒绝']);
}

function csac_api_group_invite_member(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id', csac_input_int('rid'));
    $targetUid = csac_input_int('target_uid', csac_input_int('uid'));
    if ($roomId <= 0 || $targetUid <= 0) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    $room = requireGroupMember($roomId, $uid);
    $allowInvite = (int)($room['allow_invite'] ?? 1) === 1;
    $isOwner = (int)$room['owner_uid'] === $uid;
    $isAdmin = csac_is_group_admin($roomId, $uid);
    if (!$allowInvite && !$isOwner && !$isAdmin) {
        response_json(['success' => false, 'message' => '该群不允许成员邀请']);
    }
    if (csac_is_group_member($roomId, $targetUid)) {
        response_json(['success' => false, 'message' => '目标用户已在群内']);
    }
    $target = csac_user($targetUid, 'id, nickname, allow_auto_join');
    if (!$target) {
        response_json(['success' => false, 'message' => '用户不存在'], 404);
    }
    if ((int)($target['allow_auto_join'] ?? 1) === 1) {
        csac_insert_ignore_row('chat_group_user', ['room_id' => $roomId, 'uid' => $targetUid, 'mute_until' => 0, 'last_read_msg_id' => 0, 'title' => csac_group_default_title(1), 'level' => 1]);
        csac_notice($targetUid, '已加入群组', ($_SESSION['nickname'] ?? '用户') . ' 邀请你加入群组【' . ($room['room_name'] ?? $roomId) . '】');
        response_json(['success' => true, 'message' => '已自动加入群组', 'auto_joined' => true]);
    }
    csac_insert_row('chat_room_apply', [
        'room_id' => $roomId,
        'uid' => $targetUid,
        'apply_type' => 2,
        'answer_content' => ($_SESSION['nickname'] ?? '用户') . ' 邀请加入',
                    'apply_time' => date('Y-m-d H:i:s'),
                    'status' => 0,
    ]);
    csac_notice($targetUid, '群组邀请', ($_SESSION['nickname'] ?? '用户') . ' 邀请你加入群组【' . ($room['room_name'] ?? $roomId) . '】');
    response_json(['success' => true, 'message' => '邀请已发送，等待对方确认', 'auto_joined' => false]);
}

function csac_api_group_edit_info(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id');
    if ($roomId <= 0) {
        response_json(['success' => false, 'message' => '无效的房间ID']);
    }
    requireGroupOwnerOrAdmin($roomId, $uid);
    $updates = [];
    $action = csac_input_string('action');
    if ($action !== '') {
        $value = csac_input_string('value');
        if ($action === 'name') {
            if ($value === '') {
                response_json(['success' => false, 'message' => '名称不能为空']);
            }
            $updates['room_name'] = $value;
        } elseif ($action === 'avatar') {
            if (isset($_FILES['avatar']) && ($_FILES['avatar']['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_OK) {
                $updates['avatar'] = csac_upload_file(
                    $_FILES['avatar'],
                    ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp'],
                    CSAC_MAX_IMAGE_BYTES,
                    UPLOAD_DIR . 'room/',
                    'upload/room',
                    'room_avatar_' . $roomId
                );
            } else {
                $updates['avatar'] = $value;
            }
        } elseif (in_array($action, ['intro', 'notice'], true)) {
            $updates[$action] = $value;
        } else {
            response_json(['success' => false, 'message' => '未知编辑类型']);
        }
    } else {
        foreach (['room_name', 'intro', 'notice', 'avatar'] as $field) {
            $value = csac_input_string($field, "\0");
            if ($value !== "\0") {
                $updates[$field] = $value;
            }
        }
        if (isset($_FILES['avatar']) && ($_FILES['avatar']['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_OK) {
            $updates['avatar'] = csac_upload_file(
                $_FILES['avatar'],
                ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp'],
                CSAC_MAX_IMAGE_BYTES,
                UPLOAD_DIR . 'room/',
                'upload/room',
                'room_avatar_' . $roomId
            );
        }
        if (isset($updates['room_name']) && $updates['room_name'] === '') {
            response_json(['success' => false, 'message' => '名称不能为空']);
        }
    }
    if (!$updates) {
        response_json(['success' => false, 'message' => '没有可更新内容']);
    }
    csac_update_row('chat_room', $updates, 'id = ?', [$roomId]);
    response_json(['success' => true, 'message' => '修改成功', 'avatar' => $updates['avatar'] ?? null]);
}

function csac_api_group_set_member_title(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id', csac_input_int('rid'));
    $targetUid = csac_input_int('target_uid', csac_input_int('uid'));
    if ($roomId <= 0 || $targetUid <= 0) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    $room = requireGroupOwnerOrAdmin($roomId, $uid);
    if (!csac_is_group_member($roomId, $targetUid)) {
        response_json(['success' => false, 'message' => '目标用户不是群成员']);
    }
    if (!csac_check_session_ext() && (int)$room['owner_uid'] !== $uid && csac_is_group_admin($roomId, $targetUid)) {
        response_json(['success' => false, 'message' => '管理员不能设置其他管理员头衔']);
    }
    $title = csac_input_string('title');
    $level = csac_input_int('level');
    if (mb_strlen($title, 'UTF-8') > 16) {
        response_json(['success' => false, 'message' => '头衔最多16个字符']);
    }
    if ($level < 1 || (!csac_check_session_ext() && $level > 100)) {
        response_json(['success' => false, 'message' => '等级范围需在1到100之间']);
    }
    $updates = ['title' => $title, 'level' => $level];
    if (csac_has_column('chat_group_user', 'title_custom')) {
        $updates['title_custom'] = $title === '' || csac_group_title_is_default($title) ? 0 : 1;
    }
    if (csac_has_column('chat_group_user', 'level_custom')) {
        $updates['level_custom'] = 1;
    }
    csac_update_row('chat_group_user', $updates, 'room_id = ? AND uid = ?', [$roomId, $targetUid]);
    response_json(['success' => true, 'message' => '群员头衔已更新', 'title' => $title, 'level' => $level]);
}

function csac_api_group_update_settings(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id');
    if ($roomId <= 0) {
        response_json(['success' => false, 'message' => '无效的房间ID']);
    }
    requireGroupOwnerOrAdmin($roomId, $uid);
    $updates = [];
    $joinType = csac_input_int('join_type');
    if ($joinType >= 1 && $joinType <= 4) {
        $updates['join_type'] = $joinType;
    }
    foreach (['fixed_code' => 'fixed_code', 'question' => 'ask_question', 'answer' => 'ask_answer'] as $input => $column) {
        $value = csac_input_string($input, "\0");
        if ($value !== "\0" && $value !== '') {
            $updates[$column] = $value;
        }
    }
    foreach (['show_in_list', 'allow_invite'] as $flag) {
        if (array_key_exists($flag, csac_input())) {
            $updates[$flag] = csac_input_bool($flag) ? 1 : 0;
        }
    }
    if ($updates) {
        csac_update_row('chat_room', $updates, 'id = ?', [$roomId]);
    }
    response_json(['success' => true, 'message' => '设置已更新']);
}

function csac_api_group_reset_invite_code(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id');
    if ($roomId <= 0) {
        response_json(['success' => false, 'message' => '无效的房间ID']);
    }
    requireGroupOwner($roomId, $uid);
    $code = resetRoomCode($roomId);
    response_json(['success' => true, 'message' => '邀请码已重置', 'invite_code' => $code, 'new_code' => $code]);
}

function csac_api_group_transfer(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id');
    $targetUid = csac_input_int('target_uid', csac_input_int('new_owner_uid'));
    if ($roomId <= 0 || $targetUid <= 0) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    if ($targetUid === $uid && !csac_check_session_ext()) {
        response_json(['success' => false, 'message' => '不能转让给自己']);
    }
    $room = requireGroupOwner($roomId, $uid, true);
    if (!csac_check_session_ext() && (int)($room['owner_transfer_cd'] ?? 0) > time()) {
        response_json(['success' => false, 'message' => '转让冷静期内（28天）无法转让']);
    }
    if (!csac_check_session_ext() && !csac_is_group_member($roomId, $targetUid)) {
        response_json(['success' => false, 'message' => '目标用户不是群成员']);
    }
    if (csac_check_session_ext()) {
        csac_begin();
        try {
            csac_insert_ignore_row('chat_group_user', [
                'room_id' => $roomId,
                'uid' => $targetUid,
                'add_time' => time(),
            ]);
            csac_update_row('chat_room', [
                'owner_uid' => $targetUid,
                'owner_transfer_cd' => time() + 28 * 86400,
            ], 'id = ?', [$roomId]);
            csac_execute('DELETE FROM chat_group_admin WHERE room_id = ? AND uid = ?', 'ii', $roomId, $targetUid);
            csac_commit();
        } catch (Throwable $e) {
            csac_rollback();
            throw $e;
        }
        csac_notice($targetUid, '群主变更通知', "您已成为群组【{$room['room_name']}】的群主", '#/group/' . $roomId);
        response_json(['success' => true, 'message' => '群主已转让']);
    }
    $transferId = csac_insert_row('chat_room_transfer', [
        'room_id' => $roomId,
        'old_owner' => $uid,
        'new_owner' => $targetUid,
        'status' => 0,
        'create_time' => date('Y-m-d H:i:s'),
    ]);
    $myNick = csac_user($uid, 'nickname')['nickname'] ?? '群主';
    csac_notice($targetUid, '收到群组转让申请', "{$myNick} 邀请你接管群组【{$room['room_name']}】，请前往查看并确认", '#/group/' . $roomId);
    response_json(['success' => true, 'message' => '转让申请已发送', 'transfer_id' => $transferId]);
}

function csac_api_group_disband(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id');
    if ($roomId <= 0) {
        response_json(['success' => false, 'message' => '无效的房间ID']);
    }
    $room = requireGroupOwner($roomId, $uid, true);
    csac_update_row('chat_room', ['is_disband' => 1, 'disband_time' => time()], 'id = ?', [$roomId]);
    $members = csac_fetch_all('SELECT uid FROM chat_group_user WHERE room_id = ?', 'i', $roomId);
    foreach ($members as $member) {
        csac_notice((int)$member['uid'], '群组已解散', '该群组已被群主解散，3天后将自动永久清除所有数据');
    }
    response_json(['success' => true, 'message' => '群组已解散']);
}

function csac_api_group_leave(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id', csac_input_int('rid'));
    if ($roomId <= 0) {
        response_json(['success' => false, 'message' => '无效的房间ID']);
    }
    $room = requireGroupMember($roomId, $uid, true);
    if ((int)$room['owner_uid'] === $uid) {
        response_json(['success' => false, 'message' => '群主不能直接退群，请先转让或解散群组']);
    }
    csac_execute('DELETE FROM chat_group_user WHERE room_id = ? AND uid = ?', 'ii', $roomId, $uid);
    csac_execute('DELETE FROM chat_group_admin WHERE room_id = ? AND uid = ?', 'ii', $roomId, $uid);
    response_json(['success' => true, 'message' => '已退出群组']);
}

function csac_api_group_mute_member(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id');
    $targetUid = csac_input_int('target_uid');
    $action = csac_input_string('action');
    if ($roomId <= 0 || $targetUid <= 0) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    if ($targetUid === $uid) {
        response_json(['success' => false, 'message' => '不能对自己操作']);
    }
    $room = requireGroupOwnerOrAdmin($roomId, $uid);
    if ((int)$room['owner_uid'] === $targetUid) {
        response_json(['success' => false, 'message' => '不能操作群主']);
    }
    if ((int)$room['owner_uid'] !== $uid && csac_is_group_admin($roomId, $targetUid)) {
        response_json(['success' => false, 'message' => '管理员不能操作其他管理员']);
    }
    if ($action === 'mute') {
        $minutes = csac_input_int('minutes');
        if ($minutes < 1 || $minutes > 43200) {
            response_json(['success' => false, 'message' => '禁言时长需在1到43200分钟之间']);
        }
        $until = time() + $minutes * 60;
        csac_update_row('chat_group_user', ['mute_until' => $until], 'room_id = ? AND uid = ?', [$roomId, $targetUid]);
        response_json(['success' => true, 'message' => "已禁言 {$minutes} 分钟"]);
    }
    if ($action === 'unmute') {
        csac_update_row('chat_group_user', ['mute_until' => 0], 'room_id = ? AND uid = ?', [$roomId, $targetUid]);
        response_json(['success' => true, 'message' => '已解除禁言']);
    }
    response_json(['success' => false, 'message' => '未知操作']);
}

function csac_api_group_kick_member(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id');
    $targetUid = csac_input_int('target_uid');
    if ($roomId <= 0 || $targetUid <= 0) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    if ($targetUid === $uid) {
        response_json(['success' => false, 'message' => '不能踢自己']);
    }
    $room = requireGroupOwnerOrAdmin($roomId, $uid);
    if ((int)$room['owner_uid'] === $targetUid) {
        response_json(['success' => false, 'message' => '不能踢出群主']);
    }
    if ((int)$room['owner_uid'] !== $uid && csac_is_group_admin($roomId, $targetUid)) {
        response_json(['success' => false, 'message' => '管理员不能踢出其他管理员']);
    }
    csac_execute('DELETE FROM chat_group_user WHERE room_id = ? AND uid = ?', 'ii', $roomId, $targetUid);
    csac_execute('DELETE FROM chat_group_admin WHERE room_id = ? AND uid = ?', 'ii', $roomId, $targetUid);
    resetRoomCode($roomId);
    response_json(['success' => true, 'message' => '已踢出']);
}

function csac_api_group_set_admin(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $roomId = csac_input_int('room_id');
    $targetUid = csac_input_int('target_uid');
    $action = csac_input_string('action');
    if ($roomId <= 0 || $targetUid <= 0) {
        response_json(['success' => false, 'message' => '参数错误']);
    }
    requireGroupOwner($roomId, $uid);
    if ($targetUid === $uid) {
        response_json(['success' => false, 'message' => '不能操作自己']);
    }
    if (!csac_is_group_member($roomId, $targetUid)) {
        response_json(['success' => false, 'message' => '目标用户不是群成员']);
    }
    if ($action === 'set') {
        csac_insert_ignore_row('chat_group_admin', ['room_id' => $roomId, 'uid' => $targetUid, 'add_time' => time()]);
        response_json(['success' => true, 'message' => '已设为管理员']);
    }
    if ($action === 'remove') {
        csac_execute('DELETE FROM chat_group_admin WHERE room_id = ? AND uid = ?', 'ii', $roomId, $targetUid);
        response_json(['success' => true, 'message' => '已撤销管理员']);
    }
    response_json(['success' => false, 'message' => '操作类型错误']);
}
