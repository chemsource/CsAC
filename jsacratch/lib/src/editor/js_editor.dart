import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/javascript.dart' as re_highlight_js;
import 'package:re_highlight/styles/github.dart' as re_highlight_github;

import '../models/project.dart';
import 'code_completion.dart';

class JsEditor extends StatefulWidget {
  const JsEditor({
    required this.project,
    required this.activeScriptIndex,
    required this.onScriptChanged,
    required this.onSelectScript,
    required this.onAddScript,
    required this.onRemoveScript,
    this.scriptType = 'script',
    this.ajlImportMethods,
    super.key,
  });

  final JsacratchProject project;
  final int activeScriptIndex;
  final VoidCallback onScriptChanged;
  final ValueChanged<int> onSelectScript;
  final VoidCallback onAddScript;
  final ValueChanged<int> onRemoveScript;

  /// 'script' = BotJS, 'acr' = ACR lib, 'miniapp' = mini app
  final String scriptType;

  /// AJL 导入方法：{ libName -> [methodName, ...] }
  final Map<String, List<String>>? ajlImportMethods;

  @override
  State<JsEditor> createState() => _JsEditorState();
}

class _JsEditorState extends State<JsEditor> {
  late CodeLineEditingController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.activeScriptIndex;
    final script = widget.project.scripts[_currentIndex];
    _controller = CodeLineEditingController.fromText(script.code);
  }

  @override
  void didUpdateWidget(JsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Detect project change (e.g. opening a new .jap file)
    if (oldWidget.project != widget.project) {
      _currentIndex = widget.activeScriptIndex;
      if (_currentIndex < widget.project.scripts.length) {
        final script = widget.project.scripts[_currentIndex];
        _controller = CodeLineEditingController.fromText(script.code);
      }
      return;
    }
    if (widget.activeScriptIndex != _currentIndex) {
      // Save current script code only if the index is still valid
      if (_currentIndex < widget.project.scripts.length) {
        widget.project.scripts[_currentIndex].code = _controller.text;
      }
      // Switch to new script
      _currentIndex = widget.activeScriptIndex;
      final script = widget.project.scripts[_currentIndex];
      _controller.text = script.code;
    }
  }

  @override
  void dispose() {
    // Save code on dispose
    if (_currentIndex < widget.project.scripts.length) {
      widget.project.scripts[_currentIndex].code = _controller.text;
    }
    _controller.dispose();
    super.dispose();
  }

  void _saveCurrentScript() {
    if (_currentIndex < widget.project.scripts.length) {
      widget.project.scripts[_currentIndex].code = _controller.text;
    }
    widget.onScriptChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final scripts = widget.project.scripts;

    return Column(
      children: [
        // Script tabs
        Container(
          height: 36,
          color: cs.surfaceContainer,
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: scripts.length,
                  itemBuilder: (context, i) {
                    final script = scripts[i];
                    final isActive = i == _currentIndex;
                    return GestureDetector(
                      onTap: () {
                        _saveCurrentScript();
                        widget.onSelectScript(i);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isActive ? cs.surface : cs.surfaceContainer,
                          border: Border(
                            bottom: BorderSide(
                              color: isActive ? cs.primary : cs.outlineVariant,
                              width: 2,
                            ),
                            right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              script.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                                color: isActive ? cs.primary : cs.onSurfaceVariant,
                              ),
                            ),
                            if (scripts.length > 1) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () {
                                  if (scripts.length > 1) {
                                    widget.onRemoveScript(i);
                                    if (_currentIndex >= scripts.length - 1) {
                                      _saveCurrentScript();
                                      // Switch will happen through parent rebuild
                                    }
                                  }
                                },
                                child: Icon(Icons.close, size: 14, color: cs.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                icon: Icon(Icons.add, size: 18, color: cs.onSurfaceVariant),
                tooltip: 'New script',
                onPressed: widget.onAddScript,
                splashRadius: 14,
              ),
            ],
          ),
        ),

        // Editor
        Expanded(
          child: _buildEditor(cs, isDark),
        ),
      ],
    );
  }

  Widget _buildEditor(ColorScheme cs, bool isDark) {
    final codeEditor = CodeEditor(
      controller: _controller,
      onChanged: (_) => _saveCurrentScript(),
      style: CodeEditorStyle(
        codeTheme: CodeHighlightTheme(
          languages: {
            'javascript': CodeHighlightThemeMode(mode: re_highlight_js.langJavascript),
          },
          theme: re_highlight_github.githubTheme,
        ),
        backgroundColor: isDark ? cs.surfaceContainerLow : const Color(0xFF1E1E1E),
        fontFamily: 'monospace',
        fontSize: 14,
        cursorColor: cs.primary,
        cursorLineColor: isDark
            ? cs.primary.withValues(alpha: 0.1)
            : const Color(0x1AFFFFFF),
        selectionColor: cs.primary.withValues(alpha: 0.3),
      ),
    );

    // 构建补全提示
    final promptsBuilder = _buildPromptsBuilder();

    if (promptsBuilder == null) return codeEditor;

    return CodeAutocomplete(
      viewBuilder: (context, notifier, onSelected) {
        return _CompletionListView(
          notifier: notifier,
          onSelected: onSelected,
          isDark: isDark,
          cs: cs,
        );
      },
      promptsBuilder: promptsBuilder,
      child: codeEditor,
    );
  }

  DefaultCodeAutocompletePromptsBuilder? _buildPromptsBuilder() {
    switch (widget.scriptType) {
      case 'script': // BotJS
        final ajlImports = _buildAjlPromptMap();
        return DefaultCodeAutocompletePromptsBuilder(
          language: re_highlight_js.langJavascript,
          directPrompts: BotJsCompletionSets.buildDirectPrompts(ajlImports),
          relatedPrompts: BotJsCompletionSets.buildRelatedPrompts(ajlImports),
        );
      case 'acr': // ACR: 完整JS
        return DefaultCodeAutocompletePromptsBuilder(
          language: re_highlight_js.langJavascript,
        );
      default:
        return null;
    }
  }

  Map<String, List<CodePrompt>>? _buildAjlPromptMap() {
    if (widget.ajlImportMethods == null || widget.ajlImportMethods!.isEmpty) {
      return null;
    }
    final map = <String, List<CodePrompt>>{};
    for (final entry in widget.ajlImportMethods!.entries) {
      map[entry.key] = entry.value
          .map((name) => CodeFieldPrompt(word: name, type: 'function (AJL)'))
          .toList();
    }
    return map;
  }
}

