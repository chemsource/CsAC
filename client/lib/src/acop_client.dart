import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'platform/api_http_client.dart';

class AcopApiException implements Exception {
  const AcopApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AcopAuthException extends AcopApiException {
  const AcopAuthException(super.message);
}

class AcopDeveloper {
  const AcopDeveloper({
    required this.devId,
    required this.email,
    required this.devName,
    required this.apiKey,
    required this.status,
    required this.createdAt,
  });

  final int devId;
  final String email;
  final String devName;
  final String apiKey;
  final int status;
  final int createdAt;

  factory AcopDeveloper.fromJson(Map<String, dynamic> json) {
    return AcopDeveloper(
      devId: _asInt(json['dev_id']),
      email: _asString(json['email']),
      devName: _asString(json['dev_name']),
      apiKey: _asString(json['api_key']),
      status: _asInt(json['status']),
      createdAt: _asInt(json['created_at']),
    );
  }
}

class AcopBot {
  const AcopBot({
    required this.botId,
    required this.uid,
    required this.devId,
    required this.botName,
    required this.botDesc,
    required this.status,
    required this.online,
    required this.canNotify,
    required this.canHttp,
    required this.devName,
    required this.email,
    required this.botAvatar,
    required this.lastOnline,
    required this.createdAt,
    required this.nickname,
    this.botToken = '',
  });

  final int botId;
  final int uid;
  final int devId;
  final String botName;
  final String botDesc;
  final int status;
  final int online;
  final int canNotify;
  final int canHttp;
  final String devName;
  final String email;
  final String botAvatar;
  final int lastOnline;
  final int createdAt;
  final String nickname;
  final String botToken;

  bool get isOnline => online == 1;

