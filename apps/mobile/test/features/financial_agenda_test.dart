import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/agreements/agreement_item_adapter.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/agreements_tab.dart';
import 'package:bigdevz_finance/features/agreements/receipt_attempts.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/categories/categories_repository.dart';
import 'package:bigdevz_finance/features/payables/payable_creations.dart';
import 'package:bigdevz_finance/features/payables/payable_item_adapter.dart';
import 'package:bigdevz_finance/features/payables/payables_repository.dart';
import 'package:bigdevz_finance/features/payables/payables_tab.dart';
import 'package:bigdevz_finance/ui/financial/financial_desktop_table.dart';
import 'package:bigdevz_finance/ui/financial/financial_mobile_card.dart';

import '../support/fake_backend.dart';
import '../support/fake_payables_api.dart';

const pf = Space(id: 1, kind: 'PF', name: 'Pessoal');

void main() {
  group('Agenda Financeira Escalável - Desktop vs Mobile', () {
    late FakePayablesApi fakePayables;
    late MemorySessionStorage storage;

    setUp(() {
      fakePayables = FakePayablesApi();
      storage = MemorySessionStorage();
    });

    Widget wrapWidget({
      required Widget child,
      required ApiClient client,
      Size size = const Size(1200, 900),
    }) {
      return MediaQuery(
        data: MediaQueryData(size: size),
        child: MultiProvider(
          providers: [
            Provider.value(value: AgreementsRepository(client)),
            Provider.value(value: AccountsRepository(client)),
            Provider.value(value: PayablesRepository(client)),
            Provider.value(value: CategoriesRepository(client)),
            Provider(
              create: (context) => PayableCreations(
                repository: context.read<PayablesRepository>(),
                storage: storage,
              ),
            ),
            Provider(
              create: (context) => ReceiptAttempts(
                repository: context.read<AgreementsRepository>(),
                storage: storage,
                payables: context.read<PayablesRepository>(),
              ),
            ),
            ChangeNotifierProvider(
              create: (_) =>
                  SessionController(
                      api: client,
                      auth: AuthRepository(client),
                      storage: MemorySessionStorage(),
                    )
                    ..user = const AppUser(
                      id: 1,
                      name: 'Demo',
                      email: 'demo@example.com',
                    ),
            ),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        ),
      );
    }

    testWidgets(
      'Desktop (1200px): PayablesTab renderiza FinancialDesktopTableHeader e FinancialDesktopTableRow com ação rápida Pagar',
      (tester) async {
        tester.view.physicalSize = const Size(1200 * 3, 900 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        fakePayables.payables.clear();
        fakePayables.payables[1] = FakePayable(1, 'Aluguel Corporativo', 350000)
          ..dueDate = '2026-03-05';

        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: fakePayables.client,
        );

        await tester.pumpWidget(
          wrapWidget(
            child: const PayablesTab(space: pf),
            client: client,
            size: const Size(1200, 900),
          ),
        );
        await tester.pumpAndSettle();

        // No Desktop (>= 840px), renderiza tabela densa com cabeçalho e linha
        expect(find.byType(FinancialDesktopTableHeader), findsOneWidget);
        expect(
          find.byType(FinancialDesktopTableRow<PayableItemAdapter>),
          findsOneWidget,
        );
        expect(find.text('Vencimento'), findsOneWidget);
        expect(find.text('Descrição / Favorecido'), findsOneWidget);
        expect(find.text('ALUGUEL CORPORATIVO'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Pagar'), findsOneWidget);
      },
    );

    testWidgets(
      'Desktop (1200px): AgreementsTab renderiza parcelas individuais com ação Receber',
      (tester) async {
        tester.view.physicalSize = const Size(1200 * 3, 900 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        final today = DateTime.now();
        final pastDate = '2026-01-10';
        final futureDate = '${today.year + 1}-05-15';

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/spaces/1/agreements') {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 100,
                    'description': 'Desenvolvimento de App Mobile',
                    'total': '6000.00',
                    'installment_count': 2,
                    'received': '0.00',
                    'remaining': '6000.00',
                    'paid_installments': 0,
                    'overdue_installments': 1,
                    'next_due_date': pastDate,
                    'installments': [
                      {
                        'id': 501,
                        'agreement_id': 100,
                        'number': 1,
                        'due_date': pastDate,
                        'amount': '3000.00',
                        'received': '0.00',
                        'remaining': '3000.00',
                        'status': 'pending',
                        'overdue': true,
                      },
                      {
                        'id': 502,
                        'agreement_id': 100,
                        'number': 2,
                        'due_date': futureDate,
                        'amount': '3000.00',
                        'received': '0.00',
                        'remaining': '3000.00',
                        'status': 'pending',
                        'overdue': false,
                      },
                    ],
                  },
                ],
                'meta': {'status': 'open', 'today': pastDate, 'total_count': 1},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        });

        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: mockClient,
        );

        await tester.pumpWidget(
          wrapWidget(
            child: const AgreementsTab(space: pf),
            client: client,
            size: const Size(1200, 900),
          ),
        );
        await tester.pumpAndSettle();

        // No Desktop, exibe linhas de tabela para as parcelas em grupos distintos
        expect(find.byType(FinancialDesktopTableHeader), findsNWidgets(2));
        expect(
          find.byType(
            FinancialDesktopTableRow<AgreementInstallmentItemAdapter>,
          ),
          findsNWidgets(2),
        );
        expect(find.text('Parcela 1/2'), findsOneWidget);
        expect(find.text('Parcela 2/2'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Receber'), findsNWidgets(2));
      },
    );

    testWidgets(
      'Mobile (< 840px): PayablesTab renderiza FinancialMobileCard compacto com leitura rápida e botão Pagar',
      (tester) async {
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        fakePayables.payables.clear();
        fakePayables.payables[1] = FakePayable(1, 'Hospedagem AWS Cloud', 15000)
          ..dueDate = '2026-03-10';

        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: fakePayables.client,
        );

        await tester.pumpWidget(
          wrapWidget(
            child: const PayablesTab(space: pf),
            client: client,
            size: const Size(390, 844),
          ),
        );
        await tester.pumpAndSettle();

        // No Mobile (< 840px), renderiza FinancialMobileCard
        expect(
          find.byType(FinancialMobileCard<PayableItemAdapter>),
          findsOneWidget,
        );
        expect(find.text('HOSPEDAGEM AWS CLOUD'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Pagar'), findsOneWidget);
      },
    );

    testWidgets(
      'Mobile (< 840px): AgreementsTab renderiza FinancialMobileCard compacto por parcela com botão Receber',
      (tester) async {
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/spaces/1/agreements') {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 200,
                    'description': 'Mentoria de Engenharia',
                    'total': '1500.00',
                    'installment_count': 1,
                    'received': '0.00',
                    'remaining': '1500.00',
                    'paid_installments': 0,
                    'overdue_installments': 0,
                    'next_due_date': '2026-03-20',
                    'installments': [
                      {
                        'id': 601,
                        'agreement_id': 200,
                        'number': 1,
                        'due_date': '2026-03-20',
                        'amount': '1500.00',
                        'received': '0.00',
                        'remaining': '1500.00',
                        'status': 'pending',
                        'overdue': false,
                      },
                    ],
                  },
                ],
                'meta': {
                  'status': 'open',
                  'today': '2026-03-15',
                  'total_count': 1,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        });

        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: mockClient,
        );

        await tester.pumpWidget(
          wrapWidget(
            child: const AgreementsTab(space: pf),
            client: client,
            size: const Size(390, 844),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(FinancialMobileCard<AgreementInstallmentItemAdapter>),
          findsOneWidget,
        );
        expect(find.text('MENTORIA DE ENGENHARIA'), findsOneWidget);
        expect(find.text('Parcela 1/1'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Receber'), findsOneWidget);
      },
    );

    testWidgets(
      'Virtualização real com 120 itens no mesmo grupo: renderização preguiçosa sob demanda comprovada',
      (tester) async {
        tester.view.physicalSize = const Size(1200 * 3, 800 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        fakePayables.payables.clear();
        // 120 contas todas vencidas no mesmo grupo (Vencidas)
        for (int i = 1; i <= 120; i++) {
          fakePayables.payables[i] = FakePayable(
            i,
            'Obrigação Exclusiva #$i',
            5000,
          )..dueDate = '2025-01-01'; // Data passada fixa
        }

        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: fakePayables.client,
        );

        await tester.pumpWidget(
          wrapWidget(
            child: const PayablesTab(space: pf),
            client: client,
            size: const Size(1200, 800),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('120 contas a pagar'), findsOneWidget);

        // O item #1 está visível inicialmente
        expect(find.text('OBRIGAÇÃO EXCLUSIVA #1'), findsOneWidget);

        // COMPROVAÇÃO DE VIRTUALIZAÇÃO REAL:
        // Das 120 linhas existentes no mesmo grupo, apenas as visíveis no viewport
        // (menos de 20) são instanciadas no elemento tree!
        final renderedRows = find.byType(
          FinancialDesktopTableRow<PayableItemAdapter>,
        );
        expect(renderedRows.evaluate().length, lessThan(25));

        // O item #119 NÃO está na árvore de widgets inicialmente
        expect(find.text('OBRIGAÇÃO EXCLUSIVA #119'), findsNothing);

        // Faz rolagem preguiçosa até o item #119
        for (int s = 0; s < 20; s++) {
          await tester.drag(find.byType(ListView).last, const Offset(0, -600));
          await tester.pumpAndSettle();
          if (find.text('OBRIGAÇÃO EXCLUSIVA #119').evaluate().isNotEmpty) {
            break;
          }
        }

        // Agora o item #119 foi construído sob demanda no viewport!
        expect(find.text('OBRIGAÇÃO EXCLUSIVA #119'), findsOneWidget);
      },
    );

    testWidgets(
      'Ação rápida Receber na parcela N passa installmentId e direciona para aquela parcela',
      (tester) async {
        tester.view.physicalSize = const Size(1200 * 3, 900 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/spaces/1/agreements') {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 100,
                    'description': 'Contrato Consultoria',
                    'total': '4000.00',
                    'installment_count': 2,
                    'received': '0.00',
                    'remaining': '4000.00',
                    'paid_installments': 0,
                    'overdue_installments': 0,
                    'next_due_date': '2026-04-10',
                    'installments': [
                      {
                        'id': 501,
                        'agreement_id': 100,
                        'number': 1,
                        'due_date': '2026-04-10',
                        'amount': '2000.00',
                        'received': '0.00',
                        'remaining': '2000.00',
                        'status': 'pending',
                        'overdue': false,
                      },
                      {
                        'id': 502,
                        'agreement_id': 100,
                        'number': 2,
                        'due_date': '2026-05-10',
                        'amount': '2000.00',
                        'received': '0.00',
                        'remaining': '2000.00',
                        'status': 'pending',
                        'overdue': false,
                      },
                    ],
                  },
                ],
                'meta': {
                  'status': 'open',
                  'today': '2026-04-01',
                  'total_count': 1,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/spaces/1/agreements/100') {
            return http.Response(
              jsonEncode({
                'data': {
                  'id': 100,
                  'description': 'Contrato Consultoria',
                  'total': '4000.00',
                  'installment_count': 2,
                  'received': '0.00',
                  'remaining': '4000.00',
                  'paid_installments': 0,
                  'overdue_installments': 0,
                  'next_due_date': '2026-04-10',
                  'installments': [
                    {
                      'id': 501,
                      'agreement_id': 100,
                      'number': 1,
                      'due_date': '2026-04-10',
                      'amount': '2000.00',
                      'received': '0.00',
                      'remaining': '2000.00',
                      'status': 'pending',
                      'overdue': false,
                    },
                    {
                      'id': 502,
                      'agreement_id': 100,
                      'number': 2,
                      'due_date': '2026-05-10',
                      'amount': '2000.00',
                      'received': '0.00',
                      'remaining': '2000.00',
                      'status': 'pending',
                      'overdue': false,
                    },
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/spaces/1/accounts') {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 1,
                    'name': 'Banco Itaú',
                    'opening_balance': '10000.00',
                    'opening_balance_date': '2026-01-01',
                    'balance': '10000.00',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        });

        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: mockClient,
        );

        await tester.pumpWidget(
          wrapWidget(
            child: const AgreementsTab(space: pf),
            client: client,
            size: const Size(1200, 900),
          ),
        );
        await tester.pumpAndSettle();

        // Encontra o botão "Receber" da Parcela 2
        final receberButtons = find.widgetWithText(FilledButton, 'Receber');
        expect(receberButtons, findsNWidgets(2));

        // Toca no segundo botão (Parcela 2 com id=502)
        await tester.tap(receberButtons.at(1));
        await tester.pumpAndSettle();

        final err = tester.takeException();
        if (err != null) {
          // ignore: avoid_print
          print('MODAL ERROR: $err');
        }

        // O modal abre direcionado diretamente para a Parcela 2!
        expect(find.text('Baixar Parcela 2'), findsOneWidget);
        expect(find.text('Confirmar recebimento'), findsOneWidget);
      },
    );

    testWidgets(
      'Filtros unificados: chips ativos removíveis e limpeza geral funcionam',
      (tester) async {
        tester.view.physicalSize = const Size(1200 * 3, 900 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        fakePayables.payables.clear();
        fakePayables.payables[1] = FakePayable(1, 'Internet Fibra', 10000)
          ..dueDate = '2026-03-10';

        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: fakePayables.client,
        );

        await tester.pumpWidget(
          wrapWidget(
            child: const PayablesTab(space: pf),
            client: client,
            size: const Size(1200, 900),
          ),
        );
        await tester.pumpAndSettle();

        // Digita na busca
        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Buscar por descrição ou favorecido...',
          ),
          'fibra',
        );
        await tester.pumpAndSettle();

        // Chip de busca ativa aparece
        expect(find.text('Busca: "fibra"'), findsOneWidget);

        // Remove o chip de busca clicando no delete
        await tester.tap(find.byIcon(Icons.clear_rounded).first);
        await tester.pumpAndSettle();

        // Busca foi limpa
        expect(find.text('Busca: "fibra"'), findsNothing);
      },
    );

    testWidgets(
      'Filtro de categoria em PayablesTab: filtra itens de verdade e restaura ao remover o chip',
      (tester) async {
        tester.view.physicalSize = const Size(1200 * 3, 900 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/spaces/1/categories') {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 10,
                    'space_id': 1,
                    'name': 'Infraestrutura',
                    'type': 'expense',
                    'icon': 'folder',
                    'color': '#FF0000',
                  },
                  {
                    'id': 20,
                    'space_id': 1,
                    'name': 'Alimentação',
                    'type': 'expense',
                    'icon': 'folder',
                    'color': '#00FF00',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/spaces/1/payables') {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 1,
                    'kind': 'single',
                    'description': 'Servidor Cloud AWS',
                    'amount': '500.00',
                    'due_date': '2026-04-10',
                    'status': 'open',
                    'overdue': false,
                    'paid': '0.00',
                    'remaining': '500.00',
                    'category_id': 10,
                    'category': {
                      'id': 10,
                      'space_id': 1,
                      'name': 'Infraestrutura',
                      'type': 'expense',
                      'icon': 'folder',
                      'color': '#FF0000',
                    },
                    'payment_count': 0,
                    'payments': [],
                  },
                  {
                    'id': 2,
                    'kind': 'single',
                    'description': 'Mercado e Lanches',
                    'amount': '150.00',
                    'due_date': '2026-04-15',
                    'status': 'open',
                    'overdue': false,
                    'paid': '0.00',
                    'remaining': '150.00',
                    'category_id': 20,
                    'category': {
                      'id': 20,
                      'space_id': 1,
                      'name': 'Alimentação',
                      'type': 'expense',
                      'icon': 'folder',
                      'color': '#00FF00',
                    },
                    'payment_count': 0,
                    'payments': [],
                  },
                ],
                'meta': {
                  'status': 'open',
                  'today': '2026-04-01',
                  'total_count': 2,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        });

        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: mockClient,
        );

        await tester.pumpWidget(
          wrapWidget(
            child: const PayablesTab(space: pf),
            client: client,
            size: const Size(1200, 900),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Ambos os itens estão inicialmente visíveis
        expect(find.text('SERVIDOR CLOUD AWS'), findsOneWidget);
        expect(find.text('MERCADO E LANCHES'), findsOneWidget);

        // 2. Toca no chip seletor de categoria
        await tester.tap(find.widgetWithText(FilterChip, 'Categoria'));
        await tester.pumpAndSettle();

        // Modal de seleção abre: toca na categoria "INFRAESTRUTURA"
        await tester.tap(find.text('INFRAESTRUTURA').last);
        await tester.pumpAndSettle();

        // 3. Confirmar que APENAS itens daquela categoria aparecem
        expect(find.text('SERVIDOR CLOUD AWS'), findsOneWidget);
        expect(find.text('MERCADO E LANCHES'), findsNothing);

        // O chip "Categoria filtrada" está presente
        final catChip = find.widgetWithText(InputChip, 'Categoria filtrada');
        expect(catChip, findsOneWidget);

        // 4. Remover o chip de categoria
        final rawChip = tester.widget<InputChip>(catChip);
        rawChip.onDeleted?.call();
        await tester.pumpAndSettle();

        // 5. Confirmar que todos os itens voltam a aparecer
        expect(find.text('SERVIDOR CLOUD AWS'), findsOneWidget);
        expect(find.text('MERCADO E LANCHES'), findsOneWidget);
        expect(
          find.widgetWithText(InputChip, 'Categoria filtrada'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Filtro de categoria em AgreementsTab: filtra parcelas de verdade e restaura ao remover o chip',
      (tester) async {
        tester.view.physicalSize = const Size(1200 * 3, 900 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/spaces/1/categories') {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 101,
                    'space_id': 1,
                    'name': 'Consultoria',
                    'type': 'income',
                    'icon': 'folder',
                    'color': '#0000FF',
                  },
                  {
                    'id': 102,
                    'space_id': 1,
                    'name': 'Vendas',
                    'type': 'income',
                    'icon': 'folder',
                    'color': '#FF00FF',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/spaces/1/agreements') {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 1,
                    'description': 'Projeto Consultoria TI',
                    'total': '3000.00',
                    'installment_count': 1,
                    'received': '0.00',
                    'remaining': '3000.00',
                    'paid_installments': 0,
                    'overdue_installments': 0,
                    'next_due_date': '2026-04-10',
                    'category_id': 101,
                    'category': {
                      'id': 101,
                      'space_id': 1,
                      'name': 'Consultoria',
                      'type': 'income',
                      'icon': 'folder',
                      'color': '#0000FF',
                    },
                    'installments': [
                      {
                        'id': 501,
                        'agreement_id': 1,
                        'number': 1,
                        'due_date': '2026-04-10',
                        'amount': '3000.00',
                        'received': '0.00',
                        'remaining': '3000.00',
                        'status': 'pending',
                        'overdue': false,
                      },
                    ],
                  },
                  {
                    'id': 2,
                    'description': 'Venda de Equipamento',
                    'total': '1500.00',
                    'installment_count': 1,
                    'received': '0.00',
                    'remaining': '1500.00',
                    'paid_installments': 0,
                    'overdue_installments': 0,
                    'next_due_date': '2026-04-15',
                    'category_id': 102,
                    'category': {
                      'id': 102,
                      'space_id': 1,
                      'name': 'Vendas',
                      'type': 'income',
                      'icon': 'folder',
                      'color': '#FF00FF',
                    },
                    'installments': [
                      {
                        'id': 502,
                        'agreement_id': 2,
                        'number': 1,
                        'due_date': '2026-04-15',
                        'amount': '1500.00',
                        'received': '0.00',
                        'remaining': '1500.00',
                        'status': 'pending',
                        'overdue': false,
                      },
                    ],
                  },
                ],
                'meta': {
                  'status': 'open',
                  'today': '2026-04-01',
                  'total_count': 2,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        });

        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: mockClient,
        );

        await tester.pumpWidget(
          wrapWidget(
            child: const AgreementsTab(space: pf),
            client: client,
            size: const Size(1200, 900),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Ambos os lançamentos estão visíveis
        expect(find.text('PROJETO CONSULTORIA TI'), findsOneWidget);
        expect(find.text('VENDA DE EQUIPAMENTO'), findsOneWidget);

        // 2. Toca no chip seletor de categoria
        await tester.tap(find.widgetWithText(FilterChip, 'Categoria'));
        await tester.pumpAndSettle();

        // Modal de seleção abre: toca na categoria "CONSULTORIA"
        await tester.tap(find.text('CONSULTORIA').last);
        await tester.pumpAndSettle();

        // 3. Confirmar que APENAS parcelas daquela categoria aparecem
        expect(find.text('PROJETO CONSULTORIA TI'), findsOneWidget);
        expect(find.text('VENDA DE EQUIPAMENTO'), findsNothing);

        // O chip "Categoria filtrada" está presente
        final catChip = find.widgetWithText(InputChip, 'Categoria filtrada');
        expect(catChip, findsOneWidget);

        // 4. Remover o chip de categoria
        final rawChip = tester.widget<InputChip>(catChip);
        rawChip.onDeleted?.call();
        await tester.pumpAndSettle();

        // 5. Confirmar que todos os lançamentos voltam a aparecer
        expect(find.text('PROJETO CONSULTORIA TI'), findsOneWidget);
        expect(find.text('VENDA DE EQUIPAMENTO'), findsOneWidget);
        expect(
          find.widgetWithText(InputChip, 'Categoria filtrada'),
          findsNothing,
        );
      },
    );
  });
}
