part of '../../main.dart';

enum _AcopBlockCategory { event, control, message, data, platform, utility }

enum _AcopBlockFieldKind { text, number, select, multiline }

class _AcopVariableSuggestion {
  const _AcopVariableSuggestion(this.labelKey, this.expression);

  final String labelKey;
  final String expression;
}

class _AcopBlockFieldTemplate {
  const _AcopBlockFieldTemplate({
    required this.key,
    required this.labelKey,
    required this.kind,
    this.defaultValue = '',
    this.options = const <String>[],
  });

  final String key;
  final String labelKey;
  final _AcopBlockFieldKind kind;
  final String defaultValue;
  final List<String> options;
}

class _AcopBlockTemplate {
  const _AcopBlockTemplate({
    required this.id,
    required this.titleKey,
    required this.category,
    required this.color,
    required this.icon,
    required this.fields,
    required this.builder,
    this.descriptionKey = '',
    this.permissions = const <String>[],
  });

  final String id;
  final String titleKey;
  final String descriptionKey;
  final _AcopBlockCategory category;
  final Color color;
  final IconData icon;
  final List<_AcopBlockFieldTemplate> fields;
  final String Function(Map<String, String> fields) builder;
  final List<String> permissions;
}

class _AcopWorkspaceBlock {
  _AcopWorkspaceBlock({
    required this.id,
    required this.template,
    required this.values,
  });

  final String id;
  final _AcopBlockTemplate template;
  final Map<String, String> values;
  bool collapsed = false;

  String buildCode() => template.builder(values);
}

class _AcopBlockDraft {
  const _AcopBlockDraft({required this.code});

  final String code;
}

class _AcopImportedBlock {
  const _AcopImportedBlock(this.templateId, this.values);

  final String templateId;
  final Map<String, String> values;
}

class _AcopBlockEditorScreen extends StatefulWidget {
  const _AcopBlockEditorScreen({
    required this.initialCode,
    required this.showGeneratedCode,
  });

  final String initialCode;
  final bool showGeneratedCode;

  @override
  State<_AcopBlockEditorScreen> createState() => _AcopBlockEditorScreenState();
}

class _AcopBlockEditorScreenState extends State<_AcopBlockEditorScreen>
    with SingleTickerProviderStateMixin {
  TabController? tabs;
  late final String initialGeneratedCode;
  final workspace = <_AcopWorkspaceBlock>[];
  int blockSerial = 0;
  bool codeCopied = false;
  bool allowPop = false;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: widget.showGeneratedCode ? 2 : 1, vsync: this);
    _addStarterBlocks();
    initialGeneratedCode = generatedCode;
  }

  @override
  void dispose() {
    tabs?.dispose();
    super.dispose();
  }

  bool get hasUnsavedChanges =>
      generatedCode.trim() != initialGeneratedCode.trim();

  String get generatedCode {
    final parts = workspace
        .map((block) => block.buildCode().trimRight())
        .where((code) => code.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '// Add blocks to generate JavaScript.';
    }
    return '${parts.join('\n\n')}\n';
  }

  List<_AcopBlockTemplate> get templates => _acopBlockTemplates;

  List<String> get requiredPermissions {
    return workspace
        .expand((block) => block.template.permissions)
        .toSet()
        .toList()
      ..sort();
  }

  void _addStarterBlocks() {
    final current = widget.initialCode.trim();
    if (current.isEmpty || current == _defaultAcopScriptTemplate.trim()) {
      addBlock(_templateById('command.reply'), notify: false);
      addBlock(_templateById('group.keyword.reply'), notify: false);
      return;
    }
    addBlock(
      _templateById('raw.code'),
      values: {'code': current},
      notify: false,
    );
  }

  void importCurrentCode() {
    final imported = _importAcopBlocks(generatedCode);
    setState(() {
      workspace
        ..clear()
        ..addAll(imported.map(_materializeImportedBlock));
      codeCopied = false;
    });
  }

  _AcopWorkspaceBlock _materializeImportedBlock(_AcopImportedBlock imported) {
    final template = _templateById(imported.templateId);
    return _AcopWorkspaceBlock(
      id: 'block_${++blockSerial}',
      template: template,
      values: {
        for (final field in template.fields)
          field.key: imported.values[field.key] ?? field.defaultValue,
      },
    );
  }

  void addBlock(
    _AcopBlockTemplate template, {
    Map<String, String>? values,
    bool notify = true,
  }) {
    workspace.add(
      _AcopWorkspaceBlock(
        id: 'block_${++blockSerial}',
        template: template,
        values: {
          for (final field in template.fields)
            field.key: values?[field.key] ?? field.defaultValue,
        },
      ),
    );
    if (notify && mounted) {
      setState(() => codeCopied = false);
    }
  }

  void removeBlock(_AcopWorkspaceBlock block) {
    setState(() {
      workspace.remove(block);
      codeCopied = false;
    });
  }

  void duplicateBlock(_AcopWorkspaceBlock block) {
    codeCopied = false;
    addBlock(block.template, values: Map<String, String>.from(block.values));
  }

  void toggleBlockCollapsed(_AcopWorkspaceBlock block) {
    setState(() {
      block.collapsed = !block.collapsed;
    });
  }

  void reorderBlocks(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final block = workspace.removeAt(oldIndex);
      workspace.insert(newIndex, block);
      codeCopied = false;
    });
  }

  void updateField(_AcopWorkspaceBlock block, String key, String value) {
    setState(() {
      block.values[key] = value;
      codeCopied = false;
    });
  }

  void insertVariable(
    _AcopWorkspaceBlock block,
    String key,
    String expression,
  ) {
    final current = block.values[key] ?? '';
    final separator = current.isEmpty || current.endsWith(' ') ? '' : ' ';
    updateField(block, key, '$current$separator$expression');
  }

  Future<void> copyCode() async {
    await Clipboard.setData(ClipboardData(text: generatedCode));
    if (!mounted) {
      return;
    }
    setState(() => codeCopied = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.strings.text('Copied.'))));
  }

  void applyCode() {
    allowPop = true;
    Navigator.of(context).pop(_AcopBlockDraft(code: generatedCode));
  }

  Future<void> handlePopAttempt() async {
    if (!hasUnsavedChanges) {
      allowPop = true;
      Navigator.of(context).pop();
      return;
    }
    final action = await showDialog<_AcopUnsavedExitAction>(
      context: context,
      builder: (context) => const _AcopUnsavedChangesDialog(),
    );
    if (!mounted) {
      return;
    }
    switch (action) {
      case _AcopUnsavedExitAction.save:
        applyCode();
        break;
      case _AcopUnsavedExitAction.discard:
        allowPop = true;
        Navigator.of(context).pop();
        break;
      case _AcopUnsavedExitAction.cancel:
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final isWide = MediaQuery.sizeOf(context).width >= 920;
    final showGeneratedCode = widget.showGeneratedCode;
    final currentTabs = tabs!;
    final workspacePanel = _AcopWorkspacePanel(
      workspace: workspace,
      onReorder: reorderBlocks,
      onUpdateField: updateField,
      onInsertVariable: insertVariable,
      onDuplicate: duplicateBlock,
      onRemove: removeBlock,
      onToggleCollapsed: toggleBlockCollapsed,
    );
    final codePanel = _AcopGeneratedCodePanel(
      code: generatedCode,
      permissions: requiredPermissions,
    );
    return PopScope<_AcopBlockDraft>(
      canPop: allowPop || !hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(handlePopAttempt());
        }
      },
      child: Scaffold(
        drawerEdgeDragWidth: isWide ? 0 : 64,
        drawer: isWide
            ? null
            : Drawer(
                width: math.min(MediaQuery.sizeOf(context).width * 0.86, 360),
                child: SafeArea(
                  child: _AcopBlockToolSidebar(
                    templates: templates,
                    codeCopied: codeCopied,
                    onOpenGuide: () => openAcopScriptGuide(context),
                    onCopyCode: copyCode,
                    onImportCode: importCurrentCode,
                    onApplyCode: applyCode,
                    onAddBlock: addBlock,
                  ),
                ),
              ),
        appBar: AppBar(
          leading: isWide
              ? null
              : Builder(
                  builder: (context) => IconButton(
                    tooltip: strings.text('Block tools'),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.menu_open),
                  ),
                ),
          title: Text(strings.text('JavaScript block editor')),
          bottom: isWide
              ? null
              : showGeneratedCode
              ? TabBar(
                  controller: currentTabs,
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.account_tree_outlined),
                      text: strings.text('Blocks'),
                    ),
                    Tab(
                      icon: const Icon(Icons.code),
                      text: strings.text('Generated code'),
                    ),
                  ],
                )
              : null,
          actions: [
            if (isWide) ...[
              IconButton(
                tooltip: strings.text('JavaScript guide'),
                onPressed: () => openAcopScriptGuide(context),
                icon: const Icon(Icons.help_outline),
              ),
              IconButton(
                tooltip: strings.text('Copy generated code'),
                onPressed: copyCode,
                icon: Icon(codeCopied ? Icons.check : Icons.copy),
              ),
              IconButton(
                tooltip: strings.text('Import code as blocks'),
                onPressed: importCurrentCode,
                icon: const Icon(Icons.input),
              ),
              TextButton.icon(
                onPressed: applyCode,
                icon: const Icon(Icons.output_outlined),
                label: Text(strings.text('Apply code')),
              ),
              const SizedBox(width: 8),
            ] else ...[
              IconButton(
                tooltip: strings.text('Apply code'),
                onPressed: applyCode,
                icon: const Icon(Icons.output_outlined),
              ),
            ],
          ],
        ),
        body: SafeArea(
          child: isWide
              ? Row(
                  children: [
                    SizedBox(
                      width: 340,
                      child: _AcopBlockPalette(
                        templates: templates,
                        onAdd: addBlock,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(flex: 3, child: workspacePanel),
                    if (showGeneratedCode) ...[
                      const VerticalDivider(width: 1),
                      Expanded(flex: 2, child: codePanel),
                    ],
                  ],
                )
              : TabBarView(
                  controller: currentTabs,
                  children: showGeneratedCode
                      ? [workspacePanel, codePanel]
                      : [workspacePanel],
                ),
        ),
      ),
    );
  }
}

