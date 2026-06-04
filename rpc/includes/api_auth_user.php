<?php
declare(strict_types=1);

function csac_api_auth_login(): void
{
    csac_require_method('POST');
    $username = csac_input_string('username');
    $pwd = csac_input_string('pwd');
    $platform = csac_normalize_platform(csac_input_string('platform'));
    if ($username === '' || $pwd === '' || $platform === '') {
        response_json(['success' => false, 'message' => '请填写账号、密码和客户端标识']);
    }

    $user = csac_fetch_one('SELECT * FROM chat_user WHERE username = ?', 's', $username);
    if (!$user || !csac_is_password_valid($user, $pwd)) {
        response_json(['success' => false, 'message' => '账号或密码错误']);
    }

    $uid = (int)$user['id'];
    $ban = checkUserBan($uid);
    if ($ban !== false) {
        response_json(['success' => false, 'message' => '账号已封禁', 'ban_info' => $ban], 403);
    }

    session_regenerate_id(true);
    $_SESSION['user_id'] = $uid;
    $_SESSION['nickname'] = $user['nickname'] ?? '';
    $_SESSION['platform'] = $platform;
    csac_update_user_platform($uid, $platform);
    csac_touch_user($uid);

    $needGuide = (int)($user['is_first_login'] ?? 0) === 1;
    if ($needGuide) {
        csac_update_row('chat_user', ['is_first_login' => 0], 'id = ?', [$uid]);
    }
    $needsEmailVerification = CSAC_REQUIRE_EXISTING_USER_EMAIL_VERIFICATION && trim((string)($user['email'] ?? '')) === '';

    response_json([
        'success' => true,
        'message' => '登录成功',
        'need_guide' => $needGuide,
        'needs_email_verification' => $needsEmailVerification,
        'platform' => $platform,
        'user' => [
            'uid' => $uid,
            'nickname' => $user['nickname'] ?? '',
            'platform' => $platform,
        ],
    ]);
}

function csac_api_auth_send_email_bind_code(): void
{
    csac_require_method('POST');
    $uid = csac_require_pending_email_user();
    $email = csac_normalize_register_email(csac_input_string('email'));
    if ($email === '') {
        response_json(['success' => false, 'message' => '请输入有效的邮箱地址']);
    }
    if (csac_fetch_one('SELECT id FROM chat_user WHERE email = ? AND id <> ? LIMIT 1', 'si', $email, $uid)) {
        response_json(['success' => false, 'message' => '该邮箱已被注册']);
    }

    $now = time();
    $ipHash = csac_register_email_ip_hash();
    $cooldownSince = $now - CSAC_REGISTER_EMAIL_RESEND_SECONDS;
    $recentEmail = csac_fetch_one('SELECT id FROM register_email_codes WHERE email = ? AND created_at > ? LIMIT 1', 'si', $email, $cooldownSince);
    $recentIp = csac_fetch_one('SELECT id FROM register_email_codes WHERE ip_hash = ? AND created_at > ? LIMIT 1', 'si', $ipHash, $cooldownSince);
    if ($recentEmail || $recentIp) {
        response_json(['success' => false, 'message' => '验证码发送过于频繁，请稍后再试']);
    }

    $hourSince = $now - 3600;
    $emailCount = (int)(csac_fetch_one('SELECT COUNT(*) AS c FROM register_email_codes WHERE email = ? AND created_at > ?', 'si', $email, $hourSince)['c'] ?? 0);
    $ipCount = (int)(csac_fetch_one('SELECT COUNT(*) AS c FROM register_email_codes WHERE ip_hash = ? AND created_at > ?', 'si', $ipHash, $hourSince)['c'] ?? 0);
    if ($emailCount >= CSAC_REGISTER_EMAIL_MAX_SENDS_PER_HOUR || $ipCount >= CSAC_REGISTER_EMAIL_MAX_SENDS_PER_HOUR) {
        response_json(['success' => false, 'message' => '验证码发送次数过多，请稍后再试']);
    }

    $code = (string)random_int(100000, 999999);
    $codeId = csac_insert_row('register_email_codes', [
        'email' => $email,
        'code_hash' => password_hash($code, PASSWORD_DEFAULT),
        'ip_hash' => $ipHash,
        'attempts' => 0,
        'used_at' => 0,
        'expires_at' => $now + CSAC_REGISTER_EMAIL_CODE_TTL,
        'created_at' => $now,
    ]);

    try {
        csac_send_register_email_code($email, $code);
    } catch (Throwable $e) {
        csac_execute('DELETE FROM register_email_codes WHERE id = ?', 'i', $codeId);
        csac_log_error($e);
        response_json(['success' => false, 'message' => '验证码邮件发送失败，请稍后再试'], 500);
    }

    response_json([
        'success' => true,
        'message' => '验证码已发送，请查收邮箱',
        'expires_in' => CSAC_REGISTER_EMAIL_CODE_TTL,
        'resend_after' => CSAC_REGISTER_EMAIL_RESEND_SECONDS,
    ]);
}

