import 'package:bigdevz_finance/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money', () {
    test('lê o contrato da API em centavos exatos', () {
      expect(Money.parse('2000.00').cents, 200000);
      expect(Money.parse('0.01').cents, 1);
      expect(Money.parse('999999999999.99').cents, 99999999999999);
      expect(Money.parse('21500.00').toApi(), '21500.00');
    });

    test('recusa formatos ambíguos', () {
      for (final value in ['1,00', '1.001', '-1.00', '01.00', '1', '', '1000000000000.00']) {
        expect(() => Money.parse(value), throwsFormatException, reason: value);
      }
    });

    test('formata em BRL', () {
      expect(Money.parse('3500.00').brl, r'R$ 3.500,00');
      expect(Money.parse('0.05').brl, r'R$ 0,05');
      expect(Money.parse('999999999999.99').brl, r'R$ 999.999.999.999,99');
      expect(const Money(33334).brl, r'R$ 333,34');
    });

    test('digitação brasileira vira valor da API sem ponto flutuante', () {
      expect(Money.fromInput('1.500,00')?.toApi(), '1500.00');
      expect(Money.fromInput('0,10')?.toApi(), '0.10');
      expect(Money.fromInput(''), isNull);
    });
  });

  group('MoneyInputFormatter', () {
    TextEditingValue type(String text) => MoneyInputFormatter()
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text));

    test('preenche da direita para a esquerda', () {
      expect(type('5').text, '0,05');
      expect(type('150000').text, '1.500,00');
      expect(type('a1b2').text, '0,12');
    });

    test('limita ao teto suportado', () {
      expect(type('9999999999999999').text, '999.999.999.999,99');
    });
  });
}
