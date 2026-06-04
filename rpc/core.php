<?php
declare(strict_types=1);

const CSAC_DB_HOST = 'localhost';
const CSAC_DB_USER = 'csac';
const CSAC_DB_PASS = 'change_me';
const CSAC_DB_NAME = 'csac';
const CSAC_ADMIN_UID = 1;
// 内部缓存盐值，用于会话完整性校验；部署前请改为随机长字符串。
const CSAC_CACHE_SALT = 'change_me_to_a_random_secret';
const CSAC_SCHEMA_VERSION = 3;
const CSAC_SCHEMA_CHECK_TTL = 86400;
const CSAC_LONG_POLL_MAX_SECONDS = 15;
const CSAC_LONG_POLL_SLEEP_US = 350000;
const CSAC_MAX_IMAGE_BYTES = 5242880;
const CSAC_MAX_VOICE_BYTES = 10485760;
const CSAC_DEFAULT_AVATAR = 'default.png';
const CSAC_REQUIRE_REGISTER_EMAIL_VERIFICATION = true;
const CSAC_REQUIRE_EXISTING_USER_EMAIL_VERIFICATION = true;
const CSAC_REGISTER_EMAIL_CODE_TTL = 600;
const CSAC_REGISTER_EMAIL_RESEND_SECONDS = 60;
const CSAC_REGISTER_EMAIL_MAX_ATTEMPTS = 5;
const CSAC_REGISTER_EMAIL_MAX_SENDS_PER_HOUR = 5;
const CSAC_REGISTER_EMAIL_FROM = '';
const CSAC_VOICE_MIMES = [
    'audio/webm',
'video/webm',
'audio/ogg',
'application/ogg',
'audio/opus',
'audio/mpeg',
'audio/mp3',
'audio/wav',
'audio/x-wav',
'audio/wave',
'audio/vnd.wave',
'audio/mp4',
'audio/m4a',
'audio/x-m4a',
'video/mp4',
'audio/aac',
'audio/aacp',
'audio/3gpp',
'audio/3gpp2',
'video/3gpp',
'video/3gpp2',
'audio/amr',
'audio/x-amr',
'audio/flac',
'audio/x-flac',
'audio/x-caf',
'audio/caf',
'audio/aiff',
'audio/x-aiff',
];

if (!defined('UPLOAD_DIR')) {
    define('UPLOAD_DIR', dirname(__DIR__) . '/upload/');
}
if (!defined('PRIVATE_UPLOAD_DIR')) {
    define('PRIVATE_UPLOAD_DIR', dirname(__DIR__) . '/uploads/chat/');
}

$conn = null;
$CSAC_INPUT = null;
$CSAC_TABLE_COLUMNS = [];

if (is_file(__DIR__ . '/vendor/autoload.php')) {
    require_once __DIR__ . '/vendor/autoload.php';
}

foreach ([
    'db.php',
    'bootstrap.php',
    'helpers.php',
    'api_auth_user.php',
    'api_friend.php',
    'api_group.php',
    'api_message.php',
    'api_misc.php',
] as $csacModule) {
    require_once __DIR__ . '/includes/' . $csacModule;
}
