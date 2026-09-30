import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models/project.dart';
import '../models/script_file.dart';
import 'block_templates.dart';
import 'js_to_blocks.dart';

class AcratchEditor extends StatefulWidget {
  const AcratchEditor({
    required this.project,
    required this.activeScriptIndex,
    required this.scriptType,
    required this.onScriptChanged,
    required this.onSelectScript,
    required this.onAddScript,
    required this.onRemoveScript,
    super.key,
  });

  final JsacratchProject project;
  final int activeScriptIndex;
  final String scriptType;
  final VoidCallback onScriptChanged;
  final ValueChanged<int> onSelectScript;
  final VoidCallback onAddScript;
  final ValueChanged<int> onRemoveScript;

  @override
  State<AcratchEditor> createState() => _AcratchEditorState();
}

class _AcratchEditorState extends State<AcratchEditor> {
  late int _currentIndex;

  ScriptFile get _activeScript => widget.project.scripts[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.activeScriptIndex;
  }

  @override
  void didUpdateWidget(AcratchEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Detect project change (e.g. opening a new .jap file)
    if (oldWidget.project != widget.project) {
      _currentIndex = widget.activeScriptIndex;
      return;
    }
    if (widget.activeScriptIndex != _currentIndex) {
      _currentIndex = widget.activeScriptIndex;
    }
  }

  void _addBlock(BlockTemplate template, JsacratchStrings s) {
    setState(() {
      _activeScript.blocks.add(ScratchBlock(
        id: 'block_${DateTime.now().millisecondsSinceEpoch}_${_activeScript.blocks.length}',
        templateId: template.id,
        category: template.category.name,
        color: template.color,
        label: template.localizedTitle(s.text),
        values: {for (final f in template.fields) f.key: f.defaultValue},
      ));
    });
    widget.onScriptChanged();
  }

  void _removeBlock(List<ScratchBlock> list, int index) {
    setState(() => list.removeAt(index));
    widget.onScriptChanged();
  }

  void _editBlock(ScratchBlock block) {
    // Inline editing: values updated directly on block via _InlineField.
    // Just trigger rebuild.
    widget.onScriptChanged();
    setState(() {});
  }

