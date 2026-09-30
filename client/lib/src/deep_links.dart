const csacDeepLinkScheme = 'csacflutterleon';

enum CsacDeepLinkAction {
  chats,
  space,
  spacePost,
  search,
  searchResult,
  notices,
  emApps,
  emApp,
  profile,
  userProfile,
  groupChat,
  privateChat,
  groupMessage,
  privateMessage,
  unsupported,
}

class CsacDeepLinkTarget {
  const CsacDeepLinkTarget(
    this.action, {
    this.id,
    this.messageId,
    this.appId,
    this.query,
    this.draftText,
    this.confirmSend = false,
  });

  final CsacDeepLinkAction action;
  final int? id;
  final int? messageId;
  final String? appId;
  final String? query;
  final String? draftText;
  final bool confirmSend;

  bool get isSupported => action != CsacDeepLinkAction.unsupported;

  bool get hasDraftAction {
    return (draftText ?? '').isNotEmpty || confirmSend;
  }
}

bool isCsacDeepLink(Uri uri) {
  return uri.scheme.toLowerCase() == csacDeepLinkScheme;
}

CsacDeepLinkTarget parseCsacDeepLink(Uri uri) {
  if (!isCsacDeepLink(uri)) {
    return const CsacDeepLinkTarget(CsacDeepLinkAction.unsupported);
  }
  final segments = csacDeepLinkSegments(uri);
  if (segments.isEmpty) {
    return const CsacDeepLinkTarget(CsacDeepLinkAction.chats);
  }

  final command = segments.first;
  switch (command) {
    case 'home':
    case 'chatlist':
    case 'chats':
    case 'conversations':
    case 'messages':
      return const CsacDeepLinkTarget(CsacDeepLinkAction.chats);
    case 'space':
    case 'discover':
    case 'discovery':
    case 'dynamic':
    case 'feed':
      if (segments.length > 1 &&
          (segments[1] == 'post' ||
              segments[1] == 'status' ||
              segments[1] == 'dynamic')) {
        return _typedDeepLinkTarget(
          CsacDeepLinkAction.spacePost,
          segments.length > 2 ? segments[2] : uri.queryParameters['id'],
        );
      }
      return const CsacDeepLinkTarget(CsacDeepLinkAction.space);
    case 'post':
    case 'status':
      return _typedDeepLinkTarget(
        CsacDeepLinkAction.spacePost,
        segments.length > 1 ? segments[1] : uri.queryParameters['id'],
      );
    case 'search':
    case 'find':
      final query = (uri.queryParameters['q'] ?? uri.queryParameters['query'])
          ?.trim();
      if (query != null && query.isNotEmpty) {
        return CsacDeepLinkTarget(
          CsacDeepLinkAction.searchResult,
          query: query,
        );
      }
      return const CsacDeepLinkTarget(CsacDeepLinkAction.search);
    case 'notice':
    case 'notices':
    case 'notification':
    case 'notifications':
      return const CsacDeepLinkTarget(CsacDeepLinkAction.notices);
    case 'apps':
    case 'emapps':
    case 'miniapps':
      if (segments.length > 1) {
        return _emAppDeepLinkTarget(segments[1]);
      }
      final appId = uri.queryParameters['app_id'] ?? uri.queryParameters['id'];
      if (appId != null && appId.trim().isNotEmpty) {
        return _emAppDeepLinkTarget(appId);
      }
      return const CsacDeepLinkTarget(CsacDeepLinkAction.emApps);
    case 'app':
    case 'emapp':
    case 'miniapp':
      return _emAppDeepLinkTarget(
        segments.length > 1
            ? segments[1]
            : (uri.queryParameters['app_id'] ?? uri.queryParameters['id']),
      );
    case 'me':
    case 'mine':
    case 'settings':
      return const CsacDeepLinkTarget(CsacDeepLinkAction.profile);
    case 'profile':
      return _profileLinkTarget(uri, segments);
    case 'u':
    case 'uid':
    case 'user-profile':
    case 'profile-user':
      return _typedDeepLinkTarget(
        CsacDeepLinkAction.userProfile,
        segments.length > 1 ? segments[1] : uri.queryParameters['id'],
      );
    case 'chat':
    case 'conversation':
      return _chatLinkTarget(uri, segments);
    case 'message':
    case 'msg':
      return _messageLinkTarget(uri, segments);
    case 'group':
    case 'room':
      return _chatOrMessageTarget(
        CsacDeepLinkAction.groupChat,
        CsacDeepLinkAction.groupMessage,
        segments.length > 1 ? segments[1] : uri.queryParameters['id'],
        segments.length > 3 && segments[2] == 'message'
            ? segments[3]
            : uri.queryParameters['message_id'],
        uri,
      );
    case 'private':
    case 'friend':
    case 'user':
      return _chatOrMessageTarget(
        CsacDeepLinkAction.privateChat,
        CsacDeepLinkAction.privateMessage,
        segments.length > 1 ? segments[1] : uri.queryParameters['id'],
        segments.length > 3 && segments[2] == 'message'
            ? segments[3]
            : uri.queryParameters['message_id'],
        uri,
      );
  }
  return const CsacDeepLinkTarget(CsacDeepLinkAction.unsupported);
}

