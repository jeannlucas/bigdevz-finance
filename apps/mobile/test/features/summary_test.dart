import 'dart:async';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/summary/summary.dart';
import 'package:bigdevz_finance/features/summary/summary_tab.dart';
import 'package:bigdevz_finance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

/// Repositório falso multi-espaço que diferencia rigorosamente dados de PF e PJ
class _MultiSpaceSummaryRepository implements SummaryRepository {
  _MultiSpaceSummaryRepository({
    required this.pfSummary,
    required this.pjSummary,
  });

  SpaceSummary pfSummary;
  SpaceSummary pjSummary;
  final List<int> requestedSpaceIds = [];

  @override
  Future<SpaceSummary> load(int spaceId) async {
    requestedSpaceIds.add(spaceId);
    if (spaceId == 1) return pfSummary;
    if (spaceId == 2) return pjSummary;
    throw ArgumentError('Espaço não configurado para testes: $spaceId');
  }
}

/// Repositório falso para simulação determinística de respostas fora de ordem (race conditions)
class _DelayedOrderSummaryRepository implements SummaryRepository {
  final Map<int, Completer<SpaceSummary>> _completers = {};
  final List<int> requestedSpaceIds = [];

  void setCompleter(int spaceId, Completer<SpaceSummary> completer) {
    _completers[spaceId] = completer;
  }

  @override
  Future<SpaceSummary> load(int spaceId) {
    requestedSpaceIds.add(spaceId);
    final completer = _completers[spaceId];
    if (completer != null) return completer.future;
    throw StateError('Nenhum completer configurado para spaceId: $spaceId');
  }
}

/// Repositório falso para teste de erros de rede e recuperação
class _FailingSummaryRepository implements SummaryRepository {
  _FailingSummaryRepository({required this.summary, this.shouldFail = true});

  final SpaceSummary summary;
  bool shouldFail;
  int loadAttempts = 0;

  @override
  Future<SpaceSummary> load(int spaceId) async {
    loadAttempts++;
    if (shouldFail) {
      throw Exception('Falha de conexão com a API de Resumo.');
    }
    return summary;
  }
}

/// Harness para teste de alternância dinâmica emulando a KeyedSubtree do HomeShell
class _DynamicSpaceHarness extends StatefulWidget {
  const _DynamicSpaceHarness({
    required this.repository,
    required this.initialSpace,
    required this.onOpenTab,
  });

  final SummaryRepository repository;
  final Space initialSpace;
  final void Function(int tab, {String? filter}) onOpenTab;

  @override
  State<_DynamicSpaceHarness> createState() => _DynamicSpaceHarnessState();
}

class _DynamicSpaceHarnessState extends State<_DynamicSpaceHarness> {
  late Space _currentSpace;

  @override
  void initState() {
    super.initState();
    _currentSpace = widget.initialSpace;
  }

  void switchSpace(Space space) {
    setState(() {
      _currentSpace = space;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            TextButton(
              key: const ValueKey('btn-switch-pf'),
              onPressed: () =>
                  switchSpace(const Space(id: 1, name: 'Pessoal', kind: 'PF')),
              child: const Text('Mudar PF'),
            ),
            TextButton(
              key: const ValueKey('btn-switch-pj'),
              onPressed: () =>
                  switchSpace(const Space(id: 2, name: 'Empresa', kind: 'PJ')),
              child: const Text('Mudar PJ'),
            ),
          ],
        ),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey('space-${_currentSpace.id}'),
            child: SummaryTab(
              space: _currentSpace,
              onOpenTab: widget.onOpenTab,
            ),
          ),
        ),
      ],
    );
  }
}

