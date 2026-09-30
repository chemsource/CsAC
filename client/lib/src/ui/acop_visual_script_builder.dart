import 'package:flutter/material.dart';

// ===== 模板数据结构 =====

class EventTemplate {
  final String id;
  final String label;
  final String eventName;
  final String description;
  final List<ParamField> params;
  final bool hasKeywordFilter;

  const EventTemplate({
    required this.id,
    required this.label,
    required this.eventName,
    required this.description,
    this.params = const [],
    this.hasKeywordFilter = false,
  });
}

class ActionTemplate {
  final String id;
  final String label;
  final String description;
  final List<ParamField> params;

  const ActionTemplate({
    required this.id,
    required this.label,
    required this.description,
    this.params = const [],
  });
}

class ParamField {
  final String key;
  final String label;
  final String hint;
  final String type;
  final List<SelectOption>? options;
  final String defaultValue;

  const ParamField({
    required this.key,
    required this.label,
    this.hint = '',
    this.type = 'text',
    this.options,
    this.defaultValue = '',
  });
}

class SelectOption {
  final String value;
  final String label;
  const SelectOption({required this.value, required this.label});
}

// ===== 事件模板 =====

const eventTemplates = [
  EventTemplate(
    id: 'group_msg_keyword',
    label: '群聊消息包含关键词',
    eventName: 'group.message',
    description: '当群聊中出现指定关键词时触发',
    hasKeywordFilter: true,
  ),
  EventTemplate(
    id: 'group_msg_any',
    label: '收到群聊消息',
    eventName: 'group.message',
    description: '当收到任何群聊消息时触发',
  ),
  EventTemplate(
    id: 'private_msg_keyword',
    label: '私聊消息包含关键词',
    eventName: 'private.message',
    description: '当私聊中出现指定关键词时触发',
    hasKeywordFilter: true,
  ),
  EventTemplate(
    id: 'private_msg_any',
    label: '收到私聊消息',
    eventName: 'private.message',
    description: '当收到任何私聊消息时触发',
  ),
  EventTemplate(
    id: 'group_join',
    label: '用户加入群聊',
    eventName: 'group.member.join',
    description: '当有新用户加入群聊时触发',
  ),
  EventTemplate(
    id: 'group_leave',
    label: '用户退出群聊',
    eventName: 'group.member.leave',
    description: '当有用户退出或被踢出群聊时触发',
  ),
  EventTemplate(
    id: 'group_mute',
    label: '用户被禁言/解禁',
    eventName: 'group.member.mute',
    description: '当群成员被禁言或解禁时触发',
  ),
  EventTemplate(
    id: 'group_disband',
    label: '群聊解散',
    eventName: 'group.disband',
    description: '当群聊被解散时触发',
  ),
];

// ===== 动作模板 =====

const actionTemplates = [
  ActionTemplate(
    id: 'send_group_msg',
    label: '发送群消息',
    description: '向指定群聊发送文本消息',
    params: [
      ParamField(key: 'room_id', label: '群聊ID', hint: '输入群聊ID', type: 'number'),
      ParamField(key: 'content', label: '消息内容', hint: '输入要发送的消息'),
    ],
  ),
  ActionTemplate(
    id: 'reply_group_msg',
    label: '回复群消息',
    description: '回复当前触发的群消息',
    params: [ParamField(key: 'content', label: '回复内容', hint: '输入回复内容')],
  ),
  ActionTemplate(
    id: 'send_private_msg',
    label: '发送私聊消息',
    description: '向指定用户发送私聊消息',
    params: [
      ParamField(key: 'uid', label: '用户ID', hint: '输入用户ID', type: 'number'),
      ParamField(key: 'content', label: '消息内容', hint: '输入要发送的消息'),
    ],
  ),
  ActionTemplate(
    id: 'reply_private_msg',
    label: '回复私聊消息',
    description: '回复当前触发的私聊消息',
    params: [ParamField(key: 'content', label: '回复内容', hint: '输入回复内容')],
  ),
  ActionTemplate(
    id: 'mute_member',
    label: '禁言群成员',
    description: '禁言指定群成员',
    params: [
      ParamField(key: 'room_id', label: '群聊ID', hint: '输入群聊ID', type: 'number'),
      ParamField(key: 'uid', label: '用户ID', hint: '输入要禁言的用户ID', type: 'number'),
      ParamField(key: 'duration', label: '禁言时长(秒)', hint: '如60表示1分钟', type: 'number'),
    ],
  ),
  ActionTemplate(
    id: 'unmute_member',
    label: '解除禁言',
    description: '解除群成员的禁言',
    params: [
      ParamField(key: 'room_id', label: '群聊ID', hint: '输入群聊ID', type: 'number'),
      ParamField(key: 'uid', label: '用户ID', hint: '输入用户ID', type: 'number'),
    ],
  ),
  ActionTemplate(
    id: 'send_notice',
    label: '发送通知',
    description: '向用户发送系统通知',
    params: [
      ParamField(key: 'uid', label: '用户ID', hint: '输入用户ID', type: 'number'),
      ParamField(key: 'title', label: '通知标题', hint: '输入通知标题'),
      ParamField(key: 'content', label: '通知内容', hint: '输入通知内容'),
    ],
  ),
  ActionTemplate(
    id: 'send_group_image',
    label: '发送群图片',
    description: '向群聊发送图片',
    params: [
      ParamField(key: 'room_id', label: '群聊ID', hint: '输入群聊ID', type: 'number'),
      ParamField(key: 'url', label: '图片URL', hint: '输入图片地址'),
    ],
  ),
  ActionTemplate(
    id: 'leave_group',
    label: '退出群聊',
    description: '让Bot退出指定群聊',
    params: [ParamField(key: 'room_id', label: '群聊ID', hint: '输入群聊ID', type: 'number')],
  ),
  ActionTemplate(
    id: 'log_msg',
    label: '记录日志',
    description: '输出日志信息（用于调试）',
    params: [ParamField(key: 'message', label: '日志内容', hint: '输入要记录的信息')],
  ),
];

