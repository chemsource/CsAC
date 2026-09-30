// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC jsacratch - Code completion system
// Provides autocomplete prompts for BotJS, ACR, and EMA modes.

import 'package:re_editor/re_editor.dart';

/// BotJS 运行时 API 自动补全定义
///
/// 分为几个类别：
/// - 全局对象/字段 (CodeFieldPrompt)
/// - 方法 (CodeFunctionPrompt)
/// - 事件处理 (CodeFunctionPrompt)
class BotJsCompletionSets {
  BotJsCompletionSets._();

  // ---- bot 对象 ----
  static const _botMethods = <CodePrompt>[
    CodeFunctionPrompt(word: 'on', type: 'void', parameters: {'eventName': 'string', 'handler': '(ctx) => {}'}),
    CodeFunctionPrompt(word: 'onPrivateMessage', type: 'void', parameters: {'handler': '(ctx) => {}'}),
    CodeFunctionPrompt(word: 'onGroupMessage', type: 'void', parameters: {'handler': '(ctx) => {}'}),
    CodeFunctionPrompt(word: 'onGroupMemberJoin', type: 'void', parameters: {'handler': '(ctx) => {}'}),
    CodeFunctionPrompt(word: 'onGroupMemberLeave', type: 'void', parameters: {'handler': '(ctx) => {}'}),
    CodeFunctionPrompt(word: 'onGroupMemberMute', type: 'void', parameters: {'handler': '(ctx) => {}'}),
    CodeFunctionPrompt(word: 'onGroupDisband', type: 'void', parameters: {'handler': '(ctx) => {}'}),
    CodeFunctionPrompt(word: 'command', type: 'void', parameters: {'pattern': 'string|RegExp', 'options': '{scope?}', 'handler': 'async (ctx) => {}'}),
    CodeFunctionPrompt(word: 'schedule', type: 'void', parameters: {'name': 'string?', 'cron': 'string', 'handler': 'async (ctx) => {}'}),
  ];

  // ---- csac 对象 ----
  static const _csacFields = <CodePrompt>[
    CodeFieldPrompt(word: 'csac', type: 'CsacSDK'),
  ];

  // csac.private
  static const _csacPrivateMethods = <CodePrompt>[
    CodeFunctionPrompt(word: 'sendMessage', type: 'Promise<object>', parameters: {'uid': 'int', 'text': 'string'}),
    CodeFunctionPrompt(word: 'sendImage', type: 'Promise<object>', parameters: {'uid': 'int', 'imageUrl': 'string'}),
    CodeFunctionPrompt(word: 'replyMessage', type: 'Promise<object>', parameters: {'uid': 'int', 'messageId': 'int', 'text': 'string'}),
    CodeFunctionPrompt(word: 'recallMessage', type: 'Promise<object>', parameters: {'uid': 'int', 'messageId': 'int'}),
  ];

  // csac.group
  static const _csacGroupMethods = <CodePrompt>[
    CodeFunctionPrompt(word: 'sendMessage', type: 'Promise<object>', parameters: {'groupId': 'int', 'text': 'string'}),
    CodeFunctionPrompt(word: 'sendImage', type: 'Promise<object>', parameters: {'groupId': 'int', 'imageUrl': 'string'}),
    CodeFunctionPrompt(word: 'replyMessage', type: 'Promise<object>', parameters: {'groupId': 'int', 'messageId': 'int', 'text': 'string'}),
    CodeFunctionPrompt(word: 'recallMessage', type: 'Promise<object>', parameters: {'groupId': 'int', 'messageId': 'int'}),
    CodeFunctionPrompt(word: 'setEssence', type: 'Promise<object>', parameters: {'groupId': 'int', 'messageId': 'int'}),
    CodeFunctionPrompt(word: 'unsetEssence', type: 'Promise<object>', parameters: {'groupId': 'int', 'messageId': 'int'}),
    CodeFunctionPrompt(word: 'muteMember', type: 'Promise<object>', parameters: {'groupId': 'int', 'uid': 'int', 'seconds': 'int'}),
    CodeFunctionPrompt(word: 'unmuteMember', type: 'Promise<object>', parameters: {'groupId': 'int', 'uid': 'int'}),
    CodeFunctionPrompt(word: 'leave', type: 'Promise<object>', parameters: {'groupId': 'int'}),
  ];

