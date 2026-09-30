import 'dart:ui' show Color;
import '../models/script_file.dart';
import 'block_templates.dart';

/// Converts BotJS code into a list of [ScratchBlock].
/// Recognized patterns become matching blocks; unmatched code becomes [js_raw] blocks.
class JsToBlocksConverter {
  static int _blockCounter = 0;
  static String _nextId(String prefix) => '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${++_blockCounter}';

  /// Parse JS code string into blocks. Returns null if no blocks could be made.
  static List<ScratchBlock>? convert(String code, String Function(String) tr) {
    if (code.trim().isEmpty) return null;
    _blockCounter = 0;

    final blocks = <ScratchBlock>[];
    final lines = code.split('\n');
    int i = 0;

    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('//') || line == '/// @acr-script' || line.startsWith('/// @')) {
        i++;
        continue;
      }

      // Try to match a container block (event handler / control flow)
      final container = _tryMatchContainer(lines, i, tr);
      if (container != null) {
        blocks.add(container.block);
        i = container.nextIndex;
        continue;
      }

      // Try to match a single-line block
      final single = _tryMatchSingle(line, tr);
      if (single != null) {
        blocks.add(single);
        i++;
        continue;
      }

      // Collect contiguous unrecognized lines into one js_raw block
      final rawLines = <String>[line];
      i++;
      while (i < lines.length) {
        final nl = lines[i].trim();
        if (nl.isEmpty || nl.startsWith('//') || nl.startsWith('/// @')) {
          i++;
          break;
        }
        if (_tryMatchSingle(nl, tr) != null || _tryMatchContainer(lines, i, tr) != null) break;
        rawLines.add(lines[i]);
        i++;
      }
      blocks.add(_makeBlock('js_raw', 'utility', const Color(0xFF6C6C6C), tr,
          {'code': rawLines.join('\n')}));
    }

    return blocks.isEmpty ? null : blocks;
  }

  // ==================== Container pattern matching ====================

  static _MatchResult? _tryMatchContainer(List<String> lines, int start, String Function(String) tr) {
    final line = lines[start].trim();
    if (line.isEmpty) return null;

    // --- Event: bot.on('xxx', async (ctx) => { ---
    final eventMatch = RegExp(r"bot\.on\('([^']+)',\s*async\s*\(ctx\)\s*=>\s*\{").firstMatch(line);
    if (eventMatch != null) {
      String eventId;
      switch (eventMatch.group(1)!) {
        case 'private.message': eventId = 'on_private_msg'; break;
        case 'group.message': eventId = 'on_group_msg'; break;
        case 'group.member.join': eventId = 'on_member_join'; break;
        case 'group.member.leave': eventId = 'on_member_leave'; break;
        case 'group.member.mute': eventId = 'on_member_mute'; break;
        case 'group.disband': eventId = 'on_group_disband'; break;
        default: return null; // unknown event
      }
      final block = _makeBlock(eventId, 'event', const Color(0xFF4C97FF), tr, {});
      final consumed = _consumeBody(lines, start, '{', '}');
      if (consumed != null) {
        final childBlocks = _convertBody(consumed.bodyLines, tr);
        block.children.addAll(childBlocks);
        return _MatchResult(block, consumed.nextIndex);
      }
      return _MatchResult(block, start + 1);
    }

    // --- bot.schedule ---
    final scheduleMatch1 = RegExp(r"bot\.schedule\('([^']+)',\s*'([^']+)',\s*async\s*\(ctx\)\s*=>\s*\{").firstMatch(line);
    if (scheduleMatch1 != null) {
      final block = _makeBlock('on_schedule', 'event', const Color(0xFF4C97FF), tr, {
        'schedule_name': scheduleMatch1.group(1)!,
        'cron': scheduleMatch1.group(2)!,
      });
      final consumed = _consumeBody(lines, start, '{', '}');
      if (consumed != null) {
        block.children.addAll(_convertBody(consumed.bodyLines, tr));
        return _MatchResult(block, consumed.nextIndex);
      }
      return _MatchResult(block, start + 1);
    }
    final scheduleMatch2 = RegExp(r"bot\.schedule\('([^']+)',\s*async\s*\(ctx\)\s*=>\s*\{").firstMatch(line);
    if (scheduleMatch2 != null) {
      final block = _makeBlock('on_schedule', 'event', const Color(0xFF4C97FF), tr, {
        'schedule_name': '',
        'cron': scheduleMatch2.group(1)!,
      });
      final consumed = _consumeBody(lines, start, '{', '}');
      if (consumed != null) {
        block.children.addAll(_convertBody(consumed.bodyLines, tr));
        return _MatchResult(block, consumed.nextIndex);
      }
      return _MatchResult(block, start + 1);
    }

    // --- bot.command ---
    final cmdMatch = RegExp(r"bot\.command\('([^']+)',\s*async\s*\(ctx\)\s*=>\s*\{").firstMatch(line);
    if (cmdMatch != null) {
      final block = _makeBlock('on_command', 'event', const Color(0xFF4C97FF), tr, {
        'command': cmdMatch.group(1)!,
      });
      final consumed = _consumeBody(lines, start, '{', '}');
      if (consumed != null) {
        block.children.addAll(_convertBody(consumed.bodyLines, tr));
        return _MatchResult(block, consumed.nextIndex);
      }
      return _MatchResult(block, start + 1);
    }

    // --- if (...) { ---
    final ifMatch = RegExp(r'if\s*\((.+)\)\s*\{').firstMatch(line);
    if (ifMatch != null) {
      final block = _makeBlock('if_else', 'control', const Color(0xFFCF8B17), tr, {
        'condition': ifMatch.group(1)!.trim(),
      });
      final consumed = _consumeBody(lines, start, '{', '}');
      if (consumed != null) {
        // Check for "else {" on next line
        int elseStart = consumed.nextIndex;
        if (elseStart < lines.length) {
          final elseLine = lines[elseStart].trim();
          if (elseLine.startsWith('else') && elseLine.contains('{')) {
            // Skip else, capture else body
            final elseBody = _consumeBody(lines, elseStart, '{', '}');
            if (elseBody != null) {
              final elseChildBlocks = _convertBody(elseBody.bodyLines, tr);
              block.children.addAll([
                ..._convertBody(_stripOneIndent(consumed.bodyLines), tr),
                // Wrap else body in a comment block or js_raw
                ScratchBlock(
                  id: _nextId('else'),
                  templateId: 'js_raw',
                  category: 'utility',
                  color: const Color(0xFF6C6C6C),
                  label: '否则',
                  values: {'code': elseBody.bodyLines.join('\n')},
                  children: elseChildBlocks,
                ),
              ]);
              return _MatchResult(block, elseBody.nextIndex);
            }
          }
        }
        block.children.addAll(_convertBody(_stripOneIndent(consumed.bodyLines), tr));
        return _MatchResult(block, consumed.nextIndex);
      }
      return _MatchResult(block, start + 1);
    }

    // --- for (let _i = ...) --- (repeat block)
    final repeatMatch = RegExp(r"for\s*\(\s*let\s+_i\s*=\s*0\s*;\s*_i\s*<\s*(\d+)\s*;\s*_i\+\+\s*\)\s*\{").firstMatch(line);
    if (repeatMatch != null) {
      final block = _makeBlock('repeat', 'control', const Color(0xFFCF8B17), tr, {
        'count': repeatMatch.group(1)!,
      });
      final consumed = _consumeBody(lines, start, '{', '}');
      if (consumed != null) {
        block.children.addAll(_convertBody(_stripOneIndent(consumed.bodyLines), tr));
        return _MatchResult(block, consumed.nextIndex);
      }
      return _MatchResult(block, start + 1);
    }

    // --- for (const var of list) --- (for_each block)
    final forEachMatch = RegExp(r"for\s*\(\s*(?:const|let)\s+(\w+)\s+of\s+(.+)\)\s*\{").firstMatch(line);
    if (forEachMatch != null) {
      final block = _makeBlock('for_each', 'control', const Color(0xFFCF8B17), tr, {
        'var_name': forEachMatch.group(1)!,
        'list': forEachMatch.group(2)!.trim(),
      });
      final consumed = _consumeBody(lines, start, '{', '}');
      if (consumed != null) {
        block.children.addAll(_convertBody(_stripOneIndent(consumed.bodyLines), tr));
        return _MatchResult(block, consumed.nextIndex);
      }
      return _MatchResult(block, start + 1);
    }

    // --- while (...) { ---
    final whileMatch = RegExp(r'while\s*\((.+)\)\s*\{').firstMatch(line);
    if (whileMatch != null) {
      final block = _makeBlock('while_loop', 'control', const Color(0xFFCF8B17), tr, {
        'condition': whileMatch.group(1)!.trim(),
      });
      final consumed = _consumeBody(lines, start, '{', '}');
      if (consumed != null) {
        block.children.addAll(_convertBody(_stripOneIndent(consumed.bodyLines), tr));
        return _MatchResult(block, consumed.nextIndex);
      }
      return _MatchResult(block, start + 1);
    }

    // --- try { ---
    final tryMatch = RegExp(r'try\s*\{').firstMatch(line);
    if (tryMatch != null) {
      final tryConsumed = _consumeBody(lines, start, '{', '}');
      String errorVar = 'err';
      List<String> catchLines = [];
      int nextIdx = tryConsumed?.nextIndex ?? start + 1;

      if (tryConsumed != null && nextIdx < lines.length) {
        final catchMatch = RegExp(r'catch\s*\((\w*)\)\s*\{').firstMatch(lines[nextIdx].trim());
        if (catchMatch != null) {
          errorVar = catchMatch.group(1)?.isNotEmpty == true ? catchMatch.group(1)! : 'err';
          final catchConsumed = _consumeBody(lines, nextIdx, '{', '}');
          if (catchConsumed != null) {
            catchLines = catchConsumed.bodyLines;
            nextIdx = catchConsumed.nextIndex;
          }
        }
      }
      final block = _makeBlock('try_catch', 'control', const Color(0xFFCF8B17), tr, {
        'error_var': errorVar,
      });
      if (tryConsumed != null) {
        final tryBlocks = _convertBody(_stripOneIndent(tryConsumed.bodyLines), tr);
        block.children.addAll(tryBlocks);
        if (catchLines.isNotEmpty) {
          block.children.add(ScratchBlock(
            id: _nextId('catch'),
            templateId: 'js_raw',
            category: 'utility',
            color: const Color(0xFF6C6C6C),
            label: 'catch ($errorVar)',
            values: {'code': catchLines.join('\n')},
          ));
        }
      }
      return _MatchResult(block, nextIdx);
    }

    return null;
  }

  // ==================== Single-line pattern matching ====================

  static ScratchBlock? _tryMatchSingle(String line, String Function(String) tr) {
    if (line.endsWith(';')) line = line.substring(0, line.length - 1).trim();
    if (line.isEmpty || line == '{}') return null;

    // await ctx.reply('text')
    var m = RegExp(r"await\s+ctx\.reply\('([^']*)'\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('reply_text', 'message', const Color(0xFF9966FF), tr, {'content': _unescapeStr(m.group(1)!)});
    }

    // await ctx.reply({ images: ['url'] })
    m = RegExp(r"await\s+ctx\.reply\(\{\s*images:\s*\['([^']*)'\]\s*\}\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('reply_image', 'message', const Color(0xFF9966FF), tr, {'url': m.group(1)!});
    }

    // await ctx.reply({ text: '...', images: [...] })
    m = RegExp(r"await\s+ctx\.reply\(\{\s*text:\s*'([^']*)'(?:\s*,\s*images:\s*\['([^']*)'\])?\s*\}\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('reply_object', 'message', const Color(0xFF9966FF), tr, {
        'content': _unescapeStr(m.group(1) ?? ''),
        'image_url': m.group(2) ?? '',
      });
    }

    // await ctx.send('text')
    m = RegExp(r"await\s+ctx\.send\('([^']*)'\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('send_text', 'message', const Color(0xFF9966FF), tr, {'content': _unescapeStr(m.group(1)!)});
    }

    // await ctx.notice('title', 'content')
    m = RegExp(r"await\s+ctx\.notice\('([^']*)',\s*'([^']*)'\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('send_notice', 'message', const Color(0xFF9966FF), tr, {
        'title': _unescapeStr(m.group(1)!),
        'content': _unescapeStr(m.group(2)!),
      });
    }

    // await csac.private.sendMessage(uid, 'text')
    m = RegExp(r"await\s+csac\.private\.sendMessage\((\S+),\s*'([^']*)'\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('private_msg', 'message', const Color(0xFF9966FF), tr, {
        'uid': m.group(1)!, 'content': _unescapeStr(m.group(2)!),
      });
    }

    // await csac.private.sendImage(uid, 'url')
    m = RegExp(r"await\s+csac\.private\.sendImage\((\S+),\s*'([^']*)'\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('private_image', 'message', const Color(0xFF9966FF), tr, {
        'uid': m.group(1)!, 'url': m.group(2)!,
      });
    }

    // await csac.private.recallMessage(uid, msg_id)
    m = RegExp(r"await\s+csac\.private\.recallMessage\((\S+),\s*(\S+)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('private_recall', 'message', const Color(0xFF9966FF), tr, {
        'uid': m.group(1)!, 'msg_id': m.group(2)!,
      });
    }

    // await csac.group.sendMessage(gid, 'text')
    m = RegExp(r"await\s+csac\.group\.sendMessage\((\S+),\s*'([^']*)'\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('group_msg', 'message', const Color(0xFF9966FF), tr, {
        'gid': m.group(1)!, 'content': _unescapeStr(m.group(2)!),
      });
    }

    // await csac.group.sendImage(gid, 'url')
    m = RegExp(r"await\s+csac\.group\.sendImage\((\S+),\s*'([^']*)'\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('group_image', 'message', const Color(0xFF9966FF), tr, {
        'gid': m.group(1)!, 'url': m.group(2)!,
      });
    }

    // await csac.group.recallMessage(gid, msg_id)
    m = RegExp(r"await\s+csac\.group\.recallMessage\((\S+),\s*(\S+)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('group_recall', 'message', const Color(0xFF9966FF), tr, {
        'gid': m.group(1)!, 'msg_id': m.group(2)!,
      });
    }

    // await csac.group.muteMember(gid, uid, seconds)
    m = RegExp(r"await\s+csac\.group\.muteMember\((\S+),\s*(\S+),\s*(\S+)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('group_mute_member', 'message', const Color(0xFF9966FF), tr, {
        'gid': m.group(1)!, 'uid': m.group(2)!, 'seconds': m.group(3)!,
      });
    }

    // await csac.group.unmuteMember(gid, uid)
    m = RegExp(r"await\s+csac\.group\.unmuteMember\((\S+),\s*(\S+)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('group_unmute', 'message', const Color(0xFF9966FF), tr, {
        'gid': m.group(1)!, 'uid': m.group(2)!,
      });
    }

    // await csac.group.setEssence(gid, msg_id)
    m = RegExp(r"await\s+csac\.group\.setEssence\((\S+),\s*(\S+)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('group_essence', 'message', const Color(0xFF9966FF), tr, {
        'gid': m.group(1)!, 'msg_id': m.group(2)!, 'set': 'set',
      });
    }

    // await csac.group.unsetEssence(gid, msg_id)
    m = RegExp(r"await\s+csac\.group\.unsetEssence\((\S+),\s*(\S+)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('group_essence', 'message', const Color(0xFF9966FF), tr, {
        'gid': m.group(1)!, 'msg_id': m.group(2)!, 'set': 'unset',
      });
    }

    // await csac.group.leave(gid)
    m = RegExp(r"await\s+csac\.group\.leave\((\S+)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('group_leave', 'message', const Color(0xFF9966FF), tr, {'gid': m.group(1)!});
    }

    // await new Promise(r => setTimeout(r, ms));
    m = RegExp(r"await\s+new\s+Promise\(r\s*=>\s*setTimeout\(r,\s*(\d+)\)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('wait', 'control', const Color(0xFFCF8B17), tr, {'ms': m.group(1)!});
    }

    // let/const var = value;
    m = RegExp(r"(?:let|const)\s+(\w+)\s*=\s*(.+)$").firstMatch(line);
    if (m != null && !m.group(2)!.contains('await csac') && !m.group(2)!.contains('await ctx')) {
      final val = m.group(2)!.trim();
      if (val.startsWith('[') && val.endsWith(']')) {
        final inner = val.substring(1, val.length - 1);
        return _makeBlock('set_list', 'data', const Color(0xFFFF8C1A), tr, {
          'name': m.group(1)!, 'items': inner,
        });
      }
      if (val.startsWith('{') && val.endsWith('}')) {
        final inner = val.substring(1, val.length - 1);
        return _makeBlock('set_object', 'data', const Color(0xFFFF8C1A), tr, {
          'name': m.group(1)!, 'fields': inner,
        });
      }
      return _makeBlock('set_var', 'data', const Color(0xFFFF8C1A), tr, {
        'name': m.group(1)!, 'value': val,
      });
    }

    // const _res = await csac.http.get('url')
    m = RegExp(r"const\s+_res\s*=\s*await\s+csac\.http\.get\('([^']*)'\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('http_get', 'data', const Color(0xFFFF8C1A), tr, {'url': m.group(1)!});
    }

    // const _res = await csac.http.post('url', { json: body })
    m = RegExp(r"const\s+_res\s*=\s*await\s+csac\.http\.post\('([^']*)',\s*\{\s*json:\s*(.+)\s*\}\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('http_post', 'data', const Color(0xFFFF8C1A), tr, {
        'url': m.group(1)!, 'body': m.group(2)!,
      });
    }

    // const var = JSON.parse(source)
    m = RegExp(r"const\s+(\w+)\s*=\s*JSON\.parse\((.+)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('json_parse', 'data', const Color(0xFFFF8C1A), tr, {
        'var_name': m.group(1)!, 'source': m.group(2)!,
      });
    }

    // const var = JSON.stringify(value)
    m = RegExp(r"const\s+(\w+)\s*=\s*JSON\.stringify\((.+)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('json_stringify', 'data', const Color(0xFFFF8C1A), tr, {
        'var_name': m.group(1)!, 'value': m.group(2)!,
      });
    }

    // const var = expr (math op fallback)
    m = RegExp(r"const\s+(\w+)\s*=\s*(.+)$").firstMatch(line);
    if (m != null && !m.group(2)!.contains('await') && !m.group(2)!.contains('JSON.')) {
      return _makeBlock('math_op', 'data', const Color(0xFFFF8C1A), tr, {
        'var_name': m.group(1)!, 'expr': m.group(2)!,
      });
    }

    // Storage operations
    // await csac.storage.set('key', value)
    m = RegExp(r"await\s+csac\.storage\.set\('([^']*)',\s*(.+)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('storage_set', 'storage', const Color(0xFF0FBD8C), tr, {
        'key': m.group(1)!, 'value': m.group(2)!,
      });
    }

    // const var = await csac.storage.get('key', default)
    m = RegExp(r"const\s+(\w+)\s*=\s*await\s+csac\.storage\.get\('([^']*)',\s*(.+)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('storage_get', 'storage', const Color(0xFF0FBD8C), tr, {
        'var_name': m.group(1)!, 'key': m.group(2)!, 'default_val': m.group(3)!,
      });
    }

    // await csac.storage.delete('key')
    m = RegExp(r"await\s+csac\.storage\.delete\('([^']*)'\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('storage_delete', 'storage', const Color(0xFF0FBD8C), tr, {'key': m.group(1)!});
    }

    // await csac.storage.increment('key', step)
    m = RegExp(r"await\s+csac\.storage\.increment\('([^']*)',\s*(\d+)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('storage_increment', 'storage', const Color(0xFF0FBD8C), tr, {
        'key': m.group(1)!, 'step': m.group(2)!,
      });
    }

    // Platform operations
    // const _user = await csac.user.get(uid)
    m = RegExp(r"const\s+_user\s*=\s*await\s+csac\.user\.get\((\S+)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('user_info', 'platform', const Color(0xFF40BF4A), tr, {'uid': m.group(1)!});
    }

    // const _group = await csac.groupInfo.get(gid)
    m = RegExp(r"const\s+_group\s*=\s*await\s+csac\.groupInfo\.get\((\S+)\)").firstMatch(line);
    if (m != null) {
      return _makeBlock('group_info', 'platform', const Color(0xFF40BF4A), tr, {'gid': m.group(1)!});
    }

    // Logger
    m = RegExp(r"logger\.(info|warn|error)\('([^']*)'\)").firstMatch(line);
    if (m != null) {
      final id = 'log_${m.group(1)}';
      final colors = {'info': Color(0xFF8B8B8B), 'warn': Color(0xFFE6A817), 'error': Color(0xFFE53935)};
      return _makeBlock(id, 'utility', colors[m.group(1)]!, tr, {'text': _unescapeStr(m.group(2)!)});
    }

    // Comment
    m = RegExp(r'//\s*(.*)').firstMatch(line);
    if (m != null) {
      return _makeBlock('comment', 'utility', Color(0xFFA8A8A8), tr, {'text': m.group(1)!.trim()});
    }

    return null;
  }

  // ==================== Helpers ====================

  static ScratchBlock _makeBlock(String templateId, String category, Color color,
      String Function(String) tr, Map<String, String> values) {
    final t = blockTemplates.where((x) => x.id == templateId).firstOrNull;
    final label = t?.localizedTitle(tr) ?? templateId;
    return ScratchBlock(
      id: _nextId(templateId),
      templateId: templateId,
      category: category,
      color: color,
      label: label,
      values: values,
    );
  }

  /// Consume lines between an opening brace and its matching closing brace.
  /// Returns the body lines (excluding the opener and closer) and the next index.
  static _BodyResult? _consumeBody(List<String> lines, int start, String open, String close) {
    // Find the opening brace on start line
    final line = lines[start];
    final openIdx = line.indexOf(open);
    if (openIdx < 0) return null;

    // Check for inline body (e.g. `if (x) { doThing(); }`)
    int depth = 1;
    int pos = openIdx + 1;
    int lineIdx = start;
    final bodyLines = <String>[];

    while (lineIdx < lines.length) {
      final currentLine = (lineIdx == start) ? line.substring(pos) : lines[lineIdx];
      for (int j = 0; j < currentLine.length; j++) {
        final ch = currentLine[j];
        if (ch == '{') {
          depth++;
        } else if (ch == '}') {
          depth--;
          if (depth == 0) {
            // Found closing brace — capture remaining text before it as last body piece
            if (lineIdx == start && openIdx + 1 < j + pos) {
              final bodyText = currentLine.substring(0, j).trim();
              if (bodyText.isNotEmpty) bodyLines.add(bodyText);
            } else if (lineIdx > start) {
              final bodyText = currentLine.substring(0, j).trim();
              if (bodyText.isNotEmpty) bodyLines.add(bodyText);
            }
            return _BodyResult(bodyLines, lineIdx + 1);
          }
        }
      }
      // No closing brace found on this line; add the line to body
      if (lineIdx > start) {
        bodyLines.add(currentLine);
      } else if (lineIdx == start) {
        final txt = currentLine.trim();
        if (txt.isNotEmpty) bodyLines.add(txt);
      }
      lineIdx++;
    }
    return _BodyResult(bodyLines, lineIdx);
  }

  /// Convert a list of body lines into blocks.
  static List<ScratchBlock> _convertBody(List<String> lines, String Function(String) tr) {
    final blocks = <ScratchBlock>[];
    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('//')) {
        i++;
        continue;
      }
      final container = _tryMatchContainer(lines, i, tr);
      if (container != null) {
        blocks.add(container.block);
        i = container.nextIndex;
        continue;
      }
      final single = _tryMatchSingle(line, tr);
      if (single != null) {
        blocks.add(single);
        i++;
        continue;
      }
      // Group unrecognized into js_raw
      final rawLines = <String>[line];
      i++;
      while (i < lines.length) {
        final nl = lines[i].trim();
        if (nl.isEmpty) { i++; break; }
        if (_tryMatchSingle(nl, tr) != null || _tryMatchContainer(lines, i, tr) != null) break;
        rawLines.add(lines[i]);
        i++;
      }
      blocks.add(_makeBlock('js_raw', 'utility', const Color(0xFF6C6C6C), tr,
          {'code': rawLines.join('\n')}));
    }
    return blocks;
  }

  /// Remove one level of leading whitespace from lines.
  static List<String> _stripOneIndent(List<String> lines) {
    if (lines.isEmpty) return lines;
    // Find common leading whitespace
    int minIndent = 999;
    for (final l in lines) {
      final trimmed = l.trimLeft();
      if (trimmed.isEmpty) continue;
      final indent = l.length - trimmed.length;
      if (indent < minIndent) minIndent = indent;
    }
    if (minIndent == 0 || minIndent == 999) return lines;
    return lines.map((l) => l.length > minIndent ? l.substring(minIndent) : l.trimLeft()).toList();
  }

  static String _unescapeStr(String s) =>
      s.replaceAll(r"\'", "'").replaceAll(r'\n', '\n');
}

class _MatchResult {
  final ScratchBlock block;
  final int nextIndex;
  _MatchResult(this.block, this.nextIndex);
}

class _BodyResult {
  final List<String> bodyLines;
  final int nextIndex;
  _BodyResult(this.bodyLines, this.nextIndex);
}
