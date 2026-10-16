import 'package:flutter/material.dart';

import '../../core/token_storage.dart';

/// Gerencia as preferências visuais (tema) e a política de privacidade de valores na sessão.
class PreferencesController extends ChangeNotifier {
  PreferencesController({required this.storage});

  final SessionStorage storage;

  static const String themeModeKey = 'app_theme_mode';
  static const String hideByDefaultKey = 'hide_values_by_default';

  ThemeMode _themeMode = ThemeMode.system;
  bool _hideValuesByDefault = false;
  bool _obscureValues = false;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  bool get hideValuesByDefault => _hideValuesByDefault;
  bool get obscureValues => _obscureValues;
  bool get isLoaded => _loaded;

  /// Carrega as preferências salvas localmente. Na ausência de preferência anterior,
  /// o padrão inicial aprovado é Automático (ThemeMode.system) e valores visíveis.
  Future<void> load() async {
    try {
      final rawTheme = await storage.read(themeModeKey);
      if (rawTheme != null) {
        _themeMode = switch (rawTheme) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
      } else {
        _themeMode = ThemeMode.system;
      }

      final rawHide = await storage.read(hideByDefaultKey);
      _hideValuesByDefault = rawHide == 'true';
      _obscureValues = _hideValuesByDefault;
    } catch (_) {
      _themeMode = ThemeMode.system;
      _hideValuesByDefault = false;
      _obscureValues = false;
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// Altera o modo de tema e persiste a escolha localmente.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final value = switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
      await storage.write(themeModeKey, value);
    } catch (_) {
      // Falha silenciosa de escrita preserva experiência do usuário
    }
  }

  /// Altera a preferência de iniciar com valores financeiros ocultos por padrão.
  Future<void> setHideValuesByDefault(bool hide) async {
    if (_hideValuesByDefault == hide) return;
    _hideValuesByDefault = hide;
    _obscureValues = hide;
    notifyListeners();
    try {
      await storage.write(hideByDefaultKey, hide ? 'true' : 'false');
    } catch (_) {
      // Falha silenciosa de escrita preserva experiência do usuário
    }
  }

  /// Alterna temporariamente a exibição/mascaramento de valores durante a sessão atual.
  /// Sobrevive à navegação de abas e alternância de espaços PF/PJ.
  void togglePrivacy() {
    _obscureValues = !_obscureValues;
    notifyListeners();
  }

  /// Restaura a privacidade da sessão para o valor configurado como padrão.
  /// Chamado no logout para garantir isolamento e descarte de estado efêmero.
  void resetSessionPrivacy() {
    _obscureValues = _hideValuesByDefault;
    notifyListeners();
  }
}
