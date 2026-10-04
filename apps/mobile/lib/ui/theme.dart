import 'package:flutter/material.dart';

/// Paleta sóbria; cada espaço tem sua cor de identificação.
const Color brandSeed = Color(0xFF243B5A);
const Color pfSeed = Color(0xFF3A5BA0);
const Color pjSeed = Color(0xFF1F7466);

ThemeData buildTheme(Brightness brightness, {Color seed = brandSeed}) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 1, centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
  );
}

Color seedForSpace(bool isPf) => isPf ? pfSeed : pjSeed;

/// Rota que mantém a cor do espaço ativo nas telas empilhadas.
Route<T> spaceRoute<T>({required bool isPf, required Widget child}) => MaterialPageRoute<T>(
      builder: (context) => Theme(data: buildTheme(Theme.of(context).brightness, seed: seedForSpace(isPf)), child: child),
    );
