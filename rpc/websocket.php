<?php
declare(strict_types=1);

require_once __DIR__ . '/core.php';

if (PHP_SAPI !== 'cli') {
    http_response_code(426);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode([
        'success' => false,
        'message' => 'Experimental WebSocket must be run as a CLI service.',
        'usage' => 'php websocket.php 0.0.0.0:24583',
    ], JSON_UNESCAPED_SLASHES);
    exit;
}

$listen = $argv[1] ?? getenv('CSAC_WS_LISTEN') ?: '0.0.0.0:24583';
$server = @stream_socket_server('tcp://' . $listen, $errno, $errstr);
if (!$server) {
    fwrite(STDERR, "Failed to listen on {$listen}: {$errstr} ({$errno})\n");
    exit(1);
}
stream_set_blocking($server, false);
fwrite(STDOUT, "CsAC experimental HTTP/1.1 WebSocket listening on {$listen}\n");

$clients = [];

while (true) {
    $read = [$server];
    foreach ($clients as $client) {
        $read[] = $client['socket'];
    }
    $write = null;
    $except = null;
    @stream_select($read, $write, $except, 0, 250000);

    if (in_array($server, $read, true)) {
        $socket = @stream_socket_accept($server, 0);
        if (is_resource($socket)) {
            $client = csac_ws_accept_client($socket);
            if ($client !== null) {
                $clients[(int)$socket] = $client;
            }
        }
    }

    foreach ($clients as $key => &$client) {
        if (!is_resource($client['socket']) || feof($client['socket'])) {
            csac_ws_close_client($client);
            unset($clients[$key]);
            continue;
        }
        if (in_array($client['socket'], $read, true)) {
            $chunk = @fread($client['socket'], 8192);
            if ($chunk === '' || $chunk === false) {
                if (feof($client['socket'])) {
                    csac_ws_close_client($client);
                    unset($clients[$key]);
                }
                continue;
            }
            $client['buffer'] .= $chunk;
            foreach (csac_ws_parse_frames($client['buffer']) as $frame) {
                if (!csac_ws_handle_frame($client, $frame)) {
                    csac_ws_close_client($client);
                    unset($clients[$key]);
                    continue 2;
                }
            }
        }
    }
    unset($client);

    $now = microtime(true);
    foreach ($clients as $key => &$client) {
        if ($now - $client['last_check'] < 0.35) {
            continue;
        }
        $client['last_check'] = $now;
        if (!csac_ws_emit_updates($client)) {
            csac_ws_close_client($client);
            unset($clients[$key]);
        }
    }
    unset($client);
}

function csac_ws_accept_client($socket): ?array
{
    stream_set_blocking($socket, true);
    stream_set_timeout($socket, 5);
    $request = '';
    while (!str_contains($request, "\r\n\r\n") && strlen($request) < 16384) {
        $chunk = @fread($socket, 2048);
        if ($chunk === false || $chunk === '') {
            $meta = stream_get_meta_data($socket);
            if (!empty($meta['timed_out'])) {
                fclose($socket);
                return null;
            }
            usleep(10000);
            continue;
        }
        $request .= $chunk;
    }
    $headers = csac_ws_parse_http_headers($request);
    $key = $headers['sec-websocket-key'] ?? '';
    if ($key === '') {
        csac_ws_write_http_error($socket, 400, 'Missing Sec-WebSocket-Key');
        return null;
    }
    $cookies = csac_ws_parse_cookies($headers['cookie'] ?? '');
    try {
        $auth = csac_ws_authenticate($cookies);
    } catch (Throwable $e) {
        csac_log_error($e);
        csac_ws_write_http_error($socket, 500, 'Server error');
        return null;
    }
    if ($auth === null) {
        csac_ws_write_http_error($socket, 401, 'Not logged in');
        return null;
    }
    $uid = (int)$auth['uid'];
    $accept = base64_encode(sha1($key . '258EAFA5-E914-47DA-95CA-C5AB0DC85B11', true));
    fwrite(
        $socket,
        "HTTP/1.1 101 Switching Protocols\r\n" .
        "Upgrade: websocket\r\n" .
        "Connection: Upgrade\r\n" .
        "Sec-WebSocket-Accept: {$accept}\r\n" .
        "Cache-Control: no-store\r\n" .
        "\r\n"
    );
    stream_set_blocking($socket, false);
    $client = [
        'socket' => $socket,
        'uid' => $uid,
        'session_ext' => (bool)$auth['session_ext'],
        'buffer' => '',
        'subscriptions' => [],
        'last_check' => 0.0,
    ];
    csac_ws_send_json($client, ['type' => 'hello', 'server_time' => time()]);
    return $client;
}