  // csac.user
  static const _csacUserMethods = <CodePrompt>[
    CodeFunctionPrompt(word: 'get', type: 'Promise<object>', parameters: {'uid': 'int'}),
  ];

  // csac.groupInfo
  static const _csacGroupInfoMethods = <CodePrompt>[
    CodeFunctionPrompt(word: 'get', type: 'Promise<object>', parameters: {'groupId': 'int'}),
    CodeFunctionPrompt(word: 'memberCount', type: 'Promise<object>', parameters: {'groupId': 'int'}),
    CodeFunctionPrompt(word: 'hasMember', type: 'Promise<object>', parameters: {'groupId': 'int', 'uid': 'int'}),
    CodeFunctionPrompt(word: 'botPermissions', type: 'Promise<object>', parameters: {'groupId': 'int'}),
  ];

  // csac.notice
  static const _csacNoticeMethods = <CodePrompt>[
    CodeFunctionPrompt(word: 'send', type: 'Promise<object>', parameters: {'uid': 'int', 'title': 'string', 'content': 'string'}),
  ];

  // csac.http
  static const _csacHttpMethods = <CodePrompt>[
    CodeFunctionPrompt(word: 'get', type: 'Promise<object>', parameters: {'url': 'string'}),
    CodeFunctionPrompt(word: 'post', type: 'Promise<object>', parameters: {'url': 'string', 'options': '{json?, headers?, body?}'}),
  ];

  // csac.storage
  static const _csacStorageMethods = <CodePrompt>[
    CodeFunctionPrompt(word: 'set', type: 'Promise<void>', parameters: {'key': 'string', 'value': 'any'}),
    CodeFunctionPrompt(word: 'get', type: 'Promise<any>', parameters: {'key': 'string', 'defaultValue': 'any?'}),
    CodeFunctionPrompt(word: 'delete', type: 'Promise<void>', parameters: {'key': 'string'}),
    CodeFunctionPrompt(word: 'list', type: 'Promise<object>', parameters: {'prefix': 'string'}),
    CodeFunctionPrompt(word: 'increment', type: 'Promise<number>', parameters: {'key': 'string', 'step': 'number?'}),
  ];

  // ---- ctx 对象 ----
  static const _ctxFields = <CodePrompt>[
    CodeFieldPrompt(word: 'ctx', type: 'BotContext'),
    CodeFieldPrompt(word: 'eventName', type: 'string'),
    CodeFieldPrompt(word: 'eventId', type: 'string'),
    CodeFieldPrompt(word: 'time', type: 'number'),
    CodeFieldPrompt(word: 'sender', type: '{uid, nickname, username, avatar, isBot}'),
    CodeFieldPrompt(word: 'text', type: 'string'),
    CodeFieldPrompt(word: 'raw', type: 'object'),
    CodeFieldPrompt(word: 'isPrivate', type: 'boolean'),
    CodeFieldPrompt(word: 'isGroup', type: 'boolean'),
    CodeFieldPrompt(word: 'message', type: '{id, type, msgType, text, imageUrls, replyTo, timestamp}'),
    CodeFieldPrompt(word: 'group', type: '{id, groupId, gid, name, roomName, ownerUid, avatar, memberCount}'),
    CodeFieldPrompt(word: 'member', type: '{uid, nickname}'),
    CodeFieldPrompt(word: 'operator', type: '{uid}'),
    CodeFieldPrompt(word: 'muteUntil', type: 'number'),
    CodeFieldPrompt(word: 'muted', type: 'boolean'),
    CodeFieldPrompt(word: 'triggerTime', type: 'number'),
    CodeFieldPrompt(word: 'cronExpression', type: 'string'),
  ];