  void _jsToBlocks() {
    final s = JsacratchStrings.of(context);
    final code = _activeScript.code;
    if (code.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.text('js_to_blocks_empty')), duration: const Duration(seconds: 2)),
      );
      return;
    }
    final blocks = JsToBlocksConverter.convert(code, s.text);
    if (blocks == null || blocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.text('js_to_blocks_failed')), duration: const Duration(seconds: 2)),
      );
      return;
    }
    setState(() {
      _activeScript.blocks = blocks;
      widget.onScriptChanged();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.format('blocks_count', {'n': '${blocks.length}'})),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = JsacratchStrings.of(context);
    final scripts = widget.project.scripts;
    final blocks = _activeScript.blocks;

    return Row(
      children: [
        Container(
          width: 200,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(right: BorderSide(color: cs.outlineVariant)),
          ),
          child: Column(
            children: [
              _buildScriptTabs(scripts, cs, s),
              Expanded(child: _buildBlockPalette(cs, s)),
            ],
          ),
        ),
        Expanded(
          child: DragTarget<BlockTemplate>(
            onAcceptWithDetails: (d) => _addBlock(d.data, s),
            builder: (ctx, candidate, rejected) => _activeScript.name.isNotEmpty
                ? _buildWorkspace(blocks, cs, s, candidate.isNotEmpty)
                : _buildEmptyWorkspace(cs, s, candidate.isNotEmpty),
          ),
        ),
      ],
    );
  }

  Widget _buildScriptTabs(List<ScriptFile> scripts, ColorScheme cs, JsacratchStrings s) {
    return Container(
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
                  onTap: () => widget.onSelectScript(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isActive ? cs.surface : cs.surfaceContainer,
                      border: Border(
                        bottom: BorderSide(color: isActive ? cs.primary : cs.outlineVariant, width: 2),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          script.name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                            color: isActive ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                        if (scripts.length > 1) ...[
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => widget.onRemoveScript(i),
                            child: Icon(Icons.close, size: 12, color: cs.onSurfaceVariant),
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
            icon: Icon(Icons.add, size: 16, color: cs.onSurfaceVariant),
            tooltip: s.text('new_script'),
            onPressed: widget.onAddScript,
            splashRadius: 12,
          ),
        ],
      ),
    );
  }

  Widget _buildBlockPalette(ColorScheme cs, JsacratchStrings s) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: BlockCategory.values.map((cat) {
        final catBlocks = blocksByCategory(cat);
        if (catBlocks.isEmpty) return const SizedBox.shrink();
        return ExpansionTile(
          leading: Icon(catBlocks.first.icon, size: 18, color: catBlocks.first.color),
          title: Text(
            _categoryName(cat, s),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface),
          ),
          initiallyExpanded: cat == BlockCategory.event,
          childrenPadding: const EdgeInsets.only(left: 12),
          children: catBlocks.map((t) {
            final title = t.localizedTitle(s.text);
            return LongPressDraggable<BlockTemplate>(
              data: t,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: t.color.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(t.icon, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(title, style: const TextStyle(fontSize: 11, color: Colors.white)),
                    ],
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: InkWell(
                  onTap: () => _addBlock(t, s),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 24, height: 20,
                          decoration: BoxDecoration(
                            color: t.color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          alignment: Alignment.center,
                          child: Icon(t.icon, size: 13, color: t.color),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(title, style: TextStyle(fontSize: 11, color: cs.onSurface)),
                        ),
                        if (t.isContainer)
                          Icon(Icons.chevron_right, size: 12, color: cs.outline),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyWorkspace(ColorScheme cs, JsacratchStrings s, bool showDropHint) {
    return Container(
      width: double.infinity, height: double.infinity,
      decoration: BoxDecoration(
        color: showDropHint ? cs.primary.withValues(alpha: 0.06) : null,
        border: showDropHint ? Border.all(color: cs.primary.withValues(alpha: 0.3), width: 2) : null,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drag_indicator, size: 48, color: showDropHint ? cs.primary : cs.outlineVariant),
            const SizedBox(height: 8),
            Text(
              showDropHint ? s.text('drop_here') : s.text('drag_blocks_hint'),
              style: TextStyle(color: showDropHint ? cs.primary : cs.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 4),
            if (!showDropHint) Text(s.text('drag_blocks_subtitle'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspace(List<ScratchBlock> blocks, ColorScheme cs, JsacratchStrings s, bool showDropHint) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: cs.surfaceContainer,
          child: Row(
            children: [
              Text(_activeScript.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              if (_activeScript.code.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _jsToBlocks,
                  icon: Icon(Icons.transform, size: 14, color: cs.primary),
                  label: Text(s.text('js_to_blocks'), style: TextStyle(fontSize: 11, color: cs.primary)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
              const Spacer(),
              Text(s.format('blocks_count', {'n': '${_countAllBlocks(blocks)}'}), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            itemCount: blocks.length,
            onReorderItem: (oldIdx, newIdx) {
              setState(() {
                if (newIdx > oldIdx) newIdx--;
                final item = blocks.removeAt(oldIdx);
                blocks.insert(newIdx, item);
              });
              widget.onScriptChanged();
            },
            header: showDropHint
                ? Container(
                    height: 32,
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.primary.withValues(alpha: 0.5), width: 1.5),
                      borderRadius: BorderRadius.circular(8),
                      color: cs.primary.withValues(alpha: 0.08),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add, size: 14, color: cs.primary),
                      const SizedBox(width: 4),
                      Text(s.text('drop_here'), style: TextStyle(fontSize: 11, color: cs.primary)),
                    ]),
                  )
                : null,
            itemBuilder: (context, index) {
              return _RootBlockTile(
                key: ValueKey(blocks[index].id),
                block: blocks[index],
                index: index,
                palette: (container) => _showAddToContainerMenu(container, s),
                onEditBlock: _editBlock,
                onRemove: () => _removeBlock(blocks, index),
              );
            },
          ),
        ),
      ],
    );
  }

  int _countAllBlocks(List<ScratchBlock> list) {
    int count = list.length;
    for (final b in list) {
      count += _countAllBlocks(b.children);
    }
    return count;
  }

  void _showAddToContainerMenu(ScratchBlock container, JsacratchStrings s) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollCtrl) => Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.text('add_to_container'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  children: BlockCategory.values.where((cat) => blocksByCategory(cat).isNotEmpty).map((cat) {
                    final catBlocks = blocksByCategory(cat);
                    return ExpansionTile(
                      leading: Icon(catBlocks.first.icon, size: 16, color: catBlocks.first.color),
                      title: Text(_categoryName(cat, s), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
                      initiallyExpanded: catBlocks.length <= 4,
                      childrenPadding: const EdgeInsets.only(left: 16, right: 8),
                      children: catBlocks.map((t) {
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 28, height: 22,
                            decoration: BoxDecoration(
                              color: t.color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            alignment: Alignment.center,
                            child: Icon(t.icon, size: 12, color: t.color),
                          ),
                          title: Text(t.localizedTitle(s.text), style: const TextStyle(fontSize: 11)),
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onTap: () {
                            _addBlockToContainerDirect(container, t, s);
                            Navigator.pop(ctx);
                          },
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addBlockToContainerDirect(ScratchBlock container, BlockTemplate template, JsacratchStrings s) {
    setState(() {
      container.children.add(ScratchBlock(
        id: 'block_${DateTime.now().millisecondsSinceEpoch}_${container.children.length}',
        templateId: template.id,
        category: template.category.name,
        color: template.color,
        label: template.localizedTitle(s.text),
        values: {for (final f in template.fields) f.key: f.defaultValue},
      ));
    });
    widget.onScriptChanged();
  }

  String _categoryName(BlockCategory cat, JsacratchStrings s) {
    switch (cat) {
      case BlockCategory.event: return s.text('category_event');
      case BlockCategory.control: return s.text('category_control');
      case BlockCategory.message: return s.text('category_message');
      case BlockCategory.data: return s.text('category_data');
      case BlockCategory.platform: return s.text('category_platform');
      case BlockCategory.utility: return s.text('category_utility');
      case BlockCategory.storage: return s.text('category_storage');
    }
  }
}

// ========== Root Block Tile (in flat list) ==========

class _RootBlockTile extends StatelessWidget {
  const _RootBlockTile({
    required this.block,
    required this.index,
    required this.palette,
    required this.onEditBlock,
    required this.onRemove,
    super.key,
  });

  final ScratchBlock block;
  final int index;
  final void Function(ScratchBlock) palette;
  final void Function(ScratchBlock) onEditBlock;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = blockTemplates.where((x) => x.id == block.templateId).firstOrNull;
    final isContainer = t?.isContainer ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BlockHeader(
            block: block,
            index: index,
            isContainer: isContainer,
            onChanged: onEditBlock,
            onRemove: onRemove,
            palette: isContainer ? () => palette(block) : null,
          ),
          if (isContainer)
            _ContainerBody(
              block: block,
              palette: palette,
              onEditBlock: onEditBlock,
              onDropTemplate: (t) {
                final s = JsacratchStrings.of(context);
                block.children.add(ScratchBlock(
                  id: 'block_${DateTime.now().millisecondsSinceEpoch}_${block.children.length}',
                  templateId: t.id,
                  category: t.category.name,
                  color: t.color,
                  label: t.localizedTitle(s.text),
                  values: {for (final f in t.fields) f.key: f.defaultValue},
                ));
                (context as Element).markNeedsBuild();
              },
              onRemoveChild: (ci) {
                block.children.removeAt(ci);
              },
            ),
        ],
      ),
    );
  }
}

// ========== Block Header (the colored bar at top) ==========

class _BlockHeader extends StatelessWidget {
  const _BlockHeader({
    required this.block,
    required this.index,
    required this.isContainer,
    required this.onChanged,
    required this.onRemove,
    this.palette,
  });

  final ScratchBlock block;
  final int index;
  final bool isContainer;
  final void Function(ScratchBlock) onChanged;
  final VoidCallback onRemove;
  final VoidCallback? palette;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = blockTemplates.where((x) => x.id == block.templateId).firstOrNull;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: block.color.withValues(alpha: 0.15),
        borderRadius: isContainer ? const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)) : BorderRadius.circular(8),
        border: Border.all(color: block.color.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ReorderableDragStartListener(
              index: index,
              child: SizedBox(
                width: 20, height: 24,
                child: Center(
                  child: Icon(Icons.drag_handle, size: 16, color: block.color.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ),
          Expanded(
            child: _buildInlineContent(context, t),
          ),
          const SizedBox(width: 4),
          if (palette != null)
            GestureDetector(
              onTap: palette,
              child: const SizedBox(
                width: 24, height: 24,
                child: Center(child: Icon(Icons.add_circle_outline, size: 16)),
              ),
            ),
          GestureDetector(
            onTap: onRemove,
            child: SizedBox(
              width: 24, height: 24,
              child: Center(child: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineContent(BuildContext context, BlockTemplate? t) {
    final cs = Theme.of(context).colorScheme;
    if (t == null || t.fields.isEmpty) {
      return Text(block.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface));
    }
    final inline = t.fields.where((f) => f.kind != BlockFieldKind.multiline && f.kind != BlockFieldKind.code).toList();
    final multiline = t.fields.where((f) => f.kind == BlockFieldKind.multiline || f.kind == BlockFieldKind.code).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 3,
          runSpacing: 2,
          children: [
            Text(block.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
            ...inline.map((f) => _InlineField(
              key: ValueKey('${block.id}_${f.key}'),
              field: f,
              initialValue: block.values[f.key] ?? f.defaultValue,
              onChanged: (v) {
                block.values[f.key] = v;
                onChanged(block);
              },
              onBlockDropped: (_) {},
            )),
          ],
        ),
        ...multiline.map((f) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SizedBox(
            width: double.infinity,
            child: _InlineField(
              key: ValueKey('${block.id}_${f.key}'),
              field: f,
              initialValue: block.values[f.key] ?? f.defaultValue,
              onChanged: (v) {
                block.values[f.key] = v;
                onChanged(block);
              },
              onBlockDropped: (_) {},
            ),
          ),
        )),
      ],
    );
  }
}

// ========== Container Body (C-shaped border with children) ==========

class _ContainerBody extends StatelessWidget {
  const _ContainerBody({
    required this.block,
    required this.palette,
    required this.onEditBlock,
    required this.onDropTemplate,
    required this.onRemoveChild,
  });

  final ScratchBlock block;
  final void Function(ScratchBlock) palette;
  final void Function(ScratchBlock) onEditBlock;
  final void Function(BlockTemplate) onDropTemplate;
  final void Function(int) onRemoveChild;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final children = block.children;

    final s = JsacratchStrings.of(context);

    return DragTarget<BlockTemplate>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => onDropTemplate(d.data),
      builder: (ctx, candidate, rejected) {
        final showingDropHint = candidate.isNotEmpty;
        final hasChildren = children.isNotEmpty;

        return Container(
          margin: const EdgeInsets.only(left: 10),
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: block.color.withValues(alpha: 0.5), width: 3),
            ),
            color: showingDropHint ? cs.primary.withValues(alpha: 0.05) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top padding inside container
              const SizedBox(height: 6),
              if (showingDropHint && !hasChildren)
                Container(
                  height: 36,
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6, right: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.primary.withValues(alpha: 0.5), width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                    color: cs.primary.withValues(alpha: 0.08),
                  ),
                  child: Center(
                    child: Text(s.text('drop_here'), style: TextStyle(fontSize: 12, color: cs.primary)),
                  ),
                ),
              if (hasChildren) ...[
                // Hint bar when dragging over existing children
                if (showingDropHint)
                  Container(height: 4, width: double.infinity, color: cs.primary.withValues(alpha: 0.3)),
                // Each nested block
                for (var i = 0; i < children.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, right: 2),
                    child: _NestedBlockTile(
                      block: children[i],
                      index: i,
                      parentColor: block.color,
                      palette: palette,
                      onEditBlock: onEditBlock,
                      onDropInto: onDropTemplate,
                      onRemove: () => onRemoveChild(i),
                    ),
                  ),
                ],
                // Hint bar at bottom of children
                if (showingDropHint)
                  Container(height: 4, width: double.infinity, color: cs.primary.withValues(alpha: 0.3)),
              ],
              // C-shaped bottom closure with large + button
              Container(
                height: hasChildren ? 28 : 40,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: block.color.withValues(alpha: 0.5), width: 3),
                    bottom: BorderSide(color: block.color.withValues(alpha: 0.5), width: 1.5),
                  ),
                  borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8)),
                  color: showingDropHint ? cs.primary.withValues(alpha: 0.08) : null,
                ),
                alignment: Alignment.centerLeft,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: showingDropHint ? null : () => palette(block),
                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6, top: 4, bottom: 4, right: 12),
                      child: showingDropHint
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.add, size: 14, color: cs.primary),
                              const SizedBox(width: 4),
                              Text(s.text('drop_here'), style: TextStyle(fontSize: 11, color: cs.primary)),
                            ])
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.add_circle_outline, size: 16, color: block.color.withValues(alpha: 0.7)),
                              const SizedBox(width: 6),
                              Text(hasChildren ? s.text('add_block') : s.text('add_block_into'),
                                style: TextStyle(fontSize: 11, color: block.color.withValues(alpha: 0.7))),
                            ]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ========== Nested Block Tile (inside container) ==========

