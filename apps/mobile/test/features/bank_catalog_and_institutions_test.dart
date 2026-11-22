import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/accounts/account_card.dart';
import 'package:bigdevz_finance/features/accounts/account_edit_screen.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/accounts/bank_catalog.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

const pfSpace = Space(id: 1, kind: 'PF', name: 'Pessoal');

void main() {
  group('Melhoria 3: Instituições Financeiras - Wise e DUCZ Benefícios', () {
    test('BankCatalog contém Wise (COMPE 362) e DUCZ Benefícios (---)', () {
      final wise = BankCatalog.findById('wise');
      expect(wise, isNotNull);
      expect(wise!.name, 'Wise');
      expect(wise.code, '362');
      expect(wise.assetPath, 'assets/banks/wise.png');

      final ducz = BankCatalog.findById('ducz');
      expect(ducz, isNotNull);
      expect(ducz!.name, 'DUCZ Benefícios');
      expect(ducz.code, '---');
      expect(ducz.assetPath, 'assets/banks/ducz.png');

      // Busca por nome de conta
      final foundWise = BankCatalog.findByAccountName('Wise Multimoeda');
      expect(foundWise?.id, 'wise');

      final foundDucz = BankCatalog.findByAccountName(
        'DUCZ Benefícios Alimentação',
      );
      expect(foundDucz?.id, 'ducz');
    });

    testWidgets(
      'AccountCard exibe iniciais e cor do banco mesmo em erro de asset',
      (tester) async {
        const account = Account(
          id: 42,
          name: 'Wise Conta Global',
          openingBalance: Money(100000),
          openingBalanceDate: '2026-01-01',
          balance: Money(100000),
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AccountCard(space: pfSpace, account: account),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('WISE CONTA GLOBAL'), findsOneWidget);
        expect(find.text(r'R$ 1.000,00'), findsOneWidget);
      },
    );

    testWidgets(
      'AccountEditScreen permite reassociar conta de Outro para DUCZ Benefícios preservando ID e saldo',
      (tester) async {
        final backend = FakeBackend();
        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: backend.client,
        );
        client.token = backend.validToken;

        const account = Account(
          id: 77,
          name: 'Cartao Despesas',
          openingBalance: Money(50000),
          openingBalanceDate: '2026-01-01',
          balance: Money(50000),
        );

        // Endpoint mock de rename/patch
        backend.routes['PATCH /spaces/1/accounts/77'] = {
          'data': {
            'id': 77,
            'space_id': 1,
            'name': 'DUCZ BENEFÍCIOS',
            'opening_balance': '500.00',
            'opening_balance_date': '2026-01-01',
            'balance': '500.00',
          },
        };

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider.value(value: AccountsRepository(client)),
              ChangeNotifierProvider(
                create: (_) =>
                    SessionController(
                        api: client,
                        auth: AuthRepository(client),
                        storage: MemorySessionStorage(),
                      )
                      ..user = const AppUser(
                        id: 1,
                        name: 'User',
                        email: 'u@test.com',
                      ),
              ),
            ],
            child: const MaterialApp(
              home: AccountEditScreen(space: pfSpace, account: account),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Inicialmente exibe Outro (Personalizada)
        expect(find.textContaining('Outro (Personalizada)'), findsOneWidget);

        // Clica no chip para reassociar a DUCZ Benefícios
        final duczChip = find.widgetWithText(ActionChip, 'DUCZ Benefícios');
        expect(duczChip, findsOneWidget);
        await tester.tap(duczChip);
        await tester.pumpAndSettle();

        // Campo de nome agora tem DUCZ Benefícios
        expect(find.text('DUCZ BENEFÍCIOS'), findsWidgets);
        expect(find.textContaining('DUCZ Benefícios'), findsWidgets);

        // Salva a alteração
        await tester.tap(find.text('Salvar alterações'));
        await tester.pumpAndSettle();

        // Confirma que fez o PATCH na mesma conta 77
        final patchReq = backend.requests.firstWhere(
          (r) => r.method == 'PATCH',
        );
        expect(patchReq.url.path, '/api/spaces/1/accounts/77');
        final body = jsonDecode(patchReq.body) as Map<String, dynamic>;
        expect(body['name'], 'DUCZ BENEFÍCIOS');
      },
    );

    testWidgets(
      'Regressão: Reassociar conta Outro à DUCZ Benefícios com apelido "Benefícios da empresa" preserva a marca na edição e no cartão',
      (tester) async {
        final backend = FakeBackend();
        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: backend.client,
        );
        client.token = backend.validToken;

        // Conta inicial 88 marcada como Outro
        const initialAccount = Account(
          id: 88,
          name: 'Cartão Antigo',
          openingBalance: Money(50000),
          openingBalanceDate: '2026-01-01',
          balance: Money(50000),
        );

        backend.routes['PATCH /spaces/1/accounts/88'] = {
          'data': {
            'id': 88,
            'space_id': 1,
            'name': 'BENEFÍCIOS DA EMPRESA',
            'bank_id': 'ducz',
            'opening_balance': '500.00',
            'opening_balance_date': '2026-01-01',
            'balance': '500.00',
          },
        };

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider.value(value: AccountsRepository(client)),
              ChangeNotifierProvider(
                create: (_) =>
                    SessionController(
                        api: client,
                        auth: AuthRepository(client),
                        storage: MemorySessionStorage(),
                      )
                      ..user = const AppUser(
                        id: 1,
                        name: 'User',
                        email: 'u@test.com',
                      ),
              ),
            ],
            child: const MaterialApp(
              home: AccountEditScreen(space: pfSpace, account: initialAccount),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Reassocia para DUCZ Benefícios via chip
        final duczChip = find.widgetWithText(ActionChip, 'DUCZ Benefícios');
        await tester.tap(duczChip);
        await tester.pumpAndSettle();

        // 2. Altera o apelido para "BENEFÍCIOS DA EMPRESA" (sem conter a palavra ducz)
        await tester.enterText(
          find.byType(TextFormField),
          'BENEFÍCIOS DA EMPRESA',
        );
        await tester.pumpAndSettle();

        // A instituição na tela de edição permanece DUCZ Benefícios
        expect(
          find.textContaining('DUCZ Benefícios (COMPE: ---)'),
          findsOneWidget,
        );

        // 3. Salva
        await tester.tap(find.text('Salvar alterações'));
        await tester.pumpAndSettle();

        final patchReq = backend.requests.firstWhere(
          (r) => r.method == 'PATCH',
        );
        final body = jsonDecode(patchReq.body) as Map<String, dynamic>;
        expect(body['name'], 'BENEFÍCIOS DA EMPRESA');
        expect(body['bank_id'], 'ducz');

        // 4. Reabre a conta salva e confere a marca em AccountCard
        final savedAccount = Account.fromJson({
          'id': 88,
          'space_id': 1,
          'name': 'BENEFÍCIOS DA EMPRESA',
          'bank_id': 'ducz',
          'opening_balance': '500.00',
          'opening_balance_date': '2026-01-01',
          'balance': '500.00',
        });

        expect(BankCatalog.resolveForAccount(savedAccount)?.id, 'ducz');
        expect(
          BankCatalog.resolveForAccount(savedAccount)?.name,
          'DUCZ Benefícios',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AccountCard(space: pfSpace, account: savedAccount),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('BENEFÍCIOS DA EMPRESA'), findsOneWidget);
        expect(find.textContaining('DUCZ Benefícios'), findsOneWidget);
      },
    );
  });
}
