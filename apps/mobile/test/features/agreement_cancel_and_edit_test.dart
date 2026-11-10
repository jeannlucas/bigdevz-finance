import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/agreements/agreement_modal.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/receipt_attempts.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/categories/categories_repository.dart';
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

  final openAgreement = {
    'data': {
      'id': 10,
      'description': 'Consultoria Tech',
      'total': '1500.00',
      'installment_count': 1,
      'received': '0.00',
      'remaining': '1500.00',
      'paid_installments': 0,
      'overdue_installments': 0,
      'next_due_date': '2026-12-10',
      'is_cancelled': false,
      'cancel_reason': null,
      'installments': [
        {
          'id': 201,
          'agreement_id': 10,
          'number': 1,
          'due_date': '2026-12-10',
          'amount': '1500.00',
          'received': '0.00',
          'remaining': '1500.00',
          'status': 'pending',
          'overdue': false,
        },
      ],
    },
  };

  final cancelledAgreement = {
    'data': {
      'id': 11,
      'description': 'Serviço Cancelado',
      'total': '500.00',
      'installment_count': 1,
      'received': '0.00',
      'remaining': '500.00',
      'paid_installments': 0,
      'overdue_installments': 0,
      'next_due_date': '2026-12-10',
      'is_cancelled': true,
      'cancel_reason': 'Cliente desistiu do projeto',
      'installments': [
        {
          'id': 202,
          'agreement_id': 11,
          'number': 1,
          'due_date': '2026-12-10',
          'amount': '500.00',
          'received': '0.00',
          'remaining': '500.00',
          'status': 'pending',
          'overdue': false,
        },
      ],
    },
  };

  setUp(() {
    storage = MemorySessionStorage();
    requests = [];
  });

  Widget buildModal({required int agreementId, required ApiClient api}) {
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
        Provider(create: (_) => CategoriesRepository(api)),
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
                onPressed: () => showAgreementModal(
                  ctx,
                  space: pf,
                  agreementId: agreementId,
                ),
                child: const Text('Abrir modal'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'AgreementModal: exibe botões de editar e cancelar para conta em aberto e permite cancelar',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/spaces/1/agreements/10' &&
            request.method == 'GET') {
          return http.Response(jsonEncode(openAgreement), 200);
        }
        if (request.url.path == '/spaces/1/accounts' &&
            request.method == 'GET') {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (request.url.path == '/spaces/1/agreements/10/cancel' &&
            request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'data': {
                ...openAgreement['data']!,
                'is_cancelled': true,
                'cancel_reason': 'Lançado errado',
              },
            }),
            200,
          );
        }
        return http.Response('{"error": "not_found"}', 404);
      });

      final api = ApiClient(baseUrl: 'http://example.test', client: client);
      await tester.pumpWidget(buildModal(agreementId: 10, api: api));

      await tester.tap(find.text('Abrir modal'));
      await tester.pumpAndSettle();

      // Botões de editar e cancelar devem estar visíveis
      expect(find.byTooltip('Editar conta a receber'), findsOneWidget);
      expect(find.byTooltip('Cancelar conta a receber'), findsOneWidget);

      // Clica em cancelar
      await tester.tap(find.byTooltip('Cancelar conta a receber'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelar conta a receber'), findsWidgets);
      expect(find.text('Motivo do cancelamento *'), findsOneWidget);

      // Digita o motivo
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo do cancelamento *'),
        'Lançado errado',
      );
      await tester.pumpAndSettle();

      // Confirma cancelamento
      await tester.tap(find.text('Confirmar cancelamento'));
      await tester.pumpAndSettle();

      // Valida requisição de cancelamento
      final cancelReq = requests.firstWhere(
        (r) => r.url.path == '/spaces/1/agreements/10/cancel',
      );
      expect(cancelReq.method, 'POST');
      final body = jsonDecode(cancelReq.body) as Map<String, dynamic>;
      expect(body['reason'], 'Lançado errado');
    },
  );

  testWidgets(
    'AgreementModal: permite alterar valor e parcelas com pré-visualização e recálculo',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/spaces/1/agreements/10' &&
            request.method == 'GET') {
          return http.Response(jsonEncode(openAgreement), 200);
        }
        if (request.url.path == '/spaces/1/categories' &&
            request.method == 'GET') {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (request.url.path == '/spaces/1/accounts' &&
            request.method == 'GET') {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (request.url.path == '/spaces/1/agreements/10' &&
            request.method == 'PATCH') {
          return http.Response(
            jsonEncode({
              'data': {
                ...openAgreement['data']!,
                'total': '3000.00',
                'installment_count': 3,
                'installments': [
                  {
                    'id': 201,
                    'agreement_id': 10,
                    'number': 1,
                    'due_date': '2026-12-10',
                    'amount': '1000.00',
                    'received': '0.00',
                    'remaining': '1000.00',
                    'status': 'pending',
                    'overdue': false,
                  },
                ],
              },
            }),
            200,
          );
        }
        return http.Response('{"error": "not_found"}', 404);
      });

      final api = ApiClient(baseUrl: 'http://example.test', client: client);
      await tester.pumpWidget(buildModal(agreementId: 10, api: api));

      await tester.tap(find.text('Abrir modal'));
      await tester.pumpAndSettle();

      // Clica em editar
      await tester.tap(find.byTooltip('Editar conta a receber'));
      await tester.pumpAndSettle();

      expect(find.text('Editar conta a receber'), findsWidgets);
      expect(find.text('Valor e Parcelamento'), findsOneWidget);

      // Altera número de parcelas para 3
      final countFinder = find.widgetWithText(TextFormField, 'Nº Parcelas *');
      await tester.enterText(countFinder, '3');
      await tester.pumpAndSettle();

      // Altera valor total para 3000.00
      final amountFinder = find.widgetWithText(TextFormField, 'Valor total *');
      await tester.enterText(amountFinder, '3000,00');
      await tester.pumpAndSettle();

      // Verifica que o card de pré-visualização exibe o recálculo
      expect(
        find.text(
          'As parcelas em aberto serão recalculadas e redistribuídas deterministicamente.',
        ),
        findsOneWidget,
      );

      // Clica em Salvar e Recalcular
      await tester.tap(find.text('Salvar e Recalcular'));
      await tester.pumpAndSettle();

      // Deve abrir o diálogo de confirmação com double-check e diffs
      expect(find.text('Deseja realmente salvar?'), findsOneWidget);
      expect(find.text('VALOR TOTAL'), findsOneWidget);
      expect(find.text('NÚMERO DE PARCELAS'), findsOneWidget);
      await tester.tap(find.text('Confirmar e salvar'));
      await tester.pumpAndSettle();

      // Valida requisição enviada
      final patchReq = requests.firstWhere(
        (r) => r.url.path == '/spaces/1/agreements/10' && r.method == 'PATCH',
      );
      final body = jsonDecode(patchReq.body) as Map<String, dynamic>;
      expect(body['total'], '3000.00');
      expect(body['installment_count'], 3);
    },
  );

  testWidgets(
    'AgreementModal: exibe banner de cancelamento quando a conta está cancelada',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/spaces/1/agreements/11') {
          return http.Response(jsonEncode(cancelledAgreement), 200);
        }
        if (request.url.path == '/spaces/1/accounts') {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return http.Response('{"error": "not_found"}', 404);
      });

      final api = ApiClient(baseUrl: 'http://example.test', client: client);
      await tester.pumpWidget(buildModal(agreementId: 11, api: api));

      await tester.tap(find.text('Abrir modal'));
      await tester.pumpAndSettle();

      expect(find.text('Conta a receber cancelada'), findsOneWidget);
      expect(find.text('Motivo: Cliente desistiu do projeto'), findsOneWidget);
      expect(find.byTooltip('Cancelar conta a receber'), findsNothing);
      expect(find.byTooltip('Editar conta a receber'), findsNothing);
      expect(find.text('Dar baixa'), findsNothing);
      expect(find.text('Cancelada'), findsOneWidget);
    },
  );
}