function csac_api_auth_verify_email_bind_code(): void
{
    csac_require_method('POST');
    $uid = csac_require_pending_email_user();
    $email = csac_normalize_register_email(csac_input_string('email'));
    $emailCode = csac_input_string('email_code');
    if ($email === '' || $emailCode === '') {
        response_json(['success' => false, 'message' => '请填写邮箱和验证码']);
    }
    if (csac_fetch_one('SELECT id FROM chat_user WHERE email = ? AND id <> ? LIMIT 1', 'si', $email, $uid)) {
        response_json(['success' => false, 'message' => '该邮箱已被注册']);
    }

    $emailCodeId = csac_verified_register_email_code_id($email, $emailCode);
    csac_begin();
    try {
        $used = csac_execute('UPDATE register_email_codes SET used_at = ? WHERE id = ? AND used_at = 0', 'ii', time(), $emailCodeId);
        if ($used !== 1) {
            csac_rollback();
            response_json(['success' => false, 'message' => '验证码已失效，请重新获取']);
        }
        csac_update_row('chat_user', ['email' => $email], 'id = ?', [$uid]);
        csac_commit();
    } catch (Throwable $e) {
        csac_rollback();
        throw $e;
    }

    response_json(['success' => true, 'message' => '邮箱验证已完成']);
}

function csac_require_pending_email_user(): int
{
    $uid = (int)($_SESSION['user_id'] ?? 0);
    if ($uid <= 0 || !checkUserExists($uid)) {
        response_json(['success' => false, 'message' => '未登录'], 401);
    }
    $ban = checkUserBan($uid);
    if ($ban !== false) {
        session_destroy();
        response_json(['success' => false, 'message' => '账号已封禁', 'ban_info' => $ban], 403);
    }
    if (csac_user_email_verified($uid)) {
        response_json(['success' => true, 'message' => '邮箱已验证']);
    }
    return $uid;
}

function csac_api_auth_send_register_code(): void
{
    csac_require_method('POST');
    if (!CSAC_REQUIRE_REGISTER_EMAIL_VERIFICATION) {
        response_json(['success' => true, 'message' => '邮箱验证未启用']);
    }

    $email = csac_normalize_register_email(csac_input_string('email'));
    if ($email === '') {
        response_json(['success' => false, 'message' => '请输入有效的邮箱地址']);
    }
    if (csac_fetch_one('SELECT id FROM chat_user WHERE email = ? LIMIT 1', 's', $email)) {
        response_json(['success' => false, 'message' => '该邮箱已被注册']);
    }

    $now = time();
    $ipHash = csac_register_email_ip_hash();
    $cooldownSince = $now - CSAC_REGISTER_EMAIL_RESEND_SECONDS;
    $recentEmail = csac_fetch_one('SELECT id FROM register_email_codes WHERE email = ? AND created_at > ? LIMIT 1', 'si', $email, $cooldownSince);
    $recentIp = csac_fetch_one('SELECT id FROM register_email_codes WHERE ip_hash = ? AND created_at > ? LIMIT 1', 'si', $ipHash, $cooldownSince);
    if ($recentEmail || $recentIp) {
        response_json(['success' => false, 'message' => '验证码发送过于频繁，请稍后再试']);
    }

    $hourSince = $now - 3600;
    $emailCount = (int)(csac_fetch_one('SELECT COUNT(*) AS c FROM register_email_codes WHERE email = ? AND created_at > ?', 'si', $email, $hourSince)['c'] ?? 0);
    $ipCount = (int)(csac_fetch_one('SELECT COUNT(*) AS c FROM register_email_codes WHERE ip_hash = ? AND created_at > ?', 'si', $ipHash, $hourSince)['c'] ?? 0);
    if ($emailCount >= CSAC_REGISTER_EMAIL_MAX_SENDS_PER_HOUR || $ipCount >= CSAC_REGISTER_EMAIL_MAX_SENDS_PER_HOUR) {
        response_json(['success' => false, 'message' => '验证码发送次数过多，请稍后再试']);
    }

    $code = (string)random_int(100000, 999999);
    $codeId = csac_insert_row('register_email_codes', [
        'email' => $email,
        'code_hash' => password_hash($code, PASSWORD_DEFAULT),
        'ip_hash' => $ipHash,
        'attempts' => 0,
        'used_at' => 0,
        'expires_at' => $now + CSAC_REGISTER_EMAIL_CODE_TTL,
        'created_at' => $now,
    ]);

    try {
        csac_send_register_email_code($email, $code);
    } catch (Throwable $e) {
        csac_execute('DELETE FROM register_email_codes WHERE id = ?', 'i', $codeId);
        csac_log_error($e);
        response_json(['success' => false, 'message' => '验证码邮件发送失败，请稍后再试'], 500);
    }

    response_json([
        'success' => true,
        'message' => '验证码已发送，请查收邮箱',
        'expires_in' => CSAC_REGISTER_EMAIL_CODE_TTL,
        'resend_after' => CSAC_REGISTER_EMAIL_RESEND_SECONDS,
    ]);
}

