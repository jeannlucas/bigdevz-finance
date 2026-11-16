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

  testWidgets(
    'StatementTab inicializa sem filtro de direção e sem status restritivo, listando todas as movimentações do mês corrente',
    (tester) async {
      String? requestedUrl;
      final client = MockClient((request) async {
        if (request.url.path == '/spaces/1/accounts') {
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/spaces/1/statement') {
          requestedUrl = request.url.toString();
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 101,
                  'account_id': 1,
                  'account_name': 'Conta Corrente',
                  'effective_date': '2026-11-05',
                  'amount': '500.00',
                  'raw_amount_cents': 50000,
                  'direction': 'credit',
                  'type': 'receipt',
                  'description': 'Recebimento de Consultoria',
                },
                {
                  'id': 102,
                  'account_id': 1,
                  'account_name': 'Conta Corrente',
                  'effective_date': '2026-11-12',
                  'amount': '150.00',
                  'raw_amount_cents': -15000,
                  'direction': 'debit',
                  'type': 'payment',
                  'description': 'Pagamento de Energia',
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

      // Confirma que a URL não restringe direção nem status
      expect(requestedUrl, isNotNull);
      final uri = Uri.parse(requestedUrl!);
      expect(uri.queryParameters.containsKey('direction'), isFalse);
      expect(uri.queryParameters.containsKey('status'), isFalse);
      expect(uri.queryParameters.containsKey('from'), isTrue);
      expect(uri.queryParameters.containsKey('to'), isTrue);

      // Ambas as movimentações (entrada e saída) estão visíveis
      expect(find.text('RECEBIMENTO DE CONSULTORIA'), findsOneWidget);
      expect(find.text('PAGAMENTO DE ENERGIA'), findsOneWidget);
      expect(find.text('+ R\$ 500,00'), findsOneWidget);
      expect(find.text('- R\$ 150,00'), findsOneWidget);
    },
  );

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

  testWidgets(
    'filters statement by direction and shows active filter chip with clear action',
    (tester) async {
      final capturedUrls = <String>[];
      final client = MockClient((request) async {
        capturedUrls.add(request.url.toString());
        if (request.url.path == '/spaces/1/accounts') {
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/spaces/1/statement') {
          final direction = request.url.queryParameters['direction'];
          if (direction == 'credit') {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 1,
                    'account_id': 1,
                    'account_name': 'Nubank',
                    'effective_date': '2026-11-10',
                    'amount': '800.00',
                    'raw_amount_cents': 80000,
                    'direction': 'credit',
                    'type': 'receipt',
                    'description': 'Recebimento de Cliente',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      await tester.pumpWidget(buildTestWidget(client: client));
      await tester.pumpAndSettle();

      // Filtros de direção visíveis
      expect(find.widgetWithText(ChoiceChip, 'Todos'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Entradas'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Saídas'), findsOneWidget);

      // Clica em 'Entradas'
      await tester.tap(find.widgetWithText(ChoiceChip, 'Entradas'));
      await tester.pumpAndSettle();

      // Confirma envio do query param direction=credit
      expect(capturedUrls.any((u) => u.contains('direction=credit')), isTrue);
      expect(find.text('RECEBIMENTO DE CLIENTE'), findsOneWidget);

      // Chip de filtro ativo é exibido
      expect(find.text('Tipo: Entradas'), findsOneWidget);
      expect(find.text('Limpar filtros'), findsOneWidget);

      // Clica em Limpar filtros
      await tester.tap(find.text('Limpar filtros').first);
      await tester.pumpAndSettle();

      // Volta para Todos
      expect(capturedUrls.last.contains('direction='), isFalse);
    },
  );
}
