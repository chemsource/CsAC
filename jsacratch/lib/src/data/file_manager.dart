import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';
import 'dart:ui' show Color;
import 'package:file_selector/file_selector.dart';

import '../models/project.dart';
import '../models/script_file.dart';
import '../export/acr_exporter.dart';
import '../export/acrg_exporter.dart';

/// Persists and loads jsacratch project/script files:
///   .jap  - full project (JSON)
///   .ja   - single script (JSON)
///   .acr  - single ACR file (tagged JS)
///   .acrg - multi ACR package (tagged JS)
class FileManager {
  FileManager._();

  static const _extGroup = XTypeGroup(label: 'Jsacratch files', extensions: ['jap', 'ja', 'acr', 'acrg']);

  // ============ Save ============

  static Future<void> saveProject(JsacratchProject project) async {
    final path = await getSaveLocation(suggestedName: '${project.name}.jap', acceptedTypeGroups: const [
      XTypeGroup(label: 'Jsacratch Project', extensions: ['jap']),
    ]);
    if (path == null) return;
    await _writeFile(path.path, _projectToJson(project));
  }

  static Future<void> saveScript(ScriptFile script) async {
    final path = await getSaveLocation(suggestedName: '${script.name}.ja', acceptedTypeGroups: const [
      XTypeGroup(label: 'Jsacratch Script', extensions: ['ja']),
    ]);
    if (path == null) return;
    await _writeFile(path.path, _scriptToJson(script));
  }

  static Future<void> exportAcrToFile(ScriptFile script, String projectName) async {
    final code = exportAcr(script);
    final path = await getSaveLocation(suggestedName: '${script.name}.acr', acceptedTypeGroups: const [
      XTypeGroup(label: 'ACR Script', extensions: ['acr']),
    ]);
    if (path == null) return;
    await _writeFile(path.path, code);
  }

  static Future<void> exportAcrgToFile(JsacratchProject project) async {
    final code = exportAcrg(project);
    final path = await getSaveLocation(suggestedName: '${project.name}.acrg', acceptedTypeGroups: const [
      XTypeGroup(label: 'ACRG Package', extensions: ['acrg']),
    ]);
    if (path == null) return;
    await _writeFile(path.path, code);
  }

  // ============ Open ============

  /// Returns (project, fileName).
  static Future<({JsacratchProject project, String fileName})?> openProject() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Jsacratch Project', extensions: ['jap']),
    ]);
    if (file == null) return null;
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    return (project: _projectFromJson(json), fileName: file.name);
  }

  /// Returns (script, fileName).
  static Future<({ScriptFile script, String fileName})?> openScript() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Jsacratch Script', extensions: ['ja']),
    ]);
    if (file == null) return null;
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    return (script: _scriptFromJson(json), fileName: file.name);
  }

  /// Opens any supported file type. Field present indicates type.
  static Future<({JsacratchProject? project, ScriptFile? script, String? acrCode, String? acrgCode, String? fileType, String fileName})?> openAny() async {
    final file = await openFile(acceptedTypeGroups: [_extGroup]);
    if (file == null) return null;
    final content = await file.readAsString();

    if (file.name.endsWith('.jap')) {
      final json = jsonDecode(content) as Map<String, dynamic>;
      final project = _projectFromJson(json);
      return (project: project, script: null, acrCode: null, acrgCode: null, fileType: project.type, fileName: file.name);
    }
    if (file.name.endsWith('.ja')) {
      final json = jsonDecode(content) as Map<String, dynamic>;
      return (project: null, script: _scriptFromJson(json), acrCode: null, acrgCode: null, fileType: 'script', fileName: file.name);
    }
    if (file.name.endsWith('.acr')) {
      return (project: null, script: null, acrCode: content, acrgCode: null, fileType: 'acr', fileName: file.name);
    }
    if (file.name.endsWith('.acrg')) {
      return (project: null, script: null, acrCode: null, acrgCode: content, fileType: 'acr', fileName: file.name);
    }
    return null;
  }

  // ============ JSON Serialization ============

  static String _projectToJson(JsacratchProject project) {
    final map = <String, dynamic>{
      'version': 2,
      'type': project.type,
      'name': project.name,
      'scripts': project.scripts.map(_scriptToMap).toList(),
    };
    if (project.miniAppData != null) {
      map['miniAppData'] = project.miniAppData;
    }
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static JsacratchProject _projectFromJson(Map<String, dynamic> json) {
    final scripts = (json['scripts'] as List<dynamic>?)
        ?.map((s) => _scriptFromMap(s as Map<String, dynamic>))
        .toList() ?? [];
    final type = json['type'] as String? ?? 'script';
    final miniAppData = json['miniAppData'] as String?;
    return JsacratchProject(
      type: type,
      name: json['name'] as String? ?? 'Untitled',
      scripts: scripts,
      miniAppData: miniAppData,
    );
  }

  static Map<String, dynamic> _scriptToMap(ScriptFile script) => {
    'name': script.name,
    'language': script.language,
    'code': script.code,
    'blocks': script.blocks.map(_blockToMap).toList(),
  };

  static String _scriptToJson(ScriptFile script) {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'name': script.name,
      'language': script.language,
      'code': script.code,
      'blocks': script.blocks.map(_blockToMap).toList(),
    });
  }

  static ScriptFile _scriptFromJson(Map<String, dynamic> json) {
    final blocks = (json['blocks'] as List<dynamic>?)
        ?.map((b) => _blockFromMap(b as Map<String, dynamic>))
        .toList();
    return ScriptFile(
      name: json['name'] as String? ?? 'script',
      language: json['language'] as String? ?? 'javascript',
      code: json['code'] as String? ?? '',
      blocks: blocks,
    );
  }

  static ScriptFile _scriptFromMap(Map<String, dynamic> json) {
    final blocks = (json['blocks'] as List<dynamic>?)
        ?.map((b) => _blockFromMap(b as Map<String, dynamic>))
        .toList();
    return ScriptFile(
      name: json['name'] as String? ?? 'script',
      language: json['language'] as String? ?? 'javascript',
      code: json['code'] as String? ?? '',
      blocks: blocks,
    );
  }

  static Map<String, dynamic> _blockToMap(ScratchBlock block) => {
    'id': block.id,
    'templateId': block.templateId,
    'category': block.category,
    'color': block.color.toARGB32(),
    'label': block.label,
    'values': block.values,
    'children': block.children.map(_blockToMap).toList(),
  };

  static ScratchBlock _blockFromMap(Map<String, dynamic> json) {
    final children = (json['children'] as List<dynamic>?)
        ?.map((c) => _blockFromMap(c as Map<String, dynamic>))
        .toList();
    final colorVal = json['color'] as int? ?? 0xFF4C97FF;
    return ScratchBlock(
      id: json['id'] as String? ?? '',
      templateId: json['templateId'] as String? ?? '',
      category: json['category'] as String? ?? '',
      color: Color(colorVal),
      label: json['label'] as String? ?? '',
      values: (json['values'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {},
      children: children,
    );
  }

  static Future<void> _writeFile(String path, String content) async {
    await File(path).writeAsString(content);
  }

  static Future<void> saveZip(String fileName, Uint8List data) async {
    final path = await getSaveLocation(suggestedName: fileName, acceptedTypeGroups: const [
      XTypeGroup(label: 'ZIP Archive', extensions: ['zip']),
    ]);
    if (path == null) return;
    await File(path.path).writeAsBytes(data);
  }
}
