class BotInfo {
  final int botId;
  final int uid;
  final String botName;
  final String botDesc;
  final String botAvatar;
  final String? botToken;
  final int status;
  final int canNotify;
  final int canHttp;
  final int online;
  final int lastOnline;
  final int createdAt;
  final String? nickname;

  BotInfo({
    required this.botId,
    required this.uid,
    required this.botName,
    this.botDesc = '',
    this.botAvatar = '',
    this.botToken,
    this.status = 1,
    this.canNotify = 0,
    this.canHttp = 0,
    this.online = 0,
    this.lastOnline = 0,
    this.createdAt = 0,
    this.nickname,
  });

  factory BotInfo.fromJson(Map<String, dynamic> json) {
    return BotInfo(
      botId: (json['bot_id'] as num?)?.toInt() ?? 0,
      uid: (json['uid'] as num?)?.toInt() ?? 0,
      botName: json['bot_name'] as String? ?? '',
      botDesc: json['bot_desc'] as String? ?? '',
      botAvatar: json['bot_avatar'] as String? ?? '',
      botToken: json['bot_token'] as String?,
      status: (json['status'] as num?)?.toInt() ?? 1,
      canNotify: (json['can_notify'] as num?)?.toInt() ?? 0,
      canHttp: (json['can_http'] as num?)?.toInt() ?? 0,
      online: (json['online'] as num?)?.toInt() ?? 0,
      lastOnline: (json['last_online'] as num?)?.toInt() ?? 0,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      nickname: json['nickname'] as String?,
    );
  }

  bool get isOnline => online == 1;
  bool get isActive => status == 1;
}

class ScriptInfo {
  final int scriptId;
  final int botId;
  final String scriptName;
  final String? scriptContent;
  final int enabled;
  final int version;
  final int createdAt;
  final int updatedAt;

  ScriptInfo({
    required this.scriptId,
    required this.botId,
    required this.scriptName,
    this.scriptContent,
    this.enabled = 0,
    this.version = 1,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  factory ScriptInfo.fromJson(Map<String, dynamic> json) {
    return ScriptInfo(
      scriptId: (json['script_id'] as num?)?.toInt() ?? 0,
      botId: (json['bot_id'] as num?)?.toInt() ?? 0,
      scriptName: json['script_name'] as String? ?? '',
      scriptContent: json['script_content'] as String?,
      enabled: (json['enabled'] as num?)?.toInt() ?? 0,
      version: (json['version'] as num?)?.toInt() ?? 1,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isEnabled => enabled == 1;
}

class LogEntry {
  final int id;
  final int botId;
  final int scriptId;
  final String level;
  final String content;
  final int createdAt;

  LogEntry({
    required this.id,
    required this.botId,
    this.scriptId = 0,
    this.level = 'log',
    this.content = '',
    this.createdAt = 0,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      botId: (json['bot_id'] as num?)?.toInt() ?? 0,
      scriptId: (json['script_id'] as num?)?.toInt() ?? 0,
      level: json['level'] as String? ?? 'log',
      content: json['content'] as String? ?? '',
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    );
  }
}

class PermRequest {
  final int id;
  final int botId;
  final String permType;
  final String reason;
  final int status;
  final String? adminReply;
  final int createdAt;

  PermRequest({
    required this.id,
    required this.botId,
    required this.permType,
    this.reason = '',
    this.status = 0,
    this.adminReply,
    this.createdAt = 0,
  });

  factory PermRequest.fromJson(Map<String, dynamic> json) {
    return PermRequest(
      id: (json['id'] as num?)?.toInt() ?? 0,
      botId: (json['bot_id'] as num?)?.toInt() ?? 0,
      permType: json['perm_type'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      status: (json['status'] as num?)?.toInt() ?? 0,
      adminReply: json['admin_reply'] as String?,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    );
  }

  String get statusText {
    switch (status) {
      case 0:
        return '待审核';
      case 1:
        return '已通过';
      case 2:
        return '已拒绝';
      default:
        return '未知';
    }
  }
}

class DevInfo {
  final int devId;
  final String email;
  final String devName;
  final String apiKey;
  final int status;
  final int createdAt;

  DevInfo({
    required this.devId,
    this.email = '',
    this.devName = '',
    this.apiKey = '',
    this.status = 1,
    this.createdAt = 0,
  });

  factory DevInfo.fromJson(Map<String, dynamic> json) {
    return DevInfo(
      devId: (json['dev_id'] as num?)?.toInt() ?? 0,
      email: json['email'] as String? ?? '',
      devName: json['dev_name'] as String? ?? '',
      apiKey: json['api_key'] as String? ?? '',
      status: (json['status'] as num?)?.toInt() ?? 1,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    );
  }
}
