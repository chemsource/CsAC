import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'preferences.dart';

Locale localeForLanguage(CsacLanguage language) {
  switch (language) {
    case CsacLanguage.en:
      return const Locale('en');
    case CsacLanguage.zh:
      return const Locale('zh', 'CN');
    case CsacLanguage.zhTw:
      return const Locale('zh', 'TW');
    case CsacLanguage.ja:
      return const Locale('ja');
    case CsacLanguage.ko:
      return const Locale('ko');
    case CsacLanguage.es:
      return const Locale('es');
    case CsacLanguage.fr:
      return const Locale('fr');
    case CsacLanguage.de:
      return const Locale('de');
    case CsacLanguage.ru:
      return const Locale('ru');
    case CsacLanguage.ptBr:
      return const Locale('pt', 'BR');
    case CsacLanguage.vi:
      return const Locale('vi');
    case CsacLanguage.id:
      return const Locale('id');
  }
}

const supportedCsacLocales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh', 'TW'),
  Locale('ja'),
  Locale('ko'),
  Locale('es'),
  Locale('fr'),
  Locale('de'),
  Locale('ru'),
  Locale('pt', 'BR'),
  Locale('vi'),
  Locale('id'),
];

class CsacStrings {
  const CsacStrings(this.locale, [this.overrides = const <String, String>{}]);

  final Locale locale;
  final Map<String, String> overrides;

  static CsacStrings of(BuildContext context) {
    return Localizations.of<CsacStrings>(context, CsacStrings) ??
        CsacStrings(_fallbackLocale, _fallbackOverrides);
  }

  String text(String key) {
    final override = overrides[key];
    if (override != null && override.trim().isNotEmpty) {
      return override;
    }
    if (_localeCacheKey(locale) == _localeCacheKey(_fallbackLocale)) {
      final fallback = _fallbackOverrides[key];
      if (fallback != null && fallback.trim().isNotEmpty) {
        return fallback;
      }
    }
    return key;
  }

  String format(String key, Map<String, Object?> values) {
    var result = text(key);
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return result;
  }
}

class TranslationProgress {
  const TranslationProgress({required this.translated, required this.total});

  final int translated;
  final int total;

  int get missing {
    final value = total - translated;
    return value < 0 ? 0 : value;
  }

  int get percent {
    if (total <= 0) {
      return 0;
    }
    return ((translated * 100) / total).round().clamp(0, 100).toInt();
  }

  double get fraction {
    if (total <= 0) {
      return 0;
    }
    return (translated / total).clamp(0.0, 1.0);
  }

  String get percentLabel => '$percent%';
}

class CsacStringsDelegate extends LocalizationsDelegate<CsacStrings> {
  const CsacStringsDelegate();

  @override
  bool isSupported(Locale locale) {
    return supportedCsacLocales.any((supported) {
      if (supported.languageCode != locale.languageCode) {
        return false;
      }
      final country = supported.countryCode;
      return country == null ||
          country.isEmpty ||
          country == locale.countryCode;
    });
  }

  @override
  Future<CsacStrings> load(Locale locale) async {
    return CsacStrings(locale, await _loadL10nOverrides(locale));
  }

  @override
  bool shouldReload(CsacStringsDelegate old) => false;
}

Future<CsacStrings> preloadCsacStrings(CsacLanguage language) async {
  final locale = localeForLanguage(language);
  final overrides = await _loadL10nOverrides(locale);
  _fallbackLocale = locale;
  _fallbackOverrides = overrides;
  return CsacStrings(locale, overrides);
}

Future<Map<String, String>> _loadL10nOverrides(Locale locale) async {
  return _loadL10nJsonForLocale(locale);
}

Future<TranslationProgress> translationProgressForLanguage(
  CsacLanguage language,
) {
  final locale = localeForLanguage(language);
  return _translationProgressCache.putIfAbsent(
    _localeCacheKey(locale),
    () => _loadTranslationProgress(locale),
  );
}

Future<TranslationProgress> _loadTranslationProgress(Locale locale) async {
  final source = await _loadL10nJsonAsset('en');
  if (source.isEmpty) {
    return const TranslationProgress(translated: 0, total: 0);
  }
  if (_localeCacheKey(locale) == 'en') {
    return TranslationProgress(translated: source.length, total: source.length);
  }
  final target = await _loadL10nJsonForLocale(locale);
  var translated = 0;
  for (final key in source.keys) {
    final targetValue = (target[key] ?? '').trim();
    if (targetValue.isNotEmpty && targetValue != source[key]?.trim()) {
      translated++;
    }
  }
  return TranslationProgress(translated: translated, total: source.length);
}

Future<Map<String, String>> _loadL10nJsonForLocale(Locale locale) async {
  final candidates = <String>[
    if (locale.countryCode?.trim().isNotEmpty == true)
      '${locale.languageCode}-${locale.countryCode}',
    locale.languageCode,
  ];
  for (final name in candidates) {
    final loaded = await _loadL10nJsonAsset(name);
    if (loaded.isNotEmpty) {
      return loaded;
    }
  }
  return const <String, String>{};
}

Future<Map<String, String>> _loadL10nJsonAsset(String name) {
  return _l10nJsonCache.putIfAbsent(name, () async {
    try {
      final raw = await rootBundle.loadString('lib/l10n/$name.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const <String, String>{};
      }
      return decoded.map((key, value) => MapEntry(key, '$value'));
    } catch (_) {
      return const <String, String>{};
    }
  });
}

String _localeCacheKey(Locale locale) {
  final country = locale.countryCode?.trim();
  if (country == null || country.isEmpty) {
    return locale.languageCode;
  }
  return '${locale.languageCode}-$country';
}

final _l10nJsonCache = <String, Future<Map<String, String>>>{};
final _translationProgressCache = <String, Future<TranslationProgress>>{};
Locale _fallbackLocale = localeForLanguage(const CsacPreferences().language);
Map<String, String> _fallbackOverrides = const <String, String>{};

extension CsacStringsContext on BuildContext {
  CsacStrings get strings => CsacStrings.of(this);
}