class _AcopBlockPalette extends StatelessWidget {
  const _AcopBlockPalette({required this.templates, required this.onAdd});

  final List<_AcopBlockTemplate> templates;
  final void Function(_AcopBlockTemplate template) onAdd;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: [
        Text(
          strings.text('Block palette'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          strings.text(
            'Blocks are based on the ACOP JavaScript guide and generate sandbox-safe bot code.',
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (final category in _AcopBlockCategory.values) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
            child: Text(
              _acopBlockCategoryLabel(context, category),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final template in templates.where(
            (item) => item.category == category,
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AcopPaletteBlock(
                template: template,
                onTap: () => onAdd(template),
              ),
            ),
        ],
      ],
    );
  }
}

class _AcopBlockToolSidebar extends StatelessWidget {
  const _AcopBlockToolSidebar({
    required this.templates,
    required this.codeCopied,
    required this.onOpenGuide,
    required this.onCopyCode,
    required this.onImportCode,
    required this.onApplyCode,
    required this.onAddBlock,
  });

  final List<_AcopBlockTemplate> templates;
  final bool codeCopied;
  final VoidCallback onOpenGuide;
  final Future<void> Function() onCopyCode;
  final VoidCallback onImportCode;
  final VoidCallback onApplyCode;
  final void Function(_AcopBlockTemplate template) onAddBlock;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.text('Block tools'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: strings.text('Close'),
                onPressed: () => Scaffold.of(context).closeDrawer(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: onOpenGuide,
                icon: const Icon(Icons.help_outline),
                label: Text(strings.text('JavaScript guide')),
              ),
              FilledButton.tonalIcon(
                onPressed: () => unawaited(onCopyCode()),
                icon: Icon(codeCopied ? Icons.check : Icons.copy),
                label: Text(strings.text('Copy code')),
              ),
              FilledButton.tonalIcon(
                onPressed: onImportCode,
                icon: const Icon(Icons.input),
                label: Text(strings.text('Import')),
              ),
              FilledButton.icon(
                onPressed: onApplyCode,
                icon: const Icon(Icons.output_outlined),
                label: Text(strings.text('Apply code')),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _AcopBlockPalette(templates: templates, onAdd: onAddBlock),
        ),
      ],
    );
  }
}

class _AcopPaletteBlock extends StatelessWidget {
  const _AcopPaletteBlock({required this.template, required this.onTap});