// ===== 代码生成 =====

String generateScriptCode({
  required EventTemplate event,
  required List<ActionTemplate> actions,
  required Map<String, String> eventParams,
  required List<Map<String, String>> actionParamsList,
  String? keywords,
}) {
  final buf = StringBuffer();
  buf.writeln("bot.on('${event.eventName}', async (ctx) => {");

  if (event.hasKeywordFilter && keywords != null && keywords.trim().isNotEmpty) {
    final kwList = keywords.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (kwList.isNotEmpty) {
      if (kwList.length == 1) {
        buf.writeln('  if (!ctx.text.includes("${_escapeJs(kwList[0])}")) {');
        buf.writeln('    return');
        buf.writeln('  }');
      } else {
        final kwArray = kwList.map((k) => '"${_escapeJs(k)}"').join(', ');
        buf.writeln('  const keywords = [$kwArray]');
        buf.writeln('  if (!keywords.some((kw) => ctx.text.includes(kw))) {');
        buf.writeln('    return');
        buf.writeln('  }');
      }
    }
  }

  for (int i = 0; i < actions.length; i++) {
    final action = actions[i];
    final params = actionParamsList[i];
    buf.writeln('  ${_generateActionCode(action, params, event)}');
  }

  buf.writeln('})');
  return buf.toString();
}

String _generateActionCode(
  ActionTemplate action,
  Map<String, String> params,
  EventTemplate event,
) {
  switch (action.id) {
    case 'send_group_msg':
      final roomId = params['room_id'] ?? '0';
      final content = params['content'] ?? '';
      return 'await csac.group.sendMessage($roomId, "${_escapeJs(content)}")';
    case 'reply_group_msg':
      final content = params['content'] ?? '';
      return 'await ctx.reply("${_escapeJs(content)}")';
    case 'send_private_msg':
      final uid = params['uid'] ?? '0';
      final content = params['content'] ?? '';
      return 'await csac.private.sendMessage($uid, "${_escapeJs(content)}")';
    case 'reply_private_msg':
      final content = params['content'] ?? '';
      return 'await ctx.reply("${_escapeJs(content)}")';
    case 'mute_member':
      final roomId = params['room_id'] ?? '0';
      final uid = params['uid'] ?? '0';
      final duration = params['duration'] ?? '60';
      return 'await csac.group.muteMember($roomId, $uid, $duration)';
    case 'unmute_member':
      final roomId = params['room_id'] ?? '0';
      final uid = params['uid'] ?? '0';
      return 'await csac.group.unmuteMember($roomId, $uid)';
    case 'send_notice':
      final uid = params['uid'] ?? '0';
      final title = params['title'] ?? '';
      final content = params['content'] ?? '';
      return 'await csac.notice.send($uid, "${_escapeJs(title)}", "${_escapeJs(content)}")';
    case 'send_group_image':
      final roomId = params['room_id'] ?? '0';
      final url = params['url'] ?? '';
      return 'await csac.group.sendImage($roomId, "${_escapeJs(url)}")';
    case 'leave_group':
      final roomId = params['room_id'] ?? '0';
      return 'await csac.group.leave($roomId)';
    case 'log_msg':
      final message = params['message'] ?? '';
      return 'logger.info("${_escapeJs(message)}")';
    default:
      return '// unknown action: ${action.id}';
  }
}

String _escapeJs(String value) {
  return value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r');
}

// ===== 可视化构建器 Widget =====

class VisualScriptBuilder extends StatefulWidget {
  final void Function(String code) onCodeGenerated;

  const VisualScriptBuilder({super.key, required this.onCodeGenerated});

  @override
  State<VisualScriptBuilder> createState() => _VisualScriptBuilderState();
}

