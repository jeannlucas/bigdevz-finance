import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bigdevz_finance/core/text_formatters.dart';

void main() {
  group('toFinancialUpper', () {
    test('retorna string vazia quando nulo ou vazio', () {
      expect(toFinancialUpper(null), '');
      expect(toFinancialUpper(''), '');
      expect(toFinancialUpper('   '), '');
    });

    test(
      'converte texto simples para maiúsculas e remove espaços das pontas',
      () {
        expect(toFinancialUpper('mercado central'), 'MERCADO CENTRAL');
        expect(toFinancialUpper('  mercado central  '), 'MERCADO CENTRAL');
        expect(toFinancialUpper('Conta de Água'), 'CONTA DE ÁGUA');
      },
    );

    test('preserva caracteres acentuados e cedilha em português', () {
      expect(toFinancialUpper('joão da silva'), 'JOÃO DA SILVA');
      expect(toFinancialUpper('preço & ação'), 'PREÇO & AÇÃO');
      expect(toFinancialUpper('coração de mãe'), 'CORAÇÃO DE MÃE');
      expect(toFinancialUpper('ônibus & saúde'), 'ÔNIBUS & SAÚDE');
      expect(toFinancialUpper('açúcar união'), 'AÇÚCAR UNIÃO');
    });

    test('preserva múltiplos espaços internos sem corromper', () {
      expect(
        toFinancialUpper('  ALFANDEGA   FEDERAL  '),
        'ALFANDEGA   FEDERAL',
      );
    });
  });

  group('UpperCaseTextFormatter', () {
    const formatter = UpperCaseTextFormatter();

    test('converte texto digitado para maiúsculas', () {
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(
        text: 'mercado central',
        selection: TextSelection.collapsed(offset: 15),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, 'MERCADO CENTRAL');
      expect(result.selection.baseOffset, 15);
      expect(result.selection.extentOffset, 15);
    });

    test('preserva posição do cursor ao editar no meio do texto', () {
      const oldValue = TextEditingValue(
        text: 'CONTA DE LUZ',
        selection: TextSelection.collapsed(offset: 8),
      );
      // Inserindo 'água ' na posição 8 ('CONTA DE água LUZ')
      const newValue = TextEditingValue(
        text: 'CONTA DE água LUZ',
        selection: TextSelection.collapsed(offset: 13),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, 'CONTA DE ÁGUA LUZ');
      expect(result.selection.baseOffset, 13);
      expect(result.selection.extentOffset, 13);
    });

    test('preserva seleção de texto', () {
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(
        text: 'joão da silva',
        selection: TextSelection(baseOffset: 0, extentOffset: 4),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, 'JOÃO DA SILVA');
      expect(result.selection.baseOffset, 0);
      expect(result.selection.extentOffset, 4);
    });
  });
}
