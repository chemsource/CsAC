class BotJsValidator {
  BotJsValidator._();

  /// Methods defined in imported ACR files - these are allowed.
  static final Set<String> importedAcrMethods = {};

  static void registerImportedMethods(String acrCode) {
    // Extract function/const/let declarations from ACR code
    final declRe = RegExp(r'(?:async\s+)?function\s+(\w+)|const\s+(\w+)\s*=|let\s+(\w+)\s*=');
    for (final m in declRe.allMatches(acrCode)) {
      final name = m.group(1) ?? m.group(2) ?? m.group(3);
      if (name != null) importedAcrMethods.add(name);
    }
  }

  static void clearImportedMethods() => importedAcrMethods.clear();

  static List<String> validate(String code) {
    final errors = <String>[];

    if (_pattern(r'\brequire\s*\(').hasMatch(code)) {
      errors.add('Cannot use require() in BotJS');
    }
    // import is ALLOWED - needed for cloud ACR packages
    if (_pattern(r'\beval\s*\(').hasMatch(code)) {
      errors.add('Cannot use eval() in BotJS');
    }
    if (_pattern(r'\bnew\s+Function\b').hasMatch(code)) {
      errors.add('Cannot use new Function() in BotJS');
    }
    if (_pattern(r'\bfs\b').hasMatch(code)) {
      errors.add('fs module is not available');
    }
    if (_pattern(r'\bprocess\b').hasMatch(code)) {
      errors.add('process is not available');
    }
    if (_pattern(r'\bfetch\s*\(').hasMatch(code)) {
      errors.add('fetch not available. Use csac.http.get/post');
    }

    _checkInfiniteLoops(code, errors);
    _checkSelfTrigger(code, errors);

    return errors;
  }

  static void _checkInfiniteLoops(String code, List<String> errors) {
    if (_pattern(r'while\s*\(\s*true\s*\)').hasMatch(code)) {
      errors.add('while(true) may cause infinite loop');
    }
    if (_pattern(r'for\s*\(\s*;\s*;\s*\)').hasMatch(code)) {
      errors.add('for(;;) infinite loop detected');
    }
  }

  static void _checkSelfTrigger(String code, List<String> errors) {
    final hasReplyToGroup = _pattern(r'ctx\.reply|csac\.group\.sendMessage').hasMatch(code);
    final hasOnGroupMsg = code.contains("bot.on('group.message'");
    if (hasReplyToGroup && hasOnGroupMsg) {
      errors.add('Self-trigger: sending group msg in group handler');
    }

    final hasReplyToPrivate = _pattern(r'ctx\.reply|csac\.private\.sendMessage').hasMatch(code);
    final hasOnPrivateMsg = code.contains("bot.on('private.message'");
    if (hasReplyToPrivate && hasOnPrivateMsg) {
      errors.add('Self-trigger: sending private msg in private handler');
    }
  }

  static RegExp _pattern(String p) => RegExp(p);
}
