import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/settings/preferences_controller.dart';
import 'package:bigdevz_finance/features/statement/statement_repository.dart';
import 'package:bigdevz_finance/features/statement/statement_tab.dart';

import '../support/fake_backend.dart';

const pf = Space(id: 1, kind: 'PF', name: 'Pessoal');

void main() {
  late MemorySessionStorage storage;

  setUp(() {
    storage = MemorySessionStorage();
  });

  Widget buildTestWidget({
    required http.Client client,
    PreferencesController? preferences,
  }) {
    final api = ApiClient(baseUrl: 'http://test.local', client: client);

    return MultiProvider(
      providers: [
        Provider(create: (_) => AccountsRepository(api)),
        Provider(create: (_) => StatementRepository(api)),
        ChangeNotifierProvider<PreferencesController?>.value(
          value: preferences,
        ),
      ],
      child: const MaterialApp(home: StatementTab(space: pf)),
    );
  }

  testWidgets('renders statement entries with credit and debit formatting', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path == '/spaces/1/accounts') {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 10,
                'name': 'Banco do Brasil',
                'balance': '1000.00',
                'opening_balance': '1000.00',
                'opening_balance_date': '2026-01-01',
                'is_archived': false,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/spaces/1/statement') {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 1,
                'account_id': 10,
                'account_name': 'Banco do Brasil',
                'effective_date': '2026-02-15',
                'amount': '350.00',
                'raw_amount_cents': -35000,
                'direction': 'debit',
                'type': 'payment',
                'description': 'Pagamento de Internet',
              },
              {
                'id': 2,
                'account_id': 10,
                'account_name': 'Banco do Brasil',
                'effective_date': '2026-02-10',
                'amount': '1200.00',
                'raw_amount_cents': 120000,
                'direction': 'credit',
                'type': 'receipt',
                'description': 'Recebimento de Salário',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('Not found', 404);
    });

    await tester.pumpWidget(buildTestWidget(client: client));
    await tester.pumpAndSettle();

    expect(find.text('Extrato'), findsOneWidget);
    expect(find.text('PAGAMENTO DE INTERNET'), findsOneWidget);
    expect(find.text('RECEBIMENTO DE SALÁRIO'), findsOneWidget);
    expect(find.text('- R\$ 350,00'), findsOneWidget);
    expect(find.text('+ R\$ 1.200,00'), findsOneWidget);
  });

  testWidgets('masks values when obscureValues is true', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/spaces/1/accounts') {
        return http.Response(
          jsonEncode({'data': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/spaces/1/statement') {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 1,
                'account_id': 1,
                'account_name': 'Nubank',
                'effective_date': '2026-02-15',
                'amount': '500.00',
                'raw_amount_cents': 50000,
                'direction': 'credit',
                'type': 'receipt',
                'description': 'Venda',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('Not found', 404);
    });

    await storage.write(PreferencesController.hideByDefaultKey, 'true');
    final preferences = PreferencesController(storage: storage);
    await preferences.load();

    await tester.pumpWidget(
      buildTestWidget(client: client, preferences: preferences),
    );
    await tester.pumpAndSettle();

    expect(find.text('+ R\$ ••••••••'), findsOneWidget);
    expect(find.text('+ R\$ 500,00'), findsNothing);
  });

  testWidgets('shows empty state when no entries exist', (tester) async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'data': []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(buildTestWidget(client: client));
    await tester.pumpAndSettle();

    expect(find.text('Nenhuma movimentação encontrada'), findsOneWidget);
  });
}
