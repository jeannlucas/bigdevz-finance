import 'dart:async';
import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/agreements/agreement.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/receipt_attempts.dart';
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
import '../support/fake_receipts_api.dart';

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
  Account(
    id: 7,
    name: 'Banco PF',
    openingBalance: Money.parse('1000.00'),
    openingBalanceDate: '2026-01-01',
    balance: Money.parse('3000.00'),
  ),
  Account(
    id: 8,
    name: 'Reserva PF',
    openingBalance: Money.parse('0.00'),
    openingBalanceDate: '2026-01-01',
    balance: Money.parse('0.00'),
  ),
];

Map<String, Object?> success({String amount = '500.00'}) => {
  'data': {
    'receipt': {
      'id': 99,
      'installment_id': 22,
      'account_id': 7,
      'amount': amount,
      'received_on': '2026-03-10',
    },
    'installment': {
      'id': 22,
      'agreement_id': 5,
      'number': 2,
      'due_date': '2026-03-10',
      'amount': '2000.00',
      'received': amount,
      'remaining': '1500.00',
      'status': 'partial',
      'overdue': false,
    },
    'agreement': {'remaining': '21500.00'},
    'account': {'balance': '3500.00'},
    'replayed': false,
  },
};

void main() {
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  late SessionController session;
  late MemorySessionStorage storage;
  ReceiptAttemptOutcome? popped;
  var closed = false;

  /// [client] substitui a resposta fixa por uma API simulada com estado.
  Future<void> open(WidgetTester tester, {http.Client? client}) async {
    requests = [];
    popped = null;
    closed = false;
    storage = MemorySessionStorage();
    // Tela de iPhone (390 x 844 pontos), o alvo de desenvolvimento.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = ApiClient(
      baseUrl: 'http://api.test/api',
      client:
          client ??
          MockClient((request) {
            requests.add(request);
            return respond(request);
          }),
    );
    session = SessionController(
      api: api,
      auth: AuthRepository(api),
      storage: MemorySessionStorage(),
    )..user = const AppUser(id: 1, name: 'Pessoa', email: 'p@example.com');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider.value(value: AgreementsRepository(api)),
          Provider(
            create: (context) => ReceiptAttempts(
              repository: context.read<AgreementsRepository>(),
              storage: storage,
            ),
          ),
          ChangeNotifierProvider.value(value: session),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    popped = await Navigator.of(context)
                        .push<ReceiptAttemptOutcome>(
                          MaterialPageRoute(
                            builder: (_) => ReceiptFormScreen(
                              space: space,
                              installment: installment,
                              accounts: accounts,
                              today: DateTime(2026, 3, 10),
                            ),
                          ),
                        );
                    closed = true;
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> chooseAccount(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> chooseKind(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> typeAmount(WidgetTester tester, String digits) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Valor recebido'),
      digits,
    );
    await tester.pump();
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pump();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> reviewPartial(WidgetTester tester, String digits) async {
    await chooseAccount(tester, 'Banco PF');
    await chooseKind(tester, 'Parcial');
    await typeAmount(tester, digits);
    await tapButton(tester, 'Revisar recebimento');
  }

  Map<String, dynamic> body(int index) =>
      jsonDecode(requests[index].body) as Map<String, dynamic>;

  /// Valor exibido na linha da revisão com o rótulo [label].
  Finder reviewValue(String label, String value) => find.descendant(
    of: find.byKey(ValueKey('review-$label')),
    matching: find.text(value),
  );

  testWidgets('conta e tipo começam sem escolha e são obrigatórios', (
    tester,
  ) async {
    respond = (_) async => FakeBackend.json(success(), 201);
    await open(tester);
    expect(find.text('Recebimento no espaço Pessoal (PF)'), findsOneWidget);
    expect(find.text('Banco PF'), findsNothing, reason: 'sem pré-seleção');

    await tapButton(tester, 'Revisar recebimento');
    expect(find.text('Escolha a conta de destino.'), findsOneWidget);
    expect(
      find.text('Escolha se o recebimento é total ou parcial.'),
      findsOneWidget,
    );
    expect(find.text('Confirmar recebimento'), findsNothing);
    expect(requests, isEmpty);
  });

  testWidgets('recebimento total usa o restante e quita a parcela', (
    tester,
  ) async {
    respond = (_) async => FakeBackend.json(success(amount: '2000.00'), 201);
    await open(tester);
    await chooseAccount(tester, 'Reserva PF');
    await chooseKind(tester, 'Total');
    expect(
      find.widgetWithText(TextFormField, 'Valor recebido'),
      findsNothing,
      reason: 'no total o valor não é digitado',
    );
    expect(find.text(r'R$ 2.000,00'), findsOneWidget);

    await tapButton(tester, 'Revisar recebimento');
    expect(reviewValue('Acordo', 'Venda de veículo'), findsOneWidget);
    expect(reviewValue('Parcela', '2/12 · vence 10/03/2026'), findsOneWidget);
    expect(reviewValue('Tipo', 'Total'), findsOneWidget);
    expect(reviewValue('Valor', r'R$ 2.000,00'), findsOneWidget);
    expect(reviewValue('Conta', 'Reserva PF'), findsOneWidget);
    expect(reviewValue('Espaço', 'Pessoal (PF)'), findsOneWidget);
    expect(reviewValue('Data', '10/03/2026'), findsOneWidget);
    expect(
      reviewValue('Restante', r'R$ 0,00 · parcela quitada'),
      findsOneWidget,
    );
    expect(requests, isEmpty, reason: 'revisar não grava nada');

    await tapButton(tester, 'Confirmar recebimento');
    expect(body(0), {
      'account_id': 8,
      'amount': '2000.00',
      'received_on': '2026-03-10',
    });
    expect(popped, isNotNull);
  });

  testWidgets('recebimento parcial mostra o restante após e envia o valor', (
    tester,
  ) async {
    respond = (_) async => FakeBackend.json(success(), 201);
    await open(tester);
    await reviewPartial(tester, '50000');
    expect(reviewValue('Tipo', 'Parcial'), findsOneWidget);
    expect(reviewValue('Valor', r'R$ 500,00'), findsOneWidget);
    expect(reviewValue('Restante', r'R$ 1.500,00'), findsOneWidget);

    await tapButton(tester, 'Confirmar recebimento');
    expect(body(0)['amount'], '500.00');
    expect(requests.single.url.path, '/api/spaces/1/installments/22/receipts');
    expect(popped?.result?.accountBalance.brl, r'R$ 3.500,00');
  });

  testWidgets('parcial valida zero, valor integral e acima do restante', (
    tester,
  ) async {
    respond = (_) async => FakeBackend.json(success(), 201);
    await open(tester);
    await chooseAccount(tester, 'Banco PF');
    await chooseKind(tester, 'Parcial');

    await typeAmount(tester, '0');
    await tapButton(tester, 'Revisar recebimento');
    expect(find.text('Informe o valor recebido.'), findsOneWidget);

    await typeAmount(tester, '200000');
    await tapButton(tester, 'Revisar recebimento');
    expect(
      find.text('Esse é o valor integral da parcela: escolha Total.'),
      findsOneWidget,
    );

    await typeAmount(tester, '200001');
    await tapButton(tester, 'Revisar recebimento');
    expect(
      find.text(r'Máximo para esta parcela: R$ 2.000,00.'),
      findsOneWidget,
    );
    expect(requests, isEmpty);
  });

  testWidgets('voltar e corrigir não grava e preserva os dados', (
    tester,
  ) async {
    respond = (_) async => FakeBackend.json(success(), 201);
    await open(tester);
    await reviewPartial(tester, '50000');

    await tapButton(tester, 'Voltar e corrigir');
    expect(find.text('Revisar recebimento'), findsOneWidget);
    expect(find.text('500,00'), findsOneWidget);
    expect(find.text('Banco PF'), findsOneWidget);

    // O voltar do sistema na revisão também retorna ao formulário.
    await tapButton(tester, 'Revisar recebimento');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Revisar recebimento'), findsOneWidget);
    expect(closed, isFalse);

    // Sair do formulário fecha sem resultado.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(popped, isNull);
    expect(requests, isEmpty);
  });

  testWidgets('duplo toque envia uma única requisição e só fecha após a API', (
    tester,
  ) async {
    final gate = Completer<void>();
    respond = (_) async {
      await gate.future;
      return FakeBackend.json(success(), 201);
    };
    await open(tester);
    await reviewPartial(tester, '50000');

    await tester.tap(find.text('Confirmar recebimento'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(requests, hasLength(1));
    expect(popped, isNull, reason: 'nada é confirmado antes da API');
    final versionBefore = session.dataVersion;

    gate.complete();
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(popped, isNotNull);
    expect(
      session.dataVersion,
      greaterThan(versionBefore),
      reason: 'telas recarregam após a confirmação',
    );
  });

  testWidgets(
    'resposta perdida após gravar: dados travados, verificação usa a chave '
    'original e não duplica',
    (tester) async {
      final fake = FakeReceiptsApi()..script.add(Delivery.loseResponse);
      await open(tester, client: fake.client);
      await reviewPartial(tester, '50000');
      await tapButton(tester, 'Confirmar recebimento');
      expect(fake.receipts, hasLength(1), reason: 'a API gravou');

      // Sem caminho para alterar conta, valor ou data nem enviar outra chave.
      expect(find.text('Recebimento não confirmado'), findsOneWidget);
      expect(
        find.textContaining('Ainda não conseguimos confirmar este recebimento'),
        findsOneWidget,
      );
      expect(find.text('Voltar e corrigir'), findsNothing);
      expect(find.text('Confirmar recebimento'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(reviewValue('Valor', r'R$ 500,00'), findsOneWidget);

      // Toques repetidos na verificação: uma única requisição.
      await tester.tap(find.text('Verificar recebimento'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(fake.receiptRequests, hasLength(2));
      expect(
        fake.receiptRequests.map((r) => r.headers['Idempotency-Key']).toSet(),
        hasLength(1),
      );
      expect(fake.receiptRequests.map((r) => r.body).toSet(), hasLength(1));
      expect(fake.receipts, hasLength(1));
      expect(fake.balanceCents, 150000, reason: 'saldo muda uma única vez');
      expect(popped?.state, ReceiptAttemptState.confirmed);
      expect(
        popped?.message,
        r'Recebimento já estava registrado: R$ 500,00 em Banco PF.',
      );
    },
  );

  testWidgets('verificação que falha de novo continua pendente', (
    tester,
  ) async {
    final fake = FakeReceiptsApi()
      ..script.addAll([Delivery.dropBeforeServer, Delivery.serverError]);
    await open(tester, client: fake.client);
    await reviewPartial(tester, '50000');
    await tapButton(tester, 'Confirmar recebimento');
    await tapButton(tester, 'Verificar recebimento');

    expect(find.text('Verificar recebimento'), findsOneWidget);
    expect(find.text('Voltar e corrigir'), findsNothing);
    expect(popped, isNull);
    expect(fake.receipts, isEmpty);
    expect(await storage.read('pending_receipt.1.1.22'), isNotNull);

    await tapButton(tester, 'Verificar recebimento');
    expect(
      fake.receipts,
      hasLength(1),
      reason: 'a tentativa original, uma vez',
    );
    expect(fake.balanceCents, 150000);
    expect(popped?.message, startsWith('Recebimento confirmado'));
  });

  testWidgets('verificar depois mantém a tentativa guardada', (tester) async {
    final fake = FakeReceiptsApi()..script.add(Delivery.loseResponse);
    await open(tester, client: fake.client);
    await reviewPartial(tester, '50000');
    await tapButton(tester, 'Confirmar recebimento');

    await tapButton(tester, 'Verificar depois');
    expect(closed, isTrue);
    expect(popped, isNull);
    final stored = jsonDecode(
      (await storage.read('pending_receipt.1.1.22'))!,
    ) as Map<String, dynamic>;
    expect(
      stored['idempotency_key'],
      fake.receiptRequests.single.headers['Idempotency-Key'],
    );
    expect(stored['amount'], '500.00');
  });

  testWidgets(
    'recusa 422 volta ao formulário sem gravar e permite nova tentativa',
    (tester) async {
      final fake = FakeReceiptsApi()..script.add(Delivery.dropBeforeServer);
      await open(tester, client: fake.client);
      // A parcela já recebeu R$ 1.800,00 em outro aparelho: R$ 500,00 excede.
      fake.seed(7, 180000, '2026-03-09');
      await reviewPartial(tester, '50000');
      await tapButton(tester, 'Confirmar recebimento');
      await tapButton(tester, 'Verificar recebimento');

      expect(find.text('Revisar recebimento'), findsOneWidget);
      expect(
        find.text(
          'A API recusou a tentativa e nada foi gravado. Corrija os dados e '
          'revise de novo.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('O valor excede o restante da parcela (200.00).'),
        findsOneWidget,
      );
      expect(await storage.read('pending_receipt.1.1.22'), isNull);

      await typeAmount(tester, '20000');
      await tapButton(tester, 'Revisar recebimento');
      await tapButton(tester, 'Confirmar recebimento');
      final keys = fake.receiptRequests
          .map((r) => r.headers['Idempotency-Key'])
          .toList();
      expect(keys[0], keys[1], reason: 'verificação com a chave original');
      expect(keys[2], isNot(keys[1]), reason: 'nova operação após a prova');
      expect(fake.receipts.map((r) => r.amountCents), [180000, 20000]);
      expect(popped?.state, ReceiptAttemptState.confirmed);
    },
  );

  testWidgets('401 e 409 na verificação não liberam correção', (tester) async {
    final fake = FakeReceiptsApi()
      ..script.addAll([
        Delivery.loseResponse,
        Delivery.unauthorized,
        Delivery.conflict,
      ]);
    await open(tester, client: fake.client);
    await reviewPartial(tester, '50000');
    await tapButton(tester, 'Confirmar recebimento');

    await tapButton(tester, 'Verificar recebimento');
    expect(find.textContaining('Sua sessão expirou'), findsOneWidget);
    expect(find.text('Voltar e corrigir'), findsNothing);

    await tapButton(tester, 'Verificar recebimento');
    expect(
      find.textContaining('já foi usada com outros dados'),
      findsOneWidget,
    );
    expect(find.text('Voltar e corrigir'), findsNothing);
    expect(await storage.read('pending_receipt.1.1.22'), isNotNull);
    expect(fake.receipts, hasLength(1));
  });

  testWidgets('sem conta no espaço orienta o cadastro', (tester) async {
    final api = ApiClient(
      baseUrl: 'http://api.test/api',
      client: MockClient((_) async => FakeBackend.json(success())),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider.value(value: AgreementsRepository(api)),
          ChangeNotifierProvider(
            create: (_) => SessionController(
              api: api,
              auth: AuthRepository(api),
              storage: MemorySessionStorage(),
            ),
          ),
        ],
        child: MaterialApp(
          home: ReceiptFormScreen(
            space: space,
            installment: installment,
            accounts: const [],
          ),
        ),
      ),
    );
    expect(find.text('Nenhuma conta neste espaço'), findsOneWidget);
  });
}
