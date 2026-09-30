import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:webview_all/webview_all.dart' as webview_all;

import '../acop_client.dart';
import '../l10n.dart';
import '../models/project.dart';
import '../models/script_file.dart';
import '../editor/acratch_editor.dart';
import '../editor/botjs_validator.dart';
import '../editor/js_editor.dart';
import '../editor/code_completion.dart';
import '../export/acr_exporter.dart';
import '../export/acrg_exporter.dart';
import '../data/file_manager.dart';
import '../miniapp/miniapp_plugin.dart';
import '../miniapp/miniapp_preview.dart';
import 'file_toolbar.dart';
import 'script_preview.dart';
import 'upload_dialog.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.client, super.key});

  final AcopApiClient client;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late JsacratchProject _project;
  String _editMode = 'acratch'; // 'acratch' or 'js'
  String _scriptType = 'script'; // 'acr' or 'script'
  int _activeScriptIndex = 0;
  final _client = AcopApiClient();

  // BotJS cloud state
  bool _isLoggedIn = false;
  int _selectedBotId = 0;
  String _selectedBotName = '';
  List<Map<String, dynamic>> _botList = [];
  List<Map<String, dynamic>> _cloudScripts = [];
  List<Map<String, dynamic>> _libList = [];

  // MiniApp state
  MiniAppProject? _miniAppProject;
  final MiniAppPreview _preview = MiniAppPreview();
  bool _previewRunning = false;
  String? _previewUrl;
  webview_all.WebViewController? _previewController;

  @override
  void initState() {
    super.initState();
    _project = JsacratchProject(name: 'Untitled');
    _client.baseUrl = 'https://acop.csac.chat/acop';
  }

  void _notifyChanged() => setState(() {});

  void _toggleMode() {
    if (_scriptType == 'acr') return; // ACR mode: no acratch
    setState(() => _editMode = _editMode == 'acratch' ? 'js' : 'acratch');
  }

  void _toggleScriptType() {
    setState(() {
      // 三模式轮转: script → acr → miniapp → script
      switch (_scriptType) {
        case 'script':
          _scriptType = 'acr';
          _editMode = 'js';
          _project = JsacratchProject(type: 'acr', name: 'Untitled ACR');
          _miniAppProject = null;
          _activeScriptIndex = 0;
          break;
        case 'acr':
          _scriptType = 'miniapp';
          _miniAppProject = MiniAppProject();
          _project = JsacratchProject(type: 'miniapp', name: 'Untitled MiniApp');
          _activeScriptIndex = 0;
          break;
        case 'miniapp':
          _scriptType = 'script';
          _editMode = 'acratch';
          _miniAppProject = null;
          _project = JsacratchProject(type: 'script', name: 'Untitled');
          _activeScriptIndex = 0;
          break;
      }
    });
  }

  void _addScript() {
    if (_scriptType == 'miniapp') {
      _addMiniAppPage();
      return;
    }
    setState(() {
      _project.addScript(ScriptFile(name: 'script${_project.scriptCount + 1}'));
      _activeScriptIndex = _project.scriptCount - 1;
    });
  }

  void _addMiniAppPage() {
    // 简易添加页面对话框
    showDialog(
      context: context,
      builder: (ctx) {
        final nameCtrl = TextEditingController(text: 'page_${(_miniAppProject?.files.length ?? 0) + 1}.html');
        return AlertDialog(
          title: const Text('添加小程序页面'),
          content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(hintText: 'page.html'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  _miniAppProject ??= MiniAppProject();
                  _miniAppProject!.files.add(MiniAppFile(
                    name,
                    '<!DOCTYPE html>\n<html><body><h1>New Page</h1></body></html>',
                  ));
                });
              }
              Navigator.pop(ctx);
            }, child: const Text('确定')),
          ],
        );
      },
    );
  }

  void _removeScript(int index) {
    setState(() {
      _project.removeScript(index);
      if (_activeScriptIndex >= _project.scriptCount) {
        _activeScriptIndex = _project.scriptCount - 1;
      }
    });
  }

  void _selectScript(int index) => setState(() => _activeScriptIndex = index);

  // === Auth ===
  Future<bool> _showLoginDialog() {
    final completer = Completer<bool>();
    final urlCtrl = TextEditingController(text: _client.baseUrl);
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final s = JsacratchStrings.of(context);
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return AlertDialog(
            title: Text(s.text('login_title')),
            content: SizedBox(
              width: 350,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: urlCtrl,
                  decoration: InputDecoration(
                    labelText: s.text('acop_url'),
                    hintText: s.text('server_url_hint'),
                  ),
                  enabled: !loading,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                  enabled: !loading,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtrl,
                  decoration: InputDecoration(labelText: s.text('password')),
                  obscureText: true,
                  enabled: !loading,
                ),
                if (loading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ]),
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () {
                  Navigator.pop(ctx);
                  completer.complete(false);
                },
                child: Text(s.text('cancel')),
              ),
              FilledButton(
                onPressed: loading
                    ? null
                    : () async {
                        final url = urlCtrl.text.trim();
                        if (url.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.text('server_required'))),
                          );
                          return;
                        }
                        setDlg(() => loading = true);
                        _client.baseUrl = url;
                        try {
                          final result = await _client.login(
                            emailCtrl.text.trim(),
                            passCtrl.text.trim(),
                          );
                          if (!mounted) return;
                          if (result['success'] == true) {
                            setState(() => _isLoggedIn = true);
                            Navigator.pop(ctx);
                            completer.complete(true);
                            _loadBots();
                          } else {
                            setDlg(() => loading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${s.text('upload_failed')}: ${result['message'] ?? ''}')),
                            );
                          }
                        } catch (e) {
                          if (!mounted) return;
                          setDlg(() => loading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${s.text('connection_error')}: $e')),
                          );
                        }
                      },
                child: Text(loading ? s.text('uploading') : s.text('login')),
              ),
            ],
          );
        },
      ),
    );
    return completer.future;
  }

  void _logout() {
    _client.logout();
    setState(() { _isLoggedIn = false; _selectedBotId = 0; _selectedBotName = ''; _botList = []; _cloudScripts = []; });
  }

  // === Bot selection ===
  Future<void> _loadBots() async {
    final bots = await _client.getBotList();
    setState(() => _botList = bots);
  }

  void _showBotSelector() {
    final s = JsacratchStrings.of(context);
    if (_botList.isEmpty) {
      _loadBots();
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('select_bot')),
        content: SizedBox(
          width: 300,
          child: _botList.isEmpty
              ? Text(s.text('no_bots_found'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _botList.length,
                  itemBuilder: (_, i) {
                    final bot = _botList[i];
                    return ListTile(
                      leading: const Icon(Icons.smart_toy),
                      title: Text(bot['bot_name'] ?? 'Bot ${bot['bot_id']}'),
                      selected: bot['bot_id'] == _selectedBotId,
                      onTap: () {
                        setState(() {
                          _selectedBotId = bot['bot_id'] as int;
                          _selectedBotName = bot['bot_name'] as String? ?? '';
                        });
                        Navigator.pop(ctx);
                        _loadCloudScripts();
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('close'))),
        ],
      ),
    );
  }

  // === Cloud scripts CRUD ===
  Future<void> _loadCloudScripts() async {
    if (_selectedBotId <= 0) return;
    final scripts = await _client.getScriptList(_selectedBotId);
    setState(() => _cloudScripts = scripts);
  }

  void _showCloudScripts() {
    final s = JsacratchStrings.of(context);
    _loadCloudScripts();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(s.text('select_bot')),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_cloudScripts.isEmpty) Text(s.text('no_bots_found')),
              ..._cloudScripts.map((sc) => ListTile(
                title: Text(sc['script_name'] ?? ''),
                subtitle: Text('v${sc['version'] ?? 1} ${sc['enabled'] == 1 ? '[enabled]' : '[disabled]'}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.edit, size: 18), tooltip: s.text('edit_script'), onPressed: () async {
                    final detail = await _client.getScript(sc['script_id'] as int);
                    final data = detail['data'] as Map<String, dynamic>?;
                    if (detail['success'] == true && data != null) {
                      final content = data['script_content'] as String? ?? '';
                      final name = data['script_name'] as String? ?? '';
                      setState(() {
                        _project.addScript(ScriptFile(name: name, code: content));
                        _activeScriptIndex = _project.scriptCount - 1;
                      });
                      Navigator.pop(ctx);
                    }
                  }),
                  IconButton(icon: Icon(sc['enabled'] == 1 ? Icons.toggle_on : Icons.toggle_off, size: 18), tooltip: sc['enabled'] == 1 ? s.text('disable_script') : s.text('enable_script'), onPressed: () async {
                    await _client.toggleScript(sc['script_id'] as int, sc['enabled'] != 1);
                    _loadCloudScripts().then((_) { if (mounted) setDlg(() {}); });
                  }),
                  IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), tooltip: s.text('delete_script'), onPressed: () async {
                    await _client.deleteScript(sc['script_id'] as int);
                    _loadCloudScripts().then((_) { if (mounted) setDlg(() {}); });
                  }),
                  IconButton(icon: const Icon(Icons.drive_file_rename_outline, size: 18), tooltip: s.text('rename_script'), onPressed: () {
                    final oldName = sc['script_name'] as String? ?? '';
                    _showRenameDialog(sc['script_id'] as int, oldName, setDlg);
                  }),
                ]),
              )),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('close'))),
          ],
        ),
      ),
    );
  }

  void _showLibBrowser() {
    final s = JsacratchStrings.of(context);
    showDialog(
      context: context,
      builder: (ctx) => _AJLLibDialog(
        client: _client,
        isLoggedIn: _isLoggedIn,
      ),
    );
  }

  /// 扫描所有脚本的 import 语句，提取 AJL 库导入的方法名
  Map<String, List<String>> _getAjlImportMethods() {
    final result = <String, List<String>>{};
    for (final script in _project.scripts) {
      final code = script.code.isNotEmpty ? script.code : exportAcr(script);
      final imports = parseAjlImports(code);
      for (final entry in imports.entries) {
        result.putIfAbsent(entry.key, () => []);
        for (final prompt in entry.value) {
          if (!result[entry.key]!.contains(prompt.word)) {
            result[entry.key]!.add(prompt.word);
          }
        }
      }
    }
    return result;
  }

  Future<void> _saveToCloud() async {
    if (!_isLoggedIn || _selectedBotId <= 0) {
      _showLoginDialog();
      return;
    }
    final s = JsacratchStrings.of(context);
    final script = _project.scripts[_activeScriptIndex];
    final code = script.blocks.isNotEmpty ? exportAcr(script) : script.code;

    // 检查云端是否已有同名脚本
    final existing = _cloudScripts.where((sc) => sc['script_name'] == script.name).toList();
    if (existing.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.text('overwrite_confirm_title')),
          content: Text(s.format('duplicate_script_warning', {'name': script.name})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.text('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.text('overwrite'))),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final result = await _client.createScript(_selectedBotId, script.name, code);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['success'] == true ? s.text('script_saved') : '${s.text("upload_failed")}: ${result['message'] ?? ''}')),
      );
    }
  }

  // 重命名云端脚本：获取内容→用新名创建→删除旧脚本
  void _showRenameDialog(int scriptId, String oldName, void Function(void Function()) setDlg) {
    final s = JsacratchStrings.of(context);
    final nameCtrl = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.text('rename_script_title')),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(labelText: s.text('script_name')),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('cancel'))),
          FilledButton(onPressed: () async {
            final newName = nameCtrl.text.trim();
            if (newName.isEmpty || newName == oldName) {
              Navigator.pop(ctx);
              return;
            }
            Navigator.pop(ctx);
            // 获取旧脚本内容
            final detail = await _client.getScript(scriptId);
            final data = detail['data'] as Map<String, dynamic>?;
            if (detail['success'] != true || data == null) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('rename_failed'))));
              return;
            }
            final content = data['script_content'] as String? ?? '';
            // 用新名创建
            final createRes = await _client.createScript(_selectedBotId, newName, content);
            if (createRes['success'] != true) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.text("rename_failed")}: ${createRes['message'] ?? ''}')));
              return;
            }
            // 删除旧脚本
            await _client.deleteScript(scriptId);
            _loadCloudScripts().then((_) { if (mounted) setDlg(() {}); });
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.text('script_renamed'))));
          }, child: Text(s.text('ok'))),
        ],
      ),
    );
  }

  // === Export ===
  void _exportAcr() {
    final script = _project.scripts[_activeScriptIndex];
    _showExportResult(context, true, exportAcr(script));
  }

  void _exportAcrg() {
    _showExportResult(context, false, exportAcrg(_project));
  }

  // === File Save / Open ===

  void _onSaveProject() {
    if (_scriptType == 'miniapp' && _miniAppProject != null) {
      _project.setMiniAppProject(_miniAppProject!);
    }
    _project.name = _project.name; // ensure consistency
    FileManager.saveProject(_project);
  }

  void _onSaveScript() {
    final script = _project.scripts[_activeScriptIndex];
    FileManager.saveScript(script);
  }

  void _onOpen() async {
    final s = JsacratchStrings.of(context);
    final result = await FileManager.openAny();
    if (result == null) return;

    if (result.project != null) {
      final proj = result.project!;
      // 根据文件类型自动切换模式
       if (proj.type == 'miniapp') {
         MiniAppProject mp = proj.toMiniAppProject() ?? MiniAppProject(name: proj.name);
         // 同步名称：MiniAppProject.name 优先，回退到 proj.name
         if (mp.name == 'Untitled MiniApp' && proj.name != 'Untitled MiniApp') {
           mp.name = proj.name;
         }
         if (proj.name == 'Untitled MiniApp' && mp.name != 'Untitled MiniApp') {
           proj.name = mp.name;
         }
         setState(() {
           _scriptType = 'miniapp';
           _editMode = 'js';
           _project = proj;
           _miniAppProject = mp;
           _activeScriptIndex = 0;
         });
      } else if (proj.type == 'acr') {
        // 自动编译积木块到代码
        for (final sc in proj.scripts) {
          if (sc.blocks.isNotEmpty && sc.code.isEmpty) {
            sc.code = exportAcr(sc);
          }
        }
        setState(() {
          _scriptType = 'acr';
          _editMode = 'js';
          _project = proj;
          _miniAppProject = null;
          _activeScriptIndex = 0;
          _loadedAcrCodes.clear();
          BotJsValidator.clearImportedMethods();
          for (final sc in proj.scripts) {
            if (sc.code.isNotEmpty) BotJsValidator.registerImportedMethods(sc.code);
          }
        });
      } else {
        // script 模式
        for (final sc in proj.scripts) {
          if (sc.blocks.isNotEmpty && sc.code.isEmpty) {
            sc.code = exportAcr(sc);
          }
        }
        setState(() {
          _scriptType = 'script';
          _editMode = 'acratch';
          _project = proj;
          _miniAppProject = null;
          _activeScriptIndex = 0;
          _loadedAcrCodes.clear();
          BotJsValidator.clearImportedMethods();
          for (final sc in proj.scripts) {
            if (sc.code.isNotEmpty) BotJsValidator.registerImportedMethods(sc.code);
          }
        });
      }
      if (mounted) _showSnack(s.format('file_opened', {'name': result.fileName}));
    } else if (result.script != null) {
      setState(() {
        _project.addScript(result.script!);
        _activeScriptIndex = _project.scriptCount - 1;
      });
      if (mounted) _showSnack(s.format('file_opened', {'name': result.fileName}));
    } else if (result.acrCode != null) {
      // Import ACR code - register methods for validator
      final acrCode = result.acrCode!;
      BotJsValidator.registerImportedMethods(acrCode);
      _loadedAcrCodes[result.fileName] = acrCode;

      if (result.fileName.endsWith('.acrg')) {
        _importAcrg(result.acrgCode!);
      } else {
        final scriptName = result.fileName.replaceAll('.acr', '');
        setState(() {
          _project.addScript(ScriptFile(name: scriptName, code: acrCode));
          _activeScriptIndex = _project.scriptCount - 1;
        });
      }
      if (mounted) _showSnack(s.format('file_opened', {'name': result.fileName}));
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  final Map<String, String> _loadedAcrCodes = {};

  void _importAcrg(String acrgCode) {
    final scriptRe = RegExp(r"/// === SCRIPT_BEGIN: (.+?) ===\n/// @acr-script\n/// @name \1.+?\n(.*?)\n/// === SCRIPT_END:", dotAll: true);
    for (final m in scriptRe.allMatches(acrgCode)) {
      final name = m.group(1) ?? 'imported';
      final code = m.group(2) ?? '';
      _project.addScript(ScriptFile(name: name, code: code));
      BotJsValidator.registerImportedMethods(code);
    }
    if (mounted) {
      setState(() => _activeScriptIndex = _project.scriptCount - 1);
    }
  }

  void _showExportResult(BuildContext context, bool isAcr, String code) {
    final cs = Theme.of(context).colorScheme;
    final s = JsacratchStrings.of(context);
    final lines = code.split('\n').length - 1;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAcr ? s.text('export_dialog_title_acr') : s.text('export_dialog_title_acrg')),
        content: SizedBox(
          width: 550, height: 400,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(s.format('lines_generated', {'n': '$lines'}), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 8),
            Expanded(child: Container(
              width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.brightness == Brightness.dark ? cs.surfaceContainerLow : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.outlineVariant),
              ),
              child: SingleChildScrollView(child: SelectableText(code, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: cs.onSurface))),
            )),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('close'))),
          FilledButton.icon(
            icon: const Icon(Icons.save, size: 18),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(s.format('save_export_hint', {'name': '${_project.name}${isAcr ? ".acr" : ".acrg"}', 'size': '${code.length}'})),
              behavior: SnackBarBehavior.floating,
            )),
            label: Text(s.text('save_as_file')),
          ),
        ],
      ),
    );
  }

  // === Upload ===
  void _showUploadDialog() {
    final s = JsacratchStrings.of(context);

    if (_scriptType == 'acr') {
      // ACR mode: require login first
      if (!_isLoggedIn) {
        _showLoginDialog().then((loggedIn) {
          if (loggedIn && mounted) {
            _showUploadDialog(); // retry with login state
          }
        });
        return;
      }
      // ACR mode: upload acr or acrg
      final acrNameCtrl = TextEditingController(text: '${_project.scripts[_activeScriptIndex].name}.acr');
      final acrgNameCtrl = TextEditingController(text: '${_project.name}.acrg');
      final acrDescCtrl = TextEditingController();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.text('upload_dialog_title_acr')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: acrDescCtrl,
              decoration: const InputDecoration(
                labelText: '库描述',
                hintText: '描述此ACR/ACRG库的功能和用途',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: acrNameCtrl,
                  decoration: InputDecoration(
                    labelText: s.text('file_name'),
                    hintText: 'name.acr',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.description, size: 16),
                label: Text(s.text('upload_acr')),
                onPressed: () {
                  Navigator.pop(ctx);
                  final code = exportAcr(_project.scripts[_activeScriptIndex]);
                  final name = acrNameCtrl.text.trim();
                  _doUploadAcr(name.isEmpty ? '${_project.scripts[_activeScriptIndex].name}.acr' : name, code, acrDescCtrl.text.trim());
                },
              ),
            ]),
            if (_project.scriptCount > 1) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: acrgNameCtrl,
                    decoration: InputDecoration(
                      labelText: s.text('file_name'),
                      hintText: 'name.acrg',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.folder, size: 16),
                  label: Text(s.text('upload_acrg_package')),
                  onPressed: () {
                    Navigator.pop(ctx);
                    final code = exportAcrg(_project);
                    final name = acrgNameCtrl.text.trim();
                    _doUploadAcr(name.isEmpty ? '${_project.name}.acrg' : name, code, acrDescCtrl.text.trim());
                  },
                ),
              ]),
            ],
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('cancel')))],
        ),
      );
    } else if (_scriptType == 'miniapp') {
      _showMiniAppExportDialog();
    } else {
      // BotJS mode: save to cloud
      _saveToCloud();
    }
  }

  void _showMiniAppExportDialog() {
    final s = JsacratchStrings.of(context);
    final project = _miniAppProject;
    if (project == null) return;

    final appIdCtrl = TextEditingController(text: project.appId);
    final nameCtrl = TextEditingController(text: project.name == 'Untitled MiniApp' ? '' : project.name);
    final descCtrl = TextEditingController(text: project.desc);
    final fileCtrl = TextEditingController(text: project.appId.isNotEmpty ? '${project.appId}.ema' : 'miniapp.ema');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('上传小程序 (.ema)'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: appIdCtrl,
                decoration: const InputDecoration(labelText: 'App ID', hintText: 'com.example.myapp'),
                onChanged: (v) {
                  if (fileCtrl.text.isEmpty || fileCtrl.text == 'miniapp.ema') {
                    fileCtrl.text = '$v.ema';
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '应用名称', hintText: '显示在客户端小程序中心的名称'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: '应用描述', hintText: '小程序的功能和用途说明'),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: fileCtrl,
                decoration: const InputDecoration(labelText: '文件名', hintText: 'appId.ema'),
              ),
              const SizedBox(height: 8),
              Text('页面数: ${project.files.length}'),
              const SizedBox(height: 4),
              Text('上传后将由管理员审核，通过后自动签名发布。',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.text('cancel'))),
          FilledButton.icon(
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('上传到 ACOP'),
            onPressed: () async {
              final appId = appIdCtrl.text.trim();
              if (appId.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('请填写 App ID')),
                );
                return;
              }
              if (!_isLoggedIn) {
                Navigator.pop(ctx);
                _showLoginDialog();
                return;
              }
              Navigator.pop(ctx);
              project.appId = appId;
              final displayName = nameCtrl.text.trim();
              project.name = displayName.isEmpty ? appId : displayName;
              project.desc = descCtrl.text.trim();
              _project.name = project.name;
              final emaContent = project.exportEma();
              final fileName = fileCtrl.text.trim().isEmpty ? '$appId.ema' : fileCtrl.text.trim();
              _doUploadEma(fileName, emaContent, project.desc);
            },
          ),
        ],
      ),
    );
  }

  void _doUploadEma(String fileName, String content, String desc) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    _client.uploadEma(fileName, content, desc).then((result) {
      if (!mounted) return;
      Navigator.pop(context);
      if (result['success'] == true) {
        _showSnack('EMA 已提交审核，请等待管理员审核通过');
      } else {
        _showSnack('上传失败: ${result['message'] ?? ''}');
      }
    }).catchError((e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack('上传失败: $e');
    });
  }

  void _doUploadAcr(String name, String code, String desc) {
    showDialog(
      context: context,
      builder: (_) => UploadDialog(
        code: code,
        fileName: name,
        serverUrl: _client.baseUrl,
        sessionCookie: _client.sessionCookie,
        isAcrUpload: true,
        acrDesc: desc,
      ),
    );
  }

  // --- MiniApp Preview ---

  void _openPreview() {
    final project = _miniAppProject;
    if (project == null) return;

    if (_previewRunning) {
      _stopPreview();
      return;
    }

    setState(() {
      _previewRunning = true;
      _previewUrl = null;
    });

    _preview.start(project).then((result) {
      if (!mounted) return;
      if (result.success) {
        final ctrl = webview_all.WebViewController()
          ..setJavaScriptMode(webview_all.JavaScriptMode.unrestricted)
          ..setNavigationDelegate(webview_all.NavigationDelegate(
            onPageFinished: (_) {},
            onWebResourceError: (err) {
              _showSnack('预览资源错误: ${err.description}');
            },
          ))
          ..loadRequest(Uri.parse(result.baseUrl!));
        setState(() {
          _previewUrl = result.baseUrl;
          _previewController = ctrl;
        });
      } else {
        setState(() => _previewRunning = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('预览失败'),
            content: Text(result.error ?? '未知错误'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    });
  }

  void _stopPreview() {
    _previewController = null;
    _previewUrl = null;
    _preview.stop().then((_) {
      if (mounted) {
        setState(() => _previewRunning = false);
        _showSnack('预览已停止');
      }
    });
  }

  @override
  void dispose() {
    _preview.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          FileToolbar(
            projectName: _project.name,
            editMode: _editMode,
            scriptType: _scriptType,
            hasScripts: _project.scripts.isNotEmpty,
            isLoggedIn: _isLoggedIn,
            botName: _selectedBotName,
            onToggleMode: _toggleMode,
            onToggleScriptType: _toggleScriptType,
            onNewScript: _addScript,
            onExportAcr: _exportAcr,
            onExportAcrg: _exportAcrg,
            onUpload: _showUploadDialog,
            onRename: (name) => setState(() {
              _project.name = name;
              if (_miniAppProject != null) _miniAppProject!.name = name;
            }),
            onLogin: () => _showLoginDialog(),
            onLogout: _logout,
            onSelectBot: _showBotSelector,
            onManageScripts: _showCloudScripts,
            onSaveProject: _onSaveProject,
            onSaveScript: _onSaveScript,
            onOpen: _onOpen,
            onPreview: _openPreview,
            previewRunning: _previewRunning,
            onBrowseLibs: _showLibBrowser,
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _scriptType == 'miniapp' && _previewRunning && _previewController != null
                      ? webview_all.WebViewWidget(controller: _previewController!)
                      : _scriptType == 'miniapp'
                      ? _MiniAppEditor(
                          key: ValueKey(_miniAppProject.hashCode),
                          project: _miniAppProject!,
                          onChanged: _notifyChanged,
                          onAddPage: _addMiniAppPage,
                          onRemovePage: (index) {
                            setState(() => _miniAppProject?.files.removeAt(index));
                          },
                        )
                      : _scriptType == 'acr'
                      ? JsEditor(
                          key: ValueKey(_project.hashCode),
                          project: _project,
                          activeScriptIndex: _activeScriptIndex,
                          onScriptChanged: _notifyChanged,
                          onSelectScript: _selectScript,
                          onAddScript: _addScript,
                          onRemoveScript: _removeScript,
                          scriptType: 'acr',
                        )
                      : _editMode == 'acratch'
                          ? AcratchEditor(
                              key: ValueKey(_project.hashCode),
                              project: _project,
                              activeScriptIndex: _activeScriptIndex,
                              scriptType: _scriptType,
                              onScriptChanged: _notifyChanged,
                              onSelectScript: _selectScript,
                              onAddScript: _addScript,
                              onRemoveScript: _removeScript,
                            )
                          : JsEditor(
                              key: ValueKey(_project.hashCode),
                              project: _project,
                              activeScriptIndex: _activeScriptIndex,
                              onScriptChanged: _notifyChanged,
                              onSelectScript: _selectScript,
                              onAddScript: _addScript,
                              onRemoveScript: _removeScript,
                              scriptType: 'script',
                              ajlImportMethods: _getAjlImportMethods(),
                            ),
                ),
                if (_scriptType != 'miniapp')
              Expanded(
                flex: 2,
                child: ScriptPreview(
                  project: _project,
                  activeScript: _activeScriptIndex < _project.scriptCount ? _project.scripts[_activeScriptIndex] : null,
                  scriptType: _scriptType,
                ).animate().fadeIn(duration: 300.ms),
              ),
          ],
            ),
          ),
        ],
      ),
    );
  }
}

