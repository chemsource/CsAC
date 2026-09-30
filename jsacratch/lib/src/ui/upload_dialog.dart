import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../l10n.dart';

class UploadDialog extends StatefulWidget {
  const UploadDialog({
    required this.code,
    required this.fileName,
    required this.serverUrl,
    this.sessionCookie,
    this.isAcrUpload = false,
    this.isBotScript = false,
    this.botId = 0,
    this.scriptName = '',
    this.acrDesc = '',
    super.key,
  });

  final String code;
  final String fileName;
  final String serverUrl;
  final String? sessionCookie;
  final bool isAcrUpload;
  final bool isBotScript;
  final int botId;
  final String scriptName;
  final String acrDesc;

  @override
  State<UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<UploadDialog> {
  bool _uploading = false;
  String? _error;

  Future<void> _upload() async {
    setState(() { _uploading = true; _error = null; });
    final s = JsacratchStrings.of(context);

    try {
      final isAcrg = widget.fileName.endsWith('.acrg');
      String action;
      Map<String, dynamic> params;

      if (widget.isBotScript) {
        action = 'script/create';
        params = {
          'bot_id': widget.botId,
          'script_name': widget.scriptName,
          'script_content': widget.code,
        };
      } else if (widget.isAcrUpload) {
        action = isAcrg ? 'script/upload_acrg' : 'script/upload_acr';
        params = {
          'file_name': widget.fileName,
          'content': widget.code,
          'desc': widget.acrDesc,
        };
      } else {
        action = 'script/upload_acr';
        params = {
          'file_name': widget.fileName,
          'content': widget.code,
          'desc': widget.acrDesc,
        };
      }

      final uri = Uri.parse('${widget.serverUrl}/?route=$action');
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (widget.sessionCookie != null) {
        headers['Cookie'] = widget.sessionCookie!;
      }
      final resp = await http.post(uri, headers: headers, body: jsonEncode(params));
      if (resp.statusCode != 200) {
        if (mounted) setState(() { _error = '${s.text("upload_failed")}: HTTP ${resp.statusCode} ${resp.reasonPhrase}'; _uploading = false; });
        return;
      }
      Map<String, dynamic> body;
      try {
        body = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        if (mounted) {
          final preview = resp.body.length > 200 ? '${resp.body.substring(0, 200)}...' : resp.body;
          setState(() { _error = '${s.text("upload_failed")}: ${preview.isNotEmpty ? preview : "服务器返回空响应"}'; _uploading = false; });
        }
        return;
      }

      if (!mounted) return;
      if (body['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('upload_success'))));
        Navigator.pop(context);
      } else {
        setState(() { _error = '${s.text("upload_failed")}: ${body['message'] ?? body["error"] ?? ""}'; _uploading = false; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '${s.text("connection_error")}: $e'; _uploading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = JsacratchStrings.of(context);
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(s.text('upload_dialog_title')),
      content: SizedBox(
        width: 500,
        height: 300,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${s.text("script_name")}: ${widget.fileName}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 8),
          Expanded(child: Container(
            width: double.infinity, padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.brightness == Brightness.dark ? cs.surfaceContainerLow : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.outlineVariant),
            ),
            child: SingleChildScrollView(child: SelectableText(
              widget.code,
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: cs.onSurface, height: 1.4),
            )),
          )),
          if (_uploading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: cs.error, fontSize: 12)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _uploading ? null : () => Navigator.pop(context), child: Text(s.text('cancel'))),
        FilledButton(onPressed: _uploading ? null : _upload, child: Text(_uploading ? s.text('uploading') : s.text('upload'))),
      ],
    );
  }
}
