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

  final paidPayable = {
    'data': {
      'id': 100,
      'kind': 'single',
      'description': 'Aluguel do Mês',
      'amount': '1000.00',
      'paid': '1000.00',
      'remaining': '0.00',
      'due_date': '2026-03-10',
      'status': 'paid',
      'overdue': false,
      'payments': [
        {
          'id': 501,
          'account_id': 10,
          'amount': '1000.00',
          'principal': '1000.00',
          'interest': '0.00',
          'fine': '0.00',
          'discount': '0.00',
          'total': '1000.00',
          'paid_on': '2026-03-05',
          'reversal': null,
        },
      ],
    },
  };

  final accountsResponse = {
    'data': [
      {
        'id': 10,
        'name': 'Banco do Brasil',
        'opening_balance': '500.00',
        'opening_balance_date': '2026-01-01',
        'balance': '2500.00',
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
    'Exibe histórico de pagamentos e permite estornar com justificativa obrigatória (AC-PAY-REV-001..004)',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.contains('/payables/100') &&
            request.method == 'GET') {
          return http.Response(jsonEncode(paidPayable), 200);
        }
        if (request.url.path.contains('/accounts')) {
          return http.Response(jsonEncode(accountsResponse), 200);
        }
        if (request.url.path.contains('/payments/501/reversal')) {
          return http.Response(
            jsonEncode({
              'data': {
                'original': {
                  'id': 501,
                  'account_id': 10,
                  'amount': '1000.00',
                  'paid_on': '2026-03-05',
                  'reversal': {'kind': 'reversal', 'reason': 'Baixa indevida'},
                },
                'payable': {
                  'id': 100,
                  'kind': 'single',
                  'description': 'Aluguel do Mês',
                  'amount': '1000.00',
                  'paid': '0.00',
                  'remaining': '1000.00',
                  'due_date': '2026-03-10',
                  'status': 'open',
                  'overdue': false,
                  'payments': [],
                },
                'accounts': [
                  {'id': 10, 'balance': '3500.00'},
                ],
                'replayed': false,
              },
            }),
            200,
          );
        }
        return http.Response('{"message": "Not found"}', 404);
      });

      final api = ApiClient(baseUrl: 'https://example.com/api', client: client);

      await tester.pumpWidget(buildModal(payableId: 100, api: api));
      await tester.pumpAndSettle();

      // Clica para abrir o modal
      await tester.tap(find.text('Abrir modal payable'));
      await tester.pumpAndSettle();

      // 1. Verifica exibição do histórico de pagamentos (AC-PAY-REV-001)
      expect(find.textContaining('Histórico de pagamentos'), findsOneWidget);
      expect(find.text('Liquidado'), findsOneWidget);
      expect(find.text('Estornar'), findsOneWidget);

      // 2. Clica em Estornar (AC-PAY-REV-002)
      await tester.tap(find.text('Estornar'));
      await tester.pumpAndSettle();

      // 3. Verifica diálogo de estorno e prévia de impacto financeiro (AC-PAY-REV-004)
      expect(find.text('Estornar pagamento'), findsOneWidget);
      expect(
        find.textContaining('Impacto financeiro do estorno:'),
        findsOneWidget,
      );
      expect(find.textContaining('Saldo a devolver na conta'), findsOneWidget);
      expect(
        find.textContaining('Valor a reabrir na conta a pagar'),
        findsOneWidget,
      );

      // 4. Tenta confirmar sem justificativa -> validação bloqueia (AC-PAY-REV-003)
      await tester.tap(find.text('Confirmar estorno'));
      await tester.pumpAndSettle();
      expect(
        find.text('Informe a justificativa do estorno (mínimo 3 caracteres).'),
        findsOneWidget,
      );

      // 5. Preenche justificativa válida e confirma
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Justificativa do estorno *'),
        'Baixa indevida por engano',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirmar estorno'));
      await tester.pumpAndSettle();

      // 6. Verifica requisição à API
      final reversalReq = requests.firstWhere(
        (r) => r.url.path.contains('/payments/501/reversal'),
      );
      final body = jsonDecode(reversalReq.body) as Map<String, dynamic>;
      expect(body['reason'], 'Baixa indevida por engano');
      expect(reversalReq.headers.containsKey('Idempotency-Key'), isTrue);
    },
  );
}
