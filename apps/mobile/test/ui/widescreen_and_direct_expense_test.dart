import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/accounts/accounts_tab.dart';
import 'package:bigdevz_finance/features/agreements/agreement.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/agreements_tab.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/categories/category.dart';
import 'package:bigdevz_finance/features/payables/payable.dart';
import 'package:bigdevz_finance/features/payables/payable_creations.dart';
import 'package:bigdevz_finance/features/payables/payables_repository.dart';
import 'package:bigdevz_finance/features/payables/payables_tab.dart';
import 'package:bigdevz_finance/features/settings/preferences_controller.dart';
import 'package:bigdevz_finance/features/statement/statement_tab.dart';
import 'package:bigdevz_finance/features/summary/summary.dart';
import 'package:bigdevz_finance/features/summary/summary_tab.dart';
import 'package:bigdevz_finance/ui/financial/financial_desktop_table.dart';
import 'package:bigdevz_finance/ui/financial/financial_item_view.dart';
import 'package:bigdevz_finance/ui/widgets.dart';

const pfSpace = Space(id: 1, kind: 'PF', name: 'Pessoal');

class _TestItem extends Fake implements FinancialItemView {
  _TestItem({
    required this.id,
    required this.title,
    required this.dueDate,
    this.counterparty,
    this.pendingAmount,
    this.totalAmount,
    this.category,
    this.kindLabel = 'Avulsa',
    this.statusLabel = 'Em aberto',
  });

  @override
  final int id;
  @override
  final String title;
  @override
  final String? counterparty;
  @override
  final String dueDate;
  @override
  final Object? category;
  @override
  final String kindLabel;
  @override
  final String statusLabel;
  @override
  final StatusTone statusTone = StatusTone.neutral;
  @override
  final Money? pendingAmount;
  @override
  final Money? totalAmount;
  @override
  final bool isOverdue = false;
  @override
  final bool isAwaitingAmount = false;
  @override
  final bool isSettled = false;
  @override
  final bool isEligibleForBatch = true;
}

class _FakeSummaryRepository extends Fake implements SummaryRepository {
  _FakeSummaryRepository(this.summary);
  final SpaceSummary summary;

  @override
  Future<SpaceSummary> load(int spaceId) async => summary;
}