function csac_api_auth_register(): void
{
    csac_require_method('POST');
    $banNames = ['root', 'admin', 'administrator', 'system', 'guest', '客服', '管理', '管理员', '超级管理员', '官方', '站长', '后台'];
    $username = csac_input_string('username');
    $nickname = csac_input_string('nickname');
    $pwd = csac_input_string('pwd');
    $confirmPwd = csac_input_string('confirm_pwd');
    $email = csac_normalize_register_email(csac_input_string('email'));
    $emailCode = csac_input_string('email_code');

    if ($username === '' || $nickname === '' || $pwd === '' || $confirmPwd === '' || (CSAC_REQUIRE_REGISTER_EMAIL_VERIFICATION && ($email === '' || $emailCode === ''))) {
        response_json(['success' => false, 'message' => '请填写完整表单']);
    }
    if (CSAC_REQUIRE_REGISTER_EMAIL_VERIFICATION && $email === '') {
        response_json(['success' => false, 'message' => '请输入有效的邮箱地址']);
    }
    if (in_array(strtolower($username), $banNames, true) || in_array(strtolower($nickname), $banNames, true)) {
        response_json(['success' => false, 'message' => '不允许使用管理员/系统保留账号昵称！']);
    }
    if (!preg_match('/^[A-Za-z0-9_@.\-]{3,32}$/', $username)) {
        response_json(['success' => false, 'message' => '账号需为3-32位字母、数字或常用符号']);
    }
    if (mb_strlen($nickname, 'UTF-8') > 16) {
        response_json(['success' => false, 'message' => '昵称最多16个字符']);
    }
    if ($pwd !== $confirmPwd) {
        response_json(['success' => false, 'message' => '两次密码不一致']);
    }
    if (strlen($pwd) < 6) {
        response_json(['success' => false, 'message' => '密码至少6位']);
    }
    if (csac_fetch_one('SELECT id FROM chat_user WHERE username = ?', 's', $username)) {
        response_json(['success' => false, 'message' => '该登录账号已被注册']);
    }
    if (CSAC_REQUIRE_REGISTER_EMAIL_VERIFICATION && csac_fetch_one('SELECT id FROM chat_user WHERE email = ? LIMIT 1', 's', $email)) {
        response_json(['success' => false, 'message' => '该邮箱已被注册']);
    }

    $emailCodeId = CSAC_REQUIRE_REGISTER_EMAIL_VERIFICATION
        ? csac_verified_register_email_code_id($email, $emailCode)
        : 0;

    csac_begin();
    try {
        if ($emailCodeId > 0) {
            $used = csac_execute('UPDATE register_email_codes SET used_at = ? WHERE id = ? AND used_at = 0', 'ii', time(), $emailCodeId);
            if ($used !== 1) {
                csac_rollback();
                response_json(['success' => false, 'message' => '验证码已失效，请重新获取']);
            }
        }
        $newUid = csac_insert_row('chat_user', [
            'username' => $username,
            'nickname' => $nickname,
            'email' => $email !== '' ? $email : null,
            'pwd' => hash_password($pwd, $username),
                                  'add_time' => time(),
                                  'avatar' => CSAC_DEFAULT_AVATAR,
                                  'is_first_login' => 1,
                                  'last_active' => time(),
        ]);

        if (isset($_FILES['avatar']) && ($_FILES['avatar']['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_OK) {
            $avatar = csac_upload_file(
                $_FILES['avatar'],
                ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp'],
                CSAC_MAX_IMAGE_BYTES,
                UPLOAD_DIR,
                'upload',
                'avatar_' . $newUid
            );
            csac_update_row('chat_user', ['avatar' => $avatar], 'id = ?', [$newUid]);
        }

        $regDate = date('Y-m-d H:i:s');
        csac_notice(
            $newUid,
            '欢迎使用 CsAC 在线聊天',
            "亲爱的{$nickname}：\n您好！\n感谢您使用Chemsource AtsukaCIT Chatting。\n\n使用指南：\n1. 登录后可创建群组，或通过群组编号、邀请码加入聊天室；\n2. 支持文字、图片、语音、好友和群组管理；\n3. 请文明交流，遇到问题可联系网站管理员。\n\nCsAC在线聊天网站管理员 xiaohua\n{$regDate}"
        );
        csac_commit();
    } catch (Throwable $e) {
        csac_rollback();
        throw $e;
    }

    session_regenerate_id(true);
    $_SESSION['user_id'] = $newUid;
    $_SESSION['nickname'] = $nickname;

    response_json([
        'success' => true,
        'message' => '注册成功',
        'need_guide' => true,
        'user' => ['uid' => $newUid, 'nickname' => $nickname],
    ]);
}

function csac_normalize_register_email(string $email): string
{
    $email = strtolower(trim($email));
    if ($email === '' || strlen($email) > 255 || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
        return '';
    }
    return $email;
}

function csac_register_email_ip_hash(): string
{
    $ip = (string)($_SERVER['HTTP_CF_CONNECTING_IP'] ?? $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '');
    if (str_contains($ip, ',')) {
        $ip = trim(explode(',', $ip)[0]);
    }
    return hash_hmac('sha256', $ip, CSAC_CACHE_SALT);
}

function csac_verified_register_email_code_id(string $email, string $code): int
{
    if ($email === '' || !preg_match('/^\d{6}$/', $code)) {
        response_json(['success' => false, 'message' => '邮箱验证码错误']);
    }
    $row = csac_fetch_one(
        'SELECT * FROM register_email_codes WHERE email = ? AND used_at = 0 ORDER BY id DESC LIMIT 1',
        's',
        $email
    );
    if (!$row) {
        response_json(['success' => false, 'message' => '请先获取邮箱验证码']);
    }
    if ((int)$row['expires_at'] < time()) {
        response_json(['success' => false, 'message' => '验证码已过期，请重新获取']);
    }
    if ((int)($row['attempts'] ?? 0) >= CSAC_REGISTER_EMAIL_MAX_ATTEMPTS) {
        response_json(['success' => false, 'message' => '验证码错误次数过多，请重新获取']);
    }
    if (!password_verify($code, (string)$row['code_hash'])) {
        csac_execute('UPDATE register_email_codes SET attempts = attempts + 1 WHERE id = ?', 'i', (int)$row['id']);
        response_json(['success' => false, 'message' => '邮箱验证码错误']);
    }
    return (int)$row['id'];
}

function csac_smtp_config(): array
{
    $config = [];
    $localPath = dirname(__DIR__) . '/smtp.local.php';
    if (is_file($localPath)) {
        $loaded = require $localPath;
        if (is_array($loaded)) {
            $config = $loaded;
        }
    }

    foreach ([
        'host' => 'CSAC_SMTP_HOST',
        'port' => 'CSAC_SMTP_PORT',
        'secure' => 'CSAC_SMTP_SECURE',
        'username' => 'CSAC_SMTP_USERNAME',
        'password' => 'CSAC_SMTP_PASSWORD',
        'from_email' => 'CSAC_SMTP_FROM_EMAIL',
        'from_name' => 'CSAC_SMTP_FROM_NAME',
    ] as $key => $envName) {
        $value = getenv($envName);
        if (is_string($value) && $value !== '') {
            $config[$key] = $value;
        }
    }

    return $config;
}

function csac_send_register_email_code(string $email, string $code): void
{
    if (!class_exists('PHPMailer\\PHPMailer\\PHPMailer')) {
        throw new RuntimeException('PHPMailer dependency is missing. Run composer install in the backend directory.');
    }

    $config = csac_smtp_config();
    foreach (['host', 'username', 'password', 'from_email'] as $key) {
        if (trim((string)($config[$key] ?? '')) === '') {
            throw new RuntimeException('SMTP config is incomplete: ' . $key);
        }
    }

    $mail = new PHPMailer\PHPMailer\PHPMailer(true);
    $mail->CharSet = 'UTF-8';
    $mail->isSMTP();
    $mail->Host = (string)$config['host'];
    $mail->SMTPAuth = true;
    $mail->Username = (string)$config['username'];
    $mail->Password = (string)$config['password'];
    $mail->Port = (int)($config['port'] ?? 465);
    $secure = strtolower((string)($config['secure'] ?? 'ssl'));
    if ($secure === 'ssl' || $secure === 'smtps') {
        $mail->SMTPSecure = PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_SMTPS;
    } elseif ($secure === 'tls' || $secure === 'starttls') {
        $mail->SMTPSecure = PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_STARTTLS;
    }
    $mail->setFrom((string)$config['from_email'], (string)($config['from_name'] ?? 'CsAC'));
    $mail->addAddress($email);
    $mail->isHTML(false);
    $mail->Subject = 'CsAC 注册邮箱验证码';
    $minutes = (int)ceil(CSAC_REGISTER_EMAIL_CODE_TTL / 60);
    $mail->Body = "你的 CsAC 注册验证码是：{$code}\n\n验证码 {$minutes} 分钟内有效，请勿转发给他人。\n如果不是你本人操作，请忽略这封邮件。";
    $mail->send();
}

function csac_api_auth_logout(): void
{
    $uid = (int)($_SESSION['user_id'] ?? 0);
    if ($uid > 0) {
        csac_update_user_platform($uid, 'none');
    }
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        $params = session_get_cookie_params();
        setcookie(session_name(), '', time() - 42000, $params['path'], $params['domain'], (bool)$params['secure'], (bool)$params['httponly']);
    }
    session_destroy();
    response_json(['success' => true, 'message' => '已退出登录']);
}

function csac_api_user_get_info(): void
{
    $myUid = requireLogin();
    $viewUid = csac_input_int('uid', $myUid);
    if ($viewUid <= 0) {
        response_json(['success' => false, 'message' => '无效的用户ID']);
    }
    $user = csac_user($viewUid, 'id, avatar, nickname, username, last_active, allow_auto_join, pat_action, platform');
    if (!$user) {
        response_json(['success' => false, 'message' => '用户不存在'], 404);
    }

    $isSelf = $viewUid === $myUid;
    $remark = '';
    $isFriend = false;
    $friendRequestSent = false;
    $friendRequestReceived = false;
    $isBlocked = false;
    $canAddFriend = !$isSelf;

    if (!$isSelf) {
        $rel = csac_friend_relation($myUid, $viewUid);
        if ($rel) {
            [$uid1] = csac_friend_pair($myUid, $viewUid);
            $status = (int)$rel['status'];
            $remark = $myUid === $uid1 ? (string)($rel['remark1'] ?? '') : (string)($rel['remark2'] ?? '');
            if ($status === 1) {
                $isFriend = true;
                $canAddFriend = false;
            } elseif ($status === 0) {
                $friendRequestSent = (int)($rel['from_uid'] ?? 0) === $myUid;
                $friendRequestReceived = !$friendRequestSent;
                $canAddFriend = false;
            } elseif ($status === 4) {
                $isBlocked = (int)($rel['delete_by'] ?? 0) === $myUid;
                $canAddFriend = false;
            }
        }
        $pendingOut = csac_fetch_one('SELECT id FROM friend_request WHERE from_uid = ? AND to_uid = ? AND status = 0 LIMIT 1', 'ii', $myUid, $viewUid);
        $pendingIn = csac_fetch_one('SELECT id FROM friend_request WHERE from_uid = ? AND to_uid = ? AND status = 0 LIMIT 1', 'ii', $viewUid, $myUid);
        if ($pendingOut) {
            $friendRequestSent = true;
            $canAddFriend = false;
        }
        if ($pendingIn) {
            $friendRequestReceived = true;
            $canAddFriend = false;
        }
    }

    response_json([
        'success' => true,
        'user' => [
            'uid' => (int)$user['id'],
                  'username' => $user['username'],
                  'nickname' => $user['nickname'],
                  'avatar' => ($user['avatar'] ?? '') !== '' ? $user['avatar'] : CSAC_DEFAULT_AVATAR,
                  'last_active' => $user['last_active'],
                  'online_status' => getOnlineStatus($user['last_active']),
                  'platform' => csac_is_online($user['last_active']) ? ((string)($user['platform'] ?? '') ?: 'none') : 'none',
                  'allow_auto_join' => (int)($user['allow_auto_join'] ?? 1),
                  'pat_action' => (string)($user['pat_action'] ?? '拍了拍'),
                  'is_self' => $isSelf,
                  'remark' => $remark,
                  'is_friend' => $isFriend,
                  'friend_request_sent' => $friendRequestSent,
                  'friend_request_received' => $friendRequestReceived,
                  'is_blocked' => $isBlocked,
                  'can_add_friend' => $canAddFriend,
        ],
    ]);
}

function csac_api_user_update_profile(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $user = csac_user($uid, 'id, username, nickname, pwd, avatar, allow_auto_join, pat_action');
    if (!$user) {
        response_json(['success' => false, 'message' => '用户不存在'], 404);
    }

    $action = csac_input_string('action');
    if ($action === 'nickname') {
        $nickname = csac_input_string('nickname');
        if ($nickname === '') {
            response_json(['success' => false, 'message' => '昵称不能为空']);
        }
        if (mb_strlen($nickname, 'UTF-8') > 16) {
            response_json(['success' => false, 'message' => '昵称最多16个字符']);
        }
        csac_update_row('chat_user', ['nickname' => $nickname], 'id = ?', [$uid]);
        $_SESSION['nickname'] = $nickname;
        response_json(['success' => true, 'message' => '昵称修改成功', 'nickname' => $nickname]);
    }

    if ($action === 'password') {
        csac_change_password($uid, $user, true);
    }

    if ($action === 'avatar') {
        if (!isset($_FILES['avatar'])) {
            response_json(['success' => false, 'message' => '请选择图片']);
        }
        $avatar = csac_upload_file(
            $_FILES['avatar'],
            ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp'],
            CSAC_MAX_IMAGE_BYTES,
            UPLOAD_DIR,
            'upload',
            'avatar_' . $uid
        );
        csac_update_row('chat_user', ['avatar' => $avatar], 'id = ?', [$uid]);
        response_json(['success' => true, 'message' => '头像更换成功', 'avatar' => $avatar]);
    }

    if ($action === 'privacy') {
        $updates = [];
        if (array_key_exists('allow_auto_join', csac_input())) {
            $updates['allow_auto_join'] = csac_input_bool('allow_auto_join') ? 1 : 0;
        }
        if (!$updates) {
            response_json(['success' => false, 'message' => '没有可更新内容']);
        }
        csac_update_row('chat_user', $updates, 'id = ?', [$uid]);
        response_json(['success' => true, 'message' => '设置已更新'] + $updates);
    }

    if ($action === 'pat_action') {
        $patAction = csac_input_string('pat_action', csac_input_string('value', '拍了拍'));
        if ($patAction === '') {
            $patAction = '拍了拍';
        }
        if (mb_strlen($patAction, 'UTF-8') > 16) {
            response_json(['success' => false, 'message' => '拍一拍动作最多16个字符']);
        }
        csac_update_row('chat_user', ['pat_action' => $patAction], 'id = ?', [$uid]);
        response_json(['success' => true, 'message' => '拍一拍动作已更新', 'pat_action' => $patAction]);
    }

    response_json(['success' => false, 'message' => '未知操作']);
}

function csac_change_password(int $uid, array $user, bool $requireOld): void
{
    $oldPwd = csac_input_string('old_password');
    $newPwd = csac_input_string('new_password');
    $confirmPwd = csac_input_string('confirm_password');
    if (($requireOld && $oldPwd === '') || $newPwd === '' || $confirmPwd === '') {
        response_json(['success' => false, 'message' => '请填写完整']);
    }
    if ($requireOld && !csac_is_password_valid($user, $oldPwd)) {
        response_json(['success' => false, 'message' => '原密码错误']);
    }
    if (strlen($newPwd) < 6) {
        response_json(['success' => false, 'message' => '新密码至少6位']);
    }
    if ($newPwd !== $confirmPwd) {
        response_json(['success' => false, 'message' => '两次输入的密码不一致']);
    }
    csac_update_row('chat_user', ['pwd' => hash_password($newPwd, (string)$user['username']), 'last_active' => time()], 'id = ?', [$uid]);
    response_json(['success' => true, 'message' => '密码修改成功']);
}

function csac_api_user_upgrade_password(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $user = csac_user($uid, 'id, username, pwd');
    if (!$user) {
        response_json(['success' => false, 'message' => '用户不存在'], 404);
    }
    csac_change_password($uid, $user, false);
}

function csac_api_user_delete_account(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    $rooms = csac_fetch_all('SELECT id FROM chat_room WHERE owner_uid = ?', 'i', $uid);

    csac_begin();
    try {
        foreach ($rooms as $room) {
            $rid = (int)$room['id'];
            csac_execute('DELETE FROM chat_group_user WHERE room_id = ?', 'i', $rid);
            csac_execute('DELETE FROM chat_group_admin WHERE room_id = ?', 'i', $rid);
            csac_execute('DELETE FROM chat_msg WHERE room_id = ?', 'i', $rid);
            csac_execute('DELETE FROM chat_essence WHERE room_id = ?', 'i', $rid);
            csac_execute('DELETE FROM chat_room_apply WHERE room_id = ?', 'i', $rid);
            csac_execute('DELETE FROM chat_room WHERE id = ?', 'i', $rid);
        }
        csac_execute('DELETE FROM chat_group_user WHERE uid = ?', 'i', $uid);
        csac_execute('DELETE FROM chat_group_admin WHERE uid = ?', 'i', $uid);
        csac_execute('DELETE FROM chat_msg WHERE uid = ?', 'i', $uid);
        csac_execute('DELETE FROM chat_essence WHERE set_uid = ?', 'i', $uid);
        csac_execute('DELETE FROM chat_user_notice WHERE uid = ?', 'i', $uid);
        csac_execute('DELETE FROM friend_request WHERE from_uid = ? OR to_uid = ?', 'ii', $uid, $uid);
        csac_execute('DELETE FROM private_msg WHERE from_uid = ? OR to_uid = ?', 'ii', $uid, $uid);
        csac_execute('DELETE FROM chat_user WHERE id = ?', 'i', $uid);
        csac_commit();
    } catch (Throwable $e) {
        csac_rollback();
        throw $e;
    }
    session_destroy();
    response_json(['success' => true, 'message' => '账号已注销']);
}

function csac_api_user_get_friends(): void
{
    $uid = requireLogin();
    $rows = csac_fetch_all(
        "SELECT
        CASE WHEN f.uid1 = ? THEN f.uid2 ELSE f.uid1 END AS friend_id,
        CASE WHEN f.uid1 = ? THEN f.remark1 ELSE f.remark2 END AS remark,
        u.nickname, u.avatar, u.username, u.last_active,
        COALESCE(pm.unread, 0) AS unread_count
        FROM friend_relation f
        JOIN chat_user u ON ((f.uid1 = ? AND f.uid2 = u.id) OR (f.uid2 = ? AND f.uid1 = u.id))
    LEFT JOIN (
        SELECT from_uid, COUNT(*) AS unread
        FROM private_msg
        WHERE to_uid = ? AND is_read = 0 AND type = 'private'
        GROUP BY from_uid
    ) pm ON pm.from_uid = CASE WHEN f.uid1 = ? THEN f.uid2 ELSE f.uid1 END
    WHERE f.status = 1 AND (f.uid1 = ? OR f.uid2 = ?)
    ORDER BY COALESCE(f.update_time, f.create_time) DESC, f.uid1 DESC",
                           'iiiiiiii',
                           $uid,
                           $uid,
                           $uid,
                           $uid,
                           $uid,
                           $uid,
                           $uid,
                           $uid
    );
    $friends = array_map(static function (array $row): array {
        return [
            'friend_id' => (int)$row['friend_id'],
                         'nickname' => $row['nickname'],
                         'avatar' => ($row['avatar'] ?? '') !== '' ? $row['avatar'] : CSAC_DEFAULT_AVATAR,
                         'username' => $row['username'],
                         'last_active' => $row['last_active'],
                         'online_status' => getOnlineStatus($row['last_active']),
                         'remark' => $row['remark'] ?? '',
                         'display_name' => ($row['remark'] ?? '') !== '' ? $row['remark'] : $row['nickname'],
                         'unread_count' => (int)$row['unread_count'],
        ];
    }, $rows);
    response_json(['success' => true, 'friends' => $friends]);
}

function csac_api_user_get_groups(): void
{
    $uid = requireLogin();
    $rows = csac_fetch_all(
        "SELECT
        r.*,
        COALESCE(NULLIF(u.nickname, ''), CONCAT('UID ', r.owner_uid)) AS owner_name,
                           COALESCE(member.member_count, 0) AS member_count,
                           COALESCE(unread.cnt, 0) AS unread_count
                           FROM chat_room r
                           JOIN chat_group_user g ON r.id = g.room_id AND g.uid = ?
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
    ) member ON member.room_id = r.id
    LEFT JOIN (
        SELECT m.room_id, COUNT(*) AS cnt
        FROM chat_msg m
        JOIN chat_group_user gu ON gu.room_id = m.room_id AND gu.uid = ?
        WHERE m.id > COALESCE(gu.last_read_msg_id, 0)
    GROUP BY m.room_id
    ) unread ON r.id = unread.room_id
    WHERE COALESCE(r.is_disband, 0) = 0
    ORDER BY r.id ASC",
    'ii',
    $uid,
    $uid
    );
    $groups = array_map(static function (array $row): array {
        return array_merge([
            'room_id' => (int)$row['id'],
                           'id' => (int)$row['id'],
                           'room_name' => $row['room_name'],
                           'avatar' => (string)($row['avatar'] ?? ''),
                           'intro' => $row['intro'] ?? '',
                           'invite_code' => $row['invite_code'] ?? '',
                           'join_type' => (int)($row['join_type'] ?? 1),
                           'owner_uid' => (int)($row['owner_uid'] ?? 0),
                           'owner_name' => (string)($row['owner_name'] ?? '未知'),
                           'member_count' => (int)($row['member_count'] ?? 0),
                           'unread_count' => (int)$row['unread_count'],
        ], csac_room_ban_fields($row));
    }, $rows);
    response_json([
        'success' => true,
        'message' => '群组加载成功',
        'count' => count($groups),
                  'groups' => $groups,
    ]);
}

