import 'api_client.dart';

class DevService {
  final ApiClient _api;
  DevService(this._api);

  Future<Map<String, dynamic>> register({
    required String email,
    required String pwd,
    required String devName,
    required String code,
    required String csacUsername,
    required String csacPassword,
  }) async {
    return await _api.post('dev/register', {
      'email': email,
      'pwd': pwd,
      'dev_name': devName,
      'code': code,
      'csac_username': csacUsername,
      'csac_password': csacPassword,
    });
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String pwd,
  }) async {
    return await _api.post('dev/login', {'email': email, 'pwd': pwd});
  }

  Future<Map<String, dynamic>> sendCode({
    required String email,
    required String purpose,
  }) async {
    return await _api.post('dev/send_code', {
      'email': email,
      'purpose': purpose,
    });
  }

  Future<Map<String, dynamic>> loginByCode({
    required String email,
    required String code,
  }) async {
    return await _api.post('dev/login_by_code', {'email': email, 'code': code});
  }

  Future<Map<String, dynamic>> getInfo() async {
    return await _api.post('dev/get_info', {});
  }

  Future<void> logout() async {
    await _api.logout();
  }
}

class BotService {
  final ApiClient _api;
  BotService(this._api);

  Future<Map<String, dynamic>> create({
    required String botName,
    String botDesc = '',
  }) async {
    return await _api.post('bot/create', {
      'bot_name': botName,
      'bot_desc': botDesc,
    });
  }

  Future<Map<String, dynamic>> list() async {
    return await _api.post('bot/list', {});
  }

  Future<Map<String, dynamic>> getInfo(int botId) async {
    return await _api.post('bot/get_info', {'bot_id': botId});
  }

  Future<Map<String, dynamic>> update({
    required int botId,
    String? botName,
    String? botDesc,
    String? botAvatar,
  }) async {
    final data = <String, dynamic>{'bot_id': botId};
    if (botName != null) data['bot_name'] = botName;
    if (botDesc != null) data['bot_desc'] = botDesc;
    if (botAvatar != null) data['bot_avatar'] = botAvatar;
    return await _api.post('bot/update', data);
  }

  Future<Map<String, dynamic>> uploadAvatar({
    required int botId,
    required String filename,
    required List<int> bytes,
  }) async {
    return await _api.postMultipart(
      'bot/upload_avatar',
      fields: {'bot_id': '$botId'},
      fileField: 'avatar',
      filename: filename,
      bytes: bytes,
    );
  }

  Future<Map<String, dynamic>> resetToken(int botId) async {
    return await _api.post('bot/reset_token', {'bot_id': botId});
  }

  Future<Map<String, dynamic>> delete(int botId) async {
    return await _api.post('bot/delete', {'bot_id': botId});
  }
}

class ScriptService {
  final ApiClient _api;
  ScriptService(this._api);

  Future<Map<String, dynamic>> create({
    required int botId,
    required String scriptName,
    String scriptContent = '',
  }) async {
    return await _api.post('script/create', {
      'bot_id': botId,
      'script_name': scriptName,
      'script_content': scriptContent,
    });
  }

  Future<Map<String, dynamic>> list(int botId) async {
    return await _api.post('script/list', {'bot_id': botId});
  }

  Future<Map<String, dynamic>> get(int scriptId) async {
    return await _api.post('script/get', {'script_id': scriptId});
  }

  Future<Map<String, dynamic>> update({
    required int scriptId,
    String? scriptName,
    String? scriptContent,
  }) async {
    final data = <String, dynamic>{'script_id': scriptId};
    if (scriptName != null) data['script_name'] = scriptName;
    if (scriptContent != null) data['script_content'] = scriptContent;
    return await _api.post('script/update', data);
  }

  Future<Map<String, dynamic>> delete(int scriptId) async {
    return await _api.post('script/delete', {'script_id': scriptId});
  }

  Future<Map<String, dynamic>> toggle(int scriptId, int enabled) async {
    return await _api.post('script/toggle', {
      'script_id': scriptId,
      'enabled': enabled,
    });
  }

  Future<Map<String, dynamic>> test({
    required int scriptId,
    String eventType = 'group_message',
    String? scriptContent,
    Map<String, dynamic>? eventData,
  }) async {
    final data = <String, dynamic>{
      'script_id': scriptId,
      'event_type': eventType,
    };
    if (scriptContent != null) data['script_content'] = scriptContent;
    if (eventData != null) data['event_data'] = eventData;
    return await _api.post('script/test', data);
  }
}