void main() {
  const pfSpace = Space(id: 1, name: 'Pessoal', kind: 'PF');

  const pjSpace = Space(id: 2, name: 'Empresa', kind: 'PJ');

  // Dados deliberadamente distintos para PF (Pessoa Física)
  final pfSummary = SpaceSummary(
    balance: const Money(125000), // R$ 1.250,00
    receivableRemaining: const Money(30000), // R$ 300,00
    receivedTotal: const Money(5000), // R$ 50,00
    accountsCount: 2,
    agreementsCount: 3,
    overdueInstallments: 1,
    archivedAccountsCount: 0,
    payables: const PayablesSummary(
      openTotal: Money(15000), // R$ 150,00
      overdueTotal: Money(5000), // R$ 50,00
      overdueCount: 1,
      dueNext30DaysTotal: Money(10000), // R$ 100,00
      paidTotal: Money(4000), // R$ 40,00
      awaitingAmountCount: 0,
    ),
  );

  // Dados deliberadamente distintos para PJ (Pessoa Jurídica)
  final pjSummary = SpaceSummary(
    balance: const Money(980000), // R$ 9.800,00
    receivableRemaining: const Money(240000), // R$ 2.400,00
    receivedTotal: const Money(80000), // R$ 800,00
    accountsCount: 5,
    agreementsCount: 12,
    overdueInstallments: 4,
    archivedAccountsCount: 1,
    payables: const PayablesSummary(
      openTotal: Money(110000), // R$ 1.100,00
      overdueTotal: Money(30000), // R$ 300,00
      overdueCount: 2,
      dueNext30DaysTotal: Money(80000), // R$ 800,00
      paidTotal: Money(65000), // R$ 650,00
      awaitingAmountCount: 1,
    ),
  );

  Widget createTestWidget({
    required Space space,
    required SummaryRepository repository,
    required void Function(int tab, {String? filter}) onOpenTab,
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
    Size size = const Size(402, 874),
  }) {
    final client = ApiClient(
      baseUrl: 'http://api.test/api',
      client: FakeBackend().client,
    );
    return MultiProvider(
      providers: [
        Provider<SummaryRepository>.value(value: repository),
        ChangeNotifierProvider(
          create: (_) =>
              SessionController(
                  api: client,
                  auth: AuthRepository(client),
                  storage: MemorySessionStorage(),
                )
                ..user = const AppUser(
                  id: 1,
                  name: 'Demo User',
                  email: 'demo@example.com',
                ),
        ),
      ],
      child: MaterialApp(
        theme: buildTheme(brightness, seed: seedForSpace(space.isPf)),
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            size: size,
          ),
          child: Scaffold(
            body: SummaryTab(space: space, onOpenTab: onOpenTab),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 1. ISOLAMENTO REAL PF / PJ E IDENTIDADE VISUAL
  // =========================================================================

  testWidgets(
    '1.1: renderiza Dashboard PF exibindo estritamente dados PF e identidade Azul Profundo',
    (tester) async {
      final repo = _MultiSpaceSummaryRepository(
        pfSummary: pfSummary,
        pjSummary: pjSummary,
      );

      await tester.pumpWidget(
        createTestWidget(
          space: pfSpace,
          repository: repo,
          onOpenTab: (_, {filter}) {},
        ),
      );
      await tester.pumpAndSettle();

      // Identificação PF
      expect(find.text('Visão Geral Financeira'), findsOneWidget);
      expect(find.text('Pessoal (PF)'), findsOneWidget);
      expect(find.text('PF'), findsOneWidget);

      // Saldo disponível exclusivo de PF (R$ 1.250,00)
      expect(find.text(r'R$ 1.250,00'), findsOneWidget);
      expect(
        find.text(r'R$ 9.800,00'),
        findsNothing,
      ); // Prova de ausência de dados PJ

      // Métricas exclusivas de PF no topo
      expect(find.text(r'R$ 300,00'), findsOneWidget); // A receber
      expect(find.text(r'R$ 50,00'), findsOneWidget); // Já recebido (topo)
      expect(find.text('1 parcela vencida a receber'), findsOneWidget);

      // Obrigações a pagar exclusivas de PF
      await tester.scrollUntilVisible(
        find.text('Obrigações e Faturas'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(r'R$ 150,00'), findsOneWidget); // Em aberto PF
      expect(
        find.text(r'R$ 50,00'),
        findsNWidgets(2),
      ); // Já recebido (topo) e Vencido a pagar (card)
      expect(find.text(r'R$ 1.100,00'), findsNothing); // Dado PJ ausente

      // Confirma que o repositório foi chamado estritamente para o spaceId 1
      expect(repo.requestedSpaceIds, [1]);
    },
  );

  testWidgets(
    '1.2: renderiza Dashboard PJ exibindo estritamente dados PJ e identidade Verde Esmeralda',
    (tester) async {
      final repo = _MultiSpaceSummaryRepository(
        pfSummary: pfSummary,
        pjSummary: pjSummary,
      );

      await tester.pumpWidget(
        createTestWidget(
          space: pjSpace,
          repository: repo,
          onOpenTab: (_, {filter}) {},
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();

      // Identificação PJ
      expect(find.text('Visão Geral Financeira'), findsOneWidget);
      expect(find.text('Empresa (PJ)'), findsOneWidget);
      expect(find.text('PJ'), findsOneWidget);

      // Saldo disponível exclusivo de PJ (R$ 9.800,00)
      expect(find.text(r'R$ 9.800,00'), findsOneWidget);
      expect(
        find.text(r'R$ 1.250,00'),
        findsNothing,
      ); // Prova de ausência de dados PF

      // Métricas exclusivas de PJ no topo
      expect(find.text(r'R$ 2.400,00'), findsOneWidget); // A receber
      expect(find.text(r'R$ 800,00'), findsOneWidget); // Já recebido (topo)
      expect(find.text('4 parcelas vencidas a receber'), findsOneWidget);

      // Obrigações a pagar exclusivas de PJ
      await tester.scrollUntilVisible(
        find.text('Obrigações e Faturas'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(r'R$ 1.100,00'), findsOneWidget); // Em aberto PJ
      expect(
        find.text(r'R$ 800,00'),
        findsNWidgets(2),
      ); // Já recebido (topo) e Próximos 30 dias (card)
      expect(find.text(r'R$ 150,00'), findsNothing); // Dado PF ausente

      // Confirma que o repositório foi chamado estritamente para o spaceId 2
      expect(repo.requestedSpaceIds, [2]);
    },
  );

  testWidgets(
    '1.3: alternância dinâmica PF -> PJ -> PF atualiza dados e limpa estado anterior',
    (tester) async {
      final repo = _MultiSpaceSummaryRepository(
        pfSummary: pfSummary,
        pjSummary: pjSummary,
      );

      final client = ApiClient(
        baseUrl: 'http://api.test/api',
        client: FakeBackend().client,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SummaryRepository>.value(value: repo),
            ChangeNotifierProvider(
              create: (_) =>
                  SessionController(
                      api: client,
                      auth: AuthRepository(client),
                      storage: MemorySessionStorage(),
                    )
                    ..user = const AppUser(
                      id: 1,
                      name: 'Demo User',
                      email: 'demo@example.com',
                    ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: _DynamicSpaceHarness(
                repository: repo,
                initialSpace: pfSpace,
                onOpenTab: (_, {filter}) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Estado inicial: PF
      expect(find.text('Pessoal (PF)'), findsOneWidget);
      expect(find.text(r'R$ 1.250,00'), findsOneWidget);
      expect(find.text(r'R$ 9.800,00'), findsNothing);

      // 2. Transição para PJ
      await tester.tap(find.byKey(const ValueKey('btn-switch-pj')));
      await tester.pumpAndSettle();

      expect(find.text('Empresa (PJ)'), findsOneWidget);
      expect(find.text(r'R$ 9.800,00'), findsOneWidget);
      expect(
        find.text(r'R$ 1.250,00'),
        findsNothing,
      ); // Dados de PF não vazaram

      // 3. Retorno para PF
      await tester.tap(find.byKey(const ValueKey('btn-switch-pf')));
      await tester.pumpAndSettle();

      expect(find.text('Pessoal (PF)'), findsOneWidget);
      expect(find.text(r'R$ 1.250,00'), findsOneWidget);
      expect(find.text(r'R$ 9.800,00'), findsNothing);

      // Sequência de requisições registradas no repositório
      expect(repo.requestedSpaceIds, [1, 2, 1]);
    },
  );

  // =========================================================================
  // 2. RESPOSTAS ASSÍNCRONAS FORA DE ORDEM (RACE CONDITION PREVENTION)
  // =========================================================================

  testWidgets(
    '2.1: resposta atrasada do espaço anterior é descartada e não sobrescreve espaço ativo',
    (tester) async {
      final repo = _DelayedOrderSummaryRepository();
      final pfCompleter = Completer<SpaceSummary>();
      final pjCompleter = Completer<SpaceSummary>();

      repo.setCompleter(1, pfCompleter);
      repo.setCompleter(2, pjCompleter);

      final client = ApiClient(
        baseUrl: 'http://api.test/api',
        client: FakeBackend().client,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SummaryRepository>.value(value: repo),
            ChangeNotifierProvider(
              create: (_) =>
                  SessionController(
                      api: client,
                      auth: AuthRepository(client),
                      storage: MemorySessionStorage(),
                    )
                    ..user = const AppUser(
                      id: 1,
                      name: 'Demo User',
                      email: 'demo@example.com',
                    ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: _DynamicSpaceHarness(
                repository: repo,
                initialSpace: pfSpace,
                onOpenTab: (_, {filter}) {},
              ),
            ),
          ),
        ),
      );
      // PF dispara load(1), completer ainda não completou: tela em loading
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Usuário altera imediatamente para PJ antes de PF responder
      await tester.tap(find.byKey(const ValueKey('btn-switch-pj')));
      await tester.pump();

      // PJ responde PRIMEIRO
      pjCompleter.complete(pjSummary);
      await tester.pumpAndSettle();

      // A tela agora exibe os dados de PJ
      expect(find.text('Empresa (PJ)'), findsOneWidget);
      expect(find.text(r'R$ 9.800,00'), findsOneWidget);

      // Agora a resposta atrasada de PF chega (fora de ordem)
      pfCompleter.complete(pfSummary);
      await tester.pumpAndSettle();

      // O Dashboard continua rigorosamente com os dados de PJ (descartou a resposta obsoleta de PF)
      expect(find.text('Empresa (PJ)'), findsOneWidget);
      expect(find.text(r'R$ 9.800,00'), findsOneWidget);
      expect(find.text(r'R$ 1.250,00'), findsNothing);
    },
  );

  // =========================================================================
  // 3. PRIVACIDADE DOS VALORES (OCULTAR / REVELAR)
  // =========================================================================

  testWidgets(
    '3.1: aciona botão de privacidade e mascara saldo, métricas e compromissos',
    (tester) async {
      final repo = _MultiSpaceSummaryRepository(
        pfSummary: pfSummary,
        pjSummary: pjSummary,
      );

      await tester.pumpWidget(
        createTestWidget(
          space: pfSpace,
          repository: repo,
          onOpenTab: (_, {filter}) {},
        ),
      );
      await tester.pumpAndSettle();

      // 1. Inicialmente visível no topo
      expect(find.text(r'R$ 1.250,00'), findsOneWidget);
      expect(find.text(r'R$ 300,00'), findsOneWidget);

      // 2. Clica para ocultar
      await tester.tap(find.byTooltip('Ocultar saldo'));
      await tester.pump();

      // Confirma que saldo e métricas estão mascarados no topo
      expect(find.text(r'R$ 1.250,00'), findsNothing);
      expect(find.text(r'R$ 300,00'), findsNothing);
      expect(find.text(r'R$ ••••••••'), findsOneWidget); // Saldo
      expect(find.text(r'R$ ••••'), findsWidgets); // Métricas de recebimento

      // 3. Clica para revelar novamente no topo
      await tester.tap(find.byTooltip('Mostrar saldo'));
      await tester.pump();

      // Valores restaurados no topo
      expect(find.text(r'R$ 1.250,00'), findsOneWidget);
      expect(find.text(r'R$ 300,00'), findsOneWidget);
      expect(find.text(r'R$ ••••••••'), findsNothing);

      // 4. Oculta novamente e rola até Obrigações para verificar a máscara lá também
      await tester.tap(find.byTooltip('Ocultar saldo'));
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Obrigações e Faturas'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(r'R$ 150,00'), findsNothing);
      expect(find.text(r'R$ 50,00'), findsNothing);
      expect(find.text(r'R$ ••••'), findsWidgets);
    },
  );

  // =========================================================================
  // 4. ERROS E FALHAS DE CARREGAMENTO COM RECUPERAÇÃO
  // =========================================================================

  testWidgets(
    '4.1: exibe tela de erro ao falhar carregamento e se recupera após retry',
    (tester) async {
      final repo = _FailingSummaryRepository(
        summary: pfSummary,
        shouldFail: true,
      );

      await tester.pumpWidget(
        createTestWidget(
          space: pfSpace,
          repository: repo,
          onOpenTab: (_, {filter}) {},
        ),
      );
      await tester.pumpAndSettle();

      // Verifica que exibiu a mensagem de erro sem crashar
      expect(find.text('Não foi possível carregar os dados.'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(repo.loadAttempts, 1);

      // Corrige a falha no repositório e clica em Tentar novamente
      repo.shouldFail = false;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();

      // Recuperação concluída com sucesso
      expect(repo.loadAttempts, 2);
      expect(find.text('Não foi possível carregar os dados.'), findsNothing);
      expect(find.text('Visão Geral Financeira'), findsOneWidget);
      expect(find.text(r'R$ 1.250,00'), findsOneWidget);
    },
  );

  // =========================================================================
  // 5. PULL-TO-REFRESH
  // =========================================================================

  testWidgets('5.1: pull-to-refresh atualiza dados exibidos na tela', (
    tester,
  ) async {
    final repo = _MultiSpaceSummaryRepository(
      pfSummary: pfSummary,
      pjSummary: pjSummary,
    );

    await tester.pumpWidget(
      createTestWidget(
        space: pfSpace,
        repository: repo,
        onOpenTab: (_, {filter}) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(r'R$ 1.250,00'), findsOneWidget);

    // Atualiza o saldo de PF no repositório para R$ 1.750,00
    repo.pfSummary = pfSummary.copyWith(
      balance: const Money(175000), // R$ 1.750,00
    );

    // Dispara pull-to-refresh no topo da ListView
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    // Novo saldo é refletido na interface
    expect(find.text(r'R$ 1.750,00'), findsOneWidget);
    expect(find.text(r'R$ 1.250,00'), findsNothing);
  });

  // =========================================================================
  // 6. ACESSIBILIDADE E VIEWPORTS COMPACTOS (150% E 200%)
  // =========================================================================

  testWidgets(
    '6.1: tela compacta (375pt) sob escala 150% renderiza sem overflow',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = _MultiSpaceSummaryRepository(
        pfSummary: pfSummary,
        pjSummary: pjSummary,
      );

      await tester.pumpWidget(
        createTestWidget(
          space: pfSpace,
          repository: repo,
          onOpenTab: (_, {filter}) {},
          textScale: 1.5,
          size: const Size(375, 667), // iPhone SE
        ),
      );
      await tester.pumpAndSettle();

      // Rola para cobrir toda a interface sob fonte ampliada
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      // Nenhuma exceção de overflow visual disparada
      expect(tester.takeException(), isNull);
      expect(find.text('Obrigações e Faturas'), findsOneWidget);
    },
  );

  testWidgets(
    '6.2: tela compacta (375pt) sob escala 200% extrema rola sem overflow',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = _MultiSpaceSummaryRepository(
        pfSummary: pfSummary,
        pjSummary: pjSummary,
      );

      await tester.pumpWidget(
        createTestWidget(
          space: pjSpace,
          repository: repo,
          onOpenTab: (_, {filter}) {},
          textScale: 2.0,
          brightness: Brightness.dark,
          size: const Size(375, 667),
        ),
      );
      await tester.pumpAndSettle();

      // Rola de forma determinística até o final garantindo que o card seja construído
      await tester.scrollUntilVisible(
        find.text('Carteira de Contas'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Carteira de Contas'), findsOneWidget);
    },
  );

  // =========================================================================
  // 7. AÇÕES RÁPIDAS E NAVEGAÇÃO CONTEXTUAL
  // =========================================================================

  testWidgets(
    '7.1: atalhos e cartões navegam diretamente com filtros adequados',
    (tester) async {
      int? openedTab;
      String? appliedFilter;

      final repo = _MultiSpaceSummaryRepository(
        pfSummary: pfSummary,
        pjSummary: pjSummary,
      );

      await tester.pumpWidget(
        createTestWidget(
          space: pfSpace,
          repository: repo,
          onOpenTab: (tab, {filter}) {
            openedTab = tab;
            appliedFilter = filter;
          },
        ),
      );
      await tester.pumpAndSettle();

      // 1. Ação rápida 'A receber'
      await tester.tap(find.widgetWithText(InkWell, 'A receber').first);
      expect(openedTab, 1);

      // 2. Ação rápida 'A pagar'
      await tester.tap(find.widgetWithText(InkWell, 'A pagar').first);
      expect(openedTab, 2);

      // 3. Ação rápida 'Contas'
      await tester.tap(find.widgetWithText(InkWell, 'Contas').first);
      expect(openedTab, 3);

      // 4. Métrica 'A receber (previsto)' com filtro 'open'
      await tester.tap(find.text('A receber (previsto)'));
      expect(openedTab, 1);
      expect(appliedFilter, 'open');

      // 5. Métrica 'Já recebido' com filtro 'all'
      await tester.tap(find.text('Já recebido'));
      expect(openedTab, 1);
      expect(appliedFilter, 'all');

      // 6. Alerta de parcelas vencidas com filtro 'overdue'
      await tester.tap(find.text('1 parcela vencida a receber'));
      expect(openedTab, 1);
      expect(appliedFilter, 'overdue');

      // 7. Cartão de Obrigações e Faturas
      await tester.scrollUntilVisible(
        find.text('Obrigações e Faturas'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Obrigações e Faturas'));
      expect(openedTab, 2);

      // 8. Cartão de Acesso à Carteira de Contas
      await tester.scrollUntilVisible(
        find.text('Carteira de Contas'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Carteira de Contas'));
      expect(openedTab, 3);
    },
  );

  // =========================================================================
  // 8. INTEGRIDADE DA APRESENTAÇÃO FINANCEIRA
  // =========================================================================

  testWidgets(
    '8.1: compromissos previstos não alteram saldo disponível e exibem ressalva contábil',
    (tester) async {
      final repo = _MultiSpaceSummaryRepository(
        pfSummary: pfSummary,
        pjSummary: pjSummary,
      );

      await tester.pumpWidget(
        createTestWidget(
          space: pfSpace,
          repository: repo,
          onOpenTab: (_, {filter}) {},
        ),
      );
      await tester.pumpAndSettle();

      // Saldo disponível intacto (R$ 1.250,00)
      expect(find.text(r'R$ 1.250,00'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Obrigações e Faturas'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      // Obrigações em aberto: R$ 150,00 (não reduziu o saldo disponível de R$ 1.250,00)
      expect(find.text(r'R$ 150,00'), findsOneWidget);

      // Ressalva contábil mandatória explícita
      expect(
        find.text(
          'Obrigações não alteram saldo bancário; somente pagamentos efetivados.',
        ),
        findsOneWidget,
      );
    },
  );
}

extension on SpaceSummary {
  SpaceSummary copyWith({
    Money? balance,
    Money? receivableRemaining,
    Money? receivedTotal,
    int? accountsCount,
    int? agreementsCount,
    int? overdueInstallments,
    int? archivedAccountsCount,
    PayablesSummary? payables,
  }) {
    return SpaceSummary(
      balance: balance ?? this.balance,
      receivableRemaining: receivableRemaining ?? this.receivableRemaining,
      receivedTotal: receivedTotal ?? this.receivedTotal,
      accountsCount: accountsCount ?? this.accountsCount,
      agreementsCount: agreementsCount ?? this.agreementsCount,
      overdueInstallments: overdueInstallments ?? this.overdueInstallments,
      archivedAccountsCount:
          archivedAccountsCount ?? this.archivedAccountsCount,
      payables: payables ?? this.payables,
    );
  }
}