  final _AcopBlockTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = template.color.computeLuminance() > 0.45
        ? Colors.black
        : Colors.white;
    return Material(
      color: template.color.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(template.icon, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.strings.text(template.titleKey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (template.descriptionKey.isNotEmpty)
                      Text(
                        context.strings.text(template.descriptionKey),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Color.alphaBlend(
                            foreground.withValues(alpha: 0.72),
                            template.color,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.add_circle_outline, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

class _AcopWorkspacePanel extends StatelessWidget {
  const _AcopWorkspacePanel({
    required this.workspace,
    required this.onReorder,
    required this.onUpdateField,
    required this.onInsertVariable,
    required this.onDuplicate,
    required this.onRemove,
    required this.onToggleCollapsed,
  });

  final List<_AcopWorkspaceBlock> workspace;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(_AcopWorkspaceBlock block, String key, String value)
  onUpdateField;
  final void Function(_AcopWorkspaceBlock block, String key, String expression)
  onInsertVariable;
  final void Function(_AcopWorkspaceBlock block) onDuplicate;
  final void Function(_AcopWorkspaceBlock block) onRemove;
  final void Function(_AcopWorkspaceBlock block) onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    if (workspace.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            strings.text('Add blocks from the palette to start.'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      buildDefaultDragHandles: false,
      itemCount: workspace.length,
      onReorder: onReorder,
      itemBuilder: (context, index) {
        final block = workspace[index];
        return Padding(
          key: ValueKey(block.id),
          padding: const EdgeInsets.only(bottom: 12),
          child: _AcopWorkspaceBlockCard(
            index: index,
            block: block,
            onUpdateField: onUpdateField,
            onInsertVariable: onInsertVariable,
            onDuplicate: () => onDuplicate(block),
            onRemove: () => onRemove(block),
            onToggleCollapsed: () => onToggleCollapsed(block),
          ),
        );
      },
    );
  }
}

class _AcopWorkspaceBlockCard extends StatelessWidget {
  const _AcopWorkspaceBlockCard({
    required this.index,
    required this.block,
    required this.onUpdateField,
    required this.onInsertVariable,
    required this.onDuplicate,
    required this.onRemove,
    required this.onToggleCollapsed,
  });

  final int index;
  final _AcopWorkspaceBlock block;
  final void Function(_AcopWorkspaceBlock block, String key, String value)
  onUpdateField;
  final void Function(_AcopWorkspaceBlock block, String key, String expression)
  onInsertVariable;
  final VoidCallback onDuplicate;
  final VoidCallback onRemove;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = block.template.color;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: accent.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 28,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(block.template.icon, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.strings.text(block.template.titleKey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.strings.text(
                      block.collapsed ? 'Expand' : 'Collapse',
                    ),
                    onPressed: onToggleCollapsed,
                    icon: Icon(
                      block.collapsed
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                    ),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: IconButton(
                      tooltip: context.strings.text('Drag to reorder'),
                      onPressed: () {},
                      icon: const Icon(Icons.drag_handle),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: context.strings.text('More'),
                    onSelected: (value) {
                      switch (value) {
                        case 'duplicate':
                          onDuplicate();
                          break;
                        case 'delete':
                          onRemove();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'duplicate',
                        child: Text(context.strings.text('Duplicate')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(context.strings.text('Delete')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!block.collapsed)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (final field in block.template.fields) ...[
                    _AcopBlockFieldEditor(
                      field: field,
                      value: block.values[field.key] ?? field.defaultValue,
                      onChanged: (value) =>
                          onUpdateField(block, field.key, value),
                      onInsertVariable: (expression) =>
                          onInsertVariable(block, field.key, expression),
                    ),
                    if (field != block.template.fields.last)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AcopBlockFieldEditor extends StatelessWidget {
  const _AcopBlockFieldEditor({
    required this.field,
    required this.value,
    required this.onChanged,
    required this.onInsertVariable,
  });

  final _AcopBlockFieldTemplate field;
  final String value;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onInsertVariable;

  Widget? _variableSuffix(BuildContext context) {
    if (field.kind == _AcopBlockFieldKind.select) {
      return null;
    }
    return PopupMenuButton<String>(
      tooltip: context.strings.text('Insert variable'),
      icon: const Icon(Icons.data_object),
      onSelected: onInsertVariable,
      itemBuilder: (context) => [
        for (final item in _acopVariableSuggestions)
          PopupMenuItem(
            value: item.expression,
            child: Text(
              '${context.strings.text(item.labelKey)}  ${item.expression}',
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    switch (field.kind) {
      case _AcopBlockFieldKind.select:
        return DropdownButtonFormField<String>(
          initialValue: field.options.contains(value)
              ? value
              : field.defaultValue,
          decoration: InputDecoration(
            labelText: strings.text(field.labelKey),
            border: const OutlineInputBorder(),
            suffixIcon: _variableSuffix(context),
          ),
          items: [
            for (final option in field.options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: (next) {
            if (next != null) {
              onChanged(next);
            }
          },
        );
      case _AcopBlockFieldKind.number:
        return TextFormField(
          initialValue: value,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
          ],
          decoration: InputDecoration(
            labelText: strings.text(field.labelKey),
            border: const OutlineInputBorder(),
          ),
          onChanged: onChanged,
        );
      case _AcopBlockFieldKind.multiline:
        return TextFormField(
          initialValue: value,
          minLines: 3,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: strings.text(field.labelKey),
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
            suffixIcon: _variableSuffix(context),
          ),
          onChanged: onChanged,
        );
      case _AcopBlockFieldKind.text:
        return TextFormField(
          initialValue: value,
          decoration: InputDecoration(
            labelText: strings.text(field.labelKey),
            border: const OutlineInputBorder(),
            suffixIcon: _variableSuffix(context),
          ),
          onChanged: onChanged,
        );
    }
  }
}

class _AcopGeneratedCodePanel extends StatelessWidget {
  const _AcopGeneratedCodePanel({
    required this.code,
    required this.permissions,
  });

  final String code;
  final List<String> permissions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AcopPermissionSummary(permissions: permissions),
          const SizedBox(height: 12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(
                    code,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: const [
                        'SF Mono',
                        'Menlo',
                        'Monaco',
                        'Liberation Mono',
                        'DejaVu Sans Mono',
                        'Noto Sans Mono',
                        'monospace',
                      ],
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AcopPermissionSummary extends StatelessWidget {
  const _AcopPermissionSummary({required this.permissions});

  final List<String> permissions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = permissions.isEmpty
        ? context.strings.text('No extra permissions')
        : permissions.join(', ');
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  context.strings.text('Required permissions'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            permissions.isEmpty
                ? Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final permission in permissions)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(permission),
                        ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

enum _AcopUnsavedExitAction { save, discard, cancel }

class _AcopUnsavedChangesDialog extends StatelessWidget {
  const _AcopUnsavedChangesDialog();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('Save changes?')),
      content: Text(
        strings.text('You have unsaved script changes. Save before leaving?'),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_AcopUnsavedExitAction.cancel),
          child: Text(strings.text('Cancel')),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_AcopUnsavedExitAction.discard),
          child: Text(strings.text('Discard')),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_AcopUnsavedExitAction.save),
          child: Text(strings.text('Save')),
        ),
      ],
    );
  }
}

String _acopBlockCategoryLabel(
  BuildContext context,
  _AcopBlockCategory category,
) {
  final strings = context.strings;
  return switch (category) {
    _AcopBlockCategory.event => strings.text('Events'),
    _AcopBlockCategory.control => strings.text('Control'),
    _AcopBlockCategory.message => strings.text('Messages'),
    _AcopBlockCategory.data => strings.text('Data'),
    _AcopBlockCategory.platform => strings.text('Platform APIs'),
    _AcopBlockCategory.utility => strings.text('Utilities'),
  };
}

_AcopBlockTemplate _templateById(String id) {
  return _acopBlockTemplates.firstWhere((template) => template.id == id);
}

List<_AcopImportedBlock> _importAcopBlocks(String code) {
  final source = code.trim();
  if (source.isEmpty || source == _defaultAcopScriptTemplate.trim()) {
    return const [
      _AcopImportedBlock('command.reply', {}),
      _AcopImportedBlock('group.keyword.reply', {}),
    ];
  }

  final blocks = <_AcopImportedBlock>[];
  final commandPattern = RegExp(
    r'''bot\.command\((['"])(.*?)\1(?:,\s*\{\s*scope:\s*(['"])(.*?)\3\s*\})?,\s*async\s*\(ctx\)\s*=>\s*\{\s*await\s+ctx\.reply\((['"])(.*?)\5\)\s*\}\)''',
    dotAll: true,
  );
  for (final match in commandPattern.allMatches(source)) {
    blocks.add(
      _AcopImportedBlock('command.reply', {
        'command': match.group(2) ?? '/ping',
        'scope': match.group(4) ?? 'all',
        'reply': match.group(6) ?? 'pong',
      }),
    );
  }

  final groupKeywordPattern = RegExp(
    r'''bot\.on\('group\.message',\s*async\s*\(ctx\)\s*=>\s*\{\s*if\s*\(ctx\.text\.includes\((['"])(.*?)\1\)\)\s*\{\s*await\s+ctx\.reply\((.*?)\)\s*\}\s*\}\)''',
    dotAll: true,
  );
  for (final match in groupKeywordPattern.allMatches(source)) {
    blocks.add(
      _AcopImportedBlock('group.keyword.reply', {
        'keyword': match.group(2) ?? '',
        'replyExpression': (match.group(3) ?? '').trim(),
      }),
    );
  }

  final privateKeywordPattern = RegExp(
    r'''bot\.on\('private\.message',\s*async\s*\(ctx\)\s*=>\s*\{\s*if\s*\(ctx\.text\.trim\(\)\s*===\s*(['"])(.*?)\1\)\s*\{\s*await\s+ctx\.reply\((['"])(.*?)\3\)\s*\}\s*\}\)''',
    dotAll: true,
  );
  for (final match in privateKeywordPattern.allMatches(source)) {
    blocks.add(
      _AcopImportedBlock('private.message.reply', {
        'keyword': match.group(2) ?? '',
        'reply': match.group(4) ?? '',
      }),
    );
  }

  final constPattern = RegExp(
    r'const\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(.+?)(?:\n|$)',
  );
  for (final match in constPattern.allMatches(source)) {
    final expression = (match.group(2) ?? '').trim();
    if (expression.startsWith('await ')) {
      continue;
    }
    blocks.add(
      _AcopImportedBlock('constant', {
        'name': match.group(1) ?? 'VALUE',
        'value': expression,
      }),
    );
  }

  if (source.contains('ctx.requireGroupAdmin()')) {
    blocks.add(const _AcopImportedBlock('require.group.admin', {}));
  }

  final logPattern = RegExp(
    r'''logger\.(info|warn|error)\((['"])(.*?)\2\)''',
    dotAll: true,
  );
  for (final match in logPattern.allMatches(source)) {
    blocks.add(
      _AcopImportedBlock('logger', {
        'level': match.group(1) ?? 'info',
        'message': match.group(3) ?? '',
      }),
    );
  }

  if (blocks.isEmpty) {
    return [
      _AcopImportedBlock('raw.code', {'code': source}),
    ];
  }
  return blocks;
}

String _f(Map<String, String> fields, String key) => fields[key] ?? '';

String _jsString(String value) {
  return jsonEncode(value);
}

String _jsIdentifier(String value, String fallback) {
  final trimmed = value.trim();
  final normalized = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9_$]'), '_');
  if (RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(normalized)) {
    return normalized;
  }
  return fallback;
}

String _jsNumber(String value, String fallback) {
  final trimmed = value.trim();
  if (num.tryParse(trimmed) == null) {
    return fallback;
  }
  return trimmed;
}

String _jsExpression(String value, String fallback) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

String _indentJs(String code, [String indent = '  ']) {
  return code
      .trim()
      .split('\n')
      .map((line) => line.trim().isEmpty ? '' : '$indent$line')
      .join('\n');
}

const _acopVariableSuggestions = <_AcopVariableSuggestion>[
  _AcopVariableSuggestion('Message text variable', 'ctx.text'),
  _AcopVariableSuggestion('Sender UID variable', 'ctx.sender.uid'),
  _AcopVariableSuggestion('Sender nickname variable', 'ctx.sender.nickname'),
  _AcopVariableSuggestion('Group ID variable', 'ctx.group.id'),
  _AcopVariableSuggestion('Matched regex group variable', 'match[1]'),
  _AcopVariableSuggestion('Current time variable', 'Date.now()'),
];

final _acopEventColor = Colors.indigo.shade600;
final _acopControlColor = Colors.deepOrange.shade600;
final _acopMessageColor = Colors.teal.shade600;
final _acopDataColor = Colors.blue.shade600;
final _acopPlatformColor = Colors.purple.shade600;
final _acopUtilityColor = Colors.blueGrey.shade600;

final _acopBlockTemplates = <_AcopBlockTemplate>[
  _AcopBlockTemplate(
    id: 'command.reply',
    titleKey: 'Command reply',
    descriptionKey: 'bot.command from the JavaScript guide.',
    category: _AcopBlockCategory.event,
    color: _acopEventColor,
    icon: Icons.terminal,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'command',
        labelKey: 'Command',
        kind: _AcopBlockFieldKind.text,
        defaultValue: '/ping',
      ),
      _AcopBlockFieldTemplate(
        key: 'scope',
        labelKey: 'Scope',
        kind: _AcopBlockFieldKind.select,
        defaultValue: 'all',
        options: ['all', 'private', 'group'],
      ),
      _AcopBlockFieldTemplate(
        key: 'reply',
        labelKey: 'Reply text',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'pong',
      ),
    ],
    builder: (fields) {
      final command = _jsString(
        _f(fields, 'command').trim().isEmpty
            ? '/ping'
            : _f(fields, 'command').trim(),
      );
      final scope = _f(fields, 'scope').trim();
      final options = scope == 'all' ? '' : ', { scope: ${_jsString(scope)} }';
      return '''
bot.command($command$options, async (ctx) => {
  await ctx.reply(${_jsString(_f(fields, 'reply'))})
})''';
    },
  ),
  _AcopBlockTemplate(
    id: 'regex.command.reply',
    titleKey: 'Regex command reply',
    descriptionKey: 'Matches a regular expression command.',
    category: _AcopBlockCategory.event,
    color: _acopEventColor,
    icon: Icons.manage_search,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'pattern',
        labelKey: 'Regex pattern',
        kind: _AcopBlockFieldKind.text,
        defaultValue: r'^/echo\s+(.+)$',
      ),
      _AcopBlockFieldTemplate(
        key: 'flags',
        labelKey: 'Regex flags',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'i',
      ),
      _AcopBlockFieldTemplate(
        key: 'replyExpression',
        labelKey: 'Reply expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'match[1]',
      ),
    ],
    builder: (fields) {
      final pattern = _f(fields, 'pattern').replaceAll('/', r'\/');
      final flags = _f(fields, 'flags').replaceAll(RegExp(r'[^a-z]'), '');
      return '''
bot.command(/$pattern/$flags, async (ctx, match) => {
  await ctx.reply(${_jsExpression(_f(fields, 'replyExpression'), 'match[1]')})
})''';
    },
  ),
  _AcopBlockTemplate(
    id: 'private.message.reply',
    titleKey: 'Private keyword reply',
    descriptionKey: 'bot.on private.message keyword handler.',
    category: _AcopBlockCategory.event,
    color: _acopEventColor,
    icon: Icons.person_outline,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'keyword',
        labelKey: 'Keyword',
        kind: _AcopBlockFieldKind.text,
        defaultValue: '测试bot',
      ),
      _AcopBlockFieldTemplate(
        key: 'reply',
        labelKey: 'Reply text',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'bot正在运行',
      ),
    ],
    builder: (fields) {
      return '''
bot.on('private.message', async (ctx) => {
  if (ctx.text.trim() === ${_jsString(_f(fields, 'keyword'))}) {
    await ctx.reply(${_jsString(_f(fields, 'reply'))})
  }
})''';
    },
  ),
  _AcopBlockTemplate(
    id: 'group.keyword.reply',
    titleKey: 'Group keyword reply',
    descriptionKey: 'bot.on group.message keyword handler.',
    category: _AcopBlockCategory.event,
    color: _acopEventColor,
    icon: Icons.groups_outlined,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'keyword',
        labelKey: 'Keyword',
        kind: _AcopBlockFieldKind.text,
        defaultValue: '你好',
      ),
      _AcopBlockFieldTemplate(
        key: 'replyExpression',
        labelKey: 'Reply expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: r'`你好，${ctx.sender.nickname || ctx.sender.uid}`',
      ),
    ],
    builder: (fields) {
      return '''
bot.on('group.message', async (ctx) => {
  if (ctx.text.includes(${_jsString(_f(fields, 'keyword'))})) {
    await ctx.reply(${_jsExpression(_f(fields, 'replyExpression'), _jsString('你好'))})
  }
})''';
    },
  ),
  _AcopBlockTemplate(
    id: 'member.join.welcome',
    titleKey: 'Group join welcome',
    descriptionKey: 'Welcomes new group members.',
    category: _AcopBlockCategory.event,
    color: _acopEventColor,
    icon: Icons.person_add_alt_1_outlined,
    permissions: const ['group', 'user'],
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'messageExpression',
        labelKey: 'Message expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: r'`欢迎 ${name} 加入群聊`',
      ),
    ],
    builder: (fields) {
      return '''
bot.on('group.member.join', async (ctx) => {
  const user = await csac.user.get(ctx.member.uid)
  const name = user.success ? user.nickname : `UID \${ctx.member.uid}`
  await csac.group.sendMessage(ctx.group.id, ${_jsExpression(_f(fields, 'messageExpression'), r'`欢迎 ${name} 加入群聊`')})
})''';
    },
  ),
  _AcopBlockTemplate(
    id: 'schedule.log',
    titleKey: 'Scheduled task',
    descriptionKey: 'bot.schedule cron task.',
    category: _AcopBlockCategory.event,
    color: _acopEventColor,
    icon: Icons.schedule,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'name',
        labelKey: 'Task name',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'daily-log',
      ),
      _AcopBlockFieldTemplate(
        key: 'cron',
        labelKey: 'Cron expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: '0 9 * * *',
      ),
      _AcopBlockFieldTemplate(
        key: 'body',
        labelKey: 'JavaScript body',
        kind: _AcopBlockFieldKind.multiline,
        defaultValue: "logger.info('daily job triggered')",
      ),
    ],
    builder: (fields) {
      return '''
bot.schedule(${_jsString(_f(fields, 'name'))}, ${_jsString(_f(fields, 'cron'))}, async (ctx) => {
${_indentJs(_f(fields, 'body'))}
})''';
    },
  ),
  _AcopBlockTemplate(
    id: 'if.text.includes',
    titleKey: 'If message contains',
    descriptionKey: 'Creates an if block using ctx.text.includes.',
    category: _AcopBlockCategory.control,
    color: _acopControlColor,
    icon: Icons.call_split,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'keyword',
        labelKey: 'Keyword',
        kind: _AcopBlockFieldKind.text,
        defaultValue: '你好',
      ),
      _AcopBlockFieldTemplate(
        key: 'body',
        labelKey: 'JavaScript body',
        kind: _AcopBlockFieldKind.multiline,
        defaultValue: "await ctx.reply('你好')",
      ),
    ],
    builder: (fields) {
      return '''
if (ctx.text.includes(${_jsString(_f(fields, 'keyword'))})) {
${_indentJs(_f(fields, 'body'))}
}''';
    },
  ),
  _AcopBlockTemplate(
    id: 'if.expression',
    titleKey: 'If expression',
    descriptionKey: 'Generic if block with a JavaScript condition.',
    category: _AcopBlockCategory.control,
    color: _acopControlColor,
    icon: Icons.segment,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'condition',
        labelKey: 'Condition expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'ctx.text.length > 0',
      ),
      _AcopBlockFieldTemplate(
        key: 'body',
        labelKey: 'JavaScript body',
        kind: _AcopBlockFieldKind.multiline,
        defaultValue: "await ctx.reply('ok')",
      ),
    ],
    builder: (fields) {
      return '''
if (${_jsExpression(_f(fields, 'condition'), 'true')}) {
${_indentJs(_f(fields, 'body'))}
}''';
    },
  ),
  _AcopBlockTemplate(
    id: 'else.if',
    titleKey: 'If / else',
    descriptionKey: 'Adds an else branch.',
    category: _AcopBlockCategory.control,
    color: _acopControlColor,
    icon: Icons.alt_route,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'condition',
        labelKey: 'Condition expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'ctx.text.includes("help")',
      ),
      _AcopBlockFieldTemplate(
        key: 'ifBody',
        labelKey: 'If body',
        kind: _AcopBlockFieldKind.multiline,
        defaultValue: "await ctx.reply('help')",
      ),
      _AcopBlockFieldTemplate(
        key: 'elseBody',
        labelKey: 'Else body',
        kind: _AcopBlockFieldKind.multiline,
        defaultValue: "await ctx.reply('no match')",
      ),
    ],
    builder: (fields) {
      return '''
if (${_jsExpression(_f(fields, 'condition'), 'true')}) {
${_indentJs(_f(fields, 'ifBody'))}
} else {
${_indentJs(_f(fields, 'elseBody'))}
}''';
    },
  ),
  _AcopBlockTemplate(
    id: 'loop.for',
    titleKey: 'For loop',
    descriptionKey: 'Classic counted loop.',
    category: _AcopBlockCategory.control,
    color: _acopControlColor,
    icon: Icons.loop,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'index',
        labelKey: 'Index variable',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'i',
      ),
      _AcopBlockFieldTemplate(
        key: 'start',
        labelKey: 'Start',
        kind: _AcopBlockFieldKind.number,
        defaultValue: '0',
      ),
      _AcopBlockFieldTemplate(
        key: 'end',
        labelKey: 'End',
        kind: _AcopBlockFieldKind.number,
        defaultValue: '10',
      ),
      _AcopBlockFieldTemplate(
        key: 'step',
        labelKey: 'Step',
        kind: _AcopBlockFieldKind.number,
        defaultValue: '1',
      ),
      _AcopBlockFieldTemplate(
        key: 'body',
        labelKey: 'JavaScript body',
        kind: _AcopBlockFieldKind.multiline,
        defaultValue: "logger.info(String(i))",
      ),
    ],
    builder: (fields) {
      final index = _jsIdentifier(_f(fields, 'index'), 'i');
      return '''
for (let $index = ${_jsNumber(_f(fields, 'start'), '0')}; $index < ${_jsNumber(_f(fields, 'end'), '10')}; $index += ${_jsNumber(_f(fields, 'step'), '1')}) {
${_indentJs(_f(fields, 'body'))}
}''';
    },
  ),
  _AcopBlockTemplate(
    id: 'loop.for.of',
    titleKey: 'For each item',
    descriptionKey: 'Iterates an array or list.',
    category: _AcopBlockCategory.control,
    color: _acopControlColor,
    icon: Icons.view_list_outlined,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'item',
        labelKey: 'Item variable',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'item',
      ),
      _AcopBlockFieldTemplate(
        key: 'items',
        labelKey: 'Items expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: '[1, 2, 3]',
      ),
      _AcopBlockFieldTemplate(
        key: 'body',
        labelKey: 'JavaScript body',
        kind: _AcopBlockFieldKind.multiline,
        defaultValue: "logger.info(String(item))",
      ),
    ],
    builder: (fields) {
      final item = _jsIdentifier(_f(fields, 'item'), 'item');
      return '''
for (const $item of ${_jsExpression(_f(fields, 'items'), '[]')}) {
${_indentJs(_f(fields, 'body'))}
}''';
    },
  ),
  _AcopBlockTemplate(
    id: 'loop.while',
    titleKey: 'While loop',
    descriptionKey: 'Repeats while a condition is true.',
    category: _AcopBlockCategory.control,
    color: _acopControlColor,
    icon: Icons.restart_alt,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'condition',
        labelKey: 'Condition expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'true',
      ),
      _AcopBlockFieldTemplate(
        key: 'body',
        labelKey: 'JavaScript body',
        kind: _AcopBlockFieldKind.multiline,
        defaultValue: "break",
      ),
    ],
    builder: (fields) {
      return '''
while (${_jsExpression(_f(fields, 'condition'), 'true')}) {
${_indentJs(_f(fields, 'body'))}
}''';
    },
  ),
  _AcopBlockTemplate(
    id: 'loop.repeat',
    titleKey: 'Repeat N times',
    descriptionKey: 'Scratch-like repeat loop.',
    category: _AcopBlockCategory.control,
    color: _acopControlColor,
    icon: Icons.repeat,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'times',
        labelKey: 'Times',
        kind: _AcopBlockFieldKind.number,
        defaultValue: '3',
      ),
      _AcopBlockFieldTemplate(
        key: 'body',
        labelKey: 'JavaScript body',
        kind: _AcopBlockFieldKind.multiline,
        defaultValue: "await ctx.reply('repeat')",
      ),
    ],
    builder: (fields) {
      return '''
for (let i = 0; i < ${_jsNumber(_f(fields, 'times'), '3')}; i += 1) {
${_indentJs(_f(fields, 'body'))}
}''';
    },
  ),
  _AcopBlockTemplate(
    id: 'try.catch',
    titleKey: 'Try / catch',
    descriptionKey: 'Wraps code with error handling.',
    category: _AcopBlockCategory.control,
    color: _acopControlColor,
    icon: Icons.warning_amber_outlined,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'tryBody',
        labelKey: 'Try body',
        kind: _AcopBlockFieldKind.multiline,
        defaultValue: "await ctx.reply('ok')",
      ),
      _AcopBlockFieldTemplate(
        key: 'catchBody',
        labelKey: 'Catch body',
        kind: _AcopBlockFieldKind.multiline,
        defaultValue: "logger.error(error)",
      ),
    ],
    builder: (fields) {
      return '''
try {
${_indentJs(_f(fields, 'tryBody'))}
} catch (error) {
${_indentJs(_f(fields, 'catchBody'))}
}''';
    },
  ),
  _AcopBlockTemplate(
    id: 'return.statement',
    titleKey: 'Return',
    descriptionKey: 'Ends the current function or handler.',
    category: _AcopBlockCategory.control,
    color: _acopControlColor,
    icon: Icons.keyboard_return,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'expression',
        labelKey: 'Return expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: '',
      ),
    ],
    builder: (fields) {
      final expression = _f(fields, 'expression').trim();
      return expression.isEmpty
          ? 'return'
          : 'return ${_jsExpression(expression, 'null')}';
    },
  ),
  _AcopBlockTemplate(
    id: 'function.declare',
    titleKey: 'Function',
    descriptionKey: 'Declares a reusable JavaScript function.',
    category: _AcopBlockCategory.utility,
    color: _acopUtilityColor,
    icon: Icons.functions,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'name',
        labelKey: 'Function name',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'handler',
      ),
      _AcopBlockFieldTemplate(
        key: 'params',
        labelKey: 'Parameters',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'ctx',
      ),
      _AcopBlockFieldTemplate(
        key: 'body',
        labelKey: 'JavaScript body',
        kind: _AcopBlockFieldKind.multiline,
        defaultValue: "return true",
      ),
    ],
    builder: (fields) {
      final name = _jsIdentifier(_f(fields, 'name'), 'handler');
      final params = _f(fields, 'params').trim().isEmpty
          ? 'ctx'
          : _f(fields, 'params').trim();
      return '''
function $name($params) {
${_indentJs(_f(fields, 'body'))}
}''';
    },
  ),
  _AcopBlockTemplate(
    id: 'delay',
    titleKey: 'Delay',
    descriptionKey: 'Waits for a number of milliseconds.',
    category: _AcopBlockCategory.utility,
    color: _acopUtilityColor,
    icon: Icons.schedule_send,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'ms',
        labelKey: 'Milliseconds',
        kind: _AcopBlockFieldKind.number,
        defaultValue: '1000',
      ),
    ],
    builder: (fields) {
      return 'await new Promise((resolve) => setTimeout(resolve, ${_jsNumber(_f(fields, 'ms'), '1000')}))';
    },
  ),
  _AcopBlockTemplate(
    id: 'require.group.admin',
    titleKey: 'Require group admin',
    descriptionKey: 'Stops when the bot lacks group admin permission.',
    category: _AcopBlockCategory.control,
    color: _acopControlColor,
    icon: Icons.admin_panel_settings_outlined,
    fields: const [],
    builder: (_) => 'if (!(await ctx.requireGroupAdmin())) return',
  ),
  _AcopBlockTemplate(
    id: 'reply.text',
    titleKey: 'Reply current message',
    descriptionKey: 'ctx.reply text.',
    category: _AcopBlockCategory.message,
    color: _acopMessageColor,
    icon: Icons.reply_outlined,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'text',
        labelKey: 'Reply text',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'hello',
      ),
    ],
    builder: (fields) => 'await ctx.reply(${_jsString(_f(fields, 'text'))})',
  ),
  _AcopBlockTemplate(
    id: 'reply.expression',
    titleKey: 'Reply expression',
    descriptionKey: 'ctx.reply with a JavaScript expression.',
    category: _AcopBlockCategory.message,
    color: _acopMessageColor,
    icon: Icons.functions,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'expression',
        labelKey: 'Reply expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: r'`你好，${ctx.sender.nickname || ctx.sender.uid}`',
      ),
    ],
    builder: (fields) =>
        'await ctx.reply(${_jsExpression(_f(fields, 'expression'), _jsString('hello'))})',
  ),
  _AcopBlockTemplate(
    id: 'send.group.message',
    titleKey: 'Send group message',
    descriptionKey: 'csac.group.sendMessage.',
    category: _AcopBlockCategory.message,
    color: _acopMessageColor,
    icon: Icons.forum_outlined,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'groupId',
        labelKey: 'Group ID expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'ctx.group.id',
      ),
      _AcopBlockFieldTemplate(
        key: 'text',
        labelKey: 'Message text',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'hello',
      ),
    ],
    builder: (fields) {
      return 'await csac.group.sendMessage(${_jsExpression(_f(fields, 'groupId'), 'ctx.group.id')}, ${_jsString(_f(fields, 'text'))})';
    },
  ),
  _AcopBlockTemplate(
    id: 'send.private.message',
    titleKey: 'Send private message',
    descriptionKey: 'csac.private.sendMessage.',
    category: _AcopBlockCategory.message,
    color: _acopMessageColor,
    icon: Icons.mark_chat_unread_outlined,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'uid',
        labelKey: 'UID expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'ctx.sender.uid',
      ),
      _AcopBlockFieldTemplate(
        key: 'text',
        labelKey: 'Message text',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'hello',
      ),
    ],
    builder: (fields) {
      return 'await csac.private.sendMessage(${_jsExpression(_f(fields, 'uid'), 'ctx.sender.uid')}, ${_jsString(_f(fields, 'text'))})';
    },
  ),
  _AcopBlockTemplate(
    id: 'notice.send',
    titleKey: 'Send notice',
    descriptionKey: 'ctx.notice requires notify permission.',
    category: _AcopBlockCategory.message,
    color: _acopMessageColor,
    icon: Icons.notifications_active_outlined,
    permissions: const ['notify'],
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'title',
        labelKey: 'Title',
        kind: _AcopBlockFieldKind.text,
        defaultValue: '处理完成',
      ),
      _AcopBlockFieldTemplate(
        key: 'content',
        labelKey: 'Content',
        kind: _AcopBlockFieldKind.text,
        defaultValue: '你的请求已处理完成',
      ),
    ],
    builder: (fields) {
      return 'await ctx.notice(${_jsString(_f(fields, 'title'))}, ${_jsString(_f(fields, 'content'))})';
    },
  ),
  _AcopBlockTemplate(
    id: 'storage.get',
    titleKey: 'Read storage',
    descriptionKey: 'csac.storage.get.',
    category: _AcopBlockCategory.data,
    color: _acopDataColor,
    icon: Icons.inventory_2_outlined,
    permissions: const ['storage'],
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'variable',
        labelKey: 'Variable name',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'count',
      ),
      _AcopBlockFieldTemplate(
        key: 'key',
        labelKey: 'Storage key',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'hello.count',
      ),
      _AcopBlockFieldTemplate(
        key: 'fallback',
        labelKey: 'Default value expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: '0',
      ),
    ],
    builder: (fields) {
      return 'const ${_jsIdentifier(_f(fields, 'variable'), 'value')} = await csac.storage.get(${_jsString(_f(fields, 'key'))}, ${_jsExpression(_f(fields, 'fallback'), '0')})';
    },
  ),
  _AcopBlockTemplate(
    id: 'storage.set',
    titleKey: 'Write storage',
    descriptionKey: 'csac.storage.set.',
    category: _AcopBlockCategory.data,
    color: _acopDataColor,
    icon: Icons.save_as_outlined,
    permissions: const ['storage'],
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'key',
        labelKey: 'Storage key',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'hello.count',
      ),
      _AcopBlockFieldTemplate(
        key: 'value',
        labelKey: 'Value expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: '1',
      ),
    ],
    builder: (fields) {
      return 'await csac.storage.set(${_jsString(_f(fields, 'key'))}, ${_jsExpression(_f(fields, 'value'), '1')})';
    },
  ),
  _AcopBlockTemplate(
    id: 'storage.increment',
    titleKey: 'Increment storage',
    descriptionKey: 'csac.storage.increment counter.',
    category: _AcopBlockCategory.data,
    color: _acopDataColor,
    icon: Icons.exposure_plus_1,
    permissions: const ['storage'],
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'variable',
        labelKey: 'Variable name',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'count',
      ),
      _AcopBlockFieldTemplate(
        key: 'key',
        labelKey: 'Storage key expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: r'`counter:${ctx.sender.uid}`',
      ),
      _AcopBlockFieldTemplate(
        key: 'step',
        labelKey: 'Step',
        kind: _AcopBlockFieldKind.number,
        defaultValue: '1',
      ),
    ],
    builder: (fields) {
      return 'const ${_jsIdentifier(_f(fields, 'variable'), 'count')} = await csac.storage.increment(${_jsExpression(_f(fields, 'key'), _jsString('counter'))}, ${_jsNumber(_f(fields, 'step'), '1')})';
    },
  ),
  _AcopBlockTemplate(
    id: 'http.get',
    titleKey: 'HTTP GET',
    descriptionKey: 'csac.http.get requires http permission.',
    category: _AcopBlockCategory.platform,
    color: _acopPlatformColor,
    icon: Icons.http,
    permissions: const ['http'],
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'variable',
        labelKey: 'Variable name',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'res',
      ),
      _AcopBlockFieldTemplate(
        key: 'url',
        labelKey: 'URL',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'https://api.example.com/status',
      ),
    ],
    builder: (fields) {
      return 'const ${_jsIdentifier(_f(fields, 'variable'), 'res')} = await csac.http.get(${_jsString(_f(fields, 'url'))})';
    },
  ),
  _AcopBlockTemplate(
    id: 'user.get',
    titleKey: 'Get user info',
    descriptionKey: 'csac.user.get.',
    category: _AcopBlockCategory.platform,
    color: _acopPlatformColor,
    icon: Icons.account_circle_outlined,
    permissions: const ['user'],
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'variable',
        labelKey: 'Variable name',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'user',
      ),
      _AcopBlockFieldTemplate(
        key: 'uid',
        labelKey: 'UID expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'ctx.sender.uid',
      ),
    ],
    builder: (fields) {
      return 'const ${_jsIdentifier(_f(fields, 'variable'), 'user')} = await csac.user.get(${_jsExpression(_f(fields, 'uid'), 'ctx.sender.uid')})';
    },
  ),
  _AcopBlockTemplate(
    id: 'group.info',
    titleKey: 'Get group info',
    descriptionKey: 'csac.groupInfo.get.',
    category: _AcopBlockCategory.platform,
    color: _acopPlatformColor,
    icon: Icons.info_outline,
    permissions: const ['group'],
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'variable',
        labelKey: 'Variable name',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'group',
      ),
      _AcopBlockFieldTemplate(
        key: 'groupId',
        labelKey: 'Group ID expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'ctx.group.id',
      ),
    ],
    builder: (fields) {
      return 'const ${_jsIdentifier(_f(fields, 'variable'), 'group')} = await csac.groupInfo.get(${_jsExpression(_f(fields, 'groupId'), 'ctx.group.id')})';
    },
  ),
  _AcopBlockTemplate(
    id: 'logger',
    titleKey: 'Write log',
    descriptionKey: 'logger.info, logger.warn or logger.error.',
    category: _AcopBlockCategory.utility,
    color: _acopUtilityColor,
    icon: Icons.article_outlined,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'level',
        labelKey: 'Log level',
        kind: _AcopBlockFieldKind.select,
        defaultValue: 'info',
        options: ['info', 'warn', 'error'],
      ),
      _AcopBlockFieldTemplate(
        key: 'message',
        labelKey: 'Message text',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'message',
      ),
    ],
    builder: (fields) {
      final level = switch (_f(fields, 'level')) {
        'warn' => 'warn',
        'error' => 'error',
        _ => 'info',
      };
      return 'logger.$level(${_jsString(_f(fields, 'message'))})';
    },
  ),
  _AcopBlockTemplate(
    id: 'constant',
    titleKey: 'Constant',
    descriptionKey: 'Creates a const variable.',
    category: _AcopBlockCategory.utility,
    color: _acopUtilityColor,
    icon: Icons.data_object,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'name',
        labelKey: 'Variable name',
        kind: _AcopBlockFieldKind.text,
        defaultValue: 'VERSION',
      ),
      _AcopBlockFieldTemplate(
        key: 'value',
        labelKey: 'Value expression',
        kind: _AcopBlockFieldKind.text,
        defaultValue: "'1.0.0'",
      ),
    ],
    builder: (fields) {
      return 'const ${_jsIdentifier(_f(fields, 'name'), 'VALUE')} = ${_jsExpression(_f(fields, 'value'), "''")}';
    },
  ),
  _AcopBlockTemplate(
    id: 'raw.code',
    titleKey: 'Raw JavaScript',
    descriptionKey: 'Keeps hand-written JavaScript in the generated output.',
    category: _AcopBlockCategory.utility,
    color: _acopUtilityColor,
    icon: Icons.code,
    fields: const [
      _AcopBlockFieldTemplate(
        key: 'code',
        labelKey: 'JavaScript code',
        kind: _AcopBlockFieldKind.multiline,
        defaultValue: "logger.info('hello')",
      ),
    ],
    builder: (fields) => _f(fields, 'code'),
  ),
];
