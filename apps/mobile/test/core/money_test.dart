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
      for (final value in [
        '1,00',
        '1.001',
        // Saldo negativo é aceito ("-1.00"); sinal mal formado não.
        '--1.00',
        '-01.00',
        '+1.00',
        '01.00',
        '1',
        '',
        '92233720368547758.08', // Overflow do teto int64 (9223372036854775807 centavos)
        '99999999999999999999999999999999999999999999.00', // Milhares de dígitos
      ]) {
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

  test('saldo negativo da API: lê e formata com sinal', () {
    final balance = Money.parse('-250.05');
    expect(balance.cents, -25005);
    expect(balance.brl, r'-R$ 250,05');
    expect(balance.toApi(), '-250.05');
    expect(Money.parse('-0.05').brl, r'-R$ 0,05');
    expect(
      Money.fromInput('-1,00')?.cents,
      100,
      reason: 'entrada nunca negativa',
    );
  });

  test('lê valores agregados acima de maxCents com exatidão sem float', () {
    expect(Money.parse('1000000000000.00').cents, 100000000000000);
    expect(Money.parse('1000000000000.00').brl, r'R$ 1.000.000.000.000,00');
    expect(Money.parseAggregate('1000000000000.00').cents, 100000000000000);
    expect(Money.parse('-1000000000000.00').cents, -100000000000000);
    // Suporta exatamente os extremos de int64 (-9223372036854775808 até 9223372036854775807)
    final minMoney = Money.parse('-92233720368547758.08');
    expect(minMoney.cents, -9223372036854775808);
    expect(minMoney.toApi(), '-92233720368547758.08');
    expect(minMoney.plain, '-92.233.720.368.547.758,08');
    expect(minMoney.brl, r'-R$ 92.233.720.368.547.758,08');

    final maxMoney = Money.parse('92233720368547758.07');
    expect(maxMoney.cents, 9223372036854775807);
    expect(maxMoney.toApi(), '92233720368547758.07');
    expect(maxMoney.plain, '92.233.720.368.547.758,07');
    expect(maxMoney.brl, r'R$ 92.233.720.368.547.758,07');

    expect(() => Money.parse('-92233720368547758.09'), throwsFormatException);
    expect(() => Money.parse('92233720368547758.08'), throwsFormatException);
    // Input individual continua limitado a maxCents (R$ 999 bilhões)
    expect(Money.fromInput('100000000000001'), isNull);
  });
}