/// AJL 签名库浏览对话框
/// 公开库 + "我的库"（登录后）
class _AJLLibDialog extends StatefulWidget {
  const _AJLLibDialog({
    required this.client,
    required this.isLoggedIn,
  });

  final AcopApiClient client;
  final bool isLoggedIn;

  @override
  State<_AJLLibDialog> createState() => _AJLLibDialogState();
}

class _AJLLibDialogState extends State<_AJLLibDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  List<Map<String, dynamic>> _publicLibs = [];
  List<Map<String, dynamic>> _myLibs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: widget.isLoggedIn ? 2 : 1,
      vsync: this,
    );
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      widget.client.getLibList(),
      if (widget.isLoggedIn) widget.client.getMyLibs(),
    ]);
    if (!mounted) return;
    setState(() {
      _publicLibs = results[0];
      _myLibs = widget.isLoggedIn ? (results[1] as List<Map<String, dynamic>>) : [];
      _loading = false;
    });
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved': return '已通过';
      case 'rejected': return '已拒绝';
      default: return '待审核';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      default: return Colors.orange;
    }
  }

  Widget _buildLibList(List<Map<String, dynamic>> libs, {bool showStatus = false}) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (libs.isEmpty) return const Center(child: Text('暂无库记录'));
    return ListView.separated(
      itemCount: libs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final lib = libs[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.javascript, color: Color(0xFFF7DF1E)),
          title: Text(lib['name'] as String? ?? '?',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text([
            'v${lib['version'] ?? '?'}',
            if (lib['author'] is String && (lib['author'] as String).isNotEmpty)
              'by ${lib['author']}',
            if (lib['desc'] is String && (lib['desc'] as String).isNotEmpty)
              lib['desc'],
            if (showStatus && lib['status'] is String)
              _statusLabel(lib['status'] as String),
          ].join('  ·  ')),
          trailing: showStatus && lib['status'] is String
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _statusColor(lib['status'] as String).withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _statusColor(lib['status'] as String).withAlpha(80)),
                  ),
                  child: Text(
                    _statusLabel(lib['status'] as String),
                    style: TextStyle(fontSize: 11, color: _statusColor(lib['status'] as String)),
                  ),
                )
              : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = JsacratchStrings.of(context);
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.library_books, size: 20),
        SizedBox(width: 8),
        Text('AJL 签名库'),
      ]),
      content: SizedBox(
        width: 500,
        height: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isLoggedIn)
              TabBar(
                controller: _tabCtrl,
                tabs: const [
                  Tab(text: '公开库'),
                  Tab(text: '我的库'),
                ],
              ),
            Expanded(
              child: widget.isLoggedIn
                  ? TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _buildLibList(_publicLibs),
                        _buildLibList(_myLibs, showStatus: true),
                      ],
                    )
                  : _buildLibList(_publicLibs),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.text('close'))),
      ],
    );
  }
}
/// 小程序编辑器：左侧文件列表 + 右侧代码编辑 + 右侧预览
class _MiniAppEditor extends StatefulWidget {
  final MiniAppProject project;
  final VoidCallback onChanged;
  final VoidCallback onAddPage;
  final ValueChanged<int> onRemovePage;

