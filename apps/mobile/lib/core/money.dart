import 'package:flutter/services.dart';

/// Valor monetário em centavos inteiros (decisão 0002). Nunca usa double.
class Money {
  const Money(this.cents);

  static const int maxCents = 99999999999999;
  static final RegExp _api = RegExp(r'^(0|[1-9][0-9]{0,11})\.([0-9]{2})$');

  final int cents;

  /// Lê o contrato da API: string com ponto e duas casas, como "2000.00".
  factory Money.parse(String value) {
    final match = _api.firstMatch(value);
    if (match == null) throw FormatException('Valor monetário inválido', value);
    return Money(int.parse(match.group(1)!) * 100 + int.parse(match.group(2)!));
  }

  /// Lê o texto digitado no formato brasileiro ("1.500,00").
  static Money? fromInput(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    final cents = int.parse(digits);
    return cents > maxCents ? null : Money(cents);
  }

  String toApi() =>
      '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

  /// Sem o prefixo "R$", para campos de edição.
  String get plain {
    final units = (cents ~/ 100).toString();
    final grouped = StringBuffer();
    for (var i = 0; i < units.length; i++) {
      if (i > 0 && (units.length - i) % 3 == 0) grouped.write('.');
      grouped.write(units[i]);
    }
    return '$grouped,${(cents % 100).toString().padLeft(2, '0')}';
  }

  String get brl => 'R\$ $plain';

  bool get isZero => cents == 0;
}

/// Máscara de moeda: os dígitos entram pela direita, como em apps bancários.
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return TextEditingValue.empty;
    if (digits.length > 14) digits = digits.substring(digits.length - 14);
    var cents = int.parse(digits);
    if (cents > Money.maxCents) cents = Money.maxCents;
    final text = Money(cents).plain;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