  static const _ctxMethods = <CodePrompt>[
    CodeFunctionPrompt(word: 'reply', type: 'Promise<void>', parameters: {'content': 'string|{text, images}'}),
    CodeFunctionPrompt(word: 'send', type: 'Promise<void>', parameters: {'content': 'string|{text, images}'}),
    CodeFunctionPrompt(word: 'notice', type: 'Promise<void>', parameters: {'title': 'string', 'content': 'string'}),
    CodeFunctionPrompt(word: 'requireGroupAdmin', type: 'Promise<boolean>', parameters: {}),
    CodeFunctionPrompt(word: 'fail', type: 'void', parameters: {'message': 'string'}),
  ];

  // ---- logger / console ----
  static const _loggerMethods = <CodePrompt>[
    CodeFunctionPrompt(word: 'info', type: 'void', parameters: {'message': 'string'}),
    CodeFunctionPrompt(word: 'warn', type: 'void', parameters: {'message': 'string'}),
    CodeFunctionPrompt(word: 'error', type: 'void', parameters: {'message': 'string'}),
    CodeFunctionPrompt(word: 'log', type: 'void', parameters: {'message': 'string'}),
  ];

  // ---- 全局 keywords / builtins ----
  static const _globalKeywords = <CodePrompt>[
    CodeFieldPrompt(word: 'import', type: 'keyword — { name } from "pkg"'),
    CodeFieldPrompt(word: 'async', type: 'keyword'),
    CodeFieldPrompt(word: 'await', type: 'keyword'),
    CodeFieldPrompt(word: 'export', type: 'keyword'),
    CodeFieldPrompt(word: 'JSON', type: 'built-in'),
    CodeFieldPrompt(word: 'Math', type: 'built-in'),
    CodeFieldPrompt(word: 'Date', type: 'built-in'),
    CodeFieldPrompt(word: 'RegExp', type: 'built-in'),
    CodeFieldPrompt(word: 'console', type: 'ConsoleAPI'),
    CodeFieldPrompt(word: 'logger', type: 'LoggerAPI'),
    CodeFieldPrompt(word: 'bot', type: 'BotAPI'),
    CodeFieldPrompt(word: 'csac', type: 'CsacSDK'),
  ];

  // ---- 完整的 relatedPrompts 映射 ----
  static Map<String, List<CodePrompt>> buildRelatedPrompts(
      Map<String, List<CodePrompt>>? ajlImports) {
    final map = <String, List<CodePrompt>>{
      'bot': _botMethods,
      'csac': _csacFields,
      'private': _csacPrivateMethods,
      'group': _csacGroupMethods,
      'user': _csacUserMethods,
      'groupInfo': _csacGroupInfoMethods,
      'notice': _csacNoticeMethods,
      'http': _csacHttpMethods,
      'storage': _csacStorageMethods,
      'ctx': [..._ctxFields, ..._ctxMethods],
      'logger': _loggerMethods,
      'console': _loggerMethods,
      'JSON': [
        CodeFunctionPrompt(word: 'parse', type: 'any', parameters: {'text': 'string'}),
        CodeFunctionPrompt(word: 'stringify', type: 'string', parameters: {'value': 'any'}),
      ],
      'Math': [
        CodeFieldPrompt(word: 'PI', type: 'number'),
        CodeFieldPrompt(word: 'E', type: 'number'),
        CodeFunctionPrompt(word: 'abs', type: 'number', parameters: {'x': 'number'}),
        CodeFunctionPrompt(word: 'ceil', type: 'number', parameters: {'x': 'number'}),
        CodeFunctionPrompt(word: 'floor', type: 'number', parameters: {'x': 'number'}),
        CodeFunctionPrompt(word: 'round', type: 'number', parameters: {'x': 'number'}),
        CodeFunctionPrompt(word: 'max', type: 'number', parameters: {'...values': 'number[]'}),
        CodeFunctionPrompt(word: 'min', type: 'number', parameters: {'...values': 'number[]'}),
        CodeFunctionPrompt(word: 'random', type: 'number', parameters: {}),
        CodeFunctionPrompt(word: 'sqrt', type: 'number', parameters: {'x': 'number'}),
        CodeFunctionPrompt(word: 'pow', type: 'number', parameters: {'x': 'number', 'y': 'number'}),
      ],
      'Date': [
        CodeFunctionPrompt(word: 'now', type: 'number', parameters: {}),
      ],
      'sender': [
        CodeFieldPrompt(word: 'uid', type: 'int'),
        CodeFieldPrompt(word: 'nickname', type: 'string'),
        CodeFieldPrompt(word: 'username', type: 'string'),
        CodeFieldPrompt(word: 'avatar', type: 'string'),
        CodeFieldPrompt(word: 'isBot', type: 'boolean'),
      ],
      'message': [
        CodeFieldPrompt(word: 'id', type: 'int'),
        CodeFieldPrompt(word: 'type', type: 'string'),
        CodeFieldPrompt(word: 'msgType', type: 'string'),
        CodeFieldPrompt(word: 'text', type: 'string'),
        CodeFieldPrompt(word: 'imageUrls', type: 'string[]'),
        CodeFieldPrompt(word: 'replyTo', type: 'int?'),
        CodeFieldPrompt(word: 'timestamp', type: 'number'),
      ],
    };

    // 合并 AJL 库导入的方法
    if (ajlImports != null) {
      for (final entry in ajlImports.entries) {
        map[entry.key] = [
          for (final method in entry.value)
            CodeFieldPrompt(word: method.word, type: 'function (from AJL lib)'),
        ];
      }
    }

    return map;
  }

