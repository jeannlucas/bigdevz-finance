import 'package:flutter/services.dart';

/// Converte um texto de identificação financeira para MAIÚSCULAS
/// preservando acentuação em português e limpando espaços nas pontas.
/// Retorna string vazia se o texto for nulo ou em branco.
String toFinancialUpper(String? text) {
  if (text == null) return '';
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.toUpperCase();
}

/// Formatter de campo de texto para normalizar a digitação em MAIÚSCULAS
/// sem deslocar o cursor do usuário ou corromper seleções ativas.
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upperText = newValue.text.toUpperCase();
    return newValue.copyWith(
      text: upperText,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}
