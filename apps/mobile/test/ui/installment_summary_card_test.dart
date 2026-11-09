import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/ui/installment_summary_card.dart';

void main() {
  testWidgets(
    'InstallmentSummaryCard exibe contagem, valor por parcela e total',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InstallmentSummaryCard(
              installmentCount: 45,
              installmentAmount: Money(50502),
              totalAmount: Money(2272590),
              isByInstallmentMode: true,
            ),
          ),
        ),
      );

      expect(find.textContaining('45 parcelas de R\$ 505,02'), findsOneWidget);
      expect(find.textContaining('R\$ 22.725,90'), findsOneWidget);
    },
  );
}
