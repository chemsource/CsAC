import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum JsacratchEditMode { acratch, js }

const defaultThemeColorValue = 0xff1f8a70;
const defaultFontScale = 1.0;

class JsacratchPreferences {
  const JsacratchPreferences({
    this.themeMode = ThemeMode.system,
    this.themeColorValue = defaultThemeColorValue,
    this.editMode = JsacratchEditMode.acratch,
    this.fontScale = defaultFontScale,
    this.acopServerUrl = '',
    this.acopToken = '',
  });

  static const _themeKey = 'jsacratch.theme_mode';
  static const _themeColorKey = 'jsacratch.theme_color';
  static const _editModeKey = 'jsacratch.edit_mode';
  static const _fontScaleKey = 'jsacratch.font_scale';
  static const _acopServerUrlKey = 'jsacratch.acop_server_url';
  static const _acopTokenKey = 'jsacratch.acop_token';

  final ThemeMode themeMode;
  final int themeColorValue;
  final JsacratchEditMode editMode;
  final double fontScale;
  final String acopServerUrl;
  final String acopToken;

  Color get themeColor => Color(themeColorValue);

  JsacratchPreferences copyWith({
    ThemeMode? themeMode,
    int? themeColorValue,
    JsacratchEditMode? editMode,
    double? fontScale,
    String? acopServerUrl,
    String? acopToken,
  }) {
    return JsacratchPreferences(
      themeMode: themeMode ?? this.themeMode,
      themeColorValue: themeColorValue ?? this.themeColorValue,
      editMode: editMode ?? this.editMode,
      fontScale: fontScale ?? this.fontScale,
      acopServerUrl: acopServerUrl ?? this.acopServerUrl,
      acopToken: acopToken ?? this.acopToken,
    );
  }

  static Future<JsacratchPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return JsacratchPreferences(
      themeMode: _themeFromName(prefs.getString(_themeKey)),
      themeColorValue: prefs.getInt(_themeColorKey) ?? defaultThemeColorValue,
      editMode: _editModeFromName(prefs.getString(_editModeKey)),
      fontScale: (prefs.getDouble(_fontScaleKey) ?? defaultFontScale)
          .clamp(0.85, 1.30),
      acopServerUrl: prefs.getString(_acopServerUrlKey) ?? '',
      acopToken: prefs.getString(_acopTokenKey) ?? '',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, themeMode.name);
    await prefs.setInt(_themeColorKey, themeColorValue);
    await prefs.setString(_editModeKey, editMode.name);
    await prefs.setDouble(_fontScaleKey, fontScale);
    if (acopServerUrl.isEmpty) {
      await prefs.remove(_acopServerUrlKey);
    } else {
      await prefs.setString(_acopServerUrlKey, acopServerUrl);
    }
    if (acopToken.isEmpty) {
      await prefs.remove(_acopTokenKey);
    } else {
      await prefs.setString(_acopTokenKey, acopToken);
    }
  }

  static ThemeMode _themeFromName(String? value) {
    for (final m in ThemeMode.values) {
      if (m.name == value) return m;
    }
    return ThemeMode.system;
  }

  static JsacratchEditMode _editModeFromName(String? value) {
    for (final m in JsacratchEditMode.values) {
      if (m.name == value) return m;
    }
    return JsacratchEditMode.acratch;
  }
}