function csac_api_user_get_notifications(): void
{
    $uid = requireLogin();
    $system = csac_fetch_one('SELECT COUNT(*) AS c FROM chat_user_notice WHERE uid = ? AND is_read = 0', 'i', $uid)['c'] ?? 0;
    $requests = csac_fetch_one('SELECT COUNT(*) AS c FROM friend_request WHERE to_uid = ? AND status = 0', 'i', $uid)['c'] ?? 0;
    $deleted = csac_fetch_one("SELECT COUNT(*) AS c FROM friend_relation WHERE (uid1 = ? OR uid2 = ?) AND status = 2 AND delete_time > DATE_SUB(NOW(), INTERVAL 3 DAY)", 'ii', $uid, $uid)['c'] ?? 0;
    $total = (int)$system + (int)$requests + (int)$deleted;
    response_json([
        'success' => true,
        'system_notice_unread' => (int)$system,
                  'friend_request_unread' => (int)$requests,
                  'deleted_friend_notices' => (int)$deleted,
                  'total_unread' => $total,
    ]);
}

function csac_api_user_get_notice_list(): void
{
    $uid = requireLogin();
    $rows = csac_fetch_all('SELECT * FROM chat_user_notice WHERE uid = ? ORDER BY add_time DESC', 'i', $uid);
    $notices = array_map(static function (array $row): array {
        return [
            'id' => (int)$row['id'],
                         'title' => $row['title'] ?? '',
                         'content' => $row['content'] ?? '',
                         'add_time' => $row['add_time'] ?? '',
                         'is_read' => (int)($row['is_read'] ?? 0),
                         'link' => $row['link'] ?? '',
                         'route' => csac_notice_route((string)($row['link'] ?? '')),
        ];
    }, $rows);
    response_json(['success' => true, 'notices' => $notices]);
}

