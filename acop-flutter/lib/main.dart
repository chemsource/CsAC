import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';

void main() {
  runApp(const ACOPApp());
}

class ACOPApp extends StatelessWidget {
  const ACOPApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: MaterialApp(
        title: 'CsAC Open Platform',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1677FF),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F7FA),
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.white,
          ),
          cardTheme: CardThemeData(
            elevation: 1,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.black.withValues(alpha: 0.04)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
          navigationRailTheme: NavigationRailThemeData(
            backgroundColor: Colors.white,
            selectedIconTheme: const IconThemeData(color: Color(0xFF1677FF)),
            selectedLabelTextStyle: const TextStyle(
              color: Color(0xFF1677FF),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        home: const _AppShell(),
      ),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!state.loggedIn) {
      return const LoginPage();
    }
    return const DashboardPage();
  }
}