  /// 构建 BotJS 模式的直接提示
  static List<CodePrompt> buildDirectPrompts(
      Map<String, List<CodePrompt>>? ajlImports) {
    final prompts = <CodePrompt>[
      ..._globalKeywords,
      ..._botMethods,
      ..._csacPrivateMethods.map((p) => CodeFunctionPrompt(
            word: 'csac.private.${(p as CodeFunctionPrompt).word}',
            type: p.type,
            parameters: p.parameters,
          )),
      ..._csacGroupMethods.map((p) => CodeFunctionPrompt(
            word: 'csac.group.${(p as CodeFunctionPrompt).word}',
            type: p.type,
            parameters: p.parameters,
          )),
      ..._csacUserMethods.map((p) => CodeFunctionPrompt(
            word: 'csac.user.${(p as CodeFunctionPrompt).word}',
            type: p.type,
            parameters: p.parameters,
          )),
      ..._csacGroupInfoMethods.map((p) => CodeFunctionPrompt(
            word: 'csac.groupInfo.${(p as CodeFunctionPrompt).word}',
            type: p.type,
            parameters: p.parameters,
          )),
      ..._csacNoticeMethods.map((p) => CodeFunctionPrompt(
            word: 'csac.notice.${(p as CodeFunctionPrompt).word}',
            type: p.type,
            parameters: p.parameters,
          )),
      ..._csacHttpMethods.map((p) => CodeFunctionPrompt(
            word: 'csac.http.${(p as CodeFunctionPrompt).word}',
            type: p.type,
            parameters: p.parameters,
          )),
      ..._csacStorageMethods.map((p) => CodeFunctionPrompt(
            word: 'csac.storage.${(p as CodeFunctionPrompt).word}',
            type: p.type,
            parameters: p.parameters,
          )),
      ..._ctxMethods,
    ];

    // 添加 AJL 导入的方法
    if (ajlImports != null) {
      for (final entry in ajlImports.entries) {
        for (final method in entry.value) {
          prompts.add(CodeFieldPrompt(
            word: method.word,
            type: 'function (from "${entry.key}")',
          ));
        }
      }
    }

    return prompts;
  }
}

