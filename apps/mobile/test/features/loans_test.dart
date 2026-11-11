import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/loans/loan_form_screen.dart';
import 'package:bigdevz_finance/features/loans/loans_repository.dart';
import 'package:bigdevz_finance/features/loans/loans_screen.dart';
import 'package:bigdevz_finance/features/settings/preferences_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

const pf = Space(id: 1, kind: 'PF', name: 'Pessoal');

void main() {
  late FakeBackend backend;
  late MemorySessionStorage storage;

  final account1 = Account(
    id: 10,
    name: 'Conta Corrente',
    balance: const Money(200000), // R$ 2.000,00
    openingBalance: const Money(100000),
    openingBalanceDate: '2026-01-01',
  );

  setUp(() {
    backend = FakeBackend();
    storage = MemorySessionStorage();
  });

  Widget createHarness({
    required Widget child,
    double textScale = 1.0,
    Size size = const Size(402, 874),
  }) {
    final client = backend.client;
    final api = ApiClient(baseUrl: 'http://api.test/api', client: client);
    api.token = 'token-valido';

    final session = SessionController(
      api: api,
      auth: AuthRepository(api),
      storage: storage,
    );

    final preferences = PreferencesController(storage: storage);

    return MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<AccountsRepository>(create: (_) => AccountsRepository(api)),
          Provider<LoansRepository>(create: (_) => LoansRepository(api)),
          ChangeNotifierProvider<SessionController>.value(value: session),
          ChangeNotifierProvider<PreferencesController>.value(
            value: preferences,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  key: const ValueKey('open_child_screen'),
                  onPressed: () =>
                      Navigator.of(ctx)
                          .push(MaterialPageRoute(builder: (_) => child)),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openScreen(
    WidgetTester tester, {
    required Widget child,
    double textScale = 1.0,
    Size size = const Size(402, 874),
  }) async {
    await tester.pumpWidget(
      createHarness(child: child, textScale: textScale, size: size),
    );
    await tester.tap(find.byKey(const ValueKey('open_child_screen')));
    await tester.pumpAndSettle();
  }

  group('LoansScreen', () {
    testWidgets(
      'renderiza lista de empréstimos tomados e concedidos e cards de resumo',
      (tester) async {
        backend.overrides['GET /spaces/1/loans'] = (_) => http.Response(
          jsonEncode({
            'data': [
              {
                'id': 1,
                'space_id': 1,
                'user_id': 1,
                'kind': 'taken',
                'title': 'Financiamento Imóvel',
                'counterparty': 'Caixa Econômica',
                'principal': '100000.00',
                'total': '140000.00',
                'interest': '40000.00',
                'paid_or_received': '20000.00',
                'remaining': '120000.00',
                'installment_count': 120,
                'first_due_date': '2026-03-01',
                'disbursement_account_id': 10,
                'disbursed_at': '2026-02-01',
                'status': 'active',
                'notes': 'Contrato SFH',
              },
              {
                'id': 2,
                'space_id': 1,
                'user_id': 1,
                'kind': 'granted',
                'title': 'Empréstimo João',
                'counterparty': 'João da Silva',
                'principal': '1000.00',
                'total': '1100.00',
                'interest': '100.00',
                'paid_or_received': '0.00',
                'remaining': '1100.00',
                'installment_count': 2,
                'first_due_date': '2026-04-01',
                'status': 'active',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );

        await openScreen(tester, child: const LoansScreen(space: pf));

        expect(find.text('Empréstimos'), findsOneWidget);
        expect(find.text('FINANCIAMENTO IMÓVEL'), findsOneWidget);
        expect(find.text('CAIXA ECONÔMICA'), findsOneWidget);
        expect(find.text('Tomado'), findsOneWidget);
        expect(find.text('EMPRÉSTIMO JOÃO'), findsOneWidget);
        expect(find.text('JOÃO DA SILVA'), findsOneWidget);
        expect(find.text('Concedido'), findsOneWidget);

        // Resumo de dívidas e a receber
        expect(find.text('Dívida Total (Tomados)'), findsOneWidget);
        expect(find.text('A Receber (Concedidos)'), findsOneWidget);
      },
    );

    testWidgets('exibe estado vazio quando não há empréstimos', (tester) async {
      backend.overrides['GET /spaces/1/loans'] = (_) => http.Response(
        jsonEncode({'data': []}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

      await openScreen(tester, child: const LoansScreen(space: pf));

      expect(find.text('Nenhum empréstimo encontrado'), findsOneWidget);
      expect(find.text('Novo Empréstimo'), findsOneWidget);
    });
  });

  group('LoanFormScreen', () {
    testWidgets('valida campos obrigatórios e juros dinâmicos', (tester) async {
      await openScreen(
        tester,
        child: LoanFormScreen(space: pf, accounts: [account1]),
      );

      // Clicar em salvar sem preencher
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loan_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Informe uma descrição.'), findsOneWidget);
      expect(find.text('Informe o credor/devedor.'), findsOneWidget);
      expect(find.text('Informe o principal.'), findsOneWidget);
      expect(find.text('Informe o total.'), findsOneWidget);

      // Preencher principal maior que total
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Capital de Giro',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Banco do Brasil',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        '500000',
      ); // 5.000,00
      await tester.enterText(
        find.byType(TextFormField).at(3),
        '400000',
      ); // 4.000,00
      await tester.pumpAndSettle();

      expect(
        find.text('O total não pode ser menor que o principal.'),
        findsOneWidget,
      );

      // Corrigir total com juros
      await tester.enterText(
        find.byType(TextFormField).at(3),
        '600000',
      ); // 6.000,00
      await tester.pumpAndSettle();

      expect(find.textContaining('Juros/Encargos:'), findsOneWidget);
    });

    testWidgets('submete empréstimo tomado com desembolso em conta', (
      tester,
    ) async {
      backend.overrides['POST /spaces/1/loans'] = (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['kind'], 'taken');
        expect(body['title'], 'EMPRÉSTIMO INVESTIMENTO');
        expect(body['counterparty'], 'ITAÚ BBA');
        expect(body['principal'], '10000.00');
        expect(body['total'], '12000.00');
        expect(body['installment_count'], 12);
        expect(body['disbursement_account_id'], 10);
        expect(body['disbursed_at'], isNotNull);
        expect(request.headers['idempotency-key'], isNotNull);

        return http.Response(
          jsonEncode({
            'data': {
              'id': 99,
              'space_id': 1,
              'user_id': 1,
              'kind': 'taken',
              'title': 'Empréstimo Investimento',
              'counterparty': 'Itaú BBA',
              'principal': '10000.00',
              'total': '12000.00',
              'interest': '2000.00',
              'paid_or_received': '0.00',
              'remaining': '12000.00',
              'installment_count': 12,
              'first_due_date': '2026-03-01',
              'disbursement_account_id': 10,
              'disbursed_at': '2026-02-15',
              'status': 'active',
            },
          }),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      };

      await openScreen(
        tester,
        child: LoanFormScreen(space: pf, accounts: [account1]),
      );

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Empréstimo Investimento',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'Itaú BBA');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        '1000000',
      ); // 10.000,00
      await tester.enterText(
        find.byType(TextFormField).at(3),
        '1200000',
      ); // 12.000,00
      await tester.pumpAndSettle();

      // Ativar switch de desembolso
      final switchFinder = find.byType(Switch);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Confirmar
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loan_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Empréstimo registrado com sucesso!'), findsOneWidget);
    });

    testWidgets(
      'reflow e acessibilidade em viewport compacto de 320pt a 200% sem overflow',
      (tester) async {
        await openScreen(
          tester,
          child: LoanFormScreen(space: pf, accounts: [account1]),
          size: const Size(320, 600),
          textScale: 2.0,
        );

        // Não deve haver exceção de RenderFlex overflow
        expect(tester.takeException(), isNull);
      },
    );
  });
}