class LogService {
  final ApiClient _api;
  LogService(this._api);

  Future<Map<String, dynamic>> list({
    required int botId,
    String? level,
    int limit = 50,
  }) async {
    final data = <String, dynamic>{'bot_id': botId, 'limit': limit};
    if (level != null) data['level'] = level;
    return await _api.post('log/list', data);
  }
}

class PermService {
  final ApiClient _api;
  PermService(this._api);

  Future<Map<String, dynamic>> request({
    required int botId,
    required String permType,
    required String reason,
  }) async {
    return await _api.post('perm/request', {
      'bot_id': botId,
      'perm_type': permType,
      'reason': reason,
    });
  }

  Future<Map<String, dynamic>> list(int botId) async {
    return await _api.post('perm/list', {'bot_id': botId});
  }
}

// v2.2.1: JSLibs库管理服务
class LibService {
  final ApiClient _api;
  LibService(this._api);

  Future<Map<String, dynamic>> upload({
    required String name,
    required String version,
    required String content,
    String description = '',
  }) async {
    return await _api.post('lib/upload', {
      'name': name,
      'version': version,
      'content': content,
      'description': description,
    });
  }

  Future<Map<String, dynamic>> myLibs() async {
    return await _api.post('lib/my_libs', {});
  }

  Future<Map<String, dynamic>> list({int page = 1, int pageSize = 20}) async {
    return await _api.post('lib/list', {
      'page': page,
      'page_size': pageSize,
    });
  }
}

// v2.3.0: 管理员库审核服务
class AdminLibService {
  final ApiClient _api;
  AdminLibService(this._api);

  Future<Map<String, dynamic>> pending({int page = 1}) async {
    return await _api.post('admin/lib/pending', {'page': page});
  }

  Future<Map<String, dynamic>> review({
    required int libId,
    required String action,
    String adminNote = '',
  }) async {
    return await _api.post('admin/lib/review', {
      'id': libId,
      'action': action,
      'admin_note': adminNote,
    });
  }

  Future<Map<String, dynamic>> setUploadPerm({
    required int devId,
    required int allow,
  }) async {
    return await _api.post('admin/lib/set_upload_perm', {
      'dev_id': devId,
      'allow': allow,
    });
  }
}

// 管理员: Bot权限申请审核 + ACR脚本审核
class AdminService {
  final ApiClient _api;
  AdminService(this._api);

  // 待处理的权限申请
  Future<Map<String, dynamic>> permPending() async {
    return await _api.post('admin/perm/pending', {});
  }

  // 处理权限申请 (approve / reject)
  Future<Map<String, dynamic>> permHandle({
    required int requestId,
    required String action,
    String adminReply = '',
  }) async {
    return await _api.post('admin/perm/handle', {
      'request_id': requestId,
      'action': action,
      'admin_reply': adminReply,
    });
  }

  // 待审核的ACR上传
  Future<Map<String, dynamic>> acrPending() async {
    return await _api.post('admin/acr/pending', {});
  }

  // 读取ACR文件内容
  Future<Map<String, dynamic>> acrRead(int uploadId) async {
    return await _api.post('admin/acr/read', {'id': uploadId});
  }

  // 审核ACR上传 (approve / reject)
  Future<Map<String, dynamic>> acrReview({
    required int uploadId,
    required String action,
    String adminNote = '',
  }) async {
    return await _api.post('admin/acr/review', {
      'id': uploadId,
      'action': action,
      'admin_note': adminNote,
    });
  }

  // 待审核的EMA小程序上传
  Future<Map<String, dynamic>> emaPending() async {
    return await _api.post('admin/ema/pending', {});
  }

  // 读取EMA小程序内容
  Future<Map<String, dynamic>> emaRead(int uploadId) async {
    return await _api.post('admin/ema/read', {'id': uploadId});
  }

  // 审核EMA上传 (approve / reject)
  Future<Map<String, dynamic>> emaReview({
    required int uploadId,
    required String action,
    String adminNote = '',
  }) async {
    return await _api.post('admin/ema/review', {
      'id': uploadId,
      'action': action,
      'admin_note': adminNote,
    });
  }
}
