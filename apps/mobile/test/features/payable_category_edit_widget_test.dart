import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/receipt_attempts.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/categories/categories_repository.dart';
import 'package:bigdevz_finance/features/payables/payable_modal.dart';
import 'package:bigdevz_finance/features/payables/payables_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

const pf = Space(id: 1, kind: 'PF', name: 'Pessoal');

void main() {
  late MemorySessionStorage storage;
  late List<http.Request> requests;

  final payableWithoutCategory = {
    'data': {
      'id': 200,
      'kind': 'single',
      'description': 'Supermercado Mensal',
      'amount': '300.00',
      'paid': '300.00',
      'remaining': '0.00',
      'due_date': '2026-03-10',
      'status': 'paid',
      'overdue': false,
      'category_id': null,
      'category': null,
      'payments': [],
    },
  };

  final categoriesResponse = {
    'data': [
      {
        'id': 77,
        'name': 'Alimentação',
        'type': 'expense',
        'icon': 'restaurant',
        'color': '#E57373',
      },
    ],
  };

  final accountsResponse = {
    'data': [
      {
        'id': 10,
        'name': 'Nubank',
        'opening_balance': '500.00',
        'opening_balance_date': '2026-01-01',
        'balance': '1000.00',
      },
    ],
  };

  setUp(() {
    storage = MemorySessionStorage();
    requests = [];
  });

  Widget buildModal({required int payableId, required ApiClient api}) {
    final session =
        SessionController(api: api, auth: AuthRepository(api), storage: storage)
          ..user = const AppUser(
            id: 1,
            name: 'Jeann Lucas',
            email: 'jeann@example.com',
          );

    return MultiProvider(
      providers: [
        Provider.value(value: api),
        Provider(create: (_) => AccountsRepository(api)),
        Provider(create: (_) => AgreementsRepository(api)),
        Provider(create: (_) => CategoriesRepository(api)),
        Provider(create: (_) => PayablesRepository(api)),
        Provider(
          create: (context) => ReceiptAttempts(
            repository: context.read<AgreementsRepository>(),
            storage: storage,
            payables: context.read<PayablesRepository>(),
          ),
        ),
        ChangeNotifierProvider.value(value: session),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    showPayableModal(ctx, space: pf, payableId: payableId),
                child: const Text('Abrir modal payable'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Permite alterar categoria em conta a pagar liquidada (AC-PAY-CAT-001..005)',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.contains('/payables/200') &&
            request.method == 'GET') {
          return http.Response(jsonEncode(payableWithoutCategory), 200);
        }
        if (request.url.path.contains('/categories')) {
          return http.Response(jsonEncode(categoriesResponse), 200);
        }
        if (request.url.path.contains('/accounts')) {
          return http.Response(jsonEncode(accountsResponse), 200);
        }
        if (request.url.path.contains('/payables/200') &&
            request.method == 'PATCH') {
          return http.Response(
            jsonEncode({
              'data': {
                'id': 200,
                'kind': 'single',
                'description': 'Supermercado Mensal',
                'amount': '300.00',
                'paid': '300.00',
                'remaining': '0.00',
                'due_date': '2026-03-10',
                'status': 'paid',
                'overdue': false,
                'category_id': 77,
                'category': {
                  'id': 77,
                  'name': 'Alimentação',
                  'type': 'expense',
                  'icon': 'restaurant',
                  'color': '#E57373',
                },
                'payments': [],
              },
            }),
            200,
          );
        }
        return http.Response('{"message": "Not found"}', 404);
      });

      final api = ApiClient(baseUrl: 'https://example.com/api', client: client);

      await tester.pumpWidget(buildModal(payableId: 200, api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir modal payable'));
      await tester.pumpAndSettle();

      // 1. Verifica botão/indicador de categoria presente mesmo com status "pago"
      expect(find.byTooltip('Alterar categoria'), findsOneWidget);

      // 2. Abre diálogo de alteração de categoria
      await tester.tap(find.byTooltip('Alterar categoria'));
      await tester.pumpAndSettle();

      expect(find.text('Alterar categoria'), findsOneWidget);
      expect(find.text('Salvar categoria'), findsOneWidget);

      // 3. Salva a categoria
      await tester.tap(find.text('Salvar categoria'));
      await tester.pumpAndSettle();

      // 4. Confirma requisição PATCH para /payables/200
      final patchReq = requests.firstWhere(
        (r) => r.url.path.contains('/payables/200') && r.method == 'PATCH',
      );
      expect(patchReq, isNotNull);
    },
  );
}
