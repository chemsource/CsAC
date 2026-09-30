import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AcopApiClient {
  AcopApiClient({this.baseUrl = ''}) {
    _loadSession();
  }

  String baseUrl;
  http.Client _httpClient = http.Client();
  bool _isLoggedIn = false;
  String? _sessionCookie; // store Set-Cookie from login response

  bool get isLoggedIn => _isLoggedIn;
  String? get sessionCookie => _sessionCookie;

  Future<void> _loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('acop_session');
      if (saved != null && saved.isNotEmpty) {
        _sessionCookie = saved;
        _isLoggedIn = true;
      }
    } catch (_) {}
  }

  Future<void> _saveSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_sessionCookie != null) {
        await prefs.setString('acop_session', _sessionCookie!);
      }
    } catch (_) {}
  }

  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('acop_session');
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _request(String action, Map<String, dynamic> params) async {
    final uri = Uri.parse('$baseUrl/?route=$action');
    final body = jsonEncode(params);
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_sessionCookie != null) {
      headers['Cookie'] = _sessionCookie!;
    }
    try {
      final resp = await _httpClient.post(
        uri,
        headers: headers,
        body: body,
      );
      if (resp.statusCode != 200) {
        return {'success': false, 'message': 'HTTP ${resp.statusCode}: ${resp.reasonPhrase}'};
      }
      // Capture session cookie from response
      final setCookie = resp.headers['set-cookie'];
      if (setCookie != null && setCookie.contains('acop_session=')) {
        _sessionCookie = setCookie.split(';').first;
        _saveSession();
      }
      try {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        final preview = resp.body.length > 200 ? '${resp.body.substring(0, 200)}...' : resp.body;
        if (preview.isEmpty) return {'success': false, 'message': '服务器返回空响应'};
        return {'success': false, 'message': '服务器返回非JSON数据: $preview'};
      }
    } catch (e) {
      return {'success': false, 'message': '网络连接失败: 请检查服务器地址是否正确 ($e)'};
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final result = await _request('dev/login', {
      'email': email,
      'pwd': password,
    });
    if (result['success'] == true) {
      _isLoggedIn = true;
      _saveSession();
    }
    return result;
  }

  void logout() {
    _isLoggedIn = false;
    _sessionCookie = null;
    _clearSession();
    _httpClient.close();
    _httpClient = http.Client();
  }

  Future<List<Map<String, dynamic>>> getBotList() async {
    final result = await _request('bot/list', {});
    if (result['success'] == true) {
      final data = result['data'];
      if (data is List) return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> getBotInfo(int botId) async {
    return await _request('bot/get_info', {'bot_id': botId});
  }

  Future<Map<String, dynamic>> createScript(int botId, String name, String content) async {
    return await _request('script/create', {
      'bot_id': botId,
      'script_name': name,
      'script_content': content,
    });
  }

  Future<List<Map<String, dynamic>>> getScriptList(int botId) async {
    final result = await _request('script/list', {'bot_id': botId});
    if (result['success'] == true) {
      final data = result['data'];
      if (data is List) return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> getScript(int scriptId) async {
    return await _request('script/get', {'script_id': scriptId});
  }

  Future<Map<String, dynamic>> updateScript(int scriptId, String name, String content) async {
    return await _request('script/update', {
      'script_id': scriptId,
      'script_name': name,
      'script_content': content,
    });
  }

  Future<Map<String, dynamic>> deleteScript(int scriptId) async {
    return await _request('script/delete', {'script_id': scriptId});
  }

  Future<Map<String, dynamic>> toggleScript(int scriptId, bool enabled) async {
    return await _request('script/toggle', {
      'script_id': scriptId,
      'enabled': enabled ? 1 : 0,
    });
  }

  Future<Map<String, dynamic>> uploadAcr(String fileName, String content, {String desc = ''}) async {
    return await _request('script/upload_acr', {
      'file_name': fileName,
      'content': content,
      'desc': desc,
    });
  }

  Future<Map<String, dynamic>> uploadAcrg(String fileName, String content, {String desc = ''}) async {
    return await _request('script/upload_acrg', {
      'file_name': fileName,
      'content': content,
      'desc': desc,
    });
  }

  Future<Map<String, dynamic>> uploadEma(String fileName, String content, String desc) async {
    return await _request('script/upload_ema', {
      'file_name': fileName,
      'content': content,
      'desc': desc,
    });
  }

  // v3.1.0: AJL 库浏览
  Future<List<Map<String, dynamic>>> getLibList() async {
    final result = await _request('lib/list', {});
    if (result['success'] == true) {
      final libs = result['libs'];
      if (libs is List) return libs.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getMyLibs() async {
    final result = await _request('lib/my_libs', {});
    if (result['success'] == true) {
      final libs = result['libs'];
      if (libs is List) return libs.cast<Map<String, dynamic>>();
    }
    return [];
  }
}
