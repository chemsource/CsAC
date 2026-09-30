part of '../../main.dart';

String compactMessage(String text, {int max = 80}) {
  final value = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.length <= max) {
    return value;
  }
  return '${value.substring(0, max - 3)}...';
}

double chatBubbleMaxWidth(BuildContext context, {bool showAvatar = false}) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  final reservedWidth = showAvatar ? 64.0 : 24.0;
  final available = math.max(180.0, screenWidth - reservedWidth);
  return math.min(360.0, math.max(176.0, available * 0.72));
}

String chatMessagePlainText(ChatMessage message, CsacStrings strings) {
  if (message.isRecalled) {
    return strings.text('[recalled]');
  }
  if (message.emojiAddress.isNotEmpty || message.messageType == 5) {
    final name = message.emojiAbbr.trim();
    return name.isEmpty
        ? strings.text('[emoji]')
        : strings.format('[emoji] {abbr}', {'abbr': name});
  }
  if (message.imageUrl.isNotEmpty && message.body.startsWith('[image]')) {
    return strings.text('[image]');
  }
  if (message.voiceUrl.isNotEmpty && message.body.startsWith('[voice]')) {
    return strings.text('[voice]');
  }
  if (message.fileUrl.isNotEmpty && message.body.startsWith('[file]')) {
    return strings.text('[file]');
  }
  return message.body;
}

String notificationTextForMessage(ChatMessage message, CsacStrings strings) {
  final text = chatMessagePlainText(message, strings).trim();
  if (text.isEmpty) {
    return strings.text('New message');
  }
  return compactMessage(text, max: 120);
}

String notificationTitleForConversation(
  Conversation conversation,
  ChatMessage? message,
) {
  if (conversation.type == ConversationType.group) {
    return conversation.name.trim().isEmpty ? 'CsAC' : conversation.name;
  }
  final sender = message?.sender.trim() ?? '';
  if (sender.isNotEmpty && !sender.startsWith('UID 0')) {
    return sender;
  }
  return conversation.name.trim().isEmpty ? 'CsAC' : conversation.name;
}

String notificationBodyForConversation(
  Conversation conversation,
  int newCount,
  ChatMessage? message,
  CsacStrings strings,
) {
  if (message != null) {
    final text = notificationTextForMessage(message, strings);
    if (conversation.type == ConversationType.group) {
      final sender = message.sender.trim();
      return sender.isEmpty || sender.startsWith('UID 0')
          ? text
          : '$sender: $text';
    }
    return text;
  }
  final subtitle = conversation.subtitle.trim();
  if (subtitle.isNotEmpty) {
    return compactMessage(subtitle, max: 120);
  }
  return strings.format('New messages: {count}', {'count': newCount});
}

ChatMessage? latestIncomingNotificationMessage(
  Conversation conversation,
  List<ChatMessage> messages, {
  required int currentUserId,
}) {
  final incoming = messages.where((message) {
    if (message.id <= 0) {
      return false;
    }
    if (currentUserId > 0 && message.senderId == currentUserId) {
      return false;
    }
    return conversation.type == ConversationType.group ||
        message.senderId == conversation.id ||
        message.senderId != 0;
  }).toList();
  if (incoming.isEmpty) {
    return null;
  }
  incoming.sort((a, b) => a.id.compareTo(b.id));
  return incoming.last;
}

int latestIncomingNotificationMessageId(
  Conversation conversation,
  List<ChatMessage> messages, {
  required int currentUserId,
}) {
  return latestIncomingNotificationMessage(
        conversation,
        messages,
        currentUserId: currentUserId,
      )?.id ??
      0;
}

CsacTimestampPattern timestampPatternForPreference(MessageTimeFormat format) {
  switch (format) {
    case MessageTimeFormat.slash:
      return CsacTimestampPattern.slash;
    case MessageTimeFormat.dash:
      return CsacTimestampPattern.dash;
    case MessageTimeFormat.compact:
      return CsacTimestampPattern.compact;
    case MessageTimeFormat.timeOnly:
      return CsacTimestampPattern.timeOnly;
  }
}

String displayMessageTime(ChatMessage message, CsacPreferences preferences) {
  return formatCsacTimestamp(
    message.timeSortValue > 0 ? message.timeSortValue : message.time,
    pattern: timestampPatternForPreference(preferences.messageTimeFormat),
  );
}

