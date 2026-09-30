import 'dart:ui';

class ScratchBlock {
  ScratchBlock({
    required this.id,
    required this.templateId,
    required this.category,
    required this.color,
    required this.label,
    this.values = const <String, String>{},
    List<ScratchBlock>? children,
  }) : children = children ?? <ScratchBlock>[];

  final String id;
  final String templateId;
  final String category;
  final Color color;
  final String label;
  final Map<String, String> values;
  List<ScratchBlock> children;
  bool collapsed = false;
}

class ScriptFile {
  ScriptFile({
    required this.name,
    this.language = 'javascript',
    this.code = '',
    List<ScratchBlock>? blocks,
    this.order = 0,
  }) : blocks = blocks ?? <ScratchBlock>[];

  String name;
  String language;
  String code;
  List<ScratchBlock> blocks;
  int order;

  ScriptFile copy() {
    return ScriptFile(
      name: name,
      language: language,
      code: code,
      blocks: blocks.map((b) => _copyBlock(b)).toList(),
      order: order,
    );
  }

  static ScratchBlock _copyBlock(ScratchBlock b) {
    return ScratchBlock(
      id: b.id,
      templateId: b.templateId,
      category: b.category,
      color: b.color,
      label: b.label,
      values: Map<String, String>.from(b.values),
      children: b.children.map(_copyBlock).toList(),
    )..collapsed = b.collapsed;
  }
}
