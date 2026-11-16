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
      expect(find.text('INTERNET FIBRA'), findsOneWidget);
      expect(find.text('R\$ 150,00'), findsWidgets);

      // Verifica botão de registrar pagamento
      expect(find.text('Registrar pagamento'), findsOneWidget);

      // Toca em registrar pagamento
      await tester.tap(find.text('Registrar pagamento'));
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
      expect(find.text('FATURA NUBANK'), findsOneWidget);
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

  testWidgets(
    'PayableActionModal exige seleção explícita de conta bancária sem pré-seleção',
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
        if (request.url.path.contains('/payments')) {
          return http.Response(
            jsonEncode({
              'data': {
                'payment': {'id': 1, 'amount': '150.00'},
                'payable': {'id': 42, 'status': 'paid'},
                'account': {'id': 10, 'balance': '1350.00'},
              },
            }),
            201,
          );
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

      await tester.tap(find.text('Abrir Modal Pagável'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Registrar pagamento'));
      await tester.pumpAndSettle();

      // 1. Campo inicia sem conta selecionada exibindo o hint
      expect(find.text('Selecione uma conta'), findsOneWidget);

      // 2. Tentar confirmar sem selecionar conta exibe mensagem clara
      await tester.tap(find.text('Confirmar pagamento'));
      await tester.pumpAndSettle();

      expect(
        find.text('Selecione uma conta bancária para debitar o pagamento.'),
        findsOneWidget,
      );
      expect(requests.where((r) => r.url.path.contains('/payments')), isEmpty);

      // 3. Seleciona a conta no dropdown
      await tester.tap(find.text('Selecione uma conta'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('NUBANK (R\$ 1.500,00)').last);
      await tester.pumpAndSettle();

      // 4. Confirma pagamento com sucesso
      await tester.tap(find.text('Confirmar pagamento'));
      await tester.pumpAndSettle();

      expect(
        requests.where((r) => r.url.path.contains('/payments')),
        isNotEmpty,
      );
    },
  );
}
