import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../widgets/visual_script_builder.dart';

const _editorFontFamily = 'MapleMono';

class ScriptEditorPage extends StatefulWidget {
  final int scriptId;
  final String scriptName;
  const ScriptEditorPage({
    super.key,
    required this.scriptId,
    required this.scriptName,
  });

  @override
  State<ScriptEditorPage> createState() => _ScriptEditorPageState();
}

class _ScriptEditorPageState extends State<ScriptEditorPage> {
  final _codeCtrl = _ScriptCodeController();
  final _nameCtrl = TextEditingController();
  final _verticalScrollCtrl = ScrollController();
  final _horizontalScrollCtrl = ScrollController();
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  bool _visualMode = false; // 可视化编辑模式

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.scriptName;
    _loadScript();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _verticalScrollCtrl.dispose();
    _horizontalScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadScript() async {
    final state = context.read<AppState>();
    final result = await state.scriptService.get(widget.scriptId);
    if (!mounted) return;
    if (result['success'] == true && result['data'] != null) {
      final data = result['data'] as Map<String, dynamic>;
      _codeCtrl.text = data['script_content'] as String? ?? '';
      _nameCtrl.text = data['script_name'] as String? ?? widget.scriptName;
      _dirty = false;
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final state = context.read<AppState>();
    final result = await state.scriptService.update(
      scriptId: widget.scriptId,
      scriptName: _nameCtrl.text.trim().isNotEmpty
          ? _nameCtrl.text.trim()
          : null,
      scriptContent: _codeCtrl.text,
    );
    setState(() => _saving = false);
    if (mounted) {
      if (result['success'] == true) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存成功')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result['message'] ?? '保存失败')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _nameCtrl.text.isEmpty ? widget.scriptName : _nameCtrl.text,
        ),
        actions: [
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: const Text('未保存'),
                avatar: const CircleAvatar(
                  radius: 4,
                  backgroundColor: Colors.orange,
                ),
                backgroundColor: Colors.orange.shade50,
              ),
            ),
          if (_visualMode)
            IconButton(
              icon: const Icon(Icons.code),
              onPressed: () => setState(() => _visualMode = false),
              tooltip: '代码模式',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 脚本名称
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '脚本名称',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() => _dirty = true),
                  ),
                ),
                const SizedBox(height: 8),
                // 编辑区域
                Expanded(
                  child: _visualMode
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: VisualScriptBuilder(
                            onCodeGenerated: (code) {
                              // 将生成的代码追加到编辑器
                              final current = _codeCtrl.text.trimRight();
                              _codeCtrl.text = current.isEmpty
                                  ? code
                                  : '$current\n\n$code';
                              setState(() => _dirty = true);
                              // 切回代码模式查看
                              setState(() => _visualMode = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('代码已生成，可在代码模式中查看和编辑'),
                                ),
                              );
                            },
                          ),
                        )
                      : _buildCodeEditor(),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  Widget _buildCodeEditor() {
    final fileName = _editorFileName;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border.all(color: const Color(0xFF2D2D30)),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildTitleBar(fileName),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showExplorer = constraints.maxWidth >= 720;
                return Row(
                  children: [
                    _buildActivityBar(),
                    if (showExplorer) _buildExplorer(fileName),
                    Expanded(
                      child: Column(
                        children: [
                          _buildEditorTab(fileName),
                          _buildBreadcrumb(fileName),
                          if (!showExplorer) _buildCompactActionBar(),
                          Expanded(child: _buildEditorCanvas()),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildTitleBar(String fileName) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xFF3C3C3C),
      child: Row(
        children: [
          const Icon(Icons.code, size: 15, color: Color(0xFFD4D4D4)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$fileName - CsAC Script Editor',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD4D4D4),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _buildWindowDot(const Color(0xFFFF5F57)),
          const SizedBox(width: 7),
          _buildWindowDot(const Color(0xFFFFBD2E)),
          const SizedBox(width: 7),
          _buildWindowDot(const Color(0xFF28C840)),
        ],
      ),
    );
  }

  Widget _buildWindowDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildActivityBar() {
    return Container(
      width: 48,
      color: const Color(0xFF333333),
      child: Column(
        children: [
          const SizedBox(height: 10),
          const _ActivityIcon(icon: Icons.description, selected: true),
          _ActivityIcon(
            icon: Icons.save_outlined,
            tooltip: '保存',
            onTap: _saving ? null : _save,
          ),
          _ActivityIcon(
            icon: Icons.play_arrow_outlined,
            tooltip: '测试',
            onTap: _showTestDialog,
          ),
          _ActivityIcon(
            icon: Icons.widgets_outlined,
            tooltip: '可视化模式',
            onTap: () => setState(() => _visualMode = true),
          ),
          _ActivityIcon(
            icon: Icons.help_outline,
            tooltip: '语法帮助',
            onTap: _showHelp,
          ),
          const Spacer(),
          _ActivityIcon(
            icon: Icons.snippet_folder_outlined,
            tooltip: '插入示例',
            onTap: _insertExample,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildExplorer(String fileName) {
    return Container(
      width: 190,
      color: const Color(0xFF252526),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 12, 8),
            child: Text(
              'EXPLORER',
              style: TextStyle(
                color: Color(0xFFBBBBBB),
                fontSize: 11,
                letterSpacing: 0.7,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 18,
                  color: Color(0xFFCCCCCC),
                ),
                Expanded(
                  child: Text(
                    'CSAC BOT',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFFE5E5E5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 30,
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.only(left: 25, right: 8),
            color: const Color(0xFF37373D),
            child: Row(
              children: [
                const Icon(
                  Icons.javascript,
                  size: 16,
                  color: Color(0xFFF7DF1E),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fileName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          _buildExplorerActions(),
        ],
      ),
    );
  }

  Widget _buildExplorerActions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF252526),
        border: Border(top: BorderSide(color: Color(0xFF333333))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _dirty ? Icons.circle : Icons.check_circle_outline,
                color: _dirty
                    ? const Color(0xFFFFCC02)
                    : const Color(0xFF89D185),
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _dirty ? '未保存的更改' : '已保存',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD4D4D4),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildSidebarButton(
            icon: Icons.save_outlined,
            label: _saving ? '保存中...' : '保存脚本',
            onPressed: _saving ? null : _save,
            primary: true,
          ),
          const SizedBox(height: 8),
          _buildSidebarButton(
            icon: Icons.play_arrow_outlined,
            label: '测试脚本',
            onPressed: _showTestDialog,
          ),
          const SizedBox(height: 8),
          _buildSidebarButton(
            icon: Icons.widgets_outlined,
            label: '可视化模式',
            onPressed: () => setState(() => _visualMode = true),
          ),
          const SizedBox(height: 8),
          _buildSidebarButton(
            icon: Icons.snippet_folder_outlined,
            label: '插入示例',
            onPressed: _insertExample,
          ),
          const SizedBox(height: 8),
          _buildSidebarButton(
            icon: Icons.help_outline,
            label: '语法帮助',
            onPressed: _showHelp,
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    final foreground = primary ? Colors.white : const Color(0xFFD4D4D4);
    return SizedBox(
      height: 34,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: primary
              ? const Color(0xFF0E639C)
              : const Color(0xFF2D2D30),
          disabledForegroundColor: const Color(0xFF777777),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildEditorTab(String fileName) {
    return Container(
      height: 35,
      color: const Color(0xFF2D2D2D),
      alignment: Alignment.centerLeft,
      child: Container(
        width: 220,
        height: 35,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          border: Border(right: BorderSide(color: Color(0xFF252526))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.javascript, size: 16, color: Color(0xFFF7DF1E)),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                fileName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFDCDCAA), fontSize: 13),
              ),
            ),
            if (_dirty)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              )
            else
              const Icon(Icons.close, size: 15, color: Color(0xFF969696)),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumb(String fileName) {
    return Container(
      height: 26,
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Text(
            'scripts',
            style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 12),
          ),
          const Icon(Icons.chevron_right, size: 16, color: Color(0xFF8A8A8A)),
          Text(
            fileName,
            style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactActionBar() {
    return Container(
      height: 44,
      color: const Color(0xFF252526),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildCompactAction(
            icon: Icons.save_outlined,
            label: _saving ? '保存中' : '保存',
            onTap: _saving ? null : _save,
            primary: true,
          ),
          _buildCompactAction(
            icon: Icons.play_arrow_outlined,
            label: '测试',
            onTap: _showTestDialog,
          ),
          _buildCompactAction(
            icon: Icons.widgets_outlined,
            label: '可视化',
            onTap: () => setState(() => _visualMode = true),
          ),
          _buildCompactAction(
            icon: Icons.snippet_folder_outlined,
            label: '示例',
            onTap: _insertExample,
          ),
          _buildCompactAction(
            icon: Icons.help_outline,
            label: '帮助',
            onTap: _showHelp,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: primary
              ? const Color(0xFF0E639C)
              : const Color(0xFF3C3C3C),
          disabledForegroundColor: const Color(0xFF9A9A9A),
          minimumSize: const Size(78, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildEditorCanvas() {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = _codeContentWidth(constraints.maxWidth - 64);
          return ScrollbarTheme(
            data: ScrollbarThemeData(
              thumbColor: WidgetStateProperty.all(const Color(0xFF5A5A5A)),
              trackColor: WidgetStateProperty.all(const Color(0xFF1E1E1E)),
              thickness: WidgetStateProperty.all(10),
            ),
            child: Scrollbar(
              controller: _verticalScrollCtrl,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _verticalScrollCtrl,
                padding: const EdgeInsets.only(right: 12),
                child: Scrollbar(
                  controller: _horizontalScrollCtrl,
                  thumbVisibility: true,
                  notificationPredicate: (notification) =>
                      notification.depth == 1,
                  child: SingleChildScrollView(
                    controller: _horizontalScrollCtrl,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLineNumbers(),
                        SizedBox(
                          width: width,
                          child: TextField(
                            controller: _codeCtrl,
                            minLines: math.max(22, _lineCount() + 1),
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            autocorrect: false,
                            enableSuggestions: false,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: _editorFontFamily,
                              fontSize: 14.5,
                              height: 1.55,
                            ),
                            cursorColor: Colors.white,
                            decoration: const InputDecoration(
                              hintText:
                                  '// 在此编写 JavaScript Bot 脚本...\nbot.on(\'group.message\', async (ctx) => {\n  logger.info(\'hello\')\n})',
                              hintStyle: TextStyle(color: Color(0xFF6A9955)),
                              filled: true,
                              fillColor: Color(0xFF0D1117),
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.fromLTRB(
                                14,
                                12,
                                20,
                                18,
                              ),
                            ),
                            onChanged: (_) => setState(() => _dirty = true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBar() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _codeCtrl,
      builder: (context, value, _) {
        return Container(
          height: 24,
          color: const Color(0xFF007ACC),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              const Icon(Icons.check, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Text(
                _dirty ? 'Unsaved changes' : 'Saved',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const Spacer(),
              Text(
                'Ln ${_currentLine(value)}, Col ${_currentColumn(value)}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 18),
              const Text(
                'JavaScript',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 18),
              const Text(
                'UTF-8',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLineNumbers() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _codeCtrl,
      builder: (context, value, _) {
        final count = math.max(22, _lineCount(value.text) + 1);
        return Container(
          width: 64,
          padding: const EdgeInsets.fromLTRB(8, 12, 10, 18),
          color: const Color(0xFF1E1E1E),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int i = 1; i <= count; i++)
                SizedBox(
                  height: 22.475,
                  child: Text(
                    '$i',
                    style: const TextStyle(
                      color: Color(0xFF858585),
                      fontFamily: _editorFontFamily,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String get _editorFileName {
    final rawName = _nameCtrl.text.trim().isEmpty
        ? widget.scriptName
        : _nameCtrl.text.trim();
    final safeName = rawName.isEmpty
        ? 'script'
        : rawName.replaceAll(RegExp(r'\s+'), '_');
    return safeName.endsWith('.csac') ? safeName : '$safeName.csac';
  }

  int _currentLine(TextEditingValue value) {
    final offset = value.selection.isValid
        ? math.min(value.selection.extentOffset, value.text.length)
        : value.text.length;
    return '\n'.allMatches(value.text.substring(0, offset)).length + 1;
  }

  int _currentColumn(TextEditingValue value) {
    final offset = value.selection.isValid
        ? math.min(value.selection.extentOffset, value.text.length)
        : value.text.length;
    final prefix = value.text.substring(0, offset);
    final lastBreak = prefix.lastIndexOf('\n');
    return offset - lastBreak;
  }

  double _codeContentWidth(double availableWidth) {
    final lines = _codeCtrl.text.split('\n');
    final longestLine = lines.fold<int>(
      0,
      (max, line) => math.max(max, line.length),
    );
    return math.max(math.max(availableWidth, 720), longestLine * 8.4 + 48);
  }

  int _lineCount([String? text]) {
    final source = text ?? _codeCtrl.text;
    if (source.isEmpty) return 1;
    return '\n'.allMatches(source).length + 1;
  }

  void _insertExample() {
    const sample = '''bot.on('group.message', async (ctx) => {
  const text = ctx.text.trim()
  if (text.includes('hello')) {
    await ctx.reply('收到 hello')
  }
  logger.info('group message', { text, uid: ctx.sender.uid })
})''';
    final selection = _codeCtrl.selection;
    final oldText = _codeCtrl.text;
    final start = selection.isValid ? selection.start : oldText.length;
    final end = selection.isValid ? selection.end : oldText.length;
    final needsBreak = start > 0 && !oldText.substring(0, start).endsWith('\n');
    final insertText = needsBreak ? '\n\n$sample' : sample;
    final newText = oldText.replaceRange(start, end, insertText);
    final offset = start + insertText.length;
    _codeCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset),
    );
    setState(() => _dirty = true);
  }

  void _showTestDialog() {
    final eventTypeCtrl = TextEditingController(text: 'group_message');
    final roomIdCtrl = TextEditingController(text: '1');
    final uidCtrl = TextEditingController(text: '1001');
    final contentCtrl = TextEditingController(text: 'hello');
    final resultCtrl = TextEditingController();
    bool testing = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('测试脚本'),
              content: SizedBox(
                width: math.min(480, MediaQuery.sizeOf(ctx).width - 48),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: 'group_message',
                        decoration: const InputDecoration(
                          labelText: '事件类型',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'group_message',
                            child: Text('群消息'),
                          ),
                          DropdownMenuItem(
                            value: 'private_message',
                            child: Text('私聊消息'),
                          ),
                          DropdownMenuItem(
                            value: 'group_member_join',
                            child: Text('入群'),
                          ),
                          DropdownMenuItem(
                            value: 'group_member_leave',
                            child: Text('退群'),
                          ),
                          DropdownMenuItem(
                            value: 'group_member_mute',
                            child: Text('禁言'),
                          ),
                          DropdownMenuItem(
                            value: 'group_disband',
                            child: Text('群解散'),
                          ),
                        ],
                        onChanged: (v) =>
                            eventTypeCtrl.text = v ?? 'group_message',
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 360;
                          final roomField = TextField(
                            controller: roomIdCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Room ID',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          );
                          final uidField = TextField(
                            controller: uidCtrl,
                            decoration: const InputDecoration(
                              labelText: 'UID',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          );
                          if (narrow) {
                            return Column(
                              children: [
                                roomField,
                                const SizedBox(height: 8),
                                uidField,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: roomField),
                              const SizedBox(width: 8),
                              Expanded(child: uidField),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: contentCtrl,
                        decoration: const InputDecoration(
                          labelText: '消息内容',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '执行结果:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextField(
                          controller: resultCtrl,
                          maxLines: null,
                          readOnly: true,
                          style: TextStyle(
                            fontFamily: _editorFontFamily,
                            fontSize: 12,
                            color: resultCtrl.text.startsWith('ERROR')
                                ? Colors.red
                                : Colors.black87,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
                FilledButton(
                  onPressed: testing
                      ? null
                      : () async {
                          setDialogState(() => testing = true);
                          resultCtrl.text = '执行中...';
                          final state = context.read<AppState>();
                          final result = await state.scriptService.test(
                            scriptId: widget.scriptId,
                            eventType: eventTypeCtrl.text,
                            scriptContent: _codeCtrl.text,
                            eventData: {
                              'room_id': int.tryParse(roomIdCtrl.text) ?? 0,
                              'uid': int.tryParse(uidCtrl.text) ?? 0,
                              'content': contentCtrl.text,
                              'msg_id': 1,
                              'nickname': 'TestUser',
                              'msg_type': 1,
                              'reply_to': 0,
                              'image_urls': '',
                              'timestamp':
                                  DateTime.now().millisecondsSinceEpoch ~/ 1000,
                            },
                          );
                          setDialogState(() {
                            testing = false;
                            if (result['success'] == true) {
                              final logs = result['logs'] as List? ?? [];
                              final output = logs
                                  .map((l) => l.toString())
                                  .join('\n');
                              resultCtrl.text = output.isEmpty
                                  ? '执行成功，无输出'
                                  : output;
                            } else {
                              final errors = result['errors'] as List? ?? [];
                              final detail = errors
                                  .map((e) => e.toString())
                                  .join('\n');
                              resultCtrl.text = detail.isEmpty
                                  ? 'ERROR: ${result['message'] ?? '测试失败'}'
                                  : 'ERROR: ${result['message'] ?? '测试失败'}\n$detail';
                            }
                          });
                        },
                  child: testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('执行测试'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('JavaScript 脚本参考'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '事件注册',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text("bot.on('group.message', async (ctx) => {})"),
              Text("bot.on('private.message', async (ctx) => {})"),
              Text("bot.on('group.member.join', async (ctx) => {})"),
              Text("bot.on('group.member.leave', async (ctx) => {})"),
              Text("bot.on('group.member.mute', async (ctx) => {})"),
              Text("bot.on('group.disband', async (ctx) => {})"),
              Text("bot.command('/help', async (ctx) => {})"),
              SizedBox(height: 10),
              Text(
                '事件上下文',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text('ctx.text         - 消息文本'),
              Text('ctx.sender.uid   - 发送者UID'),
              Text('ctx.message.id   - 消息ID'),
              Text('ctx.group.id     - 群ID'),
              Text('ctx.bot.id       - Bot ID'),
              Text('ctx.reply(text)  - 回复当前消息'),
              Text('ctx.send(text)   - 发送消息不引用原消息'),
              SizedBox(height: 10),
              Text(
                '群聊方法',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text('csac.group.sendMessage(groupId, text)'),
              Text('csac.group.replyMessage(groupId, msgId, text)'),
              Text('csac.group.recallMessage(groupId, msgId)'),
              Text('csac.group.setEssence(groupId, msgId)'),
              Text('csac.group.muteMember(groupId, uid, sec)'),
              Text('csac.group.sendImage(groupId, url)'),
              Text('csac.group.leave(groupId)'),
              SizedBox(height: 10),
              Text(
                '私聊方法',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text('csac.private.sendMessage(uid, text)'),
              Text('csac.private.replyMessage(uid, msgId, text)'),
              Text('csac.private.recallMessage(uid, msgId)'),
              Text('csac.private.sendImage(uid, url)'),
              SizedBox(height: 10),
              Text(
                '通知方法',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text('csac.notice.send(uid, title, content)'),
              SizedBox(height: 10),
              Text(
                '信息查询',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text('csac.user.get(uid)'),
              Text('csac.groupInfo.get(groupId)'),
              Text('csac.groupInfo.memberCount(groupId)'),
              Text('csac.groupInfo.hasMember(groupId, uid)'),
              Text('csac.groupInfo.botPermissions(groupId)'),
              SizedBox(height: 10),
              Text(
                '外部服务',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text('csac.http.get(url, options?)'),
              Text('csac.http.post(url, { json, body, headers })'),
              SizedBox(height: 10),
              Text(
                '定时任务',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text('bot.schedule("*/5 * * * *", async (ctx) => {})'),
              Text('bot.schedule("daily", "0 9 * * *", async () => {})'),
              SizedBox(height: 10),
              Text(
                '存储与日志',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text('logger.info(...)  logger.warn(...)'),
              Text('logger.error(...) console.log(...)'),
              Text('csac.storage.get(key, defaultValue)'),
              Text('csac.storage.set(key, value)'),
              Text('csac.storage.increment(key, step)'),
              SizedBox(height: 10),
              Text(
                '语法特性',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text('const / let / function / async / await'),
              Text('对象、数组、JSON、正则、模板字符串'),
              Text('禁用 require/process/fetch/eval/new Function'),
              SizedBox(height: 10),
              Text(
                '异常类型',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text('ARG_ERROR / NOT_FRIEND / NOT_IN_GROUP'),
              Text('PERMISSION_DENIED / HTTP_PERMISSION_REQUIRED'),
              Text('NOTICE_PERMISSION_REQUIRED / TIMEOUT'),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _ActivityIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  final String? tooltip;

  const _ActivityIcon({
    required this.icon,
    this.selected = false,
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 46,
        decoration: BoxDecoration(
          border: selected
              ? const Border(left: BorderSide(color: Colors.white, width: 2))
              : null,
        ),
        child: Icon(
          icon,
          color: selected ? Colors.white : const Color(0xFFBDBDBD),
          size: 23,
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _ScriptCodeController extends TextEditingController {
  static const _baseColor = Colors.white;
  static const _keywordColor = Color(0xFFC586C0);
  static const _functionColor = Color(0xFFDCDCAA);
  static const _eventColor = Color(0xFF4EC9B0);
  static const _stringColor = Color(0xFFCE9178);
  static const _numberColor = Color(0xFFB5CEA8);
  static const _commentColor = Color(0xFF6A9955);
  static const _boolColor = Color(0xFF569CD6);

  static final _tokenPattern = RegExp(
    r'''//[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\b\d+\b|\b(?:if|else|return|for|while|break|continue|const|let|var|async|await|function|try|catch|throw|new)\b|\b(?:true|false|null|undefined)\b|\b(?:bot|csac|ctx|logger|console)\b|\b[A-Za-z_]\w*(?=\s*\()''',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = (style ?? const TextStyle()).copyWith(color: _baseColor);
    final spans = <TextSpan>[];
    int index = 0;

    for (final match in _tokenPattern.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      final token = match.group(0)!;
      spans.add(TextSpan(text: token, style: _styleForToken(token, baseStyle)));
      index = match.end;
    }

    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  TextStyle _styleForToken(String token, TextStyle baseStyle) {
    if (token.startsWith('//')) {
      return baseStyle.copyWith(
        color: _commentColor,
        fontStyle: FontStyle.italic,
      );
    }
    if (token.startsWith('"') || token.startsWith("'")) {
      return baseStyle.copyWith(color: _stringColor);
    }
    if (RegExp(r'^\d+$').hasMatch(token)) {
      return baseStyle.copyWith(color: _numberColor);
    }
    if (_events.contains(token)) {
      return baseStyle.copyWith(
        color: _eventColor,
        fontWeight: FontWeight.w600,
      );
    }
    if (_keywords.contains(token)) {
      return baseStyle.copyWith(color: _keywordColor);
    }
    if (_bools.contains(token)) {
      return baseStyle.copyWith(color: _boolColor);
    }
    return baseStyle.copyWith(color: _functionColor);
  }

  static const _events = {'bot', 'csac', 'ctx', 'logger', 'console'};

  static const _keywords = {
    'if',
    'else',
    'return',
    'for',
    'while',
    'break',
    'continue',
    'const',
    'let',
    'var',
    'async',
    'await',
    'function',
    'try',
    'catch',
    'throw',
    'new',
  };

  static const _bools = {'true', 'false', 'null', 'undefined'};
}