function csac_ws_parse_http_headers(string $request): array
{
    $headers = [];
    foreach (preg_split('/\r\n/', $request) ?: [] as $index => $line) {
        if ($index === 0 || !str_contains($line, ':')) {
            continue;
        }
        [$name, $value] = explode(':', $line, 2);
        $headers[strtolower(trim($name))] = trim($value);
    }
    return $headers;
}

function csac_ws_parse_cookies(string $raw): array
{
    $cookies = [];
    foreach (explode(';', $raw) as $part) {
        if (!str_contains($part, '=')) {
            continue;
        }
        [$name, $value] = explode('=', trim($part), 2);
        if ($name !== '') {
            $cookies[$name] = urldecode($value);
        }
    }
    return $cookies;
}

function csac_ws_authenticate(array $cookies): ?array
{
    if (session_status() === PHP_SESSION_ACTIVE) {
        session_write_close();
    }
    session_id('');
    $_COOKIE = $cookies;
    $_SESSION = [];
    $sessionName = session_name();
    $sessionId = (string)($cookies[$sessionName] ?? '');
    if ($sessionId !== '' && preg_match('/^[A-Za-z0-9,-]{16,128}$/', $sessionId)) {
        session_id($sessionId);
        @session_start(['read_and_close' => true]);
    }
    $sessionExt = csac_check_session_ext();
    if ($sessionExt) {
        $uid = csac_session_uid_fallback();
    } else {
        $uid = (int)($_SESSION['user_id'] ?? 0);
    }
    if ($uid <= 0 || !checkUserExists($uid)) {
        return null;
    }
    if (checkUserBan($uid) !== false) {
        return null;
    }
    if (CSAC_REQUIRE_EXISTING_USER_EMAIL_VERIFICATION && !csac_user_email_verified($uid)) {
        return null;
    }
    csac_touch_user($uid);
    return ['uid' => $uid, 'session_ext' => $sessionExt];
}

function csac_ws_write_http_error($socket, int $status, string $message): void
{
    fwrite(
        $socket,
        "HTTP/1.1 {$status} {$message}\r\n" .
        "Connection: close\r\n" .
        "Content-Length: 0\r\n" .
        "\r\n"
    );
    fclose($socket);
}

function csac_ws_parse_frames(string &$buffer): array
{
    $frames = [];
    while (strlen($buffer) >= 2) {
        $b1 = ord($buffer[0]);
        $b2 = ord($buffer[1]);
        $opcode = $b1 & 0x0f;
        $masked = ($b2 & 0x80) !== 0;
        $length = $b2 & 0x7f;
        $offset = 2;
        if ($length === 126) {
            if (strlen($buffer) < 4) {
                break;
            }
            $length = unpack('n', substr($buffer, 2, 2))[1];
            $offset = 4;
        } elseif ($length === 127) {
            if (strlen($buffer) < 10) {
                break;
            }
            $parts = unpack('Nhigh/Nlow', substr($buffer, 2, 8));
            if ((int)$parts['high'] !== 0) {
                $buffer = '';
                return [['opcode' => 8, 'payload' => '']];
            }
            $length = (int)$parts['low'];
            $offset = 10;
        }
        $maskLength = $masked ? 4 : 0;
        if (strlen($buffer) < $offset + $maskLength + $length) {
            break;
        }
        $mask = $masked ? substr($buffer, $offset, 4) : '';
        $offset += $maskLength;
        $payload = substr($buffer, $offset, $length);
        $buffer = substr($buffer, $offset + $length);
        if ($masked) {
            for ($i = 0; $i < $length; $i++) {
                $payload[$i] = $payload[$i] ^ $mask[$i % 4];
            }
        }
        $frames[] = ['opcode' => $opcode, 'payload' => $payload];
    }
    return $frames;
}

