import 'package:flutter/services.dart';

/// Valor monetário em centavos inteiros (decisão 0002). Nunca usa double.
class Money {
  const Money(this.cents);

  static const int maxCents = 99999999999999;
  static final RegExp _api = RegExp(r'^(-?)(0|[1-9][0-9]*)\.([0-9]{2})$');

  final int cents;

  /// Lê o contrato da API: string com ponto e duas casas, como "2000.00".
  /// Saldos podem vir negativos depois de pagamentos ("-250.00").
  /// Suporta totais agregados acima de maxCents dentro da precisão de 64 bits.
  factory Money.parse(String value) {
    final match = _api.firstMatch(value);
    if (match == null) throw FormatException('Valor monetário inválido', value);
    final units = int.tryParse(match.group(2)!);
    final centsUnit = int.tryParse(match.group(3)!);
    if (units == null || centsUnit == null) {
      throw FormatException('Valor monetário excede o limite suportado', value);
    }
    final isNeg = match.group(1) == '-';
    // No Dart (64 bits): teto positivo é 9223372036854775807, piso negativo é -9223372036854775808.
    final maxCentsUnit = isNeg ? 8 : 7;
    if (units > 92233720368547758 ||
        (units == 92233720368547758 && centsUnit > maxCentsUnit)) {
      throw FormatException('Valor monetário excede o limite suportado', value);
    }
    final cents = isNeg ? -units * 100 - centsUnit : units * 100 + centsUnit;
    return Money(cents);
  }

  /// Lê especificamente valores agregados da API.
  static Money parseAggregate(String value) => Money.parse(value);

  /// Lê o texto digitado no formato brasileiro ("1.500,00").
  static Money? fromInput(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    final cents = int.parse(digits);
    return cents > maxCents ? null : Money(cents);
  }

  String toApi() {
    final absQuotient = (cents ~/ 100).abs();
    final absRemainder = cents.remainder(100).abs();
    return '${cents < 0 ? '-' : ''}$absQuotient.${absRemainder.toString().padLeft(2, '0')}';
  }

  /// Sem o prefixo "R$", para campos de edição.
  String get plain {
    final absQuotient = (cents ~/ 100).abs();
    final absRemainder = cents.remainder(100).abs();
    final units = absQuotient.toString();
    final grouped = StringBuffer();
    for (var i = 0; i < units.length; i++) {
      if (i > 0 && (units.length - i) % 3 == 0) grouped.write('.');
      grouped.write(units[i]);
    }
    return '${cents < 0 ? '-' : ''}$grouped,${absRemainder.toString().padLeft(2, '0')}';
  }

  String get brl => cents < 0 ? '-R\$ ${plain.substring(1)}' : 'R\$ $plain';

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
