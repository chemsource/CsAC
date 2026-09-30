import '../miniapp/miniapp_plugin.dart';
import 'script_file.dart';

class JsacratchProject {
  String type; // 'script' | 'acr' | 'miniapp'
  String name;
  List<ScriptFile> scripts;
  String? miniAppData; // JSON string for miniapp files

  JsacratchProject({
    this.type = 'script',
    String name = 'Untitled',
    List<ScriptFile>? scripts,
    this.miniAppData,
  }) : name = name,
       scripts = _initScripts(type, scripts);

  static List<ScriptFile> _initScripts(String type, List<ScriptFile>? scripts) {
    if (type == 'miniapp') {
      return scripts ?? [];
    }
    if (scripts != null && scripts.isNotEmpty) {
      return List<ScriptFile>.from(scripts);
    }
    return [ScriptFile(name: 'main')];
  }

  int get scriptCount => scripts.length;

  void addScript(ScriptFile script) {
    script.order = scripts.length;
    scripts.add(script);
  }

  void removeScript(int index) {
    if (scripts.length <= 1) return;
    scripts.removeAt(index);
    for (var i = 0; i < scripts.length; i++) {
      scripts[i].order = i;
    }
  }

  void moveScript(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex--;
    final item = scripts.removeAt(oldIndex);
    scripts.insert(newIndex, item);
    for (var i = 0; i < scripts.length; i++) {
      scripts[i].order = i;
    }
  }

  /// 创建 MiniAppProject 从 miniAppData
  MiniAppProject? toMiniAppProject() {
    if (miniAppData == null || miniAppData!.isEmpty) return null;
    try {
      return MiniAppProject.fromJsonString(miniAppData!);
    } catch (_) {
      return null;
    }
  }

  /// 设置 MiniAppProject 并序列化到 miniAppData
  void setMiniAppProject(MiniAppProject mp) {
    miniAppData = mp.toJsonString();
    type = 'miniapp';
  }
}
