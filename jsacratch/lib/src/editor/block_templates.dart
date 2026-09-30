import 'package:flutter/material.dart';

enum BlockCategory { event, control, message, data, platform, utility, storage }

class BlockFieldTemplate {
  const BlockFieldTemplate({
    required this.key,
    required this.labelKey,
    required this.kind,
    this.defaultValue = '',
    this.options = const <String>[],
    this.placeholder = '',
  });

  final String key;
  final String labelKey;
  final BlockFieldKind kind;
  final String defaultValue;
  final List<String> options;
  final String placeholder;

  String localizedLabel(String Function(String) t) => t('field_$labelKey');
}

enum BlockFieldKind { text, number, select, multiline, code }

class BlockTemplate {
  const BlockTemplate({
    required this.id,
    required this.category,
    required this.color,
    required this.icon,
    required this.fields,
    required this.codeBuilder,
    this.isContainer = false,
    this.isHat = false,
  });

  final String id;
  final BlockCategory category;
  final Color color;
  final IconData icon;
  final List<BlockFieldTemplate> fields;
  final String Function(Map<String, String> values) codeBuilder;
  final bool isContainer;
  final bool isHat;

  String localizedTitle(String Function(String) t) => t('block_$id');
}

// =============================================
// Complete block templates covering all BOT_SCRIPT_JS_GUIDE.md APIs
// =============================================

