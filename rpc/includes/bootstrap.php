<?php
declare(strict_types=1);

function csac_bootstrap(): void
{
    static $booted = false;
    if ($booted) {
        return;
    }
    $booted = true;

    error_reporting(E_ALL);
    ini_set('display_errors', '0');

    csac_send_cors_headers();
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
        http_response_code(204);
        exit;
    }

    csac_configure_session_lifetime();
    if (session_status() !== PHP_SESSION_ACTIVE) {
        session_start();
    }

    set_exception_handler(static function (Throwable $e): void {
        csac_log_error($e);
        response_json(['success' => false, 'message' => '服务器内部错误'], 500);
    });
    set_error_handler(static function (int $severity, string $message, string $file, int $line): bool {
        if (!(error_reporting() & $severity)) {
            return false;
        }
        throw new ErrorException($message, 0, $severity, $file, $line);
    });
}

function csac_configure_session_lifetime(): void
{
    if (session_status() === PHP_SESSION_ACTIVE || headers_sent()) {
        return;
    }

    $lifetime = defined('CSAC_SESSION_LIFETIME_SECONDS')
        ? max(0, (int)CSAC_SESSION_LIFETIME_SECONDS)
        : 0;
    if ($lifetime <= 0) {
        return;
    }

    ini_set('session.gc_maxlifetime', (string)$lifetime);
    ini_set('session.cookie_lifetime', (string)$lifetime);

    $params = session_get_cookie_params();
    $secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
        || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
    session_set_cookie_params([
        'lifetime' => $lifetime,
        'path' => $params['path'] ?: '/',
        'domain' => $params['domain'] ?? '',
        'secure' => $secure,
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
}

function csac_send_cors_headers(): void
{
    $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
    if ($origin !== '') {
        header('Access-Control-Allow-Origin: ' . $origin);
        header('Access-Control-Allow-Credentials: true');
        header('Vary: Origin');
    }
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    header('Access-Control-Allow-Headers: ' . ($_SERVER['HTTP_ACCESS_CONTROL_REQUEST_HEADERS'] ?? 'Content-Type, Authorization, X-Requested-With, Accept'));
    header('Cache-Control: no-store');
}


function csac_log_error(Throwable $e): void
{
    $line = sprintf(
        "[%s] %s in %s:%d\n",
        date('c'),
                    $e->getMessage(),
                    $e->getFile(),
                    $e->getLine()
    );
    @error_log($line, 3, __DIR__ . '/rpc_error.log');
}

function response_json(array $data, int $http_code = 200): void
{
    if (isset($_GET['callback']) && is_string($_GET['callback']) && $_GET['callback'] !== '') {
        $callback = preg_replace('/[^A-Za-z0-9_.$]/', '', $_GET['callback']);
        if ($callback !== '') {
            http_response_code($http_code);
            header('Content-Type: application/javascript; charset=utf-8');
            echo $callback . '(' . json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . ');';
            exit;
        }
    }

    http_response_code($http_code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function csac_dispatch_current_request(?string $act = null): void
{
    $route = $act ?: csac_current_route();
    if ($route === '') {
        response_json(['success' => false, 'message' => '缺少 route 参数'], 400);
    }

    $routes = csac_routes();
    if (!isset($routes[$route])) {
        response_json(['success' => false, 'message' => '无效的 route: ' . $route], 404);
    }

    call_user_func($routes[$route]);
}

function csac_current_route(): string
{
    $route = csac_input_string('route');
    if ($route === '') {
        return '';
    }
    $route = ltrim(str_replace('\\', '/', $route), '/');
    $route = preg_replace('/[?#].*$/', '', $route) ?? $route;
    if (str_ends_with($route, '.php')) {
        $route = substr($route, 0, -4);
    }
    return trim($route, '/');
}

function csac_routes(): array
{
    return [
        'auth/login' => 'csac_api_auth_login',
        'auth/send_register_code' => 'csac_api_auth_send_register_code',
        'auth/send_email_bind_code' => 'csac_api_auth_send_email_bind_code',
        'auth/verify_email_bind_code' => 'csac_api_auth_verify_email_bind_code',
        'auth/register' => 'csac_api_auth_register',
        'auth/logout' => 'csac_api_auth_logout',
        'user/get_info' => 'csac_api_user_get_info',
        'user/update_profile' => 'csac_api_user_update_profile',
        'user/upgrade_password' => 'csac_api_user_upgrade_password',
        'user/delete_account' => 'csac_api_user_delete_account',
        'user/get_friends' => 'csac_api_user_get_friends',
        'user/get_groups' => 'csac_api_user_get_groups',
        'user/get_notifications' => 'csac_api_user_get_notifications',
        'user/get_notice_list' => 'csac_api_user_get_notice_list',
        'user/mark_notice_read' => 'csac_api_user_mark_notice_read',
        'user/get_created_groups' => 'csac_api_user_get_created_groups',
        'friend/send_request' => 'csac_api_friend_send_request',
        'friend/handle_request' => 'csac_api_friend_handle_request',
        'friend/delete_friend' => 'csac_api_friend_delete_friend',
        'friend/block_friend' => 'csac_api_friend_block_friend',
        'friend/recover_friend' => 'csac_api_friend_recover_friend',
        'friend/update_remark' => 'csac_api_friend_update_remark',
        'friend/get_common_groups' => 'csac_api_friend_get_common_groups',
        'friend/get_deleted_notices' => 'csac_api_friend_get_deleted_notices',
        'friend/get_friend_requests' => 'csac_api_friend_get_friend_requests',
        'message/send_group_msg' => 'csac_api_message_send_group_msg',
        'message/send_private_msg' => 'csac_api_message_send_private_msg',
        'message/send_voice_msg' => 'csac_api_message_send_voice_msg',
        'message/send_emoji_msg' => 'csac_api_message_send_emoji_msg',
        'emoji/get_list' => 'csac_api_emoji_get_list',
        'message/send_pat_msg' => 'csac_api_message_send_pat_msg',
        'message/pat' => 'csac_api_message_send_pat_msg',
        'message/get_group_msg' => 'csac_api_message_get_group_msg',
        'message/get_private_msg' => 'csac_api_message_get_private_msg',
        'message/recall_msg' => 'csac_api_message_recall_msg',
        'message/mark_read' => 'csac_api_message_mark_read',
        'message/get_mentions' => 'csac_api_message_get_mentions',
        'message/poll_updates' => 'csac_api_message_poll_updates',
        'group/create' => 'csac_api_group_create',
        'group/get_members' => 'csac_api_group_get_members',
        'group/get_applications' => 'csac_api_group_get_applications',
        'group/apply_join' => 'csac_api_group_apply_join',
        'group/handle_apply' => 'csac_api_group_handle_apply',
        'group/invite_member' => 'csac_api_group_invite_member',
        'group/kick_member' => 'csac_api_group_kick_member',
        'group/mute_member' => 'csac_api_group_mute_member',
        'group/set_admin' => 'csac_api_group_set_admin',
        'group/set_member_title' => 'csac_api_group_set_member_title',
        'group/edit_info' => 'csac_api_group_edit_info',
        'group/update_settings' => 'csac_api_group_update_settings',
        'group/leave' => 'csac_api_group_leave',
        'group/disband' => 'csac_api_group_disband',
        'group/transfer' => 'csac_api_group_transfer',
        'group/reset_invite_code' => 'csac_api_group_reset_invite_code',
        'group/get_group_view_info' => 'csac_api_group_get_group_view_info',
        'group/get_public_list' => 'csac_api_group_get_public_list',
        'group/get_group_msg' => 'csac_api_message_get_group_msg',
        'essence/set_essence' => 'csac_api_essence_set',
        'essence/get_essence' => 'csac_api_essence_get',
        'essence/get_essence_stats' => 'csac_api_essence_stats',
        'report/submit_report' => 'csac_api_report_submit',
        'admin/generate_token' => 'csac_api_admin_generate_token',
        'admin/admin_ban' => 'csac_api_admin_ban',
        'utils/upload_image' => 'csac_api_utils_upload_image',
        'utils/upload_voice' => 'csac_api_utils_upload_voice',
        'bug_report' => 'csac_api_bug_report',
        'test' => 'csac_api_test',
        'utils/session_extend' => 'csac_api_utils_session_extend',
        'utils/session_reset' => 'csac_api_utils_session_reset',
        'utils/session_info' => 'csac_api_utils_session_info',
    ];
}

function csac_input(): array
{
    global $CSAC_INPUT;
    if (is_array($CSAC_INPUT)) {
        return $CSAC_INPUT;
    }

    $data = array_merge($_GET, $_POST);
    $contentType = $_SERVER['CONTENT_TYPE'] ?? $_SERVER['HTTP_CONTENT_TYPE'] ?? '';
    if (stripos($contentType, 'application/json') !== false) {
        $raw = file_get_contents('php://input');
        if (is_string($raw) && trim($raw) !== '') {
            $json = json_decode($raw, true);
            if (is_array($json)) {
                $data = array_merge($data, $json);
            }
        }
    }

    $CSAC_INPUT = $data;
    return $CSAC_INPUT;
}

function csac_input_value(string $key, $default = null)
{
    $data = csac_input();
    return array_key_exists($key, $data) ? $data[$key] : $default;
}

function csac_input_string(string $key, string $default = ''): string
{
    $value = csac_input_value($key, $default);
    if (is_array($value)) {
        return $default;
    }
    return trim((string)$value);
}

function csac_input_int(string $key, int $default = 0): int
{
    $value = csac_input_value($key, $default);
    if (is_numeric($value)) {
        return (int)$value;
    }
    return $default;
}

function csac_input_bool(string $key, bool $default = false): bool
{
    $value = csac_input_value($key, $default ? '1' : '0');
    if (is_bool($value)) {
        return $value;
    }
    return in_array((string)$value, ['1', 'true', 'on', 'yes'], true);
}

function csac_require_method(string $method): void
{
    if (strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET') !== strtoupper($method)) {
        response_json(['success' => false, 'message' => '无效的请求方法'], 405);
    }
}
