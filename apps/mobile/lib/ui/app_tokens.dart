import 'package:flutter/material.dart';

/// Tokens visuais centralizados do BigDev.Z Finance conforme o design aprovado.
/// Paleta: azul principal #2459D4, superfícies #F5F7FA, texto #14243B.
/// Suporte completo a tema claro e escuro e diferenciação semântica de PF/PJ.
class AppTokens {
  const AppTokens._();

  // Cores da marca e sementes
  static const Color brandPrimary = Color(0xFF2459D4);
  static const Color brandSeed = Color(0xFF2459D4);
  static const Color brandText = Color(0xFF14243B);
  static const Color pfSeed = Color(0xFF2459D4);
  static const Color pjSeed = Color(0xFF137A63);

  // Gradientes nobres centralizados dos cartões financeiros (Resumo, Carteira e Detalhe)
  static const List<Color> pfCardGradient = [
    Color(0xFF1E40AF),
    Color(0xFF172554),
    Color(0xFF0F172A),
  ];
  static const List<Color> pjCardGradient = [
    Color(0xFF065F46),
    Color(0xFF064E3B),
    Color(0xFF022C22),
  ];
  static const List<Color> archivedCardGradient = [
    Color(0xFF334155),
    Color(0xFF1E293B),
  ];

  static List<Color> cardGradientFor({
    required bool isPf,
    bool isArchived = false,
  }) {
    if (isArchived) return archivedCardGradient;
    return isPf ? pfCardGradient : pjCardGradient;
  }

  // Semântica financeira
  static const Color income = Color(0xFF128A54); // Verde entrada / recebido
  static const Color expense = Color(
    0xFFD63939,
  ); // Vermelho saída / a pagar / vencido
  static const Color warning = Color(0xFFD97706); // Âmbar atenção / pendente
  static const Color neutral = Color(0xFF5A6E85); // Neutro secundário

  // Superfícies tema claro
  static const Color lightBackground = Color(0xFFF5F7FA);
  static const Color lightSurface = Colors.white;
  static const Color lightSurfaceContainer = Color(0xFFF0F3F8);
  static const Color lightTextPrimary = Color(0xFF14243B);
  static const Color lightTextSecondary = Color(0xFF5A6E85);
  static const Color lightBorder = Color(0xFFDCE2EC);

  // Superfícies tema escuro
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkSurfaceContainer = Color(0xFF334155);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkBorder = Color(0xFF334155);

  // Espaçamentos e métricas
  static const double p4 = 4.0;
  static const double p8 = 8.0;
  static const double p12 = 12.0;
  static const double p14 = 14.0;
  static const double p16 = 16.0;
  static const double p20 = 20.0;
  static const double p24 = 24.0;
  static const double p32 = 32.0;

  // Cantos arredondados (border radius)
  static const double r8 = 8.0;
  static const double r10 = 10.0;
  static const double r12 = 12.0;
  static const double r16 = 16.0;
  static const double r20 = 20.0;
  static const double r24 = 24.0;

  // Alvos de toque acessíveis
  static const double minTouchTarget = 48.0;
  static const double buttonHeight = 52.0;
}
