import 'package:flutter/material.dart';

import 'app_tokens.dart';

const Color brandSeed = AppTokens.brandPrimary;
const Color pfSeed = AppTokens.pfSeed;
const Color pjSeed = AppTokens.pjSeed;

ThemeData buildTheme(Brightness brightness, {Color seed = brandSeed}) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    surface: isDark ? AppTokens.darkSurface : AppTokens.lightSurface,
    onSurface: isDark ? AppTokens.darkTextPrimary : AppTokens.lightTextPrimary,
    surfaceContainerLowest: isDark
        ? AppTokens.darkBackground
        : AppTokens.lightSurface,
    surfaceContainerLow: isDark
        ? AppTokens.darkSurface
        : AppTokens.lightSurface,
    surfaceContainer: isDark
        ? AppTokens.darkSurfaceContainer
        : AppTokens.lightSurfaceContainer,
    surfaceContainerHigh: isDark
        ? const Color(0xFF2D3748)
        : const Color(0xFFE2E8F0),
    surfaceContainerHighest: isDark
        ? const Color(0xFF374151)
        : const Color(0xFFCBD5E1),
  );

  final baseTextTheme = isDark
      ? Typography.material2021().white
      : Typography.material2021().black;

  final textTheme = baseTextTheme.copyWith(
    headlineMedium: baseTextTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: isDark ? AppTokens.darkTextPrimary : AppTokens.lightTextPrimary,
      letterSpacing: -0.5,
    ),
    titleLarge: baseTextTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: isDark ? AppTokens.darkTextPrimary : AppTokens.lightTextPrimary,
      letterSpacing: -0.3,
    ),
    titleMedium: baseTextTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: isDark ? AppTokens.darkTextPrimary : AppTokens.lightTextPrimary,
    ),
    titleSmall: baseTextTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: isDark ? AppTokens.darkTextPrimary : AppTokens.lightTextPrimary,
    ),
    bodyLarge: baseTextTheme.bodyLarge?.copyWith(
      color: isDark ? AppTokens.darkTextPrimary : AppTokens.lightTextPrimary,
    ),
    bodyMedium: baseTextTheme.bodyMedium?.copyWith(
      color: isDark ? AppTokens.darkTextPrimary : AppTokens.lightTextPrimary,
    ),
    bodySmall: baseTextTheme.bodySmall?.copyWith(
      color: isDark
          ? AppTokens.darkTextSecondary
          : AppTokens.lightTextSecondary,
    ),
    labelLarge: baseTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: isDark
        ? AppTokens.darkBackground
        : AppTokens.lightBackground,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: isDark
          ? AppTokens.darkBackground
          : AppTokens.lightBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
      iconTheme: IconThemeData(
        color: isDark ? AppTokens.darkTextPrimary : AppTokens.lightTextPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? AppTokens.darkSurface : AppTokens.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.r16),
        side: BorderSide(
          color: isDark ? AppTokens.darkBorder : AppTokens.lightBorder,
          width: 1,
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        borderSide: BorderSide(
          color: isDark ? AppTokens.darkBorder : AppTokens.lightBorder,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        borderSide: BorderSide(
          color: isDark ? AppTokens.darkBorder : AppTokens.lightBorder,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      filled: true,
      fillColor: isDark ? AppTokens.darkSurface : AppTokens.lightSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(AppTokens.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.r12),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppTokens.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.r12),
        ),
        side: BorderSide(
          color: isDark ? AppTokens.darkBorder : AppTokens.lightBorder,
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.r12),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 2,
      backgroundColor: isDark ? AppTokens.darkSurface : AppTokens.lightSurface,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.primary,
          );
        }
        return TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isDark
              ? AppTokens.darkTextSecondary
              : AppTokens.lightTextSecondary,
        );
      }),
    ),
  );
}

Color seedForSpace(bool isPf) => isPf ? pfSeed : pjSeed;

/// Rota que mantém a cor do espaço ativo nas telas empilhadas.
Route<T> spaceRoute<T>({required bool isPf, required Widget child}) =>
    MaterialPageRoute<T>(
      builder: (context) => Theme(
        data: buildTheme(
          Theme.of(context).brightness,
          seed: seedForSpace(isPf),
        ),
        child: child,
      ),
    );