class _VisualScriptBuilderState extends State<VisualScriptBuilder> {
  EventTemplate? _selectedEvent;
  String? _keywords;
  final List<_ActionEntry> _actions = [];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEventSection(),
        const SizedBox(height: 16),
        if (_selectedEvent?.hasKeywordFilter == true) ...[
          _buildKeywordSection(),
          const SizedBox(height: 16),
        ],
        _buildActionsSection(),
        const SizedBox(height: 16),
        _buildAddActionButton(),
        const SizedBox(height: 20),
        if (_selectedEvent != null && _actions.isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _generateCode,
              icon: const Icon(Icons.code),
              label: const Text('生成代码'),
            ),
          ),
      ],
    );
  }

  Widget _buildEventSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 6),
                Text('选择触发事件', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: eventTemplates.map((evt) {
                final selected = _selectedEvent?.id == evt.id;
                return ChoiceChip(
                  label: Text(evt.label),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      _selectedEvent = selected ? null : evt;
                      if (!selected) _keywords = null;
                    });
                  },
                );
              }).toList(),
            ),
            if (_selectedEvent != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_selectedEvent!.description, style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKeywordSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_alt, color: Theme.of(context).colorScheme.tertiary, size: 20),
                const SizedBox(width: 6),
                Text('关键词过滤', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 4),
            const Text('多个关键词用英文逗号分隔，匹配任一即触发', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: '例如: 你好,hello,hi',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 20),
              ),
              onChanged: (v) => _keywords = v,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsSection() {
    if (_actions.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text('还没有添加动作，点击下方按钮添加', style: TextStyle(color: Colors.grey.shade500)),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (int i = 0; i < _actions.length; i++)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: _buildActionCard(i)),
      ],
    );
  }

  Widget _buildActionCard(int index) {
    final entry = _actions[index];
    final action = entry.template;
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.play_arrow, color: Theme.of(context).colorScheme.secondary, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('动作 ${index + 1}: ${action.label}', style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => setState(() => _actions.removeAt(index)),
                  tooltip: '删除此动作',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...action.params.map(
              (param) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildParamField(param, entry.params),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParamField(ParamField param, Map<String, String> params) {
    if (param.type == 'select' && param.options != null) {
      return DropdownButtonFormField<String>(
        initialValue: params[param.key] ?? param.defaultValue,
        decoration: InputDecoration(labelText: param.label, border: const OutlineInputBorder(), isDense: true),
        items: param.options!.map((opt) => DropdownMenuItem(value: opt.value, child: Text(opt.label))).toList(),
        onChanged: (v) {
          if (v != null) setState(() => params[param.key] = v);
        },
      );
    }
    return TextField(
      decoration: InputDecoration(labelText: param.label, hintText: param.hint, border: const OutlineInputBorder(), isDense: true),
      keyboardType: param.type == 'number' ? TextInputType.number : TextInputType.text,
      onChanged: (v) => params[param.key] = v,
    );
  }

  Widget _buildAddActionButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _showAddActionDialog,
        icon: const Icon(Icons.add),
        label: const Text('添加动作'),
      ),
    );
  }

  void _showAddActionDialog() {
    ActionTemplate? selected;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('选择动作'),
          content: SizedBox(
            width: 400,
            child: ListView(
              shrinkWrap: true,
              children: actionTemplates.map((action) {
                final isSelected = selected?.id == action.id;
                return ListTile(
                  leading: Icon(_getActionIcon(action.id), color: isSelected ? Theme.of(context).colorScheme.primary : null),
                  title: Text(action.label),
                  subtitle: Text(action.description, style: const TextStyle(fontSize: 12)),
                  selected: isSelected,
                  onTap: () => setDialogState(() => selected = action),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () {
                      setState(() {
                        _actions.add(_ActionEntry(
                          template: selected!,
                          params: {for (var p in selected!.params) p.key: p.defaultValue},
                        ));
                      });
                      Navigator.pop(ctx);
                    },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getActionIcon(String actionId) {
    switch (actionId) {
      case 'send_group_msg':
        return Icons.chat;
      case 'send_private_msg':
        return Icons.person;
      case 'mute_member':
        return Icons.mic_off;
      case 'unmute_member':
        return Icons.mic;
      case 'send_notice':
        return Icons.notifications;
      case 'send_group_image':
        return Icons.image;
      case 'leave_group':
        return Icons.exit_to_app;
      case 'log_msg':
        return Icons.article;
      default:
        return Icons.reply;
    }
  }

  void _generateCode() {
    if (_selectedEvent == null || _actions.isEmpty) return;
    final code = generateScriptCode(
      event: _selectedEvent!,
      actions: _actions.map((a) => a.template).toList(),
      eventParams: {},
      actionParamsList: _actions.map((a) => a.params).toList(),
      keywords: _keywords,
    );
    widget.onCodeGenerated(code);
  }
}

class _ActionEntry {
  final ActionTemplate template;
  final Map<String, String> params;
  _ActionEntry({required this.template, required this.params});
}