String csacUserProfileDeepLink(int uid) {
  return '$csacDeepLinkScheme://profile/user/$uid';
}

String csacGroupChatDeepLink(int roomId) {
  return '$csacDeepLinkScheme://chat/group/$roomId';
}

String csacGroupDraftDeepLink(
  int roomId,
  String draft, {
  bool confirmSend = false,
}) {
  return _chatDraftDeepLink('group', roomId, draft, confirmSend: confirmSend);
}

String csacPrivateDraftDeepLink(
  int uid,
  String draft, {
  bool confirmSend = false,
}) {
  return _chatDraftDeepLink('private', uid, draft, confirmSend: confirmSend);
}

String csacSpacePostDeepLink(int postId) {
  return '$csacDeepLinkScheme://space/post/$postId';
}

String csacSearchDeepLink(String query) {
  final encoded = Uri.encodeQueryComponent(query.trim());
  return encoded.isEmpty
      ? '$csacDeepLinkScheme://search'
      : '$csacDeepLinkScheme://search?q=$encoded';
}

String csacEmAppDeepLink(String appId) {
  return '$csacDeepLinkScheme://emapp/${Uri.encodeComponent(appId.trim())}';
}

String csacGroupMessageDeepLink(int roomId, int messageId) {
  return '$csacDeepLinkScheme://chat/group/$roomId/message/$messageId';
}

String csacPrivateMessageDeepLink(int uid, int messageId) {
  return '$csacDeepLinkScheme://chat/private/$uid/message/$messageId';
}

List<String> csacDeepLinkSegments(Uri uri) {
  final segments = <String>[];
  if (uri.host.trim().isNotEmpty) {
    segments.add(uri.host.trim());
  }
  for (final segment in uri.pathSegments) {
    final trimmed = segment.trim();
    if (trimmed.isNotEmpty) {
      segments.add(trimmed);
    }
  }
  if (segments.isEmpty && uri.fragment.trim().isNotEmpty) {
    final fragment = uri.fragment.trim().replaceFirst(RegExp(r'^/+'), '');
    segments.addAll(
      fragment
          .split('/')
          .map((segment) => segment.trim())
          .where((segment) => segment.isNotEmpty),
    );
  }
  return [
    for (final segment in segments) Uri.decodeComponent(segment).toLowerCase(),
  ];
}

CsacDeepLinkTarget _chatLinkTarget(Uri uri, List<String> segments) {
  final type = segments.length > 1
      ? segments[1]
      : (uri.queryParameters['type'] ?? uri.queryParameters['kind'] ?? '');
  final id = segments.length > 2 ? segments[2] : uri.queryParameters['id'];
  final messageId = segments.length > 4 && segments[3] == 'message'
      ? segments[4]
      : (uri.queryParameters['message_id'] ??
            uri.queryParameters['msg_id'] ??
            uri.queryParameters['mid']);
  switch (type.toLowerCase()) {
    case 'group':
    case 'room':
      return _chatOrMessageTarget(
        CsacDeepLinkAction.groupChat,
        CsacDeepLinkAction.groupMessage,
        id,
        messageId,
        uri,
      );
    case 'private':
    case 'friend':
    case 'user':
      return _chatOrMessageTarget(
        CsacDeepLinkAction.privateChat,
        CsacDeepLinkAction.privateMessage,
        id,
        messageId,
        uri,
      );
  }
  return const CsacDeepLinkTarget(CsacDeepLinkAction.unsupported);
}

