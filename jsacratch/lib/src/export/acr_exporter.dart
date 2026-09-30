import '../models/script_file.dart';
import '../editor/block_templates.dart';

/// Export a single script as .acr format.
String exportAcr(ScriptFile script) {
  final buf = StringBuffer();
  buf.writeln('/// @acr-script');
  buf.writeln('/// @name ${script.name}');
  buf.writeln('/// @language javascript');
  buf.writeln('/// @generated-by jsacratch');
  buf.writeln();

  if (script.blocks.isNotEmpty) {
    buf.write(generateCodeFromBlocks(script.blocks));
  } else if (script.code.isNotEmpty) {
    buf.writeln(script.code);
  } else {
    buf.writeln('// Empty script');
  }

  return buf.toString();
}

/// Recursively generate JS from block tree.
String generateCodeFromBlocks(List<ScratchBlock> blocks) {
  final buf = StringBuffer();
  for (final b in blocks) {
    final t = blockTemplates.where((t) => t.id == b.templateId).firstOrNull;
    if (t == null) continue;
    if (t.isContainer) {
      buf.writeln(_buildContainerCode(t, b));
    } else {
      buf.writeln(t.codeBuilder(b.values));
    }
  }
  return buf.toString();
}

String _buildContainerCode(BlockTemplate t, ScratchBlock block) {
  final childCode = block.children.map((c) {
    final ct = blockTemplates.where((x) => x.id == c.templateId).firstOrNull;
    if (ct == null) return '';
    if (ct.isContainer) return _buildContainerCode(ct, c);
    return ct.codeBuilder(c.values);
  }).where((s) => s.isNotEmpty).join('\n');

  switch (t.id) {
    // Event containers - wrap children in event handler
    case 'on_private_msg':
      return "bot.on('private.message', async (ctx) => {\n$childCode\n});";
    case 'on_group_msg':
      return "bot.on('group.message', async (ctx) => {\n$childCode\n});";
    case 'on_member_join':
      return "bot.on('group.member.join', async (ctx) => {\n$childCode\n});";
    case 'on_member_leave':
      return "bot.on('group.member.leave', async (ctx) => {\n$childCode\n});";
    case 'on_member_mute':
      return "bot.on('group.member.mute', async (ctx) => {\n$childCode\n});";
    case 'on_group_disband':
      return "bot.on('group.disband', async (ctx) => {\n$childCode\n});";
    case 'on_start':
      if (childCode.isEmpty) return '// Bot started';
      return childCode;
    case 'on_schedule':
      final cron = block.values['cron'] ?? '0 * * * *';
      final name = block.values['schedule_name'] ?? '';
      if (name.isNotEmpty) {
        return "bot.schedule('$name', '$cron', async (ctx) => {\n$childCode\n});";
      }
      return "bot.schedule('$cron', async (ctx) => {\n$childCode\n});";
    case 'on_command':
      final cmd = block.values['command'] ?? '/';
      return "bot.command('$cmd', async (ctx) => {\n$childCode\n});";

    // Control flow containers
    case 'if_else':
      final cond = block.values['condition'] ?? 'true';
      final indent = _indentS(childCode);
      return "if ($cond) {\n$indent\n}";
    case 'repeat':
      final count = block.values['count'] ?? '10';
      final indent = _indentS(childCode);
      return "for (let _i = 0; _i < $count; _i++) {\n$indent\n}";
    case 'for_each':
      final list = block.values['list'] ?? 'items';
      final varName = block.values['var_name'] ?? 'item';
      final indent = _indentS(childCode);
      return "for (const $varName of $list) {\n$indent\n}";
    case 'while_loop':
      final cond = block.values['condition'] ?? 'true';
      final indent = _indentS(childCode);
      return "// STOP_CHECK: 最多1000次迭代\nlet __i = 0;\nwhile ($cond) {\n  if (++__i > 1000) break;\n$indent\n}";
    case 'try_catch':
      final indent = _indentS(childCode);
      final errVar = block.values['error_var'] ?? 'err';
      return "try {\n$indent\n} catch ($errVar) {\n  logger.error('${_escapeStr(block.label)} error', $errVar);\n}";

    default:
      return childCode.isEmpty ? t.codeBuilder(block.values) : t.codeBuilder(block.values);
  }
}

String _indentS(String code) {
  if (code.isEmpty) return '';
  return code.split('\n').map((l) => '  $l').join('\n');
}

String _escapeStr(String s) => s.replaceAll("'", "\\'").replaceAll('\n', '\\n');