  factory AcopBot.fromJson(Map<String, dynamic> json) {
    return AcopBot(
      botId: _asInt(json['bot_id']),
      uid: _asInt(json['uid']),
      devId: _asInt(json['dev_id']),
      botName: _asString(json['bot_name']),
      botDesc: _asString(json['bot_desc']),
      status: _asInt(json['status']),
      online: _asInt(json['online']),
      canNotify: _asInt(json['can_notify']),
      canHttp: _asInt(json['can_http']),
      devName: _asString(json['dev_name']),
      email: _asString(json['email']),
      botAvatar: _firstString(json, const ['bot_avatar', 'avatar']),
      lastOnline: _asInt(json['last_online']),
      createdAt: _asInt(json['created_at']),
      nickname: _asString(json['nickname']),
      botToken: _asString(json['bot_token']),
    );
  }
}

class AcopScript {
  const AcopScript({
    required this.scriptId,
    required this.botId,
    required this.scriptName,
    required this.scriptContent,
    required this.enabled,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  final int scriptId;
  final int botId;
  final String scriptName;
  final String scriptContent;
  final int enabled;
  final int version;
  final int createdAt;
  final int updatedAt;

  bool get isEnabled => enabled == 1;

  factory AcopScript.fromJson(Map<String, dynamic> json) {
    return AcopScript(
      scriptId: _asInt(json['script_id']),
      botId: _asInt(json['bot_id']),
      scriptName: _asString(json['script_name']),
      scriptContent: _asString(json['script_content']),
      enabled: _asInt(json['enabled'], fallback: 1),
      version: _asInt(json['version'], fallback: 1),
      createdAt: _asInt(json['created_at']),
      updatedAt: _asInt(json['updated_at']),
    );
  }

  AcopScript copyWith({
    String? scriptName,
    String? scriptContent,
    int? enabled,
    int? version,
    int? createdAt,
    int? updatedAt,
  }) {
    return AcopScript(
      scriptId: scriptId,
      botId: botId,
      scriptName: scriptName ?? this.scriptName,
      scriptContent: scriptContent ?? this.scriptContent,
      enabled: enabled ?? this.enabled,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class AcopLogEntry {
  const AcopLogEntry({
    required this.id,
    required this.botId,
    required this.scriptId,
    required this.level,
    required this.message,
    required this.createdAt,
    required this.raw,
  });

  final int id;
  final int botId;
  final int scriptId;
  final String level;
  final String message;
  final String createdAt;
  final Map<String, dynamic> raw;

  factory AcopLogEntry.fromJson(Map<String, dynamic> json) {
    return AcopLogEntry(
      id: _asInt(json['id']),
      botId: _asInt(json['bot_id']),
      scriptId: _asInt(json['script_id']),
      level: _asString(json['level'], fallback: 'log'),
      message: _firstString(json, const ['content', 'message', 'msg', 'log']),
      createdAt: _firstString(json, const ['created_at', 'time', 'created']),
      raw: Map<String, dynamic>.from(json),
    );
  }
}

class AcopPermissionRequest {
  const AcopPermissionRequest({
    required this.requestId,
    required this.botId,
    required this.permType,
    required this.reason,
    required this.status,
    required this.adminReply,
    required this.createdAt,
    required this.handledAt,
  });

  final int requestId;
  final int botId;
  final String permType;
  final String reason;
  final int status;
  final String adminReply;
  final int createdAt;
  final int handledAt;

  factory AcopPermissionRequest.fromJson(Map<String, dynamic> json) {
    return AcopPermissionRequest(
      requestId: _asInt(json['request_id'], fallback: _asInt(json['id'])),
      botId: _asInt(json['bot_id']),
      permType: _asString(json['perm_type']),
      reason: _asString(json['reason']),
      status: _asInt(json['status']),
      adminReply: _asString(json['admin_reply']),
      createdAt: _asInt(json['created_at']),
      handledAt: _asInt(json['handled_at']),
    );
  }
}

class AcopAcrUpload {
  const AcopAcrUpload({
    required this.id,
    required this.fileName,
    required this.fileType,
    required this.content,
    required this.devId,
    required this.devName,
    required this.createdAt,
    required this.raw,
  });

  final int id;
  final String fileName;
  final String fileType;
  final String content;
  final int devId;
  final String devName;
  final String createdAt;
  final Map<String, dynamic> raw;

  factory AcopAcrUpload.fromJson(Map<String, dynamic> json) {
    return AcopAcrUpload(
      id: _asInt(json['id']),
      fileName: _asString(json['file_name']),
      fileType: _asString(json['file_type']),
      content: _asString(json['content']),
      devId: _asInt(json['dev_id']),
      devName: _asString(json['dev_name']),
      createdAt: _asString(json['created_at']),
      raw: Map<String, dynamic>.from(json),
    );
  }
}

class AcopEmaUpload {
  const AcopEmaUpload({
    required this.id,
    required this.appId,
    required this.content,
    required this.devId,
    required this.devName,
    required this.createdAt,
    required this.status,
    required this.raw,
  });

  final int id;
  final String appId;
  final String content;
  final int devId;
  final String devName;
  final String createdAt;
  final int status;
  final Map<String, dynamic> raw;

  factory AcopEmaUpload.fromJson(Map<String, dynamic> json) {
    return AcopEmaUpload(
      id: _asInt(json['id']),
      appId: _asString(json['app_id']),
      content: _asString(json['content']),
      devId: _asInt(json['dev_id']),
      devName: _asString(json['dev_name']),
      createdAt: _asString(json['created_at']),
      status: _asInt(json['status']),
      raw: Map<String, dynamic>.from(json),
    );
  }
}

class AcopLibUpload {
  const AcopLibUpload({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.content,
    required this.devId,
    required this.devName,
    required this.status,
    required this.createdAt,
    required this.raw,
  });

  final int id;
  final String name;
  final String version;
  final String description;
  final String content;
  final int devId;
  final String devName;
  final int status;
  final String createdAt;
  final Map<String, dynamic> raw;

  String get statusText => status == 1 ? '已通过' : status == 2 ? '已拒绝' : '待审核';

  factory AcopLibUpload.fromJson(Map<String, dynamic> json) {
    return AcopLibUpload(
      id: _asInt(json['id']),
      name: _asString(json['name']),
      version: _asString(json['version']),
      description: _asString(json['description']),
      content: _asString(json['content']),
      devId: _asInt(json['dev_id']),
      devName: _asString(json['dev_name']),
      status: _asInt(json['status']),
      createdAt: _asString(json['created_at']),
      raw: Map<String, dynamic>.from(json),
    );
  }
}

class AcopApiClient {
  AcopApiClient({http.Client? httpClient, String baseUrl = defaultBaseUrl})
    : _http = httpClient ?? createApiHttpClient(),
      _baseUrl = normalizeServerUrl(baseUrl);

  static const defaultBaseUrl = 'http://uk.frp.one:65218/acop';
  static const _sessionKey = 'acop.cookies';

  final http.Client _http;
  String _baseUrl;
  final Map<String, String> _cookies = <String, String>{};

  String get baseUrl => _baseUrl;

  Map<String, String> get sessionSnapshot => Map<String, String>.from(_cookies);

  void setBaseUrl(String value) {
    _baseUrl = normalizeServerUrl(value);
  }

  static String normalizeServerUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return defaultBaseUrl;
    }
    final withScheme = value.contains('://') ? value : 'http://$value';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.trim().isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('Invalid ACOP server address.');
    }
    final gatewayPath = uri.queryParameters.containsKey('route')
        ? uri.path
        : _gatewayPathFor(uri.path);
    return uri
        .replace(path: gatewayPath, query: null, fragment: null)
        .toString()
        .replaceFirst(RegExp(r'/+$'), '');
  }

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      _cookies
        ..clear()
        ..addAll(decoded.map((key, value) => MapEntry(key, value.toString())));
    }
  }