class _FakeSessionController extends ChangeNotifier
    implements SessionController {
  @override
  int get dataVersion => 1;

  @override
  AppUser? get user =>
      const AppUser(id: 1, name: 'Demo', email: 'demo@example.com');

  @override
  List<Space> get spaces => [pfSpace];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccountsRepository extends Fake implements AccountsRepository {
  _FakeAccountsRepository(this.accounts);
  final List<Account> accounts;

  @override
  Future<List<Account>> list(int spaceId) async => accounts;
}

class _FakePayablesRepository extends Fake implements PayablesRepository {
  @override
  Future<List<Payable>> list(
    int spaceId, {
    String? status,
    String? from,
    String? to,
    int? categoryId,
  }) async => [
    const Payable(
      id: 1,
      kind: 'single',
      description: 'Conta de Energia',
      amount: Money(15000),
      paid: Money(0),
      remaining: Money(15000),
      dueDate: '2026-03-25',
      status: PayableStatus.open,
      overdue: false,
    ),
  ];
}

class _FakeAgreementsRepository extends Fake implements AgreementsRepository {
  @override
  Future<AgreementsListResult> list(
    int spaceId, {
    String? status,
    String? from,
    String? to,
    int? categoryId,
  }) async => const AgreementsListResult(
    items: [
      Agreement(
        id: 1,
        description: 'Contrato Alpha',
        total: Money(50000),
        installmentCount: 2,
        received: Money(0),
        remaining: Money(50000),
        paidInstallments: 0,
        overdueInstallments: 0,
        nextDueDate: '2026-03-25',
        installments: [],
      ),
    ],
    totalCount: 1,
  );
}

class _FakePayableCreations extends Fake implements PayableCreations {
  @override
  Future<PendingCreation?> pending(int userId, int spaceId) async => null;
}

void main() {
  group('PEND-005 / AC-UI-008: Proporções e Flex da Tabela Compartilhada', () {
    testWidgets(
      'FinancialDesktopTable usa flex 5 (descrição), 3 (categoria) e 2 (tipo)',
      (tester) async {
        final item = _TestItem(
          id: 1,
          title: 'Fornecedor Alpha',
          counterparty: 'Alpha Comércio de Materiais Ltda',
          dueDate: '2026-03-25',
          category: const Category(
            id: 1,
            spaceId: 1,
            name: 'Escritório',
            type: 'expense',
            icon: 'folder',
            color: '#1E5BB8',
          ),
          kindLabel: 'Recorrente',
          statusLabel: 'Em aberto',
          pendingAmount: const Money(15000),
          totalAmount: const Money(15000),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1280,
                child: FinancialDesktopTable<_TestItem>(
                  items: [item],
                  quickActionLabel: 'Pagar',
                  onQuickAction: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final expandedWidgets = tester
            .widgetList<Expanded>(find.byType(Expanded))
            .toList();

        // No cabeçalho: flex 5 (descrição), flex 3 (categoria), flex 2 (tipo)
        final headerDesc = expandedWidgets.firstWhere(
          (e) => find
              .descendant(
                of: find.byWidget(e),
                matching: find.text('Descrição / Favorecido'),
              )
              .evaluate()
              .isNotEmpty,
        );
        final headerCat = expandedWidgets.firstWhere(
          (e) => find
              .descendant(
                of: find.byWidget(e),
                matching: find.text('Categoria'),
              )
              .evaluate()
              .isNotEmpty,
        );
        final headerKind = expandedWidgets.firstWhere(
          (e) => find
              .descendant(
                of: find.byWidget(e),
                matching: find.text('Tipo / Parcela'),
              )
              .evaluate()
              .isNotEmpty,
        );

        expect(
          headerDesc.flex,
          equals(5),
          reason: 'Header Descrição deve ter flex 5 para dar mais espaço em widescreen',
        );
        expect(
          headerCat.flex,
          equals(3),
          reason: 'Header Categoria deve ter flex 3 para subcategorias longas',
        );
        expect(
          headerKind.flex,
          equals(2),
          reason: 'Header Tipo deve manter flex 2',
        );

        // Na linha de dados:
        final rowDesc = expandedWidgets.firstWhere(
          (e) => find
              .descendant(
                of: find.byWidget(e),
                matching: find.text('FORNECEDOR ALPHA'),
              )
              .evaluate()
              .isNotEmpty,
        );
        expect(
          rowDesc.flex,
          equals(5),
          reason: 'Row Descrição deve ter flex 5',
        );
      },
    );
  });

  group('PEND-005 & PEND-010 / AC-UI-008 & AC-UI-009: Dashboard Widescreen e Ação de Despesa Paga', () {
    final fakeSummary = SpaceSummary(
      balance: const Money(500000),
      receivableRemaining: const Money(100000),
      receivedTotal: const Money(0),
      accountsCount: 2,
      agreementsCount: 1,
      overdueInstallments: 1,
      payables: const PayablesSummary(
        openTotal: Money(95000),
        overdueTotal: Money(45000),
        overdueCount: 1,
        dueNext30DaysTotal: Money(50000),
        paidTotal: Money(0),
        awaitingAmountCount: 0,
      ),
    );

    testWidgets(
      'Dashboard adota maxWidth 1280 e organiza Payables e Accounts lado a lado em Widescreen (1280px)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<SummaryRepository>(
                create: (_) => _FakeSummaryRepository(fakeSummary),
              ),
              Provider<AccountsRepository>(
                create: (_) => _FakeAccountsRepository([]),
              ),
              ChangeNotifierProvider<SessionController>(
                create: (_) => _FakeSessionController(),
              ),
              Provider<PreferencesController?>(create: (_) => null),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SummaryTab(space: pfSpace, onOpenTab: (_, {filter}) {}),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verifica contenção de maxWidth 1280
        final constrainedBoxes = tester.widgetList<ConstrainedBox>(
          find.byType(ConstrainedBox),
        );
        final mainConstraint = constrainedBoxes.firstWhere(
          (b) => b.constraints.maxWidth == 1280.0,
          orElse: () => throw TestFailure(
            'Nenhum ConstrainedBox com maxWidth: 1280 encontrado no Dashboard',
          ),
        );
        expect(mainConstraint.constraints.maxWidth, equals(1280.0));

        // Em widescreen desktop (1280px), _ModernPayablesCard e _AccountsAccessCard devem estar alinhados horizontalmente
        final payablesFinder = find.byKey(
          const ValueKey('summary_modern_payables_card'),
        );
        final accountsAccessFinder = find.byKey(
          const ValueKey('summary_accounts_access_card'),
        );
        expect(payablesFinder, findsOneWidget);
        expect(accountsAccessFinder, findsOneWidget);

        final payablesPos = tester.getTopLeft(payablesFinder);
        final accountsPos = tester.getTopLeft(accountsAccessFinder);

        expect(
          payablesPos.dy,
          equals(accountsPos.dy),
          reason: 'Em widescreen desktop, os cards de contas a pagar e carteira de contas devem estar lado a lado',
        );
      },
    );

    testWidgets(
      'PEND-010: Botão "Registrar despesa paga" tem maxWidth 320 em desktop e rótulo conciso',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<SummaryRepository>(
                create: (_) => _FakeSummaryRepository(fakeSummary),
              ),
              Provider<AccountsRepository>(
                create: (_) => _FakeAccountsRepository([]),
              ),
              ChangeNotifierProvider<SessionController>(
                create: (_) => _FakeSessionController(),
              ),
              Provider<PreferencesController?>(create: (_) => null),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SummaryTab(space: pfSpace, onOpenTab: (_, {filter}) {}),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Botão deve existir com rótulo curto e NÃO com a versão estendida
        expect(find.text('Registrar despesa paga'), findsOneWidget);
        expect(
          find.text('Registrar despesa paga (débito em conta)'),
          findsNothing,
        );

        // Em desktop (1280px), o botão deve ter largura contida (<= 320px)
        final btnFinder = find.byKey(
          const ValueKey('summary_direct_expense_button'),
        );
        expect(btnFinder, findsOneWidget);

        final btnSize = tester.getSize(btnFinder);
        expect(
          btnSize.width,
          lessThanOrEqualTo(320.0),
          reason: 'Em desktop, o botão deve estar contido em até 320px',
        );
      },
    );

    testWidgets(
      'PEND-010: Botão "Registrar despesa paga" em mobile (375px) ocupa largura total e minHeight >= 44',
      (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<SummaryRepository>(
                create: (_) => _FakeSummaryRepository(fakeSummary),
              ),
              Provider<AccountsRepository>(
                create: (_) => _FakeAccountsRepository([]),
              ),
              ChangeNotifierProvider<SessionController>(
                create: (_) => _FakeSessionController(),
              ),
              Provider<PreferencesController?>(create: (_) => null),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SummaryTab(space: pfSpace, onOpenTab: (_, {filter}) {}),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final btnFinder = find.byKey(
          const ValueKey('summary_direct_expense_button'),
        );
        expect(btnFinder, findsOneWidget);

        final btnSize = tester.getSize(btnFinder);
        expect(
          btnSize.width,
          greaterThan(300.0),
          reason: 'Em mobile, o botão ocupa toda a largura útil do container',
        );
        expect(
          btnSize.height,
          greaterThanOrEqualTo(44.0),
          reason: 'Em mobile, a altura do botão deve ser ergonômica (>= 44px)',
        );
      },
    );
  });

  group(
    'PEND-005 / AC-UI-008: Contas em Grid Multi-Colunas e Contenção 1280px',
    () {
      final activeAccounts = [
        const Account(
          id: 1,
          name: 'Conta Corrente Nubank',
          bankId: 'nubank',
          openingBalance: Money(100000),
          openingBalanceDate: '2026-01-01',
          balance: Money(250000),
        ),
        const Account(
          id: 2,
          name: 'Investimento Itaú',
          bankId: 'itau',
          openingBalance: Money(500000),
          openingBalanceDate: '2026-01-01',
          balance: Money(500000),
        ),
      ];

      testWidgets(
        'AccountsTab contém maxWidth 1280 e organiza contas em grid multi-colunas no desktop (1280px)',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() => tester.view.resetPhysicalSize());

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                Provider<AccountsRepository>(
                  create: (_) => _FakeAccountsRepository(activeAccounts),
                ),
                ChangeNotifierProvider<SessionController>(
                  create: (_) => _FakeSessionController(),
                ),
                Provider<PreferencesController?>(create: (_) => null),
              ],
              child: const MaterialApp(
                home: Scaffold(body: AccountsTab(space: pfSpace)),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Verifica contenção de maxWidth 1280
          final constrainedBoxes = tester.widgetList<ConstrainedBox>(
            find.byType(ConstrainedBox),
          );
          final has1280 = constrainedBoxes.any(
            (b) => b.constraints.maxWidth == 1280.0,
          );
          expect(
            has1280,
            isTrue,
            reason: 'AccountsTab deve ter ConstrainedBox com maxWidth: 1280',
          );

          // Verifica que as 2 contas ativas estão em layout multi-colunas lado a lado
          final acc1 = find.byKey(const ValueKey('account-1'));
          final acc2 = find.byKey(const ValueKey('account-2'));
          expect(acc1, findsOneWidget);
          expect(acc2, findsOneWidget);

          final pos1 = tester.getTopLeft(acc1);
          final pos2 = tester.getTopLeft(acc2);

          expect(
            pos1.dy,
            equals(pos2.dy),
            reason: 'Em widescreen desktop, contas ativas devem ser dispostas em colunas lado a lado (mesmo Top)',
          );
        },
      );
    },
  );

  group('PEND-005 / AC-UI-008: Contenção de Largura 1280px em StatementTab, PayablesTab e AgreementsTab', () {
    testWidgets('StatementTab possui maxWidth 1280', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [Provider<PreferencesController?>(create: (_) => null)],
          child: const MaterialApp(
            home: Scaffold(body: StatementTab(space: pfSpace)),
          ),
        ),
      );

      final constrainedBoxes = tester.widgetList<ConstrainedBox>(
        find.byType(ConstrainedBox),
      );
      final has1280 = constrainedBoxes.any(
        (b) => b.constraints.maxWidth == 1280.0,
      );
      expect(
        has1280,
        isTrue,
        reason: 'StatementTab deve conter BoxConstraints(maxWidth: 1280)',
      );
    });

    testWidgets('PayablesTab possui maxWidth 1280', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<PayablesRepository>(
              create: (_) => _FakePayablesRepository(),
            ),
            Provider<PayableCreations>(create: (_) => _FakePayableCreations()),
            ChangeNotifierProvider<SessionController>(
              create: (_) => _FakeSessionController(),
            ),
            Provider<PreferencesController?>(create: (_) => null),
          ],
          child: const MaterialApp(
            home: Scaffold(body: PayablesTab(space: pfSpace)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final constrainedBoxes = tester.widgetList<ConstrainedBox>(
        find.byType(ConstrainedBox),
      );
      final has1280 = constrainedBoxes.any(
        (b) => b.constraints.maxWidth == 1280.0,
      );
      expect(
        has1280,
        isTrue,
        reason: 'PayablesTab deve conter BoxConstraints(maxWidth: 1280)',
      );
    });

    testWidgets('AgreementsTab possui maxWidth 1280', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AgreementsRepository>(
              create: (_) => _FakeAgreementsRepository(),
            ),
            ChangeNotifierProvider<SessionController>(
              create: (_) => _FakeSessionController(),
            ),
            Provider<PreferencesController?>(create: (_) => null),
          ],
          child: const MaterialApp(
            home: Scaffold(body: AgreementsTab(space: pfSpace)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final constrainedBoxes = tester.widgetList<ConstrainedBox>(
        find.byType(ConstrainedBox),
      );
      final has1280 = constrainedBoxes.any(
        (b) => b.constraints.maxWidth == 1280.0,
      );
      expect(
        has1280,
        isTrue,
        reason: 'AgreementsTab deve conter BoxConstraints(maxWidth: 1280)',
      );
    });
  });
}
