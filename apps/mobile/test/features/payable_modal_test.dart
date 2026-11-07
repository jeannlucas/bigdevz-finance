import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/receipt_attempts.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
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

  final payableResponse = {
    'data': {
      'id': 42,
      'kind': 'single',
      'description': 'Internet Fibra',
      'amount': '150.00',
      'paid': '0.00',
      'remaining': '150.00',
      'due_date': '2026-03-10',
      'status': 'open',
      'overdue': false,
    },
  };

  final accountsResponse = {
    'data': [
      {
        'id': 10,
        'name': 'Nubank',
        'opening_balance': '500.00',
        'opening_balance_date': '2026-01-01',
        'balance': '1500.00',
      },
    ],
  };

  setUp(() {
    storage = MemorySessionStorage();
    requests = [];
  });

  Widget buildTestWidget({required Widget child, required ApiClient api}) {
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
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets(
    'PayableActionModal exibe detalhes da conta a pagar e botão para dar baixa',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.contains('/payables/42')) {
          return http.Response(jsonEncode(payableResponse), 200);
        }
        if (request.url.path.contains('/accounts')) {
          return http.Response(jsonEncode(accountsResponse), 200);
        }
        return http.Response('{"message": "Not found"}', 404);
      });

      final api = ApiClient(baseUrl: 'http://api.test/api', client: client);

      await tester.pumpWidget(
        buildTestWidget(
          api: api,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showPayableModal(context, space: pf, payableId: 42),
              child: const Text('Abrir Modal Pagável'),
            ),
          ),
        ),
      );

      // Abre o modal
      await tester.tap(find.text('Abrir Modal Pagável'));
      await tester.pumpAndSettle();

      // Verifica exibição do título e valor
      expect(find.text('Internet Fibra'), findsOneWidget);
      expect(find.text('R\$ 150,00'), findsWidgets);

      // Verifica botão de dar baixa
      expect(find.text('Dar baixa no pagamento'), findsOneWidget);

      // Toca em dar baixa
      await tester.tap(find.text('Dar baixa no pagamento'));
      await tester.pumpAndSettle();

      // Verifica formulário de confirmação de pagamento
      expect(find.text('Confirmar pagamento'), findsOneWidget);
    },
  );

  testWidgets(
    'PayableActionModal exibe fatura de cartão com valor a informar e permite preencher',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final cardBillResponse = {
        'data': {
          'id': 77,
          'kind': 'card_bill',
          'description': 'Fatura Nubank',
          'amount': null,
          'paid': '0.00',
          'remaining': null,
          'due_date': '2026-03-20',
          'status': 'awaiting_amount',
          'overdue': false,
          'card': {'id': 1, 'name': 'Nubank Ultravioleta'},
        },
      };

      final client = MockClient((request) async {
        if (request.url.path.contains('/payables/77')) {
          if (request.method == 'PATCH') {
            return http.Response(
              jsonEncode({
                'data': {
                  'id': 77,
                  'kind': 'card_bill',
                  'description': 'Fatura Nubank',
                  'amount': '2500.00',
                  'paid': '0.00',
                  'remaining': '2500.00',
                  'due_date': '2026-03-20',
                  'status': 'open',
                  'overdue': false,
                },
              }),
              200,
            );
          }
          return http.Response(jsonEncode(cardBillResponse), 200);
        }
        if (request.url.path.contains('/accounts')) {
          return http.Response(jsonEncode(accountsResponse), 200);
        }
        return http.Response('{"message": "Not found"}', 404);
      });

      final api = ApiClient(baseUrl: 'http://api.test/api', client: client);

      await tester.pumpWidget(
        buildTestWidget(
          api: api,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showPayableModal(context, space: pf, payableId: 77),
              child: const Text('Abrir Fatura'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Fatura'));
      await tester.pumpAndSettle();

      // Verifica elementos de fatura com valor a informar
      expect(find.text('Fatura Nubank'), findsOneWidget);
      expect(find.text('Valor a informar'), findsWidgets);
      expect(find.text('Informar valor da fatura'), findsOneWidget);

      // Toca em informar valor da fatura
      await tester.tap(find.text('Informar valor da fatura'));
      await tester.pumpAndSettle();

      // Preenche o valor
      expect(find.text('Total da fatura (R\$)'), findsOneWidget);
      expect(find.text('Salvar total da fatura'), findsOneWidget);
    },
  );
}