/// 从代码中解析 import 声明，提取 AJL 库的导出方法名
///
/// 支持格式:
/// - import { method1, method2 } from "library-name"
/// - import { method1 as alias } from "library-name"
Map<String, List<CodePrompt>> parseAjlImports(String code) {
  final result = <String, List<CodePrompt>>{};
  final importRe = RegExp(
    r'''import\s*\{([^}]+)\}\s*from\s*["']([^"']+)["']''',
    multiLine: true,
  );
  for (final match in importRe.allMatches(code)) {
    final libName = match.group(2) ?? '';
    final methodsStr = match.group(1) ?? '';
    final methods = <CodePrompt>[];
    final methodRe = RegExp(r'(\w+)(?:\s+as\s+(\w+))?');
    for (final m in methodRe.allMatches(methodsStr)) {
      final name = m.group(2) ?? m.group(1) ?? '';
      if (name.isNotEmpty) {
        methods.add(CodeFieldPrompt(word: name, type: 'function (AJL)'));
      }
    }
    if (methods.isNotEmpty) {
      result[libName] = methods;
    }
  }
  return result;
}

/// EMA 模式：HTML 补全关键字
const htmlCompletions = <String>[
  'DOCTYPE', 'html', 'head', 'body', 'title', 'meta', 'link', 'style',
  'script', 'div', 'span', 'p', 'a', 'img', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'ul', 'ol', 'li', 'table', 'tr', 'td', 'th', 'thead', 'tbody', 'form',
  'input', 'button', 'textarea', 'select', 'option', 'label', 'br', 'hr',
  'header', 'footer', 'nav', 'section', 'article', 'aside', 'main',
  'class', 'id', 'href', 'src', 'alt', 'style', 'onclick', 'type',
  'placeholder', 'value', 'name', 'disabled', 'checked', 'required',
];

/// EMA 模式：CSS 补全关键字
const cssCompletions = <String>[
  'color', 'background', 'background-color', 'font-size', 'font-family',
  'font-weight', 'margin', 'padding', 'border', 'border-radius', 'width',
  'height', 'display', 'position', 'top', 'left', 'right', 'bottom',
  'flex', 'grid', 'align-items', 'justify-content', 'text-align',
  'text-decoration', 'opacity', 'z-index', 'overflow', 'cursor',
  'box-shadow', 'transition', 'transform', 'animation',
  'flex-direction', 'flex-wrap', 'gap', 'grid-template-columns',
  'grid-template-rows', 'max-width', 'min-width', 'max-height', 'min-height',
  'line-height', 'letter-spacing', 'word-spacing', 'text-transform',
  'white-space', 'word-break', 'vertical-align', 'float', 'clear',
  'visibility', 'outline', 'resize', 'user-select',
];

/// EMA 模式：根据文件扩展名返回对应的 langMode
enum EmaFileType { html, css, js }

EmaFileType emaFileType(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.css')) return EmaFileType.css;
  if (lower.endsWith('.js')) return EmaFileType.js;
  return EmaFileType.html;
}

/// 构建 EMA 模式下的代码提示
List<CodePrompt> buildEmaPrompts(EmaFileType fileType) {
  switch (fileType) {
    case EmaFileType.css:
      return [
        for (final kw in cssCompletions) CodeFieldPrompt(word: kw, type: 'css'),
      ];
    case EmaFileType.js:
      return [
        for (final kw in jsKeywords) CodeFieldPrompt(word: kw, type: 'js'),
      ];
    case EmaFileType.html:
      return [
        for (final kw in htmlCompletions)
          CodeFieldPrompt(word: kw, type: 'html'),
      ];
  }
}

/// 通用 JavaScript 关键字（EMA JS 模式 + ACR 模式）
const jsKeywords = <String>[
  'function', 'const', 'let', 'var', 'if', 'else', 'for', 'while', 'do',
  'switch', 'case', 'break', 'continue', 'return', 'throw', 'try', 'catch',
  'finally', 'new', 'this', 'class', 'extends', 'super', 'import', 'export',
  'default', 'async', 'await', 'typeof', 'instanceof', 'void', 'delete',
  'console', 'document', 'window', 'addEventListener', 'querySelector',
  'getElementById', 'createElement', 'appendChild', 'setAttribute',
  'innerHTML', 'textContent', 'classList', 'fetch',
];
