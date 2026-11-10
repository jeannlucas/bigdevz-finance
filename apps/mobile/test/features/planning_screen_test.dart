import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/planning/planning_models.dart';
import 'package:bigdevz_finance/features/planning/planning_repository.dart';
import 'package:bigdevz_finance/features/planning/planning_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class FakePlanningRepository extends PlanningRepository {
  FakePlanningRepository({required this.response})
    : super(ApiClient(baseUrl: 'http://example.com'));

  final CashFlowResponse response;

  @override
  Future<CashFlowResponse> fetchCashFlow({
    required int spaceId,
    int days = 30,
    String view = 'cash',
    int? accountId,
    int? categoryId,
  }) async {
    return response;
  }
}

final fakeResponse = CashFlowResponse(
  initialBalance: const Money(500000),
  periodDays: 30,
  view: 'cash',
  startDate: '2026-11-09',
  endDate: '2026-12-08',
  summary: const CashFlowSummary(
    realizedInflow: Money(200000),
    realizedOutflow: Money(100000),
    projectedInflow: Money(600000),
    projectedOutflow: Money(300000),
    finalProjectedBalance: Money(900000),
  ),
  daily: [
    const CashFlowDaily(
      date: '2026-11-09',
      realizedInflow: Money(200000),
      realizedOutflow: Money(100000),
      projectedInflow: Money(0),
      projectedOutflow: Money(0),
      projectedBalance: Money(600000),
      itemsCount: 2,
    ),
    const CashFlowDaily(
      date: '2026-11-10',
      realizedInflow: Money(0),
      realizedOutflow: Money(0),
      projectedInflow: Money(600000),
      projectedOutflow: Money(300000),
      projectedBalance: Money(900000),
      itemsCount: 2,
    ),
  ],
);

Widget buildTestWidget({
  required Space space,
  required CashFlowResponse response,
}) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        Provider<PlanningRepository>(
          create: (_) => FakePlanningRepository(response: response),
        ),
      ],
      child: PlanningScreen(
        space: space,
        repository: FakePlanningRepository(response: response),
      ),
    ),
  );
}

void main() {
  testWidgets('PlanningScreen: renders filters, metrics and daily timeline', (
    tester,
  ) async {
    const space = Space(
      id: 1,
      kind: 'PJ',
      name: 'Empresa Teste',
      role: 'administrador',
    );

    await tester.pumpWidget(
      buildTestWidget(space: space, response: fakeResponse),
    );
    await tester.pumpAndSettle();

    expect(find.text('Planejamento e Fluxo de Caixa'), findsOneWidget);
    expect(find.text('Filtros e Projeção'), findsOneWidget);
    expect(find.text('30 dias'), findsOneWidget);
    expect(find.text('60 dias'), findsOneWidget);
    expect(find.text('90 dias'), findsOneWidget);
    expect(find.text('Visão de Caixa'), findsOneWidget);
    expect(find.text('Visão de Competência'), findsOneWidget);

    // Cards Executivos de Resumo
    expect(find.text('Saldo Inicial do Período'), findsOneWidget);
    expect(find.text('Saldo Final Projetado'), findsOneWidget);
    expect(find.text('Projeção Diária de Caixa (2 dias)'), findsOneWidget);

    // Botão de exportação ativo para Administrador
    expect(find.byTooltip('Exportar Fluxo de Caixa (CSV)'), findsOneWidget);
  });

  testWidgets('PlanningScreen: blocks export action for operator profile', (
    tester,
  ) async {
    const operatorSpace = Space(
      id: 1,
      kind: 'PJ',
      name: 'Empresa Teste',
      role: 'operador',
    );

    await tester.pumpWidget(
      buildTestWidget(space: operatorSpace, response: fakeResponse),
    );
    await tester.pumpAndSettle();

    // Botão de exportação NÃO deve estar disponível para operador
    expect(find.byTooltip('Exportar Fluxo de Caixa (CSV)'), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
  });
}
