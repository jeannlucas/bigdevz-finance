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

  final openPayable = {
    'data': {
      'id': 300,
      'kind': 'single',
      'description': 'Boleto em atraso',
      'amount': '100.00',
      'paid': '0.00',
      'remaining': '100.00',
      'due_date': '2026-02-10',
      'status': 'overdue',
      'overdue': true,
      'payments': [],
    },
  };

  final accountsResponse = {
    'data': [
      {
        'id': 10,
        'name': 'Banco Inter',
        'opening_balance': '500.00',
        'opening_balance_date': '2026-01-01',
        'balance': '2000.00',
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
    'Permite informar juros e calcula total a debitar em tempo real (AC-PAY-INT-001..007)',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.contains('/payables/300') &&
            request.method == 'GET') {
          return http.Response(jsonEncode(openPayable), 200);
        }
        if (request.url.path.contains('/accounts')) {
          return http.Response(jsonEncode(accountsResponse), 200);
        }
        if (request.url.path.contains('/payables/300/payments')) {
          return http.Response(
            jsonEncode({
              'data': {
                'payment': {
                  'id': 601,
                  'account_id': 10,
                  'amount': '115.00',
                  'principal': '100.00',
                  'interest': '15.00',
                  'fine': '0.00',
                  'discount': '0.00',
                  'total': '115.00',
                  'paid_on': '2026-03-01',
                  'reversal': null,
                },
                'payable': {
                  'id': 300,
                  'kind': 'single',
                  'description': 'Boleto em atraso',
                  'amount': '100.00',
                  'paid': '100.00',
                  'remaining': '0.00',
                  'due_date': '2026-02-10',
                  'status': 'paid',
                  'overdue': false,
                  'payments': [],
                },
                'account': {'id': 10, 'balance': '1885.00'},
                'replayed': false,
              },
            }),
            201,
          );
        }
        return http.Response('{"message": "Not found"}', 404);
      });

      final api = ApiClient(baseUrl: 'https://example.com/api', client: client);

      await tester.pumpWidget(buildModal(payableId: 300, api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir modal payable'));
      await tester.pumpAndSettle();

      // Clica em "Registrar pagamento"
      await tester.tap(find.text('Registrar pagamento'));
      await tester.pumpAndSettle();

      // Seleciona a conta bancária no dropdown
      await tester.tap(find.byType(DropdownButtonFormField<int>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('BANCO INTER (R\$ 2.000,00)').last);
      await tester.pumpAndSettle();

      // Expande seção de juros, multa e desconto
      await tester.tap(find.text('Juros, multa e desconto (opcional)'));
      await tester.pumpAndSettle();

      // Informa Juros de R$ 15,00
      final interestField = find.byKey(const ValueKey('interest-input'));
      expect(interestField, findsOneWidget);
      await tester.enterText(interestField, '15,00');
      await tester.pumpAndSettle();

      // Verifica cálculo em tempo real do Total a debitar: R$ 115,00
      expect(find.textContaining('R\$ 115,00'), findsWidgets);

      // Confirma pagamento
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar pagamento'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      // Verifica chamada à API com payload exato
      final paymentReq = requests.firstWhere(
        (r) => r.url.path.contains('/payables/300/payments'),
      );
      final body = jsonDecode(paymentReq.body) as Map<String, dynamic>;
      expect(body['amount'], '100.00'); // principal
      expect(body['interest_amount'], '15.00'); // juros
      expect(paymentReq.headers.containsKey('Idempotency-Key'), isTrue);
    },
  );
}
