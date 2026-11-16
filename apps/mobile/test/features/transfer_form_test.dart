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
const pj = Space(id: 2, kind: 'PJ', name: 'Empresa');

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
    List<Space>? spaces,
    double textScale = 1.0,
    Size size = const Size(402, 874),
    Space? initialSpace,
    int? initialDestinationSpaceId,
  }) {
    final client = backend.client;
    final api = ApiClient(baseUrl: 'http://api.test/api', client: client);
    api.token = 'token-valido';

    final session = SessionController(
      api: api,
      auth: AuthRepository(api),
      storage: storage,
    );
    session.spaces = spaces ?? const [pf];

    final space = initialSpace ?? pf;

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
                      builder: (_) => TransferFormScreen(
                        space: space,
                        accounts: accounts,
                        initialDestinationSpaceId: initialDestinationSpaceId,
                      ),
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
    List<Space>? spaces,
    double textScale = 1.0,
    Size size = const Size(402, 874),
    Space? initialSpace,
    int? initialDestinationSpaceId,
  }) async {
    await tester.pumpWidget(
      createHarness(
        accounts: accounts,
        spaces: spaces,
        textScale: textScale,
        size: size,
        initialSpace: initialSpace,
        initialDestinationSpaceId: initialDestinationSpaceId,
      ),
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
        find.text(
          'Registro contábil de movimentação: não executa Pix no banco.',
        ),
        findsOneWidget,
      );
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

  testWidgets('TransferFormScreen: submete transferência interna com sucesso', (
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

    // Avança para revisão
    await tester.tap(find.byKey(const ValueKey('transfer_submit_button')));
    await tester.pumpAndSettle();

    // Valida que está na tela de revisão com os dados detalhados
    expect(find.text('Revisar transferência'), findsWidgets);
    expect(find.text('ORIGEM (SAÍDA)'), findsOneWidget);
    expect(find.text('DESTINO (ENTRADA)'), findsOneWidget);
    expect(find.text('R\$ 250,00'), findsOneWidget);

    // Rola até o botão de confirmação e confirma
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer_confirm_button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Transferência realizada com sucesso.'), findsOneWidget);
  });

  testWidgets(
    'TransferFormScreen: realiza transferência entre espaços distintos (PJ -> PF) com sucesso',
    (tester) async {
      // Mock das listagens de contas por espaço
      backend.overrides['GET /spaces/2/accounts'] = (request) =>
          FakeBackend.json({
            'data': [
              {
                'id': 30,
                'name': 'Itaú PJ',
                'balance': '10000.00',
                'opening_balance': '10000.00',
                'opening_balance_date': '2026-01-01',
                'archived_at': null,
              },
            ],
          });

      backend.overrides['GET /spaces/1/accounts'] = (request) =>
          FakeBackend.json({
            'data': [
              {
                'id': 10,
                'name': 'Nubank PF',
                'balance': '1500.00',
                'opening_balance': '1000.00',
                'opening_balance_date': '2026-01-01',
                'archived_at': null,
              },
            ],
          });

      backend.overrides['POST /spaces/2/transfers'] = (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['destination_space_id'], equals(1));
        expect(body['source_account_id'], equals(30));
        expect(body['destination_account_id'], equals(10));
        expect(body['amount'], equals('500.00'));
        expect(body['notes'], equals('Reembolso de despesa'));

        return FakeBackend.json({
          'data': {
            'id': 101,
            'space_id': 2,
            'destination_space_id': 1,
            'source_account_id': 30,
            'destination_account_id': 10,
            'amount': '500.00',
            'transferred_at': '2026-02-15',
            'notes': 'Reembolso de despesa',
            'is_cross_space': true,
          },
        }, 201);
      };

      await openForm(
        tester,
        spaces: [pj, pf],
        initialSpace: pj,
        initialDestinationSpaceId: pf.id,
      );

      // Verifica exibição do badge de transferência entre espaços
      expect(
        find.text('Entre espaços: Empresa (PJ) → Pessoal (PF)'),
        findsOneWidget,
      );

      // Seleciona conta Itaú PJ na origem
      await tester.tap(find.byKey(const ValueKey('transfer_source_account')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ITAÚ PJ (R\$ 10.000,00)').last);
      await tester.pumpAndSettle();

      // Seleciona conta Nubank PF no destino
      await tester.tap(
        find.byKey(const ValueKey('transfer_destination_account')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('NUBANK PF (R\$ 1.500,00)').last);
      await tester.pumpAndSettle();

      // Digita valor e observação
      await tester.enterText(
        find.byKey(const ValueKey('transfer_amount')),
        '500,00',
      );
      await tester.enterText(
        find.byKey(const ValueKey('transfer_notes')),
        'Reembolso de despesa',
      );
      await tester.pumpAndSettle();

      // Rola até o botão e avança para revisão
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      final submitFinder = find.byKey(const ValueKey('transfer_submit_button'));
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      // Verifica elementos da tela de revisão
      expect(find.text('Revisar transferência'), findsWidgets);
      expect(find.text('ORIGEM (SAÍDA)'), findsOneWidget);
      expect(find.text('DESTINO (ENTRADA)'), findsOneWidget);
      expect(
        find.text('Entre espaços distintos: Empresa (PJ) → Pessoal (PF)'),
        findsOneWidget,
      );
      expect(find.text('R\$ 500,00'), findsOneWidget);
      expect(find.text('Reembolso de despesa'), findsOneWidget);

      // Rola até o botão de confirmação e confirma
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('transfer_confirm_button')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.text('Transferência entre espaços registrada com sucesso.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'TransferFormScreen: abre com espaço PF como origem quando aberto no espaço PF e contas sem pré-seleção',
    (tester) async {
      await openForm(
        tester,
        spaces: [pf, pj],
        initialSpace: pf,
        accounts: [account1, account2],
      );

      // Espaço de origem inicial é PF
      final sourceSpaceFinder = find.byKey(
        const ValueKey('transfer_source_space'),
      );
      expect(sourceSpaceFinder, findsOneWidget);
      final dropdown = tester.widget<DropdownButtonFormField<int>>(
        sourceSpaceFinder,
      );
      expect(dropdown.initialValue, equals(pf.id));

      // Nenhuma conta pré-selecionada
      final sourceAccDropdown = tester.widget<DropdownButtonFormField<int>>(
        find.byKey(const ValueKey('transfer_source_account')),
      );
      expect(sourceAccDropdown.initialValue, isNull);

      final destAccDropdown = tester.widget<DropdownButtonFormField<int>>(
        find.byKey(const ValueKey('transfer_destination_account')),
      );
      expect(destAccDropdown.initialValue, isNull);
    },
  );

  testWidgets(
    'TransferFormScreen: abre com espaço PJ como origem quando aberto no espaço PJ e contas sem pré-seleção',
    (tester) async {
      await openForm(
        tester,
        spaces: [pf, pj],
        initialSpace: pj,
        accounts: [account1, account2],
      );

      // Espaço de origem inicial é PJ
      final sourceSpaceFinder = find.byKey(
        const ValueKey('transfer_source_space'),
      );
      expect(sourceSpaceFinder, findsOneWidget);
      final dropdown = tester.widget<DropdownButtonFormField<int>>(
        sourceSpaceFinder,
      );
      expect(dropdown.initialValue, equals(pj.id));

      // Nenhuma conta pré-selecionada
      final sourceAccDropdown = tester.widget<DropdownButtonFormField<int>>(
        find.byKey(const ValueKey('transfer_source_account')),
      );
      expect(sourceAccDropdown.initialValue, isNull);

      final destAccDropdown = tester.widget<DropdownButtonFormField<int>>(
        find.byKey(const ValueKey('transfer_destination_account')),
      );
      expect(destAccDropdown.initialValue, isNull);
    },
  );

  testWidgets(
    'TransferFormScreen: troca do espaço de origem limpa a conta de origem selecionada',
    (tester) async {
      backend.overrides['GET /spaces/2/accounts'] = (request) =>
          FakeBackend.json({
            'data': [
              {
                'id': 30,
                'name': 'Itaú PJ',
                'balance': '10000.00',
                'opening_balance': '10000.00',
                'opening_balance_date': '2026-01-01',
                'archived_at': null,
              },
            ],
          });

      await openForm(
        tester,
        spaces: [pf, pj],
        initialSpace: pf,
        accounts: [account1, account2],
      );

      // Seleciona conta 1 no espaço PF
      await tester.tap(find.byKey(const ValueKey('transfer_source_account')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTA CORRENTE (R\$ 1.500,00)').last);
      await tester.pumpAndSettle();

      // Confirma que a conta 1 está selecionada
      expect(find.text('CONTA CORRENTE (R\$ 1.500,00)'), findsOneWidget);

      // Troca o espaço de origem para PJ (id: 2)
      await tester.tap(find.byKey(const ValueKey('transfer_source_space')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empresa (PJ)').last);
      await tester.pumpAndSettle();

      // Verifica que a conta selecionada foi resetada/limpa
      expect(find.text('CONTA CORRENTE (R\$ 1.500,00)'), findsNothing);
      expect(find.text('Selecione uma conta'), findsWidgets);
    },
  );

  testWidgets(
    'TransferFormScreen: permite voltar e editar a partir da tela de revisão',
    (tester) async {
      await openForm(tester, accounts: [account1, account2]);

      // Seleciona contas e valor
      await tester.tap(find.byKey(const ValueKey('transfer_source_account')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTA CORRENTE (R\$ 1.500,00)').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('transfer_destination_account')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('POUPANÇA (R\$ 500,00)').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('transfer_amount')),
        '150,00',
      );
      await tester.pumpAndSettle();

      // Avança para revisão
      await tester.tap(find.byKey(const ValueKey('transfer_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('ORIGEM (SAÍDA)'), findsOneWidget);
      expect(find.text('DESTINO (ENTRADA)'), findsOneWidget);

      // Rola até o botão de voltar e editar
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('transfer_back_button')));
      await tester.pumpAndSettle();

      // Verifica que voltou ao formulário preservando os dados
      expect(find.text('ORIGEM (SAÍDA)'), findsNothing);
      expect(find.text('DESTINO (ENTRADA)'), findsNothing);
      expect(find.byKey(const ValueKey('transfer_back_button')), findsNothing);
      expect(find.text('CONTA CORRENTE (R\$ 1.500,00)'), findsOneWidget);
      expect(find.text('POUPANÇA (R\$ 500,00)'), findsOneWidget);
      expect(find.text('150,00'), findsOneWidget);
    },
  );

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
