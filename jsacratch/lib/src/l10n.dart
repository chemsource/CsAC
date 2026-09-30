import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class _JsacratchLocalizationsDelegate
    extends LocalizationsDelegate<JsacratchStrings> {
  const _JsacratchLocalizationsDelegate();

  static const _supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh', 'CN'),
  ];

  @override
  bool isSupported(Locale locale) {
    return _supportedLocales.contains(locale);
  }

  @override
  Future<JsacratchStrings> load(Locale locale) async {
    final data = await rootBundle.loadString(
      'lib/l10n/${locale.toLanguageTag()}.json',
      cache: false,
    );
    return JsacratchStrings(locale, Map<String, String>.from(
      (jsonDecode(data) as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString())),
    ));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<JsacratchStrings> old) {
    return false;
  }
}

const jsacratchLocalizationsDelegate = _JsacratchLocalizationsDelegate();

const supportedJsacratchLocales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
];

class JsacratchStrings {
  const JsacratchStrings(this.locale, this._strings);

  final Locale locale;
  final Map<String, String> _strings;

  static JsacratchStrings of(BuildContext context) {
    return Localizations.of<JsacratchStrings>(context, JsacratchStrings)!;
  }

  String text(String key) {
    return _strings[key] ?? key;
  }

  String format(String key, Map<String, String> replacements) {
    var result = text(key);
    for (final e in replacements.entries) {
      result = result.replaceAll('{${e.key}}', e.value);
    }
    return result;
  }

  Locale get localeForTag => locale;
}
