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
  // Estado inicial conservador (fail-closed): inicia oculto até a preferência ser validada.
  // Previne qualquer exposição transitória (flicker) de saldos reais durante a inicialização.
  bool _obscureValues = true;
  bool _loaded = false;
  bool _hasReadError = false;

  ThemeMode get themeMode => _themeMode;
  bool get hideValuesByDefault => _hideValuesByDefault;
  bool get obscureValues => _obscureValues;
  bool get isLoaded => _loaded;
  bool get hasReadError => _hasReadError;

  /// Carrega as preferências salvas localmente com tratamento de falhas isolado (fail-closed).
  ///
  /// - A leitura do tema é desacoplada da leitura de privacidade.
  /// - Na ausência de preferência anterior confirmada, o padrão inicial aprovado é visível.
  /// - Em caso de exceção de I/O, erro de Keychain ou valor corrompido, adota-se política
  ///   conservadora: valores financeiros permanecem ocultos por padrão para evitar vazamento.
  Future<void> load() async {
    // 1. Leitura desacoplada de tema de aparência
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
    } catch (_) {
      _themeMode = ThemeMode.system;
    }

    // 2. Leitura desacoplada de privacidade financeira com fail-closed
    try {
      final rawHide = await storage.read(hideByDefaultKey);
      if (rawHide == null) {
        // Preferência nunca configurada: padrão aprovado do produto (visível)
        _hideValuesByDefault = false;
        _obscureValues = false;
        _hasReadError = false;
      } else if (rawHide == 'true') {
        _hideValuesByDefault = true;
        _obscureValues = true;
        _hasReadError = false;
      } else if (rawHide == 'false') {
        _hideValuesByDefault = false;
        _obscureValues = false;
        _hasReadError = false;
      } else {
        // Valor corrompido ou formato inesperado: fail-closed conservador
        _hideValuesByDefault = false;
        _obscureValues = true;
        _hasReadError = true;
      }
    } catch (_) {
      // Exceção de hardware/armazenamento: preserva os valores ocultos por precaução.
      // Não sobrescreve _hideValuesByDefault no storage.
      _obscureValues = true;
      _hasReadError = true;
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
    if (_hideValuesByDefault == hide && _obscureValues == hide) return;
    _hideValuesByDefault = hide;
    _obscureValues = hide;
    _hasReadError = false;
    notifyListeners();
    try {
      await storage.write(hideByDefaultKey, hide ? 'true' : 'false');
    } catch (_) {
      // Falha de escrita: preserva o estado de privacidade na sessão atual
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
  /// Se a carga das preferências ainda estiver pendente ou se houver erro de leitura,
  /// preserva o estado conservador (valores protegidos e mascarados).
  void resetSessionPrivacy() {
    _obscureValues = (!_loaded || _hasReadError) ? true : _hideValuesByDefault;
    notifyListeners();
  }
}
