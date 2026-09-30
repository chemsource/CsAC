import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html show window;

class ApiClient {
  late String baseUrl;
  String? _sessionCookie;

  ApiClient({String? url}) {
    baseUrl = url ?? _inferBaseUrl();
  }

  /// 自动推断baseUrl: 当前网页地址的 /acop 路径
  String _inferBaseUrl() {
    if (kIsWeb) {
      final loc = html.window.location;
      return '${loc.protocol}//${loc.host}/acop';
    }
    return 'http://localhost:8082';
  }

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionCookie = prefs.getString('acop_session');
    if (baseUrl.isEmpty) {
      baseUrl = _inferBaseUrl();
    }
  }

  Future<void> _saveSession(String? cookie) async {
    _sessionCookie = cookie;
    final prefs = await SharedPreferences.getInstance();
    if (cookie != null) {
      await prefs.setString('acop_session', cookie);
    } else {
      await prefs.remove('acop_session');
    }
  }

  bool get isLoggedIn => _sessionCookie != null && _sessionCookie!.isNotEmpty;

  Future<Map<String, dynamic>> post(
    String route,
    Map<String, dynamic> data,
  ) async {
    final uri = Uri.parse('$baseUrl/?route=$route');
    final req = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(data);

    if (_sessionCookie != null) {
      req.headers['Cookie'] = 'acop_session=$_sessionCookie';
    }

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    // 提取session cookie
    final setCookie = resp.headers['set-cookie'];
    if (setCookie != null) {
      final match = RegExp(r'acop_session=([^;]+)').firstMatch(setCookie);
      if (match != null) {
        await _saveSession(match.group(1));
      }
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> postMultipart(
    String route, {
    Map<String, String>? fields,
    required String fileField,
    required String filename,
    required List<int> bytes,
  }) async {
    final uri = Uri.parse('$baseUrl/?route=$route');
    final req = http.MultipartRequest('POST', uri);
    if (fields != null) req.fields.addAll(fields);
    req.files.add(
      http.MultipartFile.fromBytes(fileField, bytes, filename: filename),
    );

    if (_sessionCookie != null) {
      req.headers['Cookie'] = 'acop_session=$_sessionCookie';
    }

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    final setCookie = resp.headers['set-cookie'];
    if (setCookie != null) {
      final match = RegExp(r'acop_session=([^;]+)').firstMatch(setCookie);
      if (match != null) {
        await _saveSession(match.group(1));
      }
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> get(
    String route, [
    Map<String, String>? params,
  ]) async {
    final queryParams = <String, String>{'route': route};
    if (params != null) queryParams.addAll(params);
    final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams);

    final req = http.Request('GET', uri);
    if (_sessionCookie != null) {
      req.headers['Cookie'] = 'acop_session=$_sessionCookie';
    }

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    final setCookie = resp.headers['set-cookie'];
    if (setCookie != null) {
      final match = RegExp(r'acop_session=([^;]+)').firstMatch(setCookie);
      if (match != null) {
        await _saveSession(match.group(1));
      }
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> logout() async {
    await post('dev/logout', {});
    await _saveSession(null);
  }
}