CsacDeepLinkTarget _messageLinkTarget(Uri uri, List<String> segments) {
  final type = segments.length > 1
      ? segments[1]
      : (uri.queryParameters['type'] ?? uri.queryParameters['kind'] ?? '');
  final id = segments.length > 2
      ? segments[2]
      : (uri.queryParameters['room_id'] ??
            uri.queryParameters['uid'] ??
            uri.queryParameters['id']);
  final messageId = segments.length > 3
      ? segments[3]
      : (uri.queryParameters['message_id'] ??
            uri.queryParameters['msg_id'] ??
            uri.queryParameters['mid']);
  switch (type.toLowerCase()) {
    case 'group':
    case 'room':
      return _chatOrMessageTarget(
        CsacDeepLinkAction.groupChat,
        CsacDeepLinkAction.groupMessage,
        id,
        messageId,
        uri,
      );
    case 'private':
    case 'friend':
    case 'user':
      return _chatOrMessageTarget(
        CsacDeepLinkAction.privateChat,
        CsacDeepLinkAction.privateMessage,
        id,
        messageId,
        uri,
      );
  }
  return const CsacDeepLinkTarget(CsacDeepLinkAction.unsupported);
}

CsacDeepLinkTarget _chatOrMessageTarget(
  CsacDeepLinkAction chatAction,
  CsacDeepLinkAction messageAction,
  String? rawId,
  String? rawMessageId, [
  Uri? uri,
]) {
  final id = int.tryParse((rawId ?? '').trim()) ?? 0;
  if (id <= 0) {
    return const CsacDeepLinkTarget(CsacDeepLinkAction.unsupported);
  }
  final messageId = int.tryParse((rawMessageId ?? '').trim()) ?? 0;
  final draftText = uri == null ? null : _draftTextFromUri(uri);
  final confirmSend = uri == null ? false : _confirmSendFromUri(uri);
  if (messageId <= 0) {
    return CsacDeepLinkTarget(
      chatAction,
      id: id,
      draftText: draftText,
      confirmSend: confirmSend,
    );
  }
  return CsacDeepLinkTarget(
    messageAction,
    id: id,
    messageId: messageId,
    draftText: draftText,
    confirmSend: confirmSend,
  );
}

String _chatDraftDeepLink(
  String type,
  int id,
  String draft, {
  required bool confirmSend,
}) {
  final params = <String, String>{
    'draft': draft,
    if (confirmSend) 'send': 'confirm',
  };
  final query = Uri(queryParameters: params).query;
  return '$csacDeepLinkScheme://chat/$type/$id?$query';
}

String? _draftTextFromUri(Uri uri) {
  final raw =
      uri.queryParameters['draft'] ??
      uri.queryParameters['text'] ??
      uri.queryParameters['message'] ??
      uri.queryParameters['body'];
  return raw == null || raw.isEmpty ? null : raw;
}

bool _confirmSendFromUri(Uri uri) {
  final value =
      (uri.queryParameters['send'] ??
              uri.queryParameters['confirm_send'] ??
              uri.queryParameters['action'] ??
              '')
          .trim()
          .toLowerCase();
  return value == 'confirm' ||
      value == 'confirm-send' ||
      value == 'confirm_send' ||
      value == 'ask' ||
      value == 'true' ||
      value == '1';
}

CsacDeepLinkTarget _profileLinkTarget(Uri uri, List<String> segments) {
  if (segments.length > 1) {
    final kind = segments[1];
    if (kind == 'user' || kind == 'uid') {
      return _typedDeepLinkTarget(
        CsacDeepLinkAction.userProfile,
        segments.length > 2 ? segments[2] : uri.queryParameters['id'],
      );
    }
    final id = int.tryParse(kind) ?? 0;
    if (id > 0) {
      return CsacDeepLinkTarget(CsacDeepLinkAction.userProfile, id: id);
    }
  }
  final id = int.tryParse(uri.queryParameters['uid'] ?? '') ?? 0;
  if (id > 0) {
    return CsacDeepLinkTarget(CsacDeepLinkAction.userProfile, id: id);
  }
  return const CsacDeepLinkTarget(CsacDeepLinkAction.profile);
}

CsacDeepLinkTarget _typedDeepLinkTarget(
  CsacDeepLinkAction action,
  String? rawId,
) {
  final id = int.tryParse((rawId ?? '').trim()) ?? 0;
  if (id <= 0) {
    return const CsacDeepLinkTarget(CsacDeepLinkAction.unsupported);
  }
  return CsacDeepLinkTarget(action, id: id);
}

CsacDeepLinkTarget _emAppDeepLinkTarget(String? rawAppId) {
  final appId = (rawAppId ?? '').trim();
  if (appId.isEmpty) {
    return const CsacDeepLinkTarget(CsacDeepLinkAction.unsupported);
  }
  return CsacDeepLinkTarget(CsacDeepLinkAction.emApp, appId: appId);
}
