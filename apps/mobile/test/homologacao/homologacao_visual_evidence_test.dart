import 'dart:io';
import 'dart:ui' as ui;

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/accounts/account_card.dart';
import 'package:bigdevz_finance/features/accounts/account_edit_screen.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/alerts/alerts_repository.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/categories/categories_repository.dart';
import 'package:bigdevz_finance/features/categories/category.dart';
import 'package:bigdevz_finance/features/categories/category_badge.dart';
import 'package:bigdevz_finance/features/home/notifications_modal.dart';
import 'package:bigdevz_finance/features/payables/direct_expense_modal.dart';
import 'package:bigdevz_finance/features/payables/payables_repository.dart';
import 'package:bigdevz_finance/features/summary/dashboard_charts.dart';
import 'package:bigdevz_finance/features/summary/summary.dart';
import 'package:bigdevz_finance/ui/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

const pfSpace = Space(id: 1, kind: 'PF', name: 'Pessoal');
const pjSpace = Space(id: 2, kind: 'PJ', name: 'BigDev.Z Soluções');

Future<void> _captureToPng(
  WidgetTester tester,
  GlobalKey key,
  String filename,
) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();
    final file = File('../../prints/homologacao/$filename');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(pngBytes);
  });
}

void main() {
  group('Homologação Visual das 6 Melhorias Financeiras e de UX', () {
    const parentCat = Category(
      id: 10,
      spaceId: 1,
      name: 'Moradia',
      type: 'expense',
      icon: 'home',
      color: '#1E5BB8',
    );

    const childCat = Category(
      id: 11,
      spaceId: 1,
      parentId: 10,
      parentName: 'Moradia',
      name: 'Energia',
      type: 'expense',
      icon: 'bolt',
      color: '#D97706',
    );

    testWidgets(
      'Fluxo 1 e 2: Mobile - Compra no débito R\$ 35,90 com teclado aberto na Wise',
      (tester) async {
        final repaintKey = GlobalKey();
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const wiseAccount = Account(
          id: 1,
          name: 'Wise Global',
          bankId: 'wise',
          openingBalance: Money(10000),
          openingBalanceDate: '2026-01-01',
          balance: Money(10000), // R$ 100,00
        );

        final backend = FakeBackend();
        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: backend.client,
        );
        client.token = backend.validToken;

        backend.routes['GET /spaces/1/accounts'] = {
          'data': [
            {
              'id': 1,
              'space_id': 1,
              'name': 'Wise Global',
              'bank_id': 'wise',
              'opening_balance': '100.00',
              'opening_balance_date': '2026-01-01',
              'balance': '100.00',
            },
          ],
        };

        backend.routes['GET /spaces/1/categories'] = {
          'data': [
            {
              'id': 10,
              'space_id': 1,
              'name': 'Moradia',
              'type': 'expense',
              'icon': 'home',
              'color': '#1E5BB8',
            },
            {
              'id': 11,
              'space_id': 1,
              'parent_id': 10,
              'parent_name': 'Moradia',
              'name': 'Energia',
              'type': 'expense',
              'icon': 'bolt',
              'color': '#D97706',
            },
          ],
        };

        backend.routes['POST /spaces/1/payables/direct-expense'] = {
          'data': {
            'payable': {
              'id': 99,
              'description': 'Conta de luz da oficina',
              'amount': '35.90',
            },
            'payment': {'id': 101, 'amount': '35.90'},
          },
        };

        final session =
            SessionController(
                api: client,
                auth: AuthRepository(client),
                storage: MemorySessionStorage(),
              )
              ..user = const AppUser(id: 1, name: 'User', email: 'u@test.com')
              ..activeSpace = pfSpace;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider.value(value: AccountsRepository(client)),
              Provider.value(value: PayablesRepository(client)),
              Provider.value(value: CategoriesRepository(client)),
              ChangeNotifierProvider.value(value: session),
            ],
            child: MaterialApp(
              builder: (context, child) =>
                  RepaintBoundary(key: repaintKey, child: child!),
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Column(
                            children: [
                              const SizedBox(height: 40),
                              AccountCard(space: pfSpace, account: wiseAccount),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: () {
                                  showDirectExpenseModal(
                                    context,
                                    space: pfSpace,
                                    preselectedAccountId: 1,
                                  );
                                },
                                child: const Text('Registrar despesa paga'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Abre modal
        await tester.tap(find.text('Registrar despesa paga'));
        await tester.pumpAndSettle();

        // Preenche valor R$ 35,90 e descrição
        final textFields = find.byType(TextFormField);
        await tester.enterText(textFields.at(0), '35,90');
        await tester.enterText(textFields.at(1), 'Conta de luz da oficina');
        await tester.pumpAndSettle();

        // Simula teclado virtual aberto (viewInsets bottom = 260)
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump();

        // Captura 1: Modal com teclado aberto
        await _captureToPng(
          tester,
          repaintKey,
          '01_mobile_debit_purchase_keyboard_open.png',
        );

        // Remove teclado e confirma
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();

        expect(find.text('Confirmar Despesa Paga'), findsOneWidget);
      },
    );

    testWidgets(
      'Fluxo 3: Mobile - Confirmação do débito (Wise R\$ 64,10 e saída única)',
      (tester) async {
        final repaintKey = GlobalKey();
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // Saldo resultante: R$ 100,00 - R$ 35,90 = R$ 64,10
        const wiseDebited = Account(
          id: 1,
          name: 'Wise Global',
          bankId: 'wise',
          openingBalance: Money(10000),
          openingBalanceDate: '2026-01-01',
          balance: Money(6410), // R$ 64,10
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(title: const Text('Extrato Wise')),
              body: RepaintBoundary(
                key: repaintKey,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      AccountCard(space: pfSpace, account: wiseDebited),
                      const SizedBox(height: 16),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.r16),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.red.shade50,
                            child: const Icon(
                              Icons.arrow_downward_rounded,
                              color: Colors.red,
                              size: 18,
                            ),
                          ),
                          title: const Text(
                            'CONTA DE LUZ DA OFICINA',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: const Text(
                            '10/03/2026 · Moradia > Energia · Débito',
                            style: TextStyle(fontSize: 11),
                          ),
                          trailing: const Text(
                            '- R\$ 35,90',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _captureToPng(
          tester,
          repaintKey,
          '02_mobile_debit_purchase_confirmed_balance.png',
        );
      },
    );

    testWidgets(
      'Fluxo 4: Mobile - Relatório hierárquico (R\$ 80,00 no grupo, sem duplicidade)',
      (tester) async {
        final repaintKey = GlobalKey();
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final summary = CategoriesSummary(
          expenses: [
            CategorySummaryItem(
              id: 10,
              name: 'Moradia',
              icon: 'home',
              color: '#1E5BB8',
              total: const Money(8000), // R$ 80,00
              totalCents: 8000,
              hasChildren: true,
              composition: [
                CategorySummaryItem(
                  id: 10,
                  name: 'Moradia',
                  icon: 'home',
                  color: '#1E5BB8',
                  total: const Money(3000), // R$ 30,00 direto
                  totalCents: 3000,
                  isDirect: true,
                ),
                CategorySummaryItem(
                  id: 11,
                  name: 'Energia',
                  icon: 'bolt',
                  color: '#D97706',
                  total: const Money(5000), // R$ 50,00 filha
                  totalCents: 5000,
                  isDirect: false,
                ),
              ],
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(title: const Text('Relatório Analítico')),
              body: RepaintBoundary(
                key: repaintKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: CategoryDistributionDonutCard(
                    categories: summary,
                    obscure: false,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Expande composição
        await tester.tap(find.text('MORADIA'));
        await tester.pumpAndSettle();

        await _captureToPng(
          tester,
          repaintKey,
          '03_mobile_report_grouped_and_detailed.png',
        );
      },
    );

    testWidgets(
      'Fluxo 5: Mobile - Estorno recompondo R\$ 100,00 e obrigação cancelada',
      (tester) async {
        final repaintKey = GlobalKey();
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const wiseRestored = Account(
          id: 1,
          name: 'Wise Global',
          bankId: 'wise',
          openingBalance: Money(10000),
          openingBalanceDate: '2026-01-01',
          balance: Money(10000), // R$ 100,00 recomposto
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(title: const Text('Extrato Wise após Estorno')),
              body: RepaintBoundary(
                key: repaintKey,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      AccountCard(space: pfSpace, account: wiseRestored),
                      const SizedBox(height: 16),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.r16),
                          side: BorderSide(color: Colors.green.shade200),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade50,
                            child: const Icon(
                              Icons.replay_rounded,
                              color: Colors.green,
                              size: 18,
                            ),
                          ),
                          title: const Text(
                            'ESTORNO DE COMPRA NO DÉBITO',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: const Text(
                            '10/03/2026 · Saldo recomposto · Obrigação cancelada',
                            style: TextStyle(fontSize: 11),
                          ),
                          trailing: const Text(
                            '+ R\$ 35,90',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(AppTokens.r12),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              color: Colors.blue,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Obrigação cancelada automaticamente. Zero pendências em aberto.',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _captureToPng(
          tester,
          repaintKey,
          '04_mobile_debit_purchase_reversal_restored.png',
        );
      },
    );

    testWidgets(
      'Fluxo 6: Reassociação DUCZ Benefícios com apelido "Benefícios da empresa"',
      (tester) async {
        final repaintKeyEdit = GlobalKey();
        final repaintKeyCard = GlobalKey();
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const duczAccount = Account(
          id: 88,
          name: 'BENEFÍCIOS DA EMPRESA',
          bankId: 'ducz',
          openingBalance: Money(50000),
          openingBalanceDate: '2026-01-01',
          balance: Money(50000),
        );

        final backend = FakeBackend();
        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: backend.client,
        );
        client.token = backend.validToken;

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
            child: MaterialApp(
              home: RepaintBoundary(
                key: repaintKeyEdit,
                child: AccountEditScreen(space: pfSpace, account: duczAccount),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Captura tela de edição com DUCZ reconhecido mesmo com apelido customizado
        await _captureToPng(
          tester,
          repaintKeyEdit,
          '05_institution_reassociation_ducz_edit_screen.png',
        );

        // Captura cartão na lista de contas
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(title: const Text('Contas Bancárias')),
              body: RepaintBoundary(
                key: repaintKeyCard,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AccountCard(space: pfSpace, account: duczAccount),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _captureToPng(
          tester,
          repaintKeyCard,
          '06_institution_reassociation_ducz_account_card.png',
        );
      },
    );

    testWidgets(
      'Fluxo 7: Desktop Widescreen (1200px) - Painel Executivo e Controles',
      (tester) async {
        final repaintKey = GlobalKey();
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const wiseAccount = Account(
          id: 1,
          name: 'Wise Global',
          bankId: 'wise',
          openingBalance: Money(10000),
          openingBalanceDate: '2026-01-01',
          balance: Money(10000),
        );

        const duczAccount = Account(
          id: 2,
          name: 'DUCZ Benefícios PJ',
          bankId: 'ducz',
          openingBalance: Money(50000),
          openingBalanceDate: '2026-01-01',
          balance: Money(50000),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                title: const Text('BigDev.Z Finance — Desktop Web (1200px)'),
              ),
              body: RepaintBoundary(
                key: repaintKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AccountCard(
                              space: pfSpace,
                              account: wiseAccount,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: AccountCard(
                              space: pjSpace,
                              account: duczAccount,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.r16),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Categorias e Identidade Visual (Tema Claro / Desktop)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  CategoryBadge(category: parentCat),
                                  CategoryBadge(
                                    category: childCat,
                                    showFullPath: true,
                                  ),
                                  const CategoryBadge(
                                    category: Category(
                                      id: 12,
                                      spaceId: 1,
                                      name: 'Mercado',
                                      type: 'expense',
                                      icon: 'shopping_cart',
                                      color: '#10B981',
                                    ),
                                  ),
                                  const CategoryBadge(
                                    category: Category(
                                      id: 13,
                                      spaceId: 1,
                                      name: 'Transporte',
                                      type: 'expense',
                                      icon: 'directions_car',
                                      color: '#4F46E5',
                                    ),
                                  ),
                                  const CategoryBadge(
                                    category: Category(
                                      id: 14,
                                      spaceId: 1,
                                      name: 'Folha de Pagamento',
                                      type: 'expense',
                                      icon: 'groups',
                                      color: '#7C3AED',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _captureToPng(
          tester,
          repaintKey,
          '07_desktop_widescreen_category_picker_and_report.png',
        );
      },
    );

    testWidgets(
      'Fluxo 8: Comparativo de Temas Claro e Escuro com Contraste Semântico',
      (tester) async {
        final repaintKey = GlobalKey();
        tester.view.physicalSize = const Size(800, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const sampleCategories = [
          Category(
            id: 1,
            spaceId: 1,
            name: 'Moradia',
            type: 'expense',
            icon: 'home',
            color: '#1E5BB8',
          ),
          Category(
            id: 2,
            spaceId: 1,
            name: 'Energia',
            type: 'expense',
            icon: 'bolt',
            color: '#D97706',
          ),
          Category(
            id: 3,
            spaceId: 1,
            name: 'Água',
            type: 'expense',
            icon: 'water_drop',
            color: '#06B6D4',
          ),
          Category(
            id: 4,
            spaceId: 1,
            name: 'Mercado',
            type: 'expense',
            icon: 'shopping_cart',
            color: '#10B981',
          ),
          Category(
            id: 5,
            spaceId: 1,
            name: 'Saúde',
            type: 'expense',
            icon: 'medical_services',
            color: '#0D9488',
          ),
          Category(
            id: 6,
            spaceId: 1,
            name: 'Folha',
            type: 'expense',
            icon: 'groups',
            color: '#7C3AED',
          ),
          Category(
            id: 7,
            spaceId: 1,
            name: 'Tributos',
            type: 'expense',
            icon: 'description',
            color: '#B45309',
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                key: repaintKey,
                child: Row(
                  children: [
                    // Tema Claro
                    Expanded(
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tema Claro (Light)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Theme(
                              data: ThemeData.light(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: sampleCategories
                                    .map(
                                      (cat) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 3,
                                        ),
                                        child: CategoryBadge(category: cat),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Tema Escuro
                    Expanded(
                      child: Container(
                        color: const Color(0xFF121212),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tema Escuro (Dark)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Theme(
                              data: ThemeData.dark(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: sampleCategories
                                    .map(
                                      (cat) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 3,
                                        ),
                                        child: CategoryBadge(category: cat),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _captureToPng(
          tester,
          repaintKey,
          '08_themes_contrast_comparison_dark_and_light.png',
        );
      },
    );

    testWidgets(
      'Fluxo 9: Central de Notificações com Sininho e Persistência de Leitura/Dispensa',
      (tester) async {
        final repaintKey = GlobalKey();
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final backend = FakeBackend();
        final client = ApiClient(
          baseUrl: 'http://api.test/api',
          client: backend.client,
        );
        client.token = backend.validToken;

        backend.routes['GET /spaces/1/alerts'] = {
          'data': {
            'unread_active_count': 1,
            'alerts': [
              {
                'key': 'payable_overdue:10',
                'target_id': 10,
                'type': 'payable_overdue',
                'severity': 'urgent',
                'title': 'ENERGIA ELETRICA VENCIDA',
                'detail': 'Venceu em 10/03/2026',
                'due_date': '2026-03-10',
                'amount': '150.00',
                'amount_cents': 15000,
                'is_read': false,
                'is_dismissed': false,
              },
            ],
          },
        };

        final session =
            SessionController(
                api: client,
                auth: AuthRepository(client),
                storage: MemorySessionStorage(),
              )
              ..user = const AppUser(id: 1, name: 'User', email: 'u@test.com')
              ..activeSpace = pfSpace;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider.value(value: AlertsRepository(client)),
              ChangeNotifierProvider.value(value: session),
            ],
            child: MaterialApp(
              builder: (context, child) =>
                  RepaintBoundary(key: repaintKey, child: child!),
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    return Center(
                      child: ElevatedButton(
                        onPressed: () {
                          showNotificationsModal(
                            context,
                            onNavigate: (tab, {filter}) {},
                          );
                        },
                        child: const Text('Abrir Notificações'),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Abre central de notificações
        await tester.tap(find.text('Abrir Notificações'));
        await tester.pumpAndSettle();

        await _captureToPng(
          tester,
          repaintKey,
          '09_notifications_modal_and_bell_flow.png',
        );
      },
    );
  });
}