class _NestedBlockTile extends StatelessWidget {
  const _NestedBlockTile({
    required this.block,
    required this.index,
    required this.parentColor,
    required this.palette,
    required this.onEditBlock,
    required this.onDropInto,
    required this.onRemove,
  });

  final ScratchBlock block;
  final int index;
  final Color parentColor;
  final void Function(ScratchBlock) palette;
  final void Function(ScratchBlock) onEditBlock;
  final void Function(BlockTemplate) onDropInto;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final s = JsacratchStrings.of(context);
    final t = blockTemplates.where((x) => x.id == block.templateId).firstOrNull;
    final isContainer = t?.isContainer ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 1, left: 2),
      child: DragTarget<BlockTemplate>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (d) => onDropInto(d.data),
        builder: (dtx, candidate, rejected) {
          return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InnerBlockBar(
            block: block,
            isContainer: isContainer,
            onChanged: onEditBlock,
            onRemove: onRemove,
            onAdd: isContainer ? () => palette(block) : null,
          ),
          if (isContainer)
            _ContainerBody(
              block: block,
              palette: palette,
              onEditBlock: onEditBlock,
              onDropTemplate: (t) {
                block.children.add(ScratchBlock(
                  id: 'block_${DateTime.now().millisecondsSinceEpoch}_${block.children.length}',
                  templateId: t.id,
                  category: t.category.name,
                  color: t.color,
                  label: t.localizedTitle(s.text),
                  values: {for (final f in t.fields) f.key: f.defaultValue},
                ));
                (context as Element).markNeedsBuild();
              },
              onRemoveChild: (ci) {
                block.children.removeAt(ci);
              },
            ),
        ],
      ); // Column
    }, // builder
    ),
    );
  }
}