String messageTimeFormatLabelFor(
  BuildContext context,
  MessageTimeFormat format,
) {
  switch (format) {
    case MessageTimeFormat.slash:
      return context.strings.text('yyyy/mm/dd hh:mm:ss');
    case MessageTimeFormat.dash:
      return context.strings.text('yyyy-mm-dd hh:mm:ss');
    case MessageTimeFormat.compact:
      return context.strings.text('mm/dd hh:mm');
    case MessageTimeFormat.timeOnly:
      return context.strings.text('hh:mm:ss');
  }
}

String messageTimeFormatExampleFor(MessageTimeFormat format) {
  final sample = DateTime(2026, 5, 28, 21, 30, 15);
  switch (format) {
    case MessageTimeFormat.slash:
      return formatLocalDateTime(sample, separator: '/');
    case MessageTimeFormat.dash:
      return formatLocalDateTime(sample, separator: '-');
    case MessageTimeFormat.compact:
      return formatCompactLocalDateTime(sample);
    case MessageTimeFormat.timeOnly:
      return formatLocalTime(sample);
  }
}

String chatBubbleCornerStyleLabelFor(
  BuildContext context,
  ChatBubbleCornerStyle style,
) {
  switch (style) {
    case ChatBubbleCornerStyle.telegram:
      return context.strings.text('Telegram style');
    case ChatBubbleCornerStyle.ios:
      return context.strings.text('iOS style');
    case ChatBubbleCornerStyle.qq:
      return context.strings.text('QQ style');
  }
}

String fontStyleLabelFor(BuildContext context, CsacFontStyle style) {
  final strings = context.strings;
  switch (style) {
    case CsacFontStyle.system:
      return strings.text('Default system');
    case CsacFontStyle.serif:
      return strings.text('Serif');
    case CsacFontStyle.rounded:
      return strings.text('Rounded');
    case CsacFontStyle.monospace:
      return strings.text('Monospace');
  }
}

String fontStyleDescriptionFor(BuildContext context, CsacFontStyle style) {
  final strings = context.strings;
  switch (style) {
    case CsacFontStyle.system:
      return strings.text('Use the platform default font');
    case CsacFontStyle.serif:
      return strings.text('More book-like text');
    case CsacFontStyle.rounded:
      return strings.text('Softer iOS-style rounded text');
    case CsacFontStyle.monospace:
      return strings.text('Fixed-width terminal-like text');
  }
}

String pickedImageFileName(XFile picked, ImageSource source) {
  final name = picked.name.trim();
  final extension = p.extension(name).toLowerCase();
  if (name.isNotEmpty && extension.isNotEmpty) {
    return name;
  }
  final fallbackExtension = extension.isEmpty ? '.jpg' : extension;
  final prefix = source == ImageSource.camera ? 'csac_photo' : 'csac_image';
  return '${prefix}_${DateTime.now().millisecondsSinceEpoch}$fallbackExtension';
}

Future<String> persistChatBackground(XFile picked) async {
  return persistChatBackgroundFile(picked);
}

String friendlyMobileFileError(
  CsacStrings strings,
  Object error, {
  required String fallbackKey,
}) {
  if (error is MissingPluginException) {
    return strings.text(
      'This file feature is not available on this platform. Please update the app or try another device.',
    );
  }
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    final message = (error.message ?? '').toLowerCase();
    if (code.contains('photo_access_denied') ||
        code.contains('camera_access_denied') ||
        code.contains('permission') ||
        code.contains('denied') ||
        message.contains('permission') ||
        message.contains('denied') ||
        message.contains('not allow')) {
      return strings.text(
        'Permission was denied. Please allow photo, camera or file access in system settings and try again.',
      );
    }
    if (code.contains('activity_not_found') ||
        code.contains('unavailable') ||
        code.contains('not_available')) {
      return strings.text(
        'No compatible app is available to complete this action.',
      );
    }
    final detail = error.message?.trim();
    if (detail != null && detail.isNotEmpty) {
      return strings.format(fallbackKey, {'error': detail});
    }
  }
  final raw = error.toString();
  final lower = raw.toLowerCase();
  if (lower.contains('permission') ||
      lower.contains('denied') ||
      lower.contains('not allowed') ||
      lower.contains('unauthorized')) {
    return strings.text(
      'Permission was denied. Please allow photo, camera or file access in system settings and try again.',
    );
  }
  if (lower.contains('missingplugin') ||
      lower.contains('not implemented') ||
      lower.contains('unsupported')) {
    return strings.text(
      'This file feature is not available on this platform. Please update the app or try another device.',
    );
  }
  if (lower.contains('share') &&
      (lower.contains('unavailable') || lower.contains('failed'))) {
    return strings.text('Sharing is unavailable on this device.');
  }
  return strings.format(fallbackKey, {'error': raw});
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(message, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}