function csac_api_user_mark_notice_read(): void
{
    csac_require_method('POST');
    $uid = requireLogin();
    if (csac_input_bool('read_all')) {
        csac_execute('UPDATE chat_user_notice SET is_read = 1 WHERE uid = ? AND is_read = 0', 'i', $uid);
    } else {
        $noticeId = csac_input_int('notice_id');
        if ($noticeId > 0) {
            csac_execute('UPDATE chat_user_notice SET is_read = 1 WHERE id = ? AND uid = ? AND is_read = 0', 'ii', $noticeId, $uid);
        }
    }
    response_json(['success' => true, 'message' => '已标记已读']);
}

function csac_notice_route(string $link): string
{
    $link = trim($link);
    if ($link === '') {
        return '';
    }
    if (str_starts_with($link, '#/')) {
        return $link;
    }
    if (preg_match('/^(?:https?:)?\/\/[^\/]+\/#\/(.+)$/', $link, $match)) {
        return '#/' . ltrim($match[1], '/');
    }
    return '';
}

function csac_api_user_get_created_groups(): void
{
    $uid = requireLogin();
    $viewUid = csac_input_int('uid', $uid);
    $publicOnlySql = $viewUid === $uid ? '' : ' AND r.show_in_list = 1';
    $sql = "SELECT
    r.*,
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
            WHERE r.owner_uid = ?" . $publicOnlySql . "
            ORDER BY r.id DESC";
    $rows = csac_fetch_all(
        $sql,
        'i',
        $viewUid
    );
    $canManage = $viewUid === $uid;
    $groups = array_map(static function (array $row) use ($canManage): array {
        return array_merge([
            'id' => (int)$row['id'],
                           'room_id' => (int)$row['id'],
                           'room_name' => (string)($row['room_name'] ?? ('群组 ' . (int)$row['id'])),
                           'avatar' => (string)($row['avatar'] ?? ''),
                           'intro' => (string)($row['intro'] ?? ''),
                           'notice' => (string)($row['notice'] ?? ''),
                           'invite_code' => $canManage ? (string)($row['invite_code'] ?? '') : '',
                           'join_type' => (int)($row['join_type'] ?? 1),
                           'owner_uid' => (int)($row['owner_uid'] ?? 0),
                           'owner_name' => (string)($row['owner_name'] ?? '未知'),
                           'member_count' => (int)($row['member_count'] ?? 0),
                           'show_in_list' => (int)($row['show_in_list'] ?? 1),
                           'allow_invite' => (int)($row['allow_invite'] ?? 1),
                           'ask_question' => (string)($row['ask_question'] ?? ''),
                           'fixed_code' => $canManage ? (string)($row['fixed_code'] ?? '') : '',
        ], csac_room_ban_fields($row));
    }, $rows);
    response_json(['success' => true, 'groups' => $groups]);
}