class _InnerBlockBar extends StatelessWidget {
  const _InnerBlockBar({
    required this.block,
    required this.isContainer,
    required this.onChanged,
    required this.onRemove,
    this.onAdd,
  });

  final ScratchBlock block;
  final bool isContainer;
  final void Function(ScratchBlock) onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = blockTemplates.where((x) => x.id == block.templateId).firstOrNull;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: block.color.withValues(alpha: 0.12),
        borderRadius: isContainer ? const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)) : BorderRadius.circular(6),
        border: Border.all(color: block.color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildInlineContent(context, t),
          ),
          if (onAdd != null)
            GestureDetector(
              onTap: onAdd,
              child: const SizedBox(
                width: 20, height: 20,
                child: Center(child: Icon(Icons.add_circle_outline, size: 13)),
              ),
            ),
          GestureDetector(
            onTap: onRemove,
            child: SizedBox(
              width: 20, height: 20,
              child: Center(child: Icon(Icons.close, size: 13, color: cs.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineContent(BuildContext context, BlockTemplate? t) {
    final cs = Theme.of(context).colorScheme;
    if (t == null || t.fields.isEmpty) {
      return Text(block.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface));
    }
    final inline = t.fields.where((f) => f.kind != BlockFieldKind.multiline && f.kind != BlockFieldKind.code).toList();
    final multiline = t.fields.where((f) => f.kind == BlockFieldKind.multiline || f.kind == BlockFieldKind.code).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          runSpacing: 1,
          children: [
            Text(block.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface)),
            ...inline.map((f) => _InlineField(
              key: ValueKey('${block.id}_${f.key}'),
              field: f,
              initialValue: block.values[f.key] ?? f.defaultValue,
              compact: true,
              onChanged: (v) {
                block.values[f.key] = v;
                onChanged(block);
              },
              onBlockDropped: (_) {},
            )),
          ],
        ),
        ...multiline.map((f) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: SizedBox(
            width: double.infinity,
            child: _InlineField(
              key: ValueKey('${block.id}_${f.key}'),
              field: f,
              initialValue: block.values[f.key] ?? f.defaultValue,
              onChanged: (v) {
                block.values[f.key] = v;
                onChanged(block);
              },
              onBlockDropped: (_) {},
            ),
          ),
        )),
      ],
    );
  }
}

