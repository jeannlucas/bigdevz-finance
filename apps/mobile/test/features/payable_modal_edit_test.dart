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
import 'package:bigdevz_finance/ui/confirm_changes_dialog.dart';
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
      'id': 42,
      'kind': 'single',
      'description': 'Internet Fibra',
      'amount': '150.00',
      'paid': '0.00',
      'remaining': '150.00',
      'due_date': '2026-03-10',
      'status': 'open',
      'overdue': false,
      'payments': [],
    },
  };

  final cancelledPayable = {
    'data': {
      'id': 43,
      'kind': 'single',
      'description': 'Plano Antigo',
      'amount': '99.00',
      'paid': '0.00',
      'remaining': '99.00',
      'due_date': '2026-03-10',
      'status': 'cancelled',
      'cancelled_at': '2026-03-01T10:00:00Z',
      'cancel_reason': 'Mudança de plano',
      'overdue': false,
      'payments': [],
    },
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
    'PayableModal: exibe botões de editar e cancelar para conta em aberto e permite cancelar',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/spaces/1/payables/42' &&
            request.method == 'GET') {
          return http.Response(jsonEncode(openPayable), 200);
        }
        if (request.url.path == '/spaces/1/accounts' &&
            request.method == 'GET') {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (request.url.path == '/spaces/1/payables/42/cancel' &&
            request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'data': {
                ...openPayable['data']!,
                'status': 'cancelled',
                'cancelled_at': '2026-03-01T10:00:00Z',
                'cancel_reason': 'Boleto incorreto',
              },
            }),
            200,
          );
        }
        return http.Response('{"error": "not_found"}', 404);
      });

      final api = ApiClient(baseUrl: 'http://example.test', client: client);
      await tester.pumpWidget(buildModal(payableId: 42, api: api));

      await tester.tap(find.text('Abrir modal payable'));
      await tester.pumpAndSettle();

      // Botões de editar e cancelar presentes no header
      expect(find.byTooltip('Editar conta a pagar'), findsOneWidget);
      expect(find.byTooltip('Cancelar conta a pagar'), findsOneWidget);

      // Clica em cancelar
      await tester.tap(find.byTooltip('Cancelar conta a pagar'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelar conta a pagar'), findsWidgets);
      expect(find.text('Motivo do cancelamento *'), findsOneWidget);

      // Digita o motivo
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo do cancelamento *'),
        'Boleto incorreto',
      );
      await tester.pumpAndSettle();

      // Confirma cancelamento
      await tester.tap(find.text('Confirmar cancelamento'));
      await tester.pumpAndSettle();

      // Valida requisição de cancelamento enviada
      final cancelReq = requests.firstWhere(
        (r) => r.url.path == '/spaces/1/payables/42/cancel',
      );
      expect(cancelReq.method, 'POST');
      final body = jsonDecode(cancelReq.body) as Map<String, dynamic>;
      expect(body['reason'], 'Boleto incorreto');
    },
  );

  testWidgets(
    'PayableModal: exibe banner de cancelamento quando a conta está cancelada',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/spaces/1/payables/43') {
          return http.Response(jsonEncode(cancelledPayable), 200);
        }
        if (request.url.path == '/spaces/1/accounts') {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return http.Response('{"error": "not_found"}', 404);
      });

      final api = ApiClient(baseUrl: 'http://example.test', client: client);
      await tester.pumpWidget(buildModal(payableId: 43, api: api));

      await tester.tap(find.text('Abrir modal payable'));
      await tester.pumpAndSettle();

      expect(find.text('Conta a pagar cancelada'), findsOneWidget);
      expect(find.text('Motivo: Mudança de plano'), findsOneWidget);
      expect(find.byTooltip('Cancelar conta a pagar'), findsNothing);
      expect(find.byTooltip('Editar conta a pagar'), findsNothing);
      expect(find.text('Dar baixa no pagamento'), findsNothing);
      expect(find.text('Esta conta foi cancelada'), findsOneWidget);
    },
  );

  testWidgets(
    'PayableModal: permite editar conta a pagar exibindo diálogo double-check com as alterações',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/spaces/1/payables/42' &&
            request.method == 'GET') {
          return http.Response(jsonEncode(openPayable), 200);
        }
        if (request.url.path == '/spaces/1/accounts' &&
            request.method == 'GET') {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (request.url.path == '/spaces/1/payables/42' &&
            request.method == 'PATCH') {
          return http.Response(
            jsonEncode({
              'data': {
                ...openPayable['data']!,
                'description': 'Internet Empresa 1Gbps',
                'amount': '250.00',
              },
            }),
            200,
          );
        }
        return http.Response('{"error": "not_found"}', 404);
      });

      final api = ApiClient(baseUrl: 'http://example.test', client: client);
      await tester.pumpWidget(buildModal(payableId: 42, api: api));

      await tester.tap(find.text('Abrir modal payable'));
      await tester.pumpAndSettle();

      // Clica no botão de editar
      await tester.tap(find.byTooltip('Editar conta a pagar'));
      await tester.pumpAndSettle();

      expect(find.text('Editar conta a pagar'), findsWidgets);

      // Altera descrição e valor
      final descField = find.widgetWithText(TextFormField, 'Descrição *');
      await tester.enterText(descField, 'Internet Empresa 1Gbps');
      await tester.pumpAndSettle();

      final amountField = find.widgetWithText(TextFormField, 'Valor *');
      await tester.enterText(amountField, '250,00');
      await tester.pumpAndSettle();

      // Clica em Salvar alterações
      await tester.tap(find.text('Salvar alterações'));
      await tester.pumpAndSettle();

      // Verifica que o diálogo de double check foi aberto listando as alterações
      expect(find.text('Deseja realmente salvar?'), findsOneWidget);
      expect(find.text('DESCRIÇÃO'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ConfirmChangesDialog),
          matching: find.text('INTERNET FIBRA'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ConfirmChangesDialog),
          matching: find.text('INTERNET EMPRESA 1GBPS'),
        ),
        findsOneWidget,
      );
      expect(find.text('VALOR'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ConfirmChangesDialog),
          matching: find.text('R\$ 150,00'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ConfirmChangesDialog),
          matching: find.text('R\$ 250,00'),
        ),
        findsOneWidget,
      );

      // Clica em confirmar e salvar
      await tester.tap(find.text('Confirmar e salvar'));
      await tester.pumpAndSettle();

      // Valida requisição PATCH enviada
      final patchReq = requests.firstWhere(
        (r) => r.url.path == '/spaces/1/payables/42' && r.method == 'PATCH',
      );
      final body = jsonDecode(patchReq.body) as Map<String, dynamic>;
      expect(body['description'], 'INTERNET EMPRESA 1GBPS');
      expect(body['amount'], '250.00');
    },
  );
}