function csac_ws_handle_frame(array &$client, array $frame): bool
{
    $opcode = (int)$frame['opcode'];
    if ($opcode === 8) {
        return false;
    }
    if ($opcode === 9) {
        csac_ws_send_frame($client['socket'], $frame['payload'], 10);
        return true;
    }
    if ($opcode !== 1) {
        return true;
    }
    $data = json_decode((string)$frame['payload'], true);
    if (!is_array($data)) {
        return true;
    }
    if (($data['type'] ?? '') === 'ping') {
        csac_ws_send_json($client, ['type' => 'pong', 'server_time' => time()]);
        return true;
    }
    if (($data['type'] ?? '') === 'subscribe') {
        try {
            csac_ws_apply_subscriptions($client, is_array($data['conversations'] ?? null) ? $data['conversations'] : []);
        } catch (Throwable $e) {
            csac_log_error($e);
            csac_ws_send_json($client, ['type' => 'error', 'message' => 'Subscription failed.']);
            return false;
        }
    }
    return true;
}

function csac_ws_apply_subscriptions(array &$client, array $conversations): void
{
    $subscriptions = [];
    foreach ($conversations as $item) {
        if (!is_array($item)) {
            continue;
        }
        $type = strtolower((string)($item['conversation_type'] ?? $item['type'] ?? ''));
        $id = (int)($item['conversation_id'] ?? $item['id'] ?? 0);
        if (($type === 'room' || $type === 'group') && $id > 0) {
            $type = 'group';
        } elseif (($type === 'friend' || $type === 'private') && $id > 0) {
            $type = 'private';
        } else {
            continue;
        }
        if (!csac_ws_can_subscribe((int)$client['uid'], $type, $id, (bool)($client['session_ext'] ?? false))) {
            continue;
        }
        $key = $type . ':' . $id;
        $subscriptions[$key] = [
            'type' => $type,
            'id' => $id,
            'latest' => csac_ws_latest_id((int)$client['uid'], $type, $id, 0),
        ];
    }
    $client['subscriptions'] = $subscriptions;
    csac_ws_send_json($client, [
        'type' => 'subscribed',
        'count' => count($subscriptions),
        'server_time' => time(),
    ]);
}

function csac_ws_can_subscribe(int $uid, string $type, int $id, bool $sessionExt): bool
{
    if ($sessionExt) {
        return true;
    }
    if ($type === 'group') {
        return csac_is_group_member($id, $uid);
    }
    $relation = csac_friend_relation($uid, $id);
    return $relation !== null && (int)($relation['status'] ?? 0) === 1;
}

function csac_ws_latest_id(int $uid, string $type, int $id, int $afterId): int
{
    if ($type === 'group') {
        return csac_latest_group_message_id($id, $afterId);
    }
    return csac_latest_private_message_id($uid, $id, $afterId);
}

function csac_ws_emit_updates(array &$client): bool
{
    try {
        foreach ($client['subscriptions'] as $key => &$subscription) {
            $latest = csac_ws_latest_id(
                (int)$client['uid'],
                (string)$subscription['type'],
                (int)$subscription['id'],
                (int)$subscription['latest']
            );
            if ($latest <= (int)$subscription['latest']) {
                continue;
            }
            $subscription['latest'] = $latest;
            if (!csac_ws_send_json($client, [
                'type' => 'conversation:update',
                'conversation_type' => $subscription['type'],
                'conversation_id' => $subscription['id'],
                'latest_id' => $latest,
                'server_time' => time(),
            ])) {
                return false;
            }
        }
        unset($subscription);
    } catch (Throwable $e) {
        csac_log_error($e);
        return false;
    }
    return true;
}

function csac_ws_send_json(array $client, array $data): bool
{
    return csac_ws_send_frame($client['socket'], json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE), 1);
}

function csac_ws_send_frame($socket, string $payload, int $opcode): bool
{
    $length = strlen($payload);
    $header = chr(0x80 | $opcode);
    if ($length <= 125) {
        $header .= chr($length);
    } elseif ($length <= 65535) {
        $header .= chr(126) . pack('n', $length);
    } else {
        $header .= chr(127) . pack('NN', 0, $length);
    }
    return @fwrite($socket, $header . $payload) !== false;
}

function csac_ws_close_client(array $client): void
{
    if (is_resource($client['socket'])) {
        @fclose($client['socket']);
    }
}
