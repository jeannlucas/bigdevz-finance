import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/categories/categories_repository.dart';
import 'package:bigdevz_finance/features/payables/direct_expense_modal.dart';
import 'package:bigdevz_finance/features/payables/payable.dart';
import 'package:bigdevz_finance/features/payables/payable_item_adapter.dart';
import 'package:bigdevz_finance/features/payables/payables_repository.dart';
import 'package:bigdevz_finance/features/payables/payment_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

const pfSpace = Space(id: 1, kind: 'PF', name: 'Pessoal');

void main() {
  group(
    'Melhoria 4 & 5: Despesa Direta Débito e Recorrência com Valor Variável',
    () {
      test('Payable model reconhece flags isVariable e isDirectExpense', () {
        final variablePayable = Payable.fromJson({
          'id': 101,
          'space_id': 1,
          'kind': 'recurring',
          'status': 'awaiting_amount',
          'is_variable': true,
          'is_direct_expense': false,
          'amount': null,
          'amount_cents': null,
          'estimated_amount': '250.00',
          'estimated_amount_cents': 25000,
          'description': 'ENERGIA ELETRICA',
          'due_date': '2026-04-10',
        });
        expect(variablePayable.isVariable, isTrue);
        expect(variablePayable.isAwaitingAmount, isTrue);
        expect(variablePayable.isDirectExpense, isFalse);
        expect(variablePayable.estimatedAmount?.cents, 25000);

        final directExpense = Payable.fromJson({
          'id': 102,
          'space_id': 1,
          'kind': 'single',
          'status': 'paid',
          'is_variable': false,
          'is_direct_expense': true,
          'amount': '35.90',
          'amount_cents': 3590,
          'description': 'ALMOCO PADARIA',
          'due_date': '2026-03-10',
        });
        expect(directExpense.isDirectExpense, isTrue);
        expect(directExpense.isVariable, isFalse);
      });

      test(
        'PayableItemAdapter exibe status Aguardando valor para conta variável',
        () {
          final variablePayable = Payable.fromJson({
            'id': 101,
            'space_id': 1,
            'kind': 'recurring',
            'status': 'awaiting_amount',
            'is_variable': true,
            'amount': null,
            'estimated_amount': '150.00',
            'estimated_amount_cents': 15000,
            'description': 'ENERGIA',
            'due_date': '2026-04-10',
          });

          final adapter = PayableItemAdapter(variablePayable);
          expect(adapter.statusLabel, 'Aguardando valor');
          expect(adapter.isAwaitingAmount, isTrue);
        },
      );

      testWidgets(
        'DirectExpenseModal valida conta de origem, valor e submete despesa paga à vista',
        (tester) async {
          final backend = FakeBackend();
          final client = ApiClient(
            baseUrl: 'http://api.test/api',
            client: backend.client,
          );
          client.token = backend.validToken;

          backend.routes['GET /spaces/1/accounts'] = {
            'data': [
              {
                'id': 5,
                'space_id': 1,
                'name': 'CONTA CORRENTE',
                'balance': '1000.00',
                'balance_cents': 100000,
              },
            ],
          };
          backend.routes['GET /spaces/1/categories?type=expense'] = {
            'data': [
              {
                'id': 20,
                'space_id': 1,
                'name': 'Alimentação',
                'type': 'expense',
                'icon': 'restaurant',
                'color': '#EA580C',
              },
            ],
          };
          backend.routes['POST /spaces/1/payables/direct-expense'] = {
            'data': {
              'payable': {
                'id': 201,
                'space_id': 1,
                'kind': 'single',
                'status': 'paid',
                'is_direct_expense': true,
                'amount': '35.90',
                'amount_cents': 3590,
                'description': 'ALMOCO RESTAURANTE',
                'due_date': '2026-03-10',
              },
              'replayed': false,
            },
          };

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                Provider.value(value: AccountsRepository(client)),
                Provider.value(value: CategoriesRepository(client)),
                Provider.value(value: PayablesRepository(client)),
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
              child: MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () => showDirectExpenseModal(
                        context,
                        space: pfSpace,
                        preselectedAccountId: 5,
                      ),
                      child: const Text('Abrir Despesa'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Abrir Despesa'));
          await tester.pumpAndSettle();

          expect(find.text('Registrar Despesa Paga'), findsOneWidget);
          expect(find.text('Conta de Origem *'), findsOneWidget);

          // Preenche valor
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Valor Pago *'),
            '3590',
          );
          // Preenche descrição
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Descrição da Despesa *'),
            'Almoco restaurante',
          );
          await tester.pumpAndSettle();

          // Confirma registro de despesa paga
          final confirmBtn = find.text('Confirmar Despesa Paga');
          await tester.ensureVisible(confirmBtn);
          await tester.tap(confirmBtn);
          await tester.pumpAndSettle();

          // Confirma que a chamada para /payables/direct-expense foi enviada
          final directReq = backend.requests.firstWhere(
            (r) => r.url.path == '/api/spaces/1/payables/direct-expense',
          );
          expect(directReq.method, 'POST');
          expect(directReq.headers['Idempotency-Key'], isNotNull);
        },
      );

      testWidgets(
        'PaymentFormScreen permite informar valor efetivo ao liquidar conta com valor variável',
        (tester) async {
          final backend = FakeBackend();
          final client = ApiClient(
            baseUrl: 'http://api.test/api',
            client: backend.client,
          );
          client.token = backend.validToken;

          final variablePayable = Payable.fromJson({
            'id': 301,
            'space_id': 1,
            'kind': 'recurring',
            'status': 'awaiting_amount',
            'is_variable': true,
            'amount': null,
            'amount_cents': null,
            'estimated_amount': '200.00',
            'estimated_amount_cents': 20000,
            'description': 'CONTA DE ENERGIA',
            'due_date': '2026-03-20',
          });

          backend.routes['GET /spaces/1/accounts'] = {
            'data': [
              {
                'id': 9,
                'space_id': 1,
                'name': 'BANCO INTER',
                'balance': '2000.00',
                'balance_cents': 200000,
              },
            ],
          };

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                Provider.value(value: AccountsRepository(client)),
                Provider.value(value: PayablesRepository(client)),
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
              child: MaterialApp(
                home: PaymentFormScreen(
                  space: pfSpace,
                  payable: variablePayable,
                  accounts: const [
                    Account(
                      id: 9,
                      name: 'BANCO INTER',
                      openingBalance: Money(200000),
                      openingBalanceDate: '2026-01-01',
                      balance: Money(200000),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Campo de valor deve permitir digitar o valor da fatura
          expect(find.text('Valor efetivo a pagar *'), findsOneWidget);
          expect(
            find.textContaining('Estimativa planejada: R\$ 200,00'),
            findsOneWidget,
          );

          await tester.enterText(
            find.widgetWithText(TextFormField, 'Valor efetivo a pagar *'),
            '18550',
          );
          await tester.pumpAndSettle();

          expect(find.text('185,50'), findsOneWidget);
        },
      );

      test('PayablesRepository.registerDirectExpense desserializa payload canônico da API sem aninhamento redundante', () async {
        final backend = FakeBackend();
        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: backend.client,
        );
        client.token = backend.validToken;

        backend.routes['POST /spaces/1/payables/direct-expense'] = {
          'data': {
            'id': 105,
            'space_id': 1,
            'kind': 'single',
            'description': 'ALMOCO EXECUTIVO',
            'amount': '35.90',
            'amount_cents': 3590,
            'due_date': '2026-03-10',
            'status': 'paid',
            'is_direct_expense': true,
          },
          'replayed': false,
        };

        final repo = PayablesRepository(client);
        final res = await repo.registerDirectExpense(
          1,
          accountId: 1,
          amount: const Money(3590),
          date: '2026-03-10',
          description: 'ALMOCO EXECUTIVO',
          idempotencyKey: 'test-key-1',
        );

        expect(res.payable.id, 105);
        expect(res.payable.description, 'ALMOCO EXECUTIVO');
        expect(res.replayed, isFalse);
      });
    },
  );
}
