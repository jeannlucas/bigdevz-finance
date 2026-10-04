import 'dart:async';
import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/agreements/agreement.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/receipt_form_screen.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

const space = Space(id: 1, kind: 'PF', name: 'Pessoal');
final installment = Installment(
  id: 22,
  agreementId: 5,
  number: 2,
  dueDate: '2026-03-10',
  amount: Money.parse('2000.00'),
  received: const Money(0),
  remaining: Money.parse('2000.00'),
  status: InstallmentStatus.pending,
  overdue: false,
  agreementDescription: 'Venda de veículo',
  installmentCount: 12,
);
final accounts = [
  Account(id: 7, name: 'Banco PF', openingBalance: Money.parse('1000.00'), openingBalanceDate: '2026-01-01', balance: Money.parse('3000.00')),
];

Map<String, Object?> success({bool replayed = false}) => {
      'data': {
        'receipt': {'id': 99, 'installment_id': 22, 'account_id': 7, 'amount': '500.00', 'received_on': '2026-03-10'},
        'installment': {
          'id': 22, 'agreement_id': 5, 'number': 2, 'due_date': '2026-03-10', 'amount': '2000.00',
          'received': '500.00', 'remaining': '1500.00', 'status': 'partial', 'overdue': false,
        },
        'agreement': {'remaining': '21500.00'},
        'account': {'balance': '3500.00'},
        'replayed': replayed,
      }
    };

void main() {
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  late SessionController session;
  ReceiptResult? popped;

  Future<void> open(WidgetTester tester) async {
    requests = [];
    popped = null;
    final api = ApiClient(baseUrl: 'http://api.test/api', client: MockClient((request) {
      requests.add(request);
      return respond(request);
    }));
    session = SessionController(api: api, auth: AuthRepository(api), storage: MemorySessionStorage());
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: AgreementsRepository(api)),
        ChangeNotifierProvider.value(value: session),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => popped = await Navigator.of(context).push<ReceiptResult>(MaterialPageRoute(
                  builder: (_) => ReceiptFormScreen(space: space, installment: installment, accounts: accounts, today: DateTime(2026, 3, 10)),
                )),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> typeAmount(WidgetTester tester, String digits) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Valor recebido'), digits);
    await tester.pump();
  }

  testWidgets('mostra o espaço e sugere o restante da parcela', (tester) async {
    respond = (_) async => FakeBackend.json(success());
    await open(tester);
    expect(find.text('Recebimento no espaço Pessoal (PF)'), findsOneWidget);
    expect(find.text('2.000,00'), findsOneWidget);
    expect(find.text('Banco PF'), findsOneWidget);
  });

  testWidgets('duplo toque envia uma única requisição e só confirma após a API', (tester) async {
    final gate = Completer<void>();
    respond = (_) async {
      await gate.future;
      return FakeBackend.json(success(), 201);
    };
    await open(tester);
    await typeAmount(tester, '50000');

    await tester.tap(find.text('Confirmar recebimento'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(requests, hasLength(1));
    expect(popped, isNull, reason: 'nada é confirmado antes da resposta da API');
    final versionBefore = session.dataVersion;

    gate.complete();
    await tester.pumpAndSettle();
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body, {'account_id': 7, 'amount': '500.00', 'received_on': '2026-03-10'});
    expect(requests.single.url.path, '/api/spaces/1/installments/22/receipts');
    expect(popped?.accountBalance.brl, r'R$ 3.500,00');
    expect(session.dataVersion, greaterThan(versionBefore), reason: 'telas recarregam após o recebimento');
  });

  testWidgets('falha de rede permite nova tentativa com a mesma chave; outro valor gera chave nova', (tester) async {
    var attempt = 0;
    respond = (_) async {
      attempt++;
      if (attempt == 1) throw http.ClientException('rede');
      if (attempt == 2) return FakeBackend.json({'message': 'x', 'errors': {'amount': ['O valor excede o restante da parcela (1500.00).']}}, 422);
      return FakeBackend.json(success(), 201);
    };
    await open(tester);
    await typeAmount(tester, '50000');

    await tester.tap(find.text('Confirmar recebimento'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tentar de novo não duplica o recebimento'), findsOneWidget);
    expect(popped, isNull);

    await tester.tap(find.text('Confirmar recebimento'));
    await tester.pumpAndSettle();
    expect(requests[1].headers['Idempotency-Key'], requests[0].headers['Idempotency-Key']);
    expect(find.text('O valor excede o restante da parcela (1500.00).'), findsOneWidget);

    await typeAmount(tester, '40000');
    await tester.tap(find.text('Confirmar recebimento'));
    await tester.pumpAndSettle();
    expect(requests[2].headers['Idempotency-Key'], isNot(requests[1].headers['Idempotency-Key']));
    expect(requests[2].headers['Idempotency-Key'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(popped, isNotNull);
  });

  testWidgets('valida valor zerado e acima do restante antes de enviar', (tester) async {
    respond = (_) async => FakeBackend.json(success(), 201);
    await open(tester);

    await typeAmount(tester, '0');
    await tester.tap(find.text('Confirmar recebimento'));
    await tester.pump();
    expect(find.text('Informe o valor recebido.'), findsOneWidget);

    await typeAmount(tester, '200001');
    await tester.tap(find.text('Confirmar recebimento'));
    await tester.pump();
    expect(find.text(r'Máximo para esta parcela: R$ 2.000,00.'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('sem conta no espaço orienta o cadastro', (tester) async {
    respond = (_) async => FakeBackend.json(success());
    requests = [];
    final api = ApiClient(baseUrl: 'http://api.test/api', client: MockClient((request) => respond(request)));
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: AgreementsRepository(api)),
        ChangeNotifierProvider(create: (_) => SessionController(api: api, auth: AuthRepository(api), storage: MemorySessionStorage())),
      ],
      child: MaterialApp(home: ReceiptFormScreen(space: space, installment: installment, accounts: const [])),
    ));
    expect(find.text('Nenhuma conta neste espaço'), findsOneWidget);
  });
}
