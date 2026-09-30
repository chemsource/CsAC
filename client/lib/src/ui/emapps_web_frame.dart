import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Web EMA 运行器控件 — 使用 iframe + postMessage Bridge
class EmAppWebFrame extends StatefulWidget {
  const EmAppWebFrame({
    super.key,
    required this.url,
    required this.htmlContent,
    required this.onBridgeMessage,
    required this.onLog,
  });

  final String url;
  final String htmlContent;  // 完整内联 HTML，用于 srcdoc
  final Future<Object> Function(String method, Map<String, dynamic> args)
      onBridgeMessage;
  final void Function(String kind, String message) onLog;

  @override
  State<EmAppWebFrame> createState() => EmAppWebFrameState();
}

class EmAppWebFrameState extends State<EmAppWebFrame> {
  html.IFrameElement? _iframe;
  StreamSubscription<html.MessageEvent>? _messageSub;
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'emapp-web-frame-${identityHashCode(this)}';

    final doc = widget.htmlContent;

    // 每个实例注册独立的 view factory，用 srcdoc 直接注入 HTML
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        _iframe = html.IFrameElement()
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.border = 'none'
          ..allow = 'autoplay; camera; microphone'
          ..srcdoc = doc;
        widget.onLog('WEBVIEW', 'Created iframe with srcdoc (${doc.length} bytes)');
        return _iframe!;
      },
    );

    // 监听 iframe 的 postMessage
    _messageSub = html.window.onMessage.listen(_handleMessage);
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  void _handleMessage(html.MessageEvent event) {
    if (_iframe == null || event.source != _iframe!.contentWindow) {
      return;
    }
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(event.data.toString());
      if (decoded is! Map) return;
      payload = decoded.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      return;
    }
    final id = payload['id']?.toString() ?? '';
    final method = payload['method']?.toString() ?? '';
    final args = payload['args'];
    if (method.isEmpty) return;

    final argsMap = args is Map
        ? args.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};

    widget.onLog('WEBVIEW', 'Bridge call $method');
    widget.onBridgeMessage(method, argsMap).then(
      (result) => _completeBridge(id, success: true, value: result),
      onError: (err) => _completeBridge(id, success: false, value: {
        'success': false,
        'message': err.toString(),
      }),
    );
  }

  void _completeBridge(
    String id, {
    required bool success,
    required Object value,
  }) {
    if (_iframe == null || id.isEmpty) return;
    final payload = jsonEncode({
      'id': id,
      'success': success,
      'value': value,
    });
    _iframe!.contentWindow?.postMessage(payload, '*');
  }

  void reload() {
    if (_iframe != null) {
      _iframe!.srcdoc = widget.htmlContent;
      widget.onLog('WEBVIEW', 'Reloaded iframe');
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}

