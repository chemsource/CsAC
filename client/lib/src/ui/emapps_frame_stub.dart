import 'package:flutter/material.dart';

/// 原生平台桩 — EmAppWebFrame 原生平台用 WebView 代替，此处为编译占位
class EmAppWebFrame extends StatefulWidget {
  const EmAppWebFrame({
    super.key,
    required this.url,
    required this.htmlContent,
    required this.onBridgeMessage,
    required this.onLog,
  });

  final String url;
  final String htmlContent;
  final Future<Object> Function(String method, Map<String, dynamic> args)
      onBridgeMessage;
  final void Function(String kind, String message) onLog;

  @override
  State<EmAppWebFrame> createState() => EmAppWebFrameState();
}

class EmAppWebFrameState extends State<EmAppWebFrame> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  void reload() {}
}
