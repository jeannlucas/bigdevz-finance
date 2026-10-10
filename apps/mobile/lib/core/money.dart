import 'package:flutter/services.dart';

/// Valor monetário em centavos inteiros (decisão 0002). Nunca usa double.
class Money {
  const Money(this.cents);

  static const int maxCents = 99999999999999;
  static final RegExp _api = RegExp(r'^(-?)(0|[1-9][0-9]{0,11})\.([0-9]{2})$');

  final int cents;

  /// Lê o contrato da API: string com ponto e duas casas, como "2000.00".
  /// Saldos podem vir negativos depois de pagamentos ("-250.00").
  factory Money.parse(String value) {
    final match = _api.firstMatch(value);
    if (match == null) throw FormatException('Valor monetário inválido', value);
    final cents = int.parse(match.group(2)!) * 100 + int.parse(match.group(3)!);
    return Money(match.group(1) == '-' ? -cents : cents);
  }

  /// Lê o texto digitado no formato brasileiro ("1.500,00").
  static Money? fromInput(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    final cents = int.parse(digits);
    return cents > maxCents ? null : Money(cents);
  }

  String toApi() =>
      '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';

  /// Sem o prefixo "R$", para campos de edição.
  String get plain {
    final units = (cents.abs() ~/ 100).toString();
    final grouped = StringBuffer();
    for (var i = 0; i < units.length; i++) {
      if (i > 0 && (units.length - i) % 3 == 0) grouped.write('.');
      grouped.write(units[i]);
    }
    return '${cents < 0 ? '-' : ''}$grouped,${(cents.abs() % 100).toString().padLeft(2, '0')}';
  }

  String get brl => cents < 0 ? '-R\$ ${Money(-cents).plain}' : 'R\$ $plain';

  bool get isNegative => cents < 0;

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