final blockTemplates = <BlockTemplate>[
  // ===== EVENT (Hat blocks that contain children) =====
  BlockTemplate(
    id: 'on_private_msg',
    category: BlockCategory.event,
    color: const Color(0xFF4C97FF),
    icon: Icons.person,
    fields: [],
    codeBuilder: (_) => "bot.on('private.message', async (ctx) => {})",
    isContainer: true,
    isHat: true,
  ),
  BlockTemplate(
    id: 'on_group_msg',
    category: BlockCategory.event,
    color: const Color(0xFF4C97FF),
    icon: Icons.group,
    fields: [],
    codeBuilder: (_) => "bot.on('group.message', async (ctx) => {})",
    isContainer: true,
    isHat: true,
  ),
  BlockTemplate(
    id: 'on_member_join',
    category: BlockCategory.event,
    color: const Color(0xFF4C97FF),
    icon: Icons.person_add,
    fields: [],
    codeBuilder: (_) => "bot.on('group.member.join', async (ctx) => {})",
    isContainer: true,
    isHat: true,
  ),
  BlockTemplate(
    id: 'on_member_leave',
    category: BlockCategory.event,
    color: const Color(0xFF4C97FF),
    icon: Icons.person_remove,
    fields: [],
    codeBuilder: (_) => "bot.on('group.member.leave', async (ctx) => {})",
    isContainer: true,
    isHat: true,
  ),
  BlockTemplate(
    id: 'on_member_mute',
    category: BlockCategory.event,
    color: const Color(0xFF4C97FF),
    icon: Icons.volume_off,
    fields: [],
    codeBuilder: (_) => "bot.on('group.member.mute', async (ctx) => {})",
    isContainer: true,
    isHat: true,
  ),
  BlockTemplate(
    id: 'on_group_disband',
    category: BlockCategory.event,
    color: const Color(0xFF4C97FF),
    icon: Icons.group_remove,
    fields: [],
    codeBuilder: (_) => "bot.on('group.disband', async (ctx) => {})",
    isContainer: true,
    isHat: true,
  ),
  BlockTemplate(
    id: 'on_start',
    category: BlockCategory.event,
    color: const Color(0xFF4C97FF),
    icon: Icons.play_arrow,
    fields: [],
    codeBuilder: (_) => '// Bot started',
    isContainer: true,
    isHat: true,
  ),
  BlockTemplate(
    id: 'on_schedule',
    category: BlockCategory.event,
    color: const Color(0xFF4C97FF),
    icon: Icons.schedule,
    fields: [
      BlockFieldTemplate(key: 'schedule_name', labelKey: 'schedule_name', kind: BlockFieldKind.text, defaultValue: ''),
      BlockFieldTemplate(key: 'cron', labelKey: 'cron', kind: BlockFieldKind.text, defaultValue: '0 9 * * *'),
    ],
    codeBuilder: (_) => "bot.schedule('0 9 * * *', async (ctx) => {})",
    isContainer: true,
    isHat: true,
  ),
  BlockTemplate(
    id: 'on_command',
    category: BlockCategory.event,
    color: const Color(0xFF4C97FF),
    icon: Icons.terminal,
    fields: [
      BlockFieldTemplate(key: 'command', labelKey: 'command', kind: BlockFieldKind.text, defaultValue: '/'),
    ],
    codeBuilder: (v) => "bot.command('${v['command']}', async (ctx) => {})",
    isContainer: true,
    isHat: true,
  ),

  // ===== CONTROL (C-shaped container blocks) =====
  BlockTemplate(
    id: 'if_else',
    category: BlockCategory.control,
    color: const Color(0xFFCF8B17),
    icon: Icons.call_split,
    fields: [
      BlockFieldTemplate(key: 'condition', labelKey: 'condition', kind: BlockFieldKind.text, defaultValue: 'true'),
    ],
    codeBuilder: (_) => 'if (true) {}',
    isContainer: true,
  ),
  BlockTemplate(
    id: 'repeat',
    category: BlockCategory.control,
    color: const Color(0xFFCF8B17),
    icon: Icons.loop,
    fields: [
      BlockFieldTemplate(key: 'count', labelKey: 'count', kind: BlockFieldKind.number, defaultValue: '10'),
    ],
    codeBuilder: (_) => 'for (let _i = 0; _i < 10; _i++) {}',
    isContainer: true,
  ),
  BlockTemplate(
    id: 'for_each',
    category: BlockCategory.control,
    color: const Color(0xFFCF8B17),
    icon: Icons.list,
    fields: [
      BlockFieldTemplate(key: 'var_name', labelKey: 'var_name', kind: BlockFieldKind.text, defaultValue: 'item'),
      BlockFieldTemplate(key: 'list', labelKey: 'list', kind: BlockFieldKind.text, defaultValue: 'items'),
    ],
    codeBuilder: (v) => "for (const ${v['var_name']} of ${v['list']}) {}",
    isContainer: true,
  ),
  BlockTemplate(
    id: 'while_loop',
    category: BlockCategory.control,
    color: const Color(0xFFCF8B17),
    icon: Icons.sync,
    fields: [
      BlockFieldTemplate(key: 'condition', labelKey: 'condition', kind: BlockFieldKind.text, defaultValue: 'true'),
    ],
    codeBuilder: (_) => 'while (true) { /* max 1000 iterations */ }',
    isContainer: true,
  ),
  BlockTemplate(
    id: 'try_catch',
    category: BlockCategory.control,
    color: const Color(0xFFCF8B17),
    icon: Icons.error_outline,
    fields: [
      BlockFieldTemplate(key: 'error_var', labelKey: 'error_var', kind: BlockFieldKind.text, defaultValue: 'err'),
    ],
    codeBuilder: (_) => 'try {} catch (err) {}',
    isContainer: true,
  ),
  BlockTemplate(
    id: 'wait',
    category: BlockCategory.control,
    color: const Color(0xFFCF8B17),
    icon: Icons.timer,
    fields: [
      BlockFieldTemplate(key: 'ms', labelKey: 'ms', kind: BlockFieldKind.number, defaultValue: '1000'),
    ],
    codeBuilder: (v) => "await new Promise(r => setTimeout(r, ${v['ms']}));",
  ),

  // ===== MESSAGE =====
  BlockTemplate(
    id: 'reply_text',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.reply,
    fields: [
      BlockFieldTemplate(key: 'content', labelKey: 'content', kind: BlockFieldKind.multiline, defaultValue: 'Hello!'),
    ],
    codeBuilder: (v) => "await ctx.reply('${_escapeStr(v['content'] ?? '')}');",
  ),
  BlockTemplate(
    id: 'reply_image',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.image,
    fields: [
      BlockFieldTemplate(key: 'url', labelKey: 'image_url', kind: BlockFieldKind.text, defaultValue: 'https://'),
    ],
    codeBuilder: (v) => "await ctx.reply({ images: ['${v['url']}'] });",
  ),
  BlockTemplate(
    id: 'reply_object',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.chat,
    fields: [
      BlockFieldTemplate(key: 'content', labelKey: 'content', kind: BlockFieldKind.multiline, defaultValue: ''),
      BlockFieldTemplate(key: 'image_url', labelKey: 'image_url', kind: BlockFieldKind.text, defaultValue: ''),
    ],
    codeBuilder: (v) {
      final parts = <String>[];
      if ((v['content'] ?? '').isNotEmpty) parts.add("text: '${_escapeStr(v['content']!)}'");
      if ((v['image_url'] ?? '').isNotEmpty) parts.add("images: ['${v['image_url']}']");
      return "await ctx.reply({ ${parts.join(', ')} });";
    },
  ),
  BlockTemplate(
    id: 'send_text',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.send,
    fields: [
      BlockFieldTemplate(key: 'content', labelKey: 'content', kind: BlockFieldKind.multiline, defaultValue: ''),
    ],
    codeBuilder: (v) => "await ctx.send('${_escapeStr(v['content'] ?? '')}');",
  ),
  BlockTemplate(
    id: 'send_notice',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.notifications,
    fields: [
      BlockFieldTemplate(key: 'title', labelKey: 'title', kind: BlockFieldKind.text, defaultValue: '通知'),
      BlockFieldTemplate(key: 'content', labelKey: 'content', kind: BlockFieldKind.multiline, defaultValue: ''),
    ],
    codeBuilder: (v) => "await ctx.notice('${_escapeStr(v['title'] ?? '')}', '${_escapeStr(v['content'] ?? '')}');",
  ),
  // Private message operations
  BlockTemplate(
    id: 'private_msg',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.person,
    fields: [
      BlockFieldTemplate(key: 'uid', labelKey: 'uid', kind: BlockFieldKind.number, defaultValue: ''),
      BlockFieldTemplate(key: 'content', labelKey: 'content', kind: BlockFieldKind.multiline, defaultValue: ''),
    ],
    codeBuilder: (v) => "await csac.private.sendMessage(${v['uid']}, '${_escapeStr(v['content'] ?? '')}');",
  ),
  BlockTemplate(
    id: 'private_image',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.photo,
    fields: [
      BlockFieldTemplate(key: 'uid', labelKey: 'uid', kind: BlockFieldKind.number, defaultValue: ''),
      BlockFieldTemplate(key: 'url', labelKey: 'image_url', kind: BlockFieldKind.text, defaultValue: 'https://'),
    ],
    codeBuilder: (v) => "await csac.private.sendImage(${v['uid']}, '${v['url']}');",
  ),
  BlockTemplate(
    id: 'private_recall',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.undo,
    fields: [
      BlockFieldTemplate(key: 'uid', labelKey: 'uid', kind: BlockFieldKind.number, defaultValue: ''),
      BlockFieldTemplate(key: 'msg_id', labelKey: 'msg_id', kind: BlockFieldKind.number, defaultValue: ''),
    ],
    codeBuilder: (v) => "await csac.private.recallMessage(${v['uid']}, ${v['msg_id']});",
  ),
  // Group operations
  BlockTemplate(
    id: 'group_msg',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.groups,
    fields: [
      BlockFieldTemplate(key: 'gid', labelKey: 'group_id', kind: BlockFieldKind.number, defaultValue: '0'),
      BlockFieldTemplate(key: 'content', labelKey: 'content', kind: BlockFieldKind.multiline, defaultValue: ''),
    ],
    codeBuilder: (v) => "await csac.group.sendMessage(${v['gid']}, '${_escapeStr(v['content'] ?? '')}');",
  ),
  BlockTemplate(
    id: 'group_image',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.photo_library,
    fields: [
      BlockFieldTemplate(key: 'gid', labelKey: 'group_id', kind: BlockFieldKind.number, defaultValue: '0'),
      BlockFieldTemplate(key: 'url', labelKey: 'image_url', kind: BlockFieldKind.text, defaultValue: 'https://'),
    ],
    codeBuilder: (v) => "await csac.group.sendImage(${v['gid']}, '${v['url']}');",
  ),
  BlockTemplate(
    id: 'group_recall',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.undo,
    fields: [
      BlockFieldTemplate(key: 'gid', labelKey: 'group_id', kind: BlockFieldKind.number, defaultValue: '0'),
      BlockFieldTemplate(key: 'msg_id', labelKey: 'msg_id', kind: BlockFieldKind.number, defaultValue: ''),
    ],
    codeBuilder: (v) => "await csac.group.recallMessage(${v['gid']}, ${v['msg_id']});",
  ),
  BlockTemplate(
    id: 'group_mute_member',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.volume_off,
    fields: [
      BlockFieldTemplate(key: 'gid', labelKey: 'group_id', kind: BlockFieldKind.number, defaultValue: '0'),
      BlockFieldTemplate(key: 'uid', labelKey: 'uid', kind: BlockFieldKind.number, defaultValue: ''),
      BlockFieldTemplate(key: 'seconds', labelKey: 'seconds', kind: BlockFieldKind.number, defaultValue: '60'),
    ],
    codeBuilder: (v) => "await csac.group.muteMember(${v['gid']}, ${v['uid']}, ${v['seconds']});",
  ),
  BlockTemplate(
    id: 'group_unmute',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.volume_up,
    fields: [
      BlockFieldTemplate(key: 'gid', labelKey: 'group_id', kind: BlockFieldKind.number, defaultValue: '0'),
      BlockFieldTemplate(key: 'uid', labelKey: 'uid', kind: BlockFieldKind.number, defaultValue: ''),
    ],
    codeBuilder: (v) => "await csac.group.unmuteMember(${v['gid']}, ${v['uid']});",
  ),
  BlockTemplate(
    id: 'group_essence',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.star,
    fields: [
      BlockFieldTemplate(key: 'gid', labelKey: 'group_id', kind: BlockFieldKind.number, defaultValue: '0'),
      BlockFieldTemplate(key: 'msg_id', labelKey: 'msg_id', kind: BlockFieldKind.number, defaultValue: ''),
      BlockFieldTemplate(key: 'set', labelKey: 'set_essence', kind: BlockFieldKind.select, options: ['set', 'unset']),
    ],
    codeBuilder: (v) {
      if (v['set'] == 'unset') return "await csac.group.unsetEssence(${v['gid']}, ${v['msg_id']});";
      return "await csac.group.setEssence(${v['gid']}, ${v['msg_id']});";
    },
  ),
  BlockTemplate(
    id: 'group_leave',
    category: BlockCategory.message,
    color: const Color(0xFF9966FF),
    icon: Icons.exit_to_app,
    fields: [
      BlockFieldTemplate(key: 'gid', labelKey: 'group_id', kind: BlockFieldKind.number, defaultValue: '0'),
    ],
    codeBuilder: (v) => "await csac.group.leave(${v['gid']});",
  ),

  // ===== DATA =====
  BlockTemplate(
    id: 'set_var',
    category: BlockCategory.data,
    color: const Color(0xFFFF8C1A),
    icon: Icons.edit,
    fields: [
      BlockFieldTemplate(key: 'name', labelKey: 'name', kind: BlockFieldKind.text, defaultValue: 'myVar'),
      BlockFieldTemplate(key: 'value', labelKey: 'value', kind: BlockFieldKind.text, defaultValue: '0'),
    ],
    codeBuilder: (v) => "let ${v['name']} = ${v['value']};",
  ),
  BlockTemplate(
    id: 'get_var',
    category: BlockCategory.data,
    color: const Color(0xFFFF8C1A),
    icon: Icons.data_object,
    fields: [
      BlockFieldTemplate(key: 'name', labelKey: 'name', kind: BlockFieldKind.text, defaultValue: 'myVar'),
    ],
    codeBuilder: (v) => v['name'] ?? 'undefined',
  ),
  BlockTemplate(
    id: 'set_list',
    category: BlockCategory.data,
    color: const Color(0xFFFF8C1A),
    icon: Icons.list,
    fields: [
      BlockFieldTemplate(key: 'name', labelKey: 'name', kind: BlockFieldKind.text, defaultValue: 'myList'),
      BlockFieldTemplate(key: 'items', labelKey: 'items', kind: BlockFieldKind.text, defaultValue: '1, 2, 3'),
    ],
    codeBuilder: (v) => "const ${v['name']} = [${v['items']}];",
  ),
  BlockTemplate(
    id: 'set_object',
    category: BlockCategory.data,
    color: const Color(0xFFFF8C1A),
    icon: Icons.data_object,
    fields: [
      BlockFieldTemplate(key: 'name', labelKey: 'name', kind: BlockFieldKind.text, defaultValue: 'myObj'),
      BlockFieldTemplate(key: 'fields', labelKey: 'fields', kind: BlockFieldKind.multiline, defaultValue: 'key: "value"'),
    ],
    codeBuilder: (v) => "const ${v['name']} = { ${v['fields']} };",
  ),
  BlockTemplate(
    id: 'http_get',
    category: BlockCategory.data,
    color: const Color(0xFFFF8C1A),
    icon: Icons.http,
    fields: [
      BlockFieldTemplate(key: 'url', labelKey: 'url', kind: BlockFieldKind.text, defaultValue: 'https://'),
    ],
    codeBuilder: (v) => "const _res = await csac.http.get('${v['url']}');",
  ),
  BlockTemplate(
    id: 'http_post',
    category: BlockCategory.data,
    color: const Color(0xFFFF8C1A),
    icon: Icons.cloud_upload,
    fields: [
      BlockFieldTemplate(key: 'url', labelKey: 'url', kind: BlockFieldKind.text, defaultValue: 'https://'),
      BlockFieldTemplate(key: 'body', labelKey: 'body', kind: BlockFieldKind.multiline, defaultValue: '{}'),
    ],
    codeBuilder: (v) => "const _res = await csac.http.post('${v['url']}', { json: ${v['body']} });",
  ),
  BlockTemplate(
    id: 'json_parse',
    category: BlockCategory.data,
    color: const Color(0xFFFF8C1A),
    icon: Icons.code,
    fields: [
      BlockFieldTemplate(key: 'var_name', labelKey: 'name', kind: BlockFieldKind.text, defaultValue: 'data'),
      BlockFieldTemplate(key: 'source', labelKey: 'source', kind: BlockFieldKind.text, defaultValue: '_res.body'),
    ],
    codeBuilder: (v) => "const ${v['var_name']} = JSON.parse(${v['source']});",
  ),
  BlockTemplate(
    id: 'json_stringify',
    category: BlockCategory.data,
    color: const Color(0xFFFF8C1A),
    icon: Icons.data_array,
    fields: [
      BlockFieldTemplate(key: 'var_name', labelKey: 'name', kind: BlockFieldKind.text, defaultValue: 'jsonStr'),
      BlockFieldTemplate(key: 'value', labelKey: 'value', kind: BlockFieldKind.text, defaultValue: 'myObj'),
    ],
    codeBuilder: (v) => "const ${v['var_name']} = JSON.stringify(${v['value']});",
  ),
  BlockTemplate(
    id: 'math_op',
    category: BlockCategory.data,
    color: const Color(0xFFFF8C1A),
    icon: Icons.calculate,
    fields: [
      BlockFieldTemplate(key: 'var_name', labelKey: 'name', kind: BlockFieldKind.text, defaultValue: 'result'),
      BlockFieldTemplate(key: 'expr', labelKey: 'expression', kind: BlockFieldKind.text, defaultValue: '1 + 2'),
    ],
    codeBuilder: (v) => "const ${v['var_name']} = ${v['expr']};",
  ),

  // ===== STORAGE =====
  BlockTemplate(
    id: 'storage_set',
    category: BlockCategory.storage,
    color: const Color(0xFF0FBD8C),
    icon: Icons.save,
    fields: [
      BlockFieldTemplate(key: 'key', labelKey: 'key', kind: BlockFieldKind.text, defaultValue: 'myKey'),
      BlockFieldTemplate(key: 'value', labelKey: 'value', kind: BlockFieldKind.text, defaultValue: '0'),
    ],
    codeBuilder: (v) => "await csac.storage.set('${v['key']}', ${v['value']});",
  ),
  BlockTemplate(
    id: 'storage_get',
    category: BlockCategory.storage,
    color: const Color(0xFF0FBD8C),
    icon: Icons.folder_open,
    fields: [
      BlockFieldTemplate(key: 'key', labelKey: 'key', kind: BlockFieldKind.text, defaultValue: 'myKey'),
      BlockFieldTemplate(key: 'var_name', labelKey: 'name', kind: BlockFieldKind.text, defaultValue: 'stored'),
      BlockFieldTemplate(key: 'default_val', labelKey: 'default_value', kind: BlockFieldKind.text, defaultValue: 'null'),
    ],
    codeBuilder: (v) => "const ${v['var_name']} = await csac.storage.get('${v['key']}', ${v['default_val']});",
  ),
  BlockTemplate(
    id: 'storage_delete',
    category: BlockCategory.storage,
    color: const Color(0xFF0FBD8C),
    icon: Icons.delete_outline,
    fields: [
      BlockFieldTemplate(key: 'key', labelKey: 'key', kind: BlockFieldKind.text, defaultValue: 'myKey'),
    ],
    codeBuilder: (v) => "await csac.storage.delete('${v['key']}');",
  ),
  BlockTemplate(
    id: 'storage_increment',
    category: BlockCategory.storage,
    color: const Color(0xFF0FBD8C),
    icon: Icons.plus_one,
    fields: [
      BlockFieldTemplate(key: 'key', labelKey: 'key', kind: BlockFieldKind.text, defaultValue: 'counter'),
      BlockFieldTemplate(key: 'step', labelKey: 'step', kind: BlockFieldKind.number, defaultValue: '1'),
    ],
    codeBuilder: (v) => "await csac.storage.increment('${v['key']}', ${v['step']});",
  ),

  // ===== PLATFORM =====
  BlockTemplate(
    id: 'user_info',
    category: BlockCategory.platform,
    color: const Color(0xFF40BF4A),
    icon: Icons.person_search,
    fields: [
      BlockFieldTemplate(key: 'uid', labelKey: 'uid', kind: BlockFieldKind.number, defaultValue: '0'),
    ],
    codeBuilder: (v) => "const _user = await csac.user.get(${v['uid']});",
  ),
  BlockTemplate(
    id: 'group_info',
    category: BlockCategory.platform,
    color: const Color(0xFF40BF4A),
    icon: Icons.info,
    fields: [
      BlockFieldTemplate(key: 'gid', labelKey: 'group_id', kind: BlockFieldKind.number, defaultValue: '0'),
    ],
    codeBuilder: (v) => "const _group = await csac.groupInfo.get(${v['gid']});",
  ),
  BlockTemplate(
    id: 'group_member_count',
    category: BlockCategory.platform,
    color: const Color(0xFF40BF4A),
    icon: Icons.people,
    fields: [
      BlockFieldTemplate(key: 'gid', labelKey: 'group_id', kind: BlockFieldKind.number, defaultValue: '0'),
    ],
    codeBuilder: (v) => "const _memberCount = await csac.groupInfo.memberCount(${v['gid']});",
  ),
  BlockTemplate(
    id: 'group_has_member',
    category: BlockCategory.platform,
    color: const Color(0xFF40BF4A),
    icon: Icons.person_search,
    fields: [
      BlockFieldTemplate(key: 'gid', labelKey: 'group_id', kind: BlockFieldKind.number, defaultValue: '0'),
      BlockFieldTemplate(key: 'uid', labelKey: 'uid', kind: BlockFieldKind.number, defaultValue: ''),
    ],
    codeBuilder: (v) => "const _hasMember = await csac.groupInfo.hasMember(${v['gid']}, ${v['uid']});",
  ),
  BlockTemplate(
    id: 'bot_permissions',
    category: BlockCategory.platform,
    color: const Color(0xFF40BF4A),
    icon: Icons.admin_panel_settings,
    fields: [
      BlockFieldTemplate(key: 'gid', labelKey: 'group_id', kind: BlockFieldKind.number, defaultValue: '0'),
    ],
    codeBuilder: (v) => "const _pms = await csac.groupInfo.botPermissions(${v['gid']});",
  ),
  BlockTemplate(
    id: 'platform_notice',
    category: BlockCategory.platform,
    color: const Color(0xFF40BF4A),
    icon: Icons.notification_add,
    fields: [
      BlockFieldTemplate(key: 'uid', labelKey: 'uid', kind: BlockFieldKind.number, defaultValue: ''),
      BlockFieldTemplate(key: 'title', labelKey: 'title', kind: BlockFieldKind.text, defaultValue: '通知'),
      BlockFieldTemplate(key: 'content', labelKey: 'content', kind: BlockFieldKind.multiline, defaultValue: ''),
    ],
    codeBuilder: (v) => "await csac.notice.send(${v['uid']}, '${_escapeStr(v['title'] ?? '')}', '${_escapeStr(v['content'] ?? '')}');",
  ),

  // ===== UTILITY =====
  BlockTemplate(
    id: 'log_info',
    category: BlockCategory.utility,
    color: const Color(0xFF8B8B8B),
    icon: Icons.terminal,
    fields: [
      BlockFieldTemplate(key: 'text', labelKey: 'text', kind: BlockFieldKind.multiline, defaultValue: 'log message'),
    ],
    codeBuilder: (v) => "logger.info('${_escapeStr(v['text'] ?? '')}');",
  ),
  BlockTemplate(
    id: 'log_warn',
    category: BlockCategory.utility,
    color: const Color(0xFFE6A817),
    icon: Icons.warning,
    fields: [
      BlockFieldTemplate(key: 'text', labelKey: 'text', kind: BlockFieldKind.multiline, defaultValue: 'warning'),
    ],
    codeBuilder: (v) => "logger.warn('${_escapeStr(v['text'] ?? '')}');",
  ),
  BlockTemplate(
    id: 'log_error',
    category: BlockCategory.utility,
    color: const Color(0xFFE53935),
    icon: Icons.error,
    fields: [
      BlockFieldTemplate(key: 'text', labelKey: 'text', kind: BlockFieldKind.multiline, defaultValue: 'error'),
    ],
    codeBuilder: (v) => "logger.error('${_escapeStr(v['text'] ?? '')}');",
  ),
  BlockTemplate(
    id: 'comment',
    category: BlockCategory.utility,
    color: const Color(0xFFA8A8A8),
    icon: Icons.comment,
    fields: [
      BlockFieldTemplate(key: 'text', labelKey: 'text', kind: BlockFieldKind.multiline, defaultValue: ''),
    ],
    codeBuilder: (v) => "// ${v['text']}",
  ),
  BlockTemplate(
    id: 'js_raw',
    category: BlockCategory.utility,
    color: const Color(0xFF6C6C6C),
    icon: Icons.javascript,
    fields: [
      BlockFieldTemplate(key: 'code', labelKey: 'code', kind: BlockFieldKind.multiline, defaultValue: '// JS code'),
    ],
    codeBuilder: (v) => v['code'] ?? '// JS code',
  ),
];

String _escapeStr(String s) => s.replaceAll("'", "\\'").replaceAll('\n', '\\n');

List<BlockTemplate> blocksByCategory(BlockCategory category) {
  return blockTemplates.where((b) => b.category == category).toList();
}
