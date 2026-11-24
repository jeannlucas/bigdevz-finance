import 'package:bigdevz_finance/features/accounts/wise_currency_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AC-WISE-009 pesquisa nome sem acento e seleciona com bandeira', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WiseCurrencyPicker(
            codes: const ['USD', 'EUR', 'JPY'],
            onSelected: (code) => selected = code,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'dolar');
    await tester.pumpAndSettle();
    expect(find.text('Dólar americano'), findsOneWidget);
    expect(find.text('Euro'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.text('Dólar americano'));
    expect(selected, 'USD');
  });
}