// ========== Inline Field (editable field directly on block) ==========

class _InlineField extends StatefulWidget {
  const _InlineField({
    required this.field,
    required this.initialValue,
    this.compact = false,
    this.onChanged,
    this.onBlockDropped,
    super.key,
  });

  final BlockFieldTemplate field;
  final String initialValue;
  final bool compact;
  final ValueChanged<String>? onChanged;
  final void Function(BlockTemplate)? onBlockDropped;

  @override
  State<_InlineField> createState() => _InlineFieldState();
}

class _InlineFieldState extends State<_InlineField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(_InlineField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        widget.initialValue != _ctrl.text) {
      _ctrl.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _wrapDropTarget(Widget child) {
    if (widget.onBlockDropped == null) return child;
    if (widget.field.kind == BlockFieldKind.select) return child;
    return DragTarget<BlockTemplate>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        // Generate code from the dropped block template
        final t = d.data;
        final values = {for (final f in t.fields) f.key: f.defaultValue};
        final code = t.codeBuilder(values);
        // Insert code into the field
        _ctrl.text += code;
        widget.onChanged?.call(_ctrl.text);
        widget.onBlockDropped?.call(t);
      },
      builder: (ctx, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: hovering
                ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5)
                : null,
            color: hovering
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                : null,
          ),
          child: Stack(
            children: [
              child,
              if (hovering)
                Positioned(
                  right: 2,
                  top: 1,
                  child: Icon(Icons.add_circle, size: 12,
                    color: Theme.of(context).colorScheme.primary),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fontSize = widget.compact ? 10.0 : 11.0;
    final h = widget.compact ? 22.0 : 26.0;

    switch (widget.field.kind) {
      case BlockFieldKind.number:
        return _wrapDropTarget(SizedBox(
          height: h,
          width: widget.compact ? 50 : 64,
          child: TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: fontSize, color: cs.onSurface),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.4)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: widget.field.kind == BlockFieldKind.number ? cs.primary : cs.primary),
              ),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              isDense: true,
            ),
            onChanged: widget.onChanged,
          ),
        ));
      case BlockFieldKind.select:
        final options = widget.field.options;
        return SizedBox(
          height: h,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: options.contains(_ctrl.text) ? _ctrl.text : (options.isNotEmpty ? options.first : null),
              isDense: true,
              style: TextStyle(fontSize: fontSize, color: cs.onSurface),
              items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, style: TextStyle(fontSize: fontSize)))).toList(),
              onChanged: (v) {
                if (v != null) {
                  _ctrl.text = v;
                  widget.onChanged?.call(v);
                }
              },
            ),
          ),
        );
      case BlockFieldKind.multiline:
      case BlockFieldKind.code:
        return _wrapDropTarget(TextField(
          controller: _ctrl,
          maxLines: 3,
          minLines: 2,
          style: TextStyle(fontSize: fontSize, color: cs.onSurface, fontFamily: 'monospace'),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: cs.primary),
            ),
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
            isDense: true,
          ),
          onChanged: widget.onChanged,
        ));
      default:
        return _wrapDropTarget(SizedBox(
          height: h,
          width: widget.compact ? 56 : 80,
          child: TextField(
            controller: _ctrl,
            style: TextStyle(fontSize: fontSize, color: cs.onSurface),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.4)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: cs.primary),
              ),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              isDense: true,
            ),
            onChanged: widget.onChanged,
          ),
        ));
    }
  }
}