  const _MiniAppEditor({
    required this.project,
    required this.onChanged,
    required this.onAddPage,
    required this.onRemovePage,
    super.key,
  });

  @override
  State<_MiniAppEditor> createState() => _MiniAppEditorState();
}

class _MiniAppEditorState extends State<_MiniAppEditor> {
  int _selectedFileIndex = 0;
  late TextEditingController _codeCtrl;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(_MiniAppEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project != widget.project) {
      _selectedFileIndex = 0;
      _syncController();
      return;
    }
    if (oldWidget.project.files != widget.project.files) {
      _syncController();
    }
  }

  void _syncController() {
    final files = widget.project.files;
    if (_selectedFileIndex >= files.length) {
      _selectedFileIndex = files.isEmpty ? 0 : files.length - 1;
    }
    // Dispose old controller before creating new one
    try { _codeCtrl.dispose(); } catch (_) {}
    if (files.isNotEmpty) {
      _codeCtrl = TextEditingController(text: files[_selectedFileIndex].content);
    } else {
      _codeCtrl = TextEditingController();
    }
  }

  void _reloadCurrentProject() {
    _syncController();
    if (mounted) setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已重新读取项目源码'), duration: Duration(seconds: 1)),
    );
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  /// 为 EMA 模式构建编辑器
  Widget _buildEmaEditor(ColorScheme cs) {
    final files = widget.project.files;
    if (_selectedFileIndex >= files.length) {
      return const SizedBox.shrink();
    }
    final fileType = emaFileType(files[_selectedFileIndex].filename);

    return Column(
      children: [
        // 文件类型标签
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: cs.surfaceContainerHighest,
          child: Row(
            children: [
              Icon(
                fileType == EmaFileType.html ? Icons.html : fileType == EmaFileType.css ? Icons.style : Icons.javascript,
                size: 14, color: cs.primary,
              ),
              const SizedBox(width: 6),
              Text(files[_selectedFileIndex].filename,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              const Spacer(),
              Text(fileType.name.toUpperCase(),
                  style: TextStyle(fontSize: 10, color: cs.primary, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: TextField(
            key: ValueKey('ema_edit_$_selectedFileIndex'),
            controller: _codeCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: cs.surfaceContainerLowest,
              contentPadding: const EdgeInsets.all(12),
            ),
            onChanged: (v) {
              if (_selectedFileIndex < files.length) {
                files[_selectedFileIndex].content = v;
              }
              widget.onChanged();
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final files = widget.project.files;

    return Row(
      children: [
        // 文件列表
        SizedBox(
          width: 180,
          child: Column(
            children: [
              ListTile(
                dense: true,
                title: const Text('页面列表', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: '重新读取源码',
                      onPressed: _reloadCurrentProject,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      tooltip: '添加页面',
                      onPressed: widget.onAddPage,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (_, i) {
                    final f = files[i];
                    return ListTile(
                      dense: true,
                      selected: i == _selectedFileIndex,
                      selectedColor: cs.primary,
                      leading: Icon(
                        f.filename.endsWith('.html')
                            ? Icons.html
                            : f.filename.endsWith('.css')
                                ? Icons.style
                                : Icons.javascript,
                        size: 16,
                      ),
                      title: Text(f.filename, style: const TextStyle(fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        onPressed: () => widget.onRemovePage(i),
                      ),
                      onTap: () {
                        // 保存当前编辑内容
                        if (_selectedFileIndex < files.length) {
                          files[_selectedFileIndex].content = _codeCtrl.text;
                        }
                        setState(() {
                          _selectedFileIndex = i;
                          _codeCtrl.text = files[i].content;
                        });
                        widget.onChanged();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // 代码编辑器
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                color: cs.surfaceContainerHighest,
                child: Row(
                  children: [
                    Text(
                      'app.json',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'appId: ${widget.project.appId.isNotEmpty ? widget.project.appId : "(未设置)"}',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _buildEmaEditor(cs),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
