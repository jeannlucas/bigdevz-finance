import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/transfers/transfer_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

const pf = Space(id: 1, kind: 'PF', name: 'Pessoal');

void main() {
  late FakeBackend backend;
  late MemorySessionStorage storage;

  final account1 = Account(
    id: 10,
    name: 'Conta Corrente',
    balance: const Money(150000), // R$ 1.500,00
    openingBalance: const Money(100000),
    openingBalanceDate: '2026-01-01',
  );

  final account2 = Account(
    id: 20,
    name: 'Poupança',
    balance: const Money(50000), // R$ 500,00
    openingBalance: const Money(50000),
    openingBalanceDate: '2026-01-01',
  );

  setUp(() {
    backend = FakeBackend();
    storage = MemorySessionStorage();
  });

  Widget createHarness({
    List<Account>? accounts,
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

    return MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<AccountsRepository>(create: (_) => AccountsRepository(api)),
          ChangeNotifierProvider<SessionController>.value(value: session),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  key: const ValueKey('open_transfer_screen'),
                  onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TransferFormScreen(space: pf, accounts: accounts),
                    ),
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openForm(
    WidgetTester tester, {
    List<Account>? accounts,
    double textScale = 1.0,
    Size size = const Size(402, 874),
  }) async {
    await tester.pumpWidget(
      createHarness(accounts: accounts, textScale: textScale, size: size),
    );
    await tester.tap(find.byKey(const ValueKey('open_transfer_screen')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'TransferFormScreen: renderiza seletores e campos com lista de contas',
    (tester) async {
      await openForm(tester, accounts: [account1, account2]);

      expect(find.text('Transferir entre contas'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('transfer_source_account')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transfer_destination_account')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('transfer_amount')), findsOneWidget);
      expect(find.byKey(const ValueKey('transfer_date')), findsOneWidget);
      expect(find.byKey(const ValueKey('transfer_notes')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('transfer_submit_button')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'TransferFormScreen: exibe mensagem quando há menos de 2 contas',
    (tester) async {
      await openForm(tester, accounts: [account1]);

      expect(find.text('Contas insuficientes'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('transfer_submit_button')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'TransferFormScreen: valida campos obrigatórios e rejeita contas iguais',
    (tester) async {
      await openForm(tester, accounts: [account1, account2]);

      // Clica em confirmar sem preencher nada
      await tester.tap(find.byKey(const ValueKey('transfer_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Selecione a conta de origem'), findsOneWidget);
      expect(find.text('Selecione a conta de destino'), findsOneWidget);
      expect(find.text('Informe o valor'), findsOneWidget);

      // Seleciona a mesma conta na origem e no destino
      await tester.tap(find.byKey(const ValueKey('transfer_source_account')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTA CORRENTE (R\$ 1.500,00)').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('transfer_destination_account')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTA CORRENTE (R\$ 1.500,00)').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('transfer_amount')),
        '100,00',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('transfer_submit_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('A conta de destino deve ser diferente da origem'),
        findsOneWidget,
      );
    },
  );

  testWidgets('TransferFormScreen: submete transferência com sucesso', (
    tester,
  ) async {
    backend.overrides['POST /spaces/1/transfers'] = (request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['source_account_id'], equals(10));
      expect(body['destination_account_id'], equals(20));
      expect(body['amount'], equals('250.00'));
      expect(request.headers['Idempotency-Key'], isNotEmpty);

      return FakeBackend.json({
        'data': {
          'id': 99,
          'space_id': 1,
          'source_account_id': 10,
          'destination_account_id': 20,
          'amount': '250.00',
          'transferred_at': '2026-02-15',
          'notes': 'Teste',
        },
      }, 201);
    };

    await openForm(tester, accounts: [account1, account2]);

    // Seleciona conta 1 na origem
    await tester.tap(find.byKey(const ValueKey('transfer_source_account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONTA CORRENTE (R\$ 1.500,00)').last);
    await tester.pumpAndSettle();

    // Seleciona conta 2 no destino
    await tester.tap(
      find.byKey(const ValueKey('transfer_destination_account')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('POUPANÇA (R\$ 500,00)').last);
    await tester.pumpAndSettle();

    // Digita valor
    await tester.enterText(
      find.byKey(const ValueKey('transfer_amount')),
      '250,00',
    );
    await tester.pumpAndSettle();

    // Submete
    await tester.tap(find.byKey(const ValueKey('transfer_submit_button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Transferência realizada com sucesso.'), findsOneWidget);
  });

  testWidgets(
    'TransferFormScreen: reflow e acessibilidade em viewport compacto de 320pt a 200% sem overflow',
    (tester) async {
      await openForm(
        tester,
        accounts: [account1, account2],
        size: const Size(320, 600),
        textScale: 2.0,
      );

      // Nenhum erro de overflow do Flutter
      expect(tester.takeException(), isNull);
      expect(find.text('Transferir entre contas'), findsOneWidget);

      final submitFinder = find.byKey(const ValueKey('transfer_submit_button'));
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(submitFinder, findsOneWidget);
    },
  );
}