/// 代码补全下拉列表
class _CompletionListView extends StatefulWidget implements PreferredSizeWidget {
  static const double kItemHeight = 28;

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;
  final bool isDark;
  final ColorScheme cs;

  const _CompletionListView({
    required this.notifier,
    required this.onSelected,
    required this.isDark,
    required this.cs,
  });

  @override
  Size get preferredSize {
    final count = notifier.value.prompts.length;
    if (count == 0) return const Size(300, 0);
    final height = (count * kItemHeight).clamp(0, 200).toDouble();
    return Size(350, height);
  }

  @override
  State<_CompletionListView> createState() => _CompletionListViewState();
}

class _CompletionListViewState extends State<_CompletionListView> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onNotifierChanged);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onNotifierChanged);
    super.dispose();
  }

  void _onNotifierChanged() {
    if (mounted) {
      setState(() {
        _selectedIndex = widget.notifier.value.index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prompts = widget.notifier.value.prompts;
    if (prompts.isEmpty) return const SizedBox.shrink();

    final visibleCount = prompts.length.clamp(1, 8);
    final height = (visibleCount * _CompletionListView.kItemHeight).toDouble();

    return Container(
      width: 350,
      height: height,
      decoration: BoxDecoration(
        color: widget.isDark
            ? widget.cs.surfaceContainerHigh
            : const Color(0xFF252526),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: widget.isDark
              ? widget.cs.outlineVariant
              : const Color(0xFF3E3E42),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 2),
        itemCount: prompts.length,
        itemBuilder: (context, index) {
          final prompt = prompts[index];
          final isSelected = index == _selectedIndex;
          return _CompletionItem(
            prompt: prompt,
            isSelected: isSelected,
            cs: widget.cs,
            isDark: widget.isDark,
            onTap: () {
              widget.onSelected(widget.notifier.value
                  .copyWith(index: index)
                  .autocomplete);
            },
          );
        },
      ),
    );
  }
}

/// 单个补全项
class _CompletionItem extends StatelessWidget {
  final CodePrompt prompt;
  final bool isSelected;
  final ColorScheme cs;
  final bool isDark;
  final VoidCallback onTap;

  const _CompletionItem({
    required this.prompt,
    required this.isSelected,
    required this.cs,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isSelected
        ? cs.primary.withAlpha(isDark ? 40 : 30)
        : Colors.transparent;

    IconData? icon;
    Color? iconColor;
    String typeLabel = '';

    if (prompt is CodeFunctionPrompt) {
      icon = Icons.functions;
      iconColor = const Color(0xFFDCDCAA);
      typeLabel = (prompt as CodeFunctionPrompt).type;
    } else if (prompt is CodeFieldPrompt) {
      icon = Icons.data_object;
      iconColor = const Color(0xFF9CDCFE);
      typeLabel = (prompt as CodeFieldPrompt).type;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        height: _CompletionListView.kItemHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: bgColor,
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                prompt.word,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: isDark
                      ? const Color(0xFFD4D4D4)
                      : const Color(0xFFCCCCCC),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (typeLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                typeLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: isDark
                      ? cs.onSurfaceVariant
                      : const Color(0xFF808080),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
