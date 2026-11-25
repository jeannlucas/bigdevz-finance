import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/accounts/wise_wallet_panel.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

void main() {
  testWidgets(
    'AC-WISE-010 busca cotação de mercado e preenche formulário de cotação',
    (tester) async {
      final backend = FakeBackend();
      backend.overrides['GET /spaces/1/accounts/1/wise/currencies/EUR/market-rate'] =
          (request) => http.Response(
            jsonEncode({
              'data': {
                'currency': 'EUR',
                'target': 'BRL',
                'rate': '6.4457',
                'quoted_on': '2026-11-25',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );

      final api = ApiClient(
        baseUrl: 'http://example.test',
        client: backend.client,
      );
      final storage = MemorySessionStorage();
      final auth = AuthRepository(api);
      final session = SessionController(api: api, auth: auth, storage: storage);
      final repository = AccountsRepository(api);

      final account = Account.fromJson({
        'id': 1,
        'name': 'Wise',
        'bank_id': 'wise',
        'opening_balance': '0.00',
        'opening_balance_date': '2026-01-01',
        'balance': '0.00',
        'wise_currencies': [
          {'currency': 'EUR', 'balance': '2.94'},
        ],
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: session),
            Provider.value(value: repository),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: WiseWalletPanel(
                account: account,
                spaceId: 1,
                refresh: () async {},
              ),
            ),
          ),
        ),
      );

      // Abre o modal de cotação do EUR
      await tester.tap(find.text('Cotação'));
      await tester.pumpAndSettle();

      expect(find.text('Cotação de EUR'), findsOneWidget);

      // O botão de buscar cotação de mercado deve estar presente
      final fetchButton = find.text('Buscar cotação de mercado');
      expect(fetchButton, findsOneWidget);

      // Clica no botão para buscar cotação
      await tester.tap(fetchButton);
      await tester.pumpAndSettle();

      // Campo de valor deve ter sido preenchido com a taxa
      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);
      final textField = tester.widget<TextField>(inputFinder);
      expect(textField.controller?.text, '6,4457');

      // Clica em Revisar para verificar o preview
      await tester.tap(find.text('Revisar'));
      await tester.pumpAndSettle();

      expect(find.text('1 EUR = BRL 6.4457'), findsOneWidget);
    },
  );
}
