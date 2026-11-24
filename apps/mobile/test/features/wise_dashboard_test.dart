import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/accounts/wise_currency.dart';
import 'package:bigdevz_finance/features/accounts/wise_wallet_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AC-WISE-008 apresenta moedas do espaço e respeita privacidade', (
    tester,
  ) async {
    final account = Account.fromJson({
      'id': 1,
      'name': 'WISE',
      'bank_id': 'wise',
      'opening_balance': '0.00',
      'opening_balance_date': '2026-01-01',
      'balance': '0.00',
      'wise_currencies': [
        {'currency': 'USD', 'balance': '53.27'},
        {'currency': 'EUR', 'balance': '2.94'},
      ],
    });
    Future<void> render(bool obscure) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WiseDashboardCard(accounts: [account], obscure: obscure),
        ),
      ),
    );
    await render(false);
    expect(find.text('USD 53,27'), findsOneWidget);
    expect(find.text('EUR 2,94'), findsOneWidget);
    await render(true);
    expect(find.text('USD 53,27'), findsNothing);
    expect(find.text('EUR 2,94'), findsNothing);
  });

  test('AC-WISE-006 arredonda apenas o total estimado', () {
    expect(
      WiseCurrency.estimatedBrl([
        const WiseCurrency('USD', '0.01', brlRate: '0.4'),
        const WiseCurrency('EUR', '0.01', brlRate: '0.4'),
      ], 100),
      r'R$ 1,01',
    );
  });
}
