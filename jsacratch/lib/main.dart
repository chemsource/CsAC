import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'src/l10n.dart';
import 'src/acop_client.dart';
import 'src/preferences.dart';
import 'src/ui/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureWindow();
  final prefs = await JsacratchPreferences.load();
  runApp(JsacratchApp(initialPrefs: prefs));
}

Future<void> _configureWindow() async {
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(1200, 700));
  await windowManager.setTitle('Jsacratch - CsAC Bot Script Editor');
}

class JsacratchApp extends StatefulWidget {
  const JsacratchApp({required this.initialPrefs, super.key});

  final JsacratchPreferences initialPrefs;

  @override
  State<JsacratchApp> createState() => _JsacratchAppState();
}

class _JsacratchAppState extends State<JsacratchApp> {
  late JsacratchPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _prefs = widget.initialPrefs;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Jsacratch',
      themeMode: _prefs.themeMode,
      theme: _buildTheme(Brightness.light, _prefs.themeColor),
      darkTheme: _buildTheme(Brightness.dark, _prefs.themeColor),
      localizationsDelegates: const [
        jsacratchLocalizationsDelegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: supportedJsacratchLocales,
      locale: const Locale('zh', 'CN'),
      home: AppShell(client: AcopApiClient()),
    );
  }

  ThemeData _buildTheme(Brightness brightness, Color seedColor) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      contrastLevel: 0.0,
    );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: 'sans-serif',
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      cardColor: scheme.surfaceContainerLow,
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        modalBackgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    );
  }
}
