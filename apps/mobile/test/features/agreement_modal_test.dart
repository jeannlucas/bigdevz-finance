import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/agreements/agreement_modal.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/receipt_attempts.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
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

  final agreementResponse = {
    'data': {
      'id': 5,
      'description': 'Venda de Notebook',
      'total': '2000.00',
      'installment_count': 2,
      'received': '0.00',
      'remaining': '2000.00',
      'paid_installments': 0,
      'overdue_installments': 0,
      'next_due_date': '2026-03-10',
      'installments': [
        {
          'id': 101,
          'agreement_id': 5,
          'number': 1,
          'due_date': '2026-03-10',
          'amount': '1000.00',
          'received': '0.00',
          'remaining': '1000.00',
          'status': 'pending',
          'overdue': false,
        },
        {
          'id': 102,
          'agreement_id': 5,
          'number': 2,
          'due_date': '2026-04-10',
          'amount': '1000.00',
          'received': '0.00',
          'remaining': '1000.00',
          'status': 'pending',
          'overdue': false,
        },
      ],
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
    'AgreementActionModal exibe detalhes do acordo, parcelas e permite dar baixa inline',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.contains('/agreements/5')) {
          return http.Response(jsonEncode(agreementResponse), 200);
        }
        if (request.url.path.contains('/accounts')) {
          return http.Response(jsonEncode(accountsResponse), 200);
        }
        if (request.url.path.contains('/receipts')) {
          final isSecond =
              requests.where((r) => r.url.path.contains('/receipts')).length >
              1;
          final instId = isSecond ? 102 : 101;
          final instNum = isSecond ? 2 : 1;
          return http.Response(
            jsonEncode({
              'data': {
                'receipt': {
                  'id': isSecond ? 1000 : 999,
                  'installment_id': instId,
                  'account_id': 10,
                  'amount': '1000.00',
                  'received_on': '2026-03-10',
                  'kind': 'pix',
                },
                'installment': {
                  'id': instId,
                  'agreement_id': 5,
                  'number': instNum,
                  'due_date': '2026-03-10',
                  'amount': '1000.00',
                  'received': '1000.00',
                  'remaining': '0.00',
                  'status': 'paid',
                  'overdue': false,
                },
                'agreement': {'remaining': isSecond ? '0.00' : '1000.00'},
                'account': {'id': 10, 'balance': '2500.00'},
                'replayed': false,
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
                  showAgreementModal(context, space: pf, agreementId: 5),
              child: const Text('Abrir Modal'),
            ),
          ),
        ),
      );

      // Abre o modal
      await tester.tap(find.text('Abrir Modal'));
      await tester.pumpAndSettle();

      // Verifica exibição do título e parcelas
      expect(find.text('Venda de Notebook'), findsOneWidget);
      expect(find.text('Parcela 1 de 2'), findsOneWidget);
      expect(find.text('Parcela 2 de 2'), findsOneWidget);

      // Encontra botões de dar baixa
      final baixaButtons = find.text('Dar baixa');
      expect(baixaButtons, findsNWidgets(2));

      // Toca no primeiro botão de "Dar baixa"
      await tester.tap(baixaButtons.first);
      await tester.pumpAndSettle();

      // Agora deve estar na tela de formulário de baixa dentro do modal
      expect(find.text('Baixar Parcela 1'), findsOneWidget);
      expect(find.text('Confirmar recebimento'), findsOneWidget);
    },
  );

  testWidgets(
    'AgreementActionModal permite selecionar múltiplas parcelas e realizar baixa em lote',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.contains('/agreements/5')) {
          return http.Response(jsonEncode(agreementResponse), 200);
        }
        if (request.url.path.contains('/accounts')) {
          return http.Response(jsonEncode(accountsResponse), 200);
        }
        if (request.url.path.contains('/receipts')) {
          final isSecond =
              requests.where((r) => r.url.path.contains('/receipts')).length >
              1;
          final instId = isSecond ? 102 : 101;
          final instNum = isSecond ? 2 : 1;
          return http.Response(
            jsonEncode({
              'data': {
                'receipt': {
                  'id': isSecond ? 1000 : 999,
                  'installment_id': instId,
                  'account_id': 10,
                  'amount': '1000.00',
                  'received_on': '2026-03-10',
                  'kind': 'pix',
                },
                'installment': {
                  'id': instId,
                  'agreement_id': 5,
                  'number': instNum,
                  'due_date': '2026-03-10',
                  'amount': '1000.00',
                  'received': '1000.00',
                  'remaining': '0.00',
                  'status': 'paid',
                  'overdue': false,
                },
                'agreement': {'remaining': isSecond ? '0.00' : '1000.00'},
                'account': {'id': 10, 'balance': '2500.00'},
                'replayed': false,
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
                  showAgreementModal(context, space: pf, agreementId: 5),
              child: const Text('Abrir Modal'),
            ),
          ),
        ),
      );

      // Abre o modal
      await tester.tap(find.text('Abrir Modal'));
      await tester.pumpAndSettle();

      // Encontra opção de "Selecionar todas"
      final selectAllButton = find.text('Selecionar todas');
      expect(selectAllButton, findsOneWidget);

      await tester.tap(selectAllButton);
      await tester.pumpAndSettle();

      // Botão de baixa múltipla deve aparecer com o total das 2 parcelas (R$ 2.000,00)
      final batchBaixaButton = find.textContaining('Baixar selecionadas (2)');
      expect(batchBaixaButton, findsOneWidget);

      await tester.tap(batchBaixaButton);
      await tester.pumpAndSettle();

      // Deve exibir a tela unificada de baixa em lote
      expect(find.text('Baixar 2 parcelas'), findsOneWidget);
      expect(find.text('Confirmar recebimento das 2 parcelas'), findsOneWidget);

      // Confirma o recebimento em lote
      await tester.tap(find.text('Confirmar recebimento das 2 parcelas'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // Deve ter enviado 2 requisições de recebimento para a API
      final receiptRequests = requests
          .where((r) => r.url.path.contains('/receipts'))
          .toList();
      expect(receiptRequests.length, 2);
    },
  );
}
