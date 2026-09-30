import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models/project.dart';
import '../models/script_file.dart';
import '../export/acr_exporter.dart';

class ScriptPreview extends StatelessWidget {
  const ScriptPreview({
    required this.project,
    required this.activeScript,
    required this.scriptType,
    super.key,
  });

  final JsacratchProject project;
  final ScriptFile? activeScript;
  final String scriptType; // 'acr' or 'script'

  String get _previewCode {
    if (scriptType == 'acr') {
      if (activeScript == null) return '';
      return exportAcr(activeScript!);
    }
    // BotJS: show generated JS from blocks or raw code
    if (activeScript == null) return '';
    if (activeScript!.blocks.isNotEmpty) return exportAcr(activeScript!);
    return activeScript!.code;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = JsacratchStrings.of(context);
    final code = _previewCode;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border(left: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.preview, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  scriptType == 'acr' ? s.text('generated_acr_preview') : s.text('generated_bot_preview'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface),
                ),
                const Spacer(),
                if (code.isNotEmpty)
                  Text(
                    s.format('lines_generated', {'n': '${code.split('\n').length - 1}'}),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          // Code view
          Expanded(
            child: code.isEmpty
                ? Center(child: Text(s.text('no_script_selected'), style: TextStyle(color: cs.onSurfaceVariant)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      code,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: cs.onSurface,
                        height: 1.5,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
