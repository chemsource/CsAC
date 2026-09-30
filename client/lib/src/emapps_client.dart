import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'platform/api_http_client.dart';

class EmAppException implements Exception {
  const EmAppException(this.message);

  final String message;

  @override
  String toString() => message;
}

class EmAppPackage {
  const EmAppPackage({
    required this.appId,
    required this.name,
    required this.version,
    required this.description,
    required this.packageSize,
    required this.fileHash,
    required this.signature,
    required this.entryPage,
    required this.downloadUrl,
  });

  final String appId;
  final String name;
  final int version;
  final String description;
  final int packageSize;
  final String fileHash;
  final String signature;
  final String entryPage;
  final String downloadUrl;

  factory EmAppPackage.fromJson(Map<String, dynamic> json) {
    return EmAppPackage(
      appId: _asString(json['app_id'] ?? json['appId']),
      name: _asString(json['name']),
      version: _asInt(json['version']),
      description: _asString(json['desc'] ?? json['description']),
      packageSize: _asInt(json['package_size'] ?? json['packageSize']),
      fileHash: _asString(json['file_hash'] ?? json['fileHash']),
      signature: _asString(json['signature']),
      entryPage: _asString(
        json['entry_page'] ?? json['entryPage'],
        fallback: 'index.html',
      ),
      downloadUrl: _asString(json['download_url'] ?? json['downloadUrl']),
    );
  }
}

class EmAppPublicKey {
  const EmAppPublicKey({
    required this.pem,
    required this.algorithm,
    required this.bits,
  });

  final String pem;
  final String algorithm;
  final String bits;

  factory EmAppPublicKey.fromJson(Map<String, dynamic> json) {
    return EmAppPublicKey(
      pem: _asString(json['pem']),
      algorithm: _asString(json['alg'], fallback: 'RS256'),
      bits: _asString(json['bits'], fallback: '2048'),
    );
  }
}

class EmAppsClient {
  EmAppsClient({http.Client? httpClient, String baseUrl = defaultBaseUrl})
    : _http = httpClient ?? createApiHttpClient(),
      _baseUrl = normalizeServerUrl(baseUrl);

  static const defaultBaseUrl = 'http://uk.frp.one:65218/emapps';

  final http.Client _http;
  String _baseUrl;

  String get baseUrl => _baseUrl;

  void setBaseUrl(String value) {
    _baseUrl = normalizeServerUrl(value);
  }

  static String normalizeServerUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return defaultBaseUrl;
    }
    final withScheme = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.trim().isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('Invalid eMApps server address.');
    }
    return uri
        .replace(path: _rootPath(uri.path), query: null, fragment: null)
        .toString()
        .replaceFirst(RegExp(r'/+$'), '');
  }

  Future<List<EmAppPackage>> catalog({String keyword = ''}) async {
    final data = await _jsonGet(
      '/emapps/public/catalog',
      keyword.trim().isEmpty ? null : <String, String>{'kw': keyword.trim()},
    );
    return _dataList(data).map(EmAppPackage.fromJson).toList();
  }

  Future<EmAppPackage> info(String appId) async {
    final data = await _jsonPost('/emapps/public/info', <String, Object?>{
      'app_id': appId.trim(),
    });
    return EmAppPackage.fromJson(_dataMap(data));
  }

  Future<EmAppPublicKey> publicKey() async {
    final data = await _jsonGet('/emapps/public/key');
    return EmAppPublicKey.fromJson(data);
  }

  Future<Uint8List> download(String appId, {String downloadUrl = ''}) async {
    final uri = _uri(
      downloadUrl.trim().isEmpty
          ? '/emapps/dl/${Uri.encodeComponent(appId.trim())}'
          : downloadUrl.trim(),
    );
    final response = await _http.get(uri, headers: _headers('application/zip'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw EmAppException(_errorMessage(response, 'Download failed.'));
    }
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> _jsonGet(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await _http.get(
      _uri(path, query),
      headers: _headers('application/json'),
    );
    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> _jsonPost(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _http.post(
      _uri(path),
      headers: _headers('application/json')
        ..['Content-Type'] = 'application/json',
      body: jsonEncode(body),
    );
    return _decodeJsonResponse(response);
  }

  Map<String, dynamic> _decodeJsonResponse(http.Response response) {
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw EmAppException('Invalid JSON response: $body');
    }
    if (decoded is! Map) {
      throw const EmAppException('Invalid eMApps response.');
    }
    final json = decoded.map((key, value) => MapEntry(key.toString(), value));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw EmAppException(_message(json, 'HTTP ${response.statusCode}'));
    }
    if (json['success'] == false) {
      throw EmAppException(_message(json, 'Request failed.'));
    }
    return Map<String, dynamic>.from(json);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final value = path.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      final parsed = Uri.parse(value);
      return parsed.replace(
        queryParameters: {
          ...parsed.queryParameters,
          if (query != null) ...query,
        },
      );
    }
    final base = Uri.parse(_baseUrl);
    final root = base.path.replaceFirst(RegExp(r'/+$'), '');
    final relative = value.startsWith('/') ? value : '/$value';
    return base.replace(
      path: '$root$relative',
      queryParameters: query,
      fragment: null,
    );
  }

  Map<String, String> _headers(String accept) {
    return <String, String>{
      'Accept': accept,
      'User-Agent': 'CsAC-Flutter-eMApps/1.0',
    };
  }
}

String _rootPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || trimmed == '/') {
    return '';
  }
  return trimmed.replaceFirst(RegExp(r'/+$'), '');
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

String _errorMessage(http.Response response, String fallback) {
  try {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map) {
      return _message(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
        fallback,
      );
    }
  } catch (_) {}
  return 'HTTP ${response.statusCode}: $fallback';
}

String _message(Map<String, dynamic> json, String fallback) {
  final message = json['message'];
  if (message is String && message.trim().isNotEmpty) {
    return message.trim();
  }
  return fallback;
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
