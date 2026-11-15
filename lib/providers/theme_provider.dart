import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-selected appearance, persisted across launches.
///
/// Stored in [SharedPreferences] under [_storageKey]. Values are one of
/// `light`, `dark`, `system`. Defaults to [ThemeMode.light] — the professional
/// paper design is the reference experience for this product.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider() {
    _restore();
  }

  static const String _storageKey = 'balance_desk.theme_mode';

  ThemeMode _themeMode = ThemeMode.light;
  bool _restored = false;

  ThemeMode get themeMode => _themeMode;
  bool get isRestored => _restored;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, mode.name);
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      final restored = switch (raw) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        'light' => ThemeMode.light,
        _ => ThemeMode.light,
      };
      if (restored != _themeMode) {
        _themeMode = restored;
      }
    } catch (_) {
      // Keep the default when preferences are unavailable.
    } finally {
      _restored = true;
      notifyListeners();
    }
  }
}