  Future<void> saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(_cookies));
  }

  Future<void> clearSession() async {
    _cookies.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  Future<void> sendCode({
    required String email,
    required String purpose,
  }) async {
    await postForm('/dev/send_code', <String, String>{
      'email': email.trim(),
      'purpose': purpose.trim(),
    });
  }

  Future<AcopDeveloper> register({
    required String email,
    required String password,
    required String developerName,
    required String code,
    required String csacUsername,
    required String csacPassword,
  }) async {
    final data = await postForm('/dev/register', <String, String>{
      'email': email.trim(),
      'pwd': password,
      'dev_name': developerName.trim(),
      'code': code.trim(),
      'csac_username': csacUsername.trim(),
      'csac_password': csacPassword,
    });
    await saveSession();
    try {
      return await getDeveloperInfo();
    } on AcopApiException {
      return AcopDeveloper.fromJson(_dataMap(data));
    }
  }

  Future<AcopDeveloper> login({
    required String email,
    required String password,
  }) async {
    await postForm('/dev/login', <String, String>{
      'email': email.trim(),
      'pwd': password,
    });
    await saveSession();
    return getDeveloperInfo();
  }

  Future<AcopDeveloper> loginByCode({
    required String email,
    required String code,
  }) async {
    await postForm('/dev/login_by_code', <String, String>{
      'email': email.trim(),
      'code': code.trim(),
    });
    await saveSession();
    return getDeveloperInfo();
  }

  Future<AcopDeveloper> getDeveloperInfo() async {
    final data = await get('/dev/get_info');
    return AcopDeveloper.fromJson(_dataMap(data));
  }

  Future<void> logout() async {
    try {
      await postForm('/dev/logout');
    } finally {
      await clearSession();
    }
  }

  Future<AcopBot> createBot({
    required String botName,
    String botDesc = '',
  }) async {
    final data = await postForm('/bot/create', <String, String>{
      'bot_name': botName.trim(),
      if (botDesc.trim().isNotEmpty) 'bot_desc': botDesc.trim(),
    });
    return AcopBot.fromJson(_dataMap(data));
  }

  Future<List<AcopBot>> listBots() async {
    final data = await get('/bot/list');
    return _dataList(data).map(AcopBot.fromJson).toList();
  }

  Future<AcopBot> getBotInfo(int botId) async {
    final data = await get('/bot/get_info', <String, String>{
      'bot_id': '$botId',
    });
    return AcopBot.fromJson(_dataMap(data));
  }

  Future<void> updateBot({
    required int botId,
    String? botName,
    String? botDesc,
    String? botAvatar,
  }) async {
    await postForm('/bot/update', <String, String>{
      'bot_id': '$botId',
      if (botName != null && botName.trim().isNotEmpty)
        'bot_name': botName.trim(),
      if (botDesc != null && botDesc.trim().isNotEmpty)
        'bot_desc': botDesc.trim(),
      if (botAvatar != null) 'bot_avatar': botAvatar.trim(),
    });
  }

  Future<String> uploadBotAvatar({
    required int botId,
    required Uint8List avatarBytes,
    required String fileName,
  }) async {
    final data = await multipart(
      '/bot/upload_avatar',
      <String, String>{'bot_id': '$botId'},
      fileField: 'avatar',
      fileBytes: avatarBytes,
      fileName: fileName,
    );
    final avatar = _firstString(data, const ['avatar']);
    if (avatar.isNotEmpty) {
      return avatar;
    }
    return _firstString(_dataMap(data), const ['avatar']);
  }

  Future<String> resetBotToken(int botId) async {
    final data = await postForm('/bot/reset_token', <String, String>{
      'bot_id': '$botId',
    });
    final token = _firstString(data, const ['bot_token']);
    if (token.isNotEmpty) {
      return token;
    }
    return _firstString(_dataMap(data), const ['bot_token']);
  }

  Future<void> deleteBot(int botId) async {
    await postForm('/bot/delete', <String, String>{'bot_id': '$botId'});
  }

  Future<int> createScript({
    required int botId,
    required String scriptName,
    required String scriptContent,
  }) async {
    final data = await postForm('/script/create', <String, String>{
      'bot_id': '$botId',
      'script_name': scriptName.trim(),
      'script_content': scriptContent,
    });
    return _asInt(
      data['script_id'],
      fallback: _asInt(_dataMap(data)['script_id']),
    );
  }

  Future<List<AcopScript>> listScripts(int botId) async {
    final data = await get('/script/list', <String, String>{
      'bot_id': '$botId',
    });
    return _dataList(data).map(AcopScript.fromJson).toList();
  }

  Future<AcopScript> getScript(int scriptId) async {
    final data = await get('/script/get', <String, String>{
      'script_id': '$scriptId',
    });
    return AcopScript.fromJson(_dataMap(data));
  }

  Future<void> updateScript({
    required int scriptId,
    required String scriptName,
    required String scriptContent,
  }) async {
    await postForm('/script/update', <String, String>{
      'script_id': '$scriptId',
      'script_name': scriptName.trim(),
      'script_content': scriptContent,
    });
  }

  Future<void> deleteScript(int scriptId) async {
    await postForm('/script/delete', <String, String>{
      'script_id': '$scriptId',
    });
  }

  Future<void> toggleScript({
    required int scriptId,
    required bool enabled,
  }) async {
    await postForm('/script/toggle', <String, String>{
      'script_id': '$scriptId',
      'enabled': enabled ? '1' : '0',
    });
  }

  Future<Map<String, dynamic>> testScript({
    required int scriptId,
    String eventType = 'group_message',
    Object? eventData,
    String? scriptContent,
  }) {
    return postJson('/script/test', <String, Object?>{
      'script_id': '$scriptId',
      'event_type': eventType,
      'event_data': eventData ?? const <String, Object?>{},
      if (scriptContent != null) 'script_content': scriptContent,
    });
  }

  Future<Map<String, dynamic>> uploadEma({
    required String fileName,
    required String content,
  }) {
    return postJson('/script/upload_ema', <String, Object?>{
      'file_name': fileName.trim(),
      'content': content,
    });
  }

  Future<List<AcopLogEntry>> listLogs({
    required int botId,
    String level = '',
    int limit = 50,
  }) async {
    final data = await get('/log/list', <String, String>{
      'bot_id': '$botId',
      if (level.trim().isNotEmpty) 'level': level.trim(),
      'limit': '${limit.clamp(1, 200)}',
    });
    return _dataList(data).map(AcopLogEntry.fromJson).toList();
  }

  Future<void> requestPermission({
    required int botId,
    required String permType,
    required String reason,
  }) async {
    await postForm('/perm/request', <String, String>{
      'bot_id': '$botId',
      'perm_type': permType.trim(),
      'reason': reason.trim(),
    });
  }

  Future<List<AcopPermissionRequest>> listPermissionRequests(int botId) async {
    final data = await get('/perm/list', <String, String>{'bot_id': '$botId'});
    return _dataList(data).map(AcopPermissionRequest.fromJson).toList();
  }

  Future<void> handlePermissionRequest({
    required int requestId,
    required String action,
    String adminReply = '',
  }) async {
    await postForm('/admin/perm/handle', <String, String>{
      'request_id': '$requestId',
      'action': action.trim(),
      'admin_reply': adminReply.trim(),
    });
  }

  Future<List<AcopBot>> listAdminBots() async {
    final data = await get('/admin/bot/list');
    return _dataList(data).map(AcopBot.fromJson).toList();
  }

  Future<Map<String, dynamic>> runSaveChainDiagnostic({
    String name = '',
    String content = '',
    String mode = '',
  }) {
    return postJson('/diag/test-save', <String, Object?>{
      if (name.trim().isNotEmpty) 'name': name.trim(),
      if (content.isNotEmpty) 'content': content,
      if (mode.trim().isNotEmpty) 'mode': mode.trim(),
    });
  }

  Future<List<AcopAcrUpload>> listPendingAcrUploads() async {
    final data = await postJson('/admin/acr/pending');
    return _dataList(data).map(AcopAcrUpload.fromJson).toList();
  }

  Future<Map<String, dynamic>> reviewAcrUpload({
    required int id,
    required String action,
    String adminNote = '',
  }) {
    return postJson('/admin/acr/review', <String, Object?>{
      'id': id,
      'action': action.trim(),
      if (adminNote.trim().isNotEmpty) 'admin_note': adminNote.trim(),
    });
  }

  Future<Map<String, dynamic>> reviewLibUpload({
    required int id,
    required String action,
    String adminNote = '',
  }) {
    return postJson('/admin/lib/review', <String, Object?>{
      'id': id,
      'action': action.trim(),
      if (adminNote.trim().isNotEmpty) 'admin_note': adminNote.trim(),
    });
  }

  Future<List<AcopEmaUpload>> listPendingEmaUploads() async {
    final data = await postJson('/admin/ema/pending');
    return _dataList(data).map(AcopEmaUpload.fromJson).toList();
  }

  Future<Map<String, dynamic>> reviewEmaUpload({
    required int id,
    required String action,
    String adminNote = '',
  }) {
    return postJson('/admin/ema/review', <String, Object?>{
      'id': id,
      'action': action.trim(),
      if (adminNote.trim().isNotEmpty) 'admin_note': adminNote.trim(),
    });
  }

  // ---- JSLibs 库管理 ----

  Future<List<AcopLibUpload>> getLibList({int page = 1}) async {
    final data = await postJson('/lib/list', {'page': page});
    final list = _dataList(data);
    return list.map((e) => AcopLibUpload.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<AcopLibUpload>> getMyLibs() async {
    final data = await postJson('/lib/my_libs');
    final list = _dataList(data);
    return list.map((e) => AcopLibUpload.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Map<String, dynamic>> uploadLib({
    required String name,
    required String version,
    required String content,
    String description = '',
  }) {
    return postJson('/lib/upload', <String, Object?>{
      'name': name.trim(),
      'version': version.trim(),
      'content': content,
      if (description.trim().isNotEmpty) 'description': description.trim(),
    });
  }

  Future<List<AcopLibUpload>> getPendingLibs() async {
    final data = await postJson('/admin/lib/pending');
    final list = _dataList(data);
    return list.map((e) => AcopLibUpload.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Map<String, dynamic>> setUploadPerm({
    required int devId,
    required int allow,
  }) {
    return postJson('/admin/lib/set_upload_perm', <String, Object?>{
      'dev_id': devId,
      'allow': allow,
    });
  }

  Future<Map<String, dynamic>> get(
    String route, [
    Map<String, String>? values,
  ]) {
    return _send(() => http.Request('GET', _routeUri(route, values)));
  }

  Future<Map<String, dynamic>> postForm(
    String route, [
    Map<String, String>? values,
  ]) {
    return _send(() {
      final request = http.Request('POST', _routeUri(route));
      request.bodyFields = values ?? <String, String>{};
      return request;
    });
  }

  Future<Map<String, dynamic>> postJson(
    String route, [
    Map<String, Object?>? values,
  ]) {
    return _send(() {
      final request = http.Request('POST', _routeUri(route));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(values ?? const <String, Object?>{});
      return request;
    });
  }

  Future<Map<String, dynamic>> multipart(
    String route,
    Map<String, String> values, {
    required String fileField,
    required Uint8List fileBytes,
    required String fileName,
  }) {
    return _send(() {
      final request = http.MultipartRequest('POST', _routeUri(route));
      request.fields.addAll(values);
      request.files.add(
        http.MultipartFile.fromBytes(
          fileField,
          fileBytes,
          filename: fileName.trim().isEmpty ? 'avatar.png' : fileName.trim(),
        ),
      );
      return request;
    });
  }

  Future<Map<String, dynamic>> _send(
    http.BaseRequest Function() buildRequest,
  ) async {
    final response = await _sendOnce(buildRequest());
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw AcopApiException('Invalid JSON response: $body');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AcopApiException('Invalid ACOP response.');
    }
    if (response.statusCode == 401) {
      throw AcopAuthException(_message(decoded, 'Not logged in.'));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AcopApiException(
        'HTTP ${response.statusCode}: ${_message(decoded, body)}',
      );
    }
    if (decoded['success'] != true) {
      throw AcopApiException(_message(decoded, 'Request failed.'));
    }
    return decoded;
  }

  Future<http.Response> _sendOnce(http.BaseRequest request) async {
    _prepareHeaders(request);
    final streamed = await _http
        .send(request)
        .timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamed);
    _storeCookies(response);
    return response;
  }

  void _prepareHeaders(http.BaseRequest request) {
    request.headers.putIfAbsent('Accept', () => 'application/json');
    request.headers.putIfAbsent('User-Agent', () => 'CsAC-Flutter-ACOP/1.0');
    if (_cookies.isNotEmpty) {
      request.headers['Cookie'] = _cookies.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');
    }
  }

  void _storeCookies(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) {
      return;
    }
    for (final cookie in _splitSetCookie(raw)) {
      final first = cookie.split(';').first.trim();
      final index = first.indexOf('=');
      if (index <= 0) {
        continue;
      }
      _cookies[first.substring(0, index)] = first.substring(index + 1);
    }
  }

  Uri _routeUri(String route, [Map<String, String>? values]) {
    final base = Uri.parse(_baseUrl);
    final cleanRoute = route.replaceFirst(RegExp(r'^/+'), '');
    return base.replace(
      path: _gatewayPathFor(base.path),
      query: _routeQuery(cleanRoute, values),
      fragment: null,
    );
  }

  List<String> _splitSetCookie(String raw) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var inExpires = false;
    for (var i = 0; i < raw.length; i++) {
      final char = raw[i];
      if (char == ',') {
        if (!inExpires) {
          parts.add(buffer.toString());
          buffer.clear();
          continue;
        }
      }
      buffer.write(char);
      final lower = buffer.toString().toLowerCase();
      if (lower.endsWith('expires=')) {
        inExpires = true;
      } else if (inExpires && char == ';') {
        inExpires = false;
      }
    }
    if (buffer.isNotEmpty) {
      parts.add(buffer.toString());
    }
    return parts;
  }
}

Map<String, dynamic> _dataMap(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is Map<String, dynamic>) {
    return data;
  }
  if (data is Map) {
    return data.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _dataList(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is List) {
    return data
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }
  return const <Map<String, dynamic>>[];
}

String _message(Map<String, dynamic> data, String fallback) {
  final message = data['message'];
  if (message is String && message.trim().isNotEmpty) {
    return message.trim();
  }
  return fallback;
}

String _firstString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = _asString(json[key]);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

String _asString(Object? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

String _gatewayPathFor(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || trimmed == '/') {
    return '/acop/';
  }
  return '${trimmed.replaceFirst(RegExp(r'/+$'), '')}/';
}

String _routeQuery(String route, Map<String, String>? values) {
  final parts = <String>[
    'route=${Uri.encodeQueryComponent(route).replaceAll('%2F', '/')}',
  ];
  if (values != null) {
    for (final entry in values.entries) {
      parts.add(
        '${Uri.encodeQueryComponent(entry.key)}='
        '${Uri.encodeQueryComponent(entry.value)}',
      );
    }
  }
  return parts.join('&');
}
