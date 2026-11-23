import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/summary/dashboard_charts.dart';
import 'package:bigdevz_finance/features/summary/summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExecutiveDashboardCharts', () {
    final accounts = [
      const Account(
        id: 1,
        name: 'Nubank Principal',
        openingBalance: Money(100000),
        openingBalanceDate: '2026-01-01',
        balance: Money(600000), // R$ 6.000,00 (60%)
      ),
      const Account(
        id: 2,
        name: 'Itaú Empresas',
        openingBalance: Money(100000),
        openingBalanceDate: '2026-01-01',
        balance: Money(400000), // R$ 4.000,00 (40%)
      ),
    ];

    const summary = SpaceSummary(
      balance: Money(1000000),
      receivedTotal: Money(1200000), // R$ 12.000,00 recebido
      receivableRemaining: Money(
        300000,
      ), // R$ 3.000,00 a receber -> Total Entradas: R$ 15.000,00
      accountsCount: 2,
      agreementsCount: 3,
      overdueInstallments: 0,
      payables: PayablesSummary(
        paidTotal: Money(600000), // R$ 6.000,00 pago
        openTotal: Money(200000), // R$ 2.000,00 aberto
        overdueTotal: Money(100000), // R$ 1.000,00 vencido (subconjunto de openTotal) -> Total Saídas: R$ 8.000,00
        overdueCount: 1,
        dueNext30DaysTotal: Money(200000),
        awaitingAmountCount: 0,
      ),
    );

    testWidgets(
      'renderiza Donut de bancos com percentuais e Termômetro com superávit',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ExecutiveDashboardCharts(
                  summary: summary,
                  accounts: accounts,
                  obscure: false,
                  onOpenAccounts: () {},
                  onOpenReceivables: () {},
                  onOpenPayables: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Card Donut de Bancos
        expect(find.text('Distribuição por Bancos'), findsOneWidget);
        expect(find.text('NUBANK PRINCIPAL'), findsOneWidget);
        expect(find.text('ITAÚ EMPRESAS'), findsOneWidget);
        expect(find.text('60%'), findsOneWidget);
        expect(find.text('40%'), findsOneWidget);

        // Card Termômetro de Fluxo de Caixa
        expect(find.text('Fluxo de Caixa'), findsOneWidget);
        expect(find.text('Entradas'), findsOneWidget);
        expect(find.text('Saídas & Compromissos'), findsOneWidget);
        expect(find.textContaining('Previsão de sobra'), findsOneWidget);
        expect(find.textContaining(r'R$ 7.000,00'), findsOneWidget);
        expect(find.textContaining(r'R$ 8.000,00'), findsOneWidget);
        expect(find.textContaining(r'R$ 6.000,00'), findsWidgets);
      },
    );

    testWidgets('respeita modo de privacidade ocultando valores monetários', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExecutiveDashboardCharts(
                summary: summary,
                accounts: accounts,
                obscure: true,
                onOpenAccounts: () {},
                onOpenReceivables: () {},
                onOpenPayables: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('••••'), findsWidgets);
    });

    testWidgets(
      'AC-FIN-030: consolida Saídas & Compromissos sem dupla contagem de vencidos e exibe alerta de insuficiência',
      (tester) async {
        // Cenário sintético PEND-001 / AC-FIN-030:
        // R$ 520,29 vencidos + R$ 439,59 a vencer = R$ 959,88 em aberto (openTotal)
        // Ambos em aberto, sem pagamentos realizados (paidTotal = 0)
        // Entradas controladas em R$ 0,00 para disparar alerta de déficit controlado
        const syntheticSummary = SpaceSummary(
          balance: Money(0),
          receivedTotal: Money(0),
          receivableRemaining: Money(0),
          accountsCount: 1,
          agreementsCount: 0,
          overdueInstallments: 0,
          payables: PayablesSummary(
            paidTotal: Money(0), // Sem pagamentos realizados
            openTotal: Money(
              95988,
            ), // R$ 959,88 em aberto (vencidos + a vencer)
            overdueTotal: Money(
              52029,
            ), // R$ 520,29 vencidos (subconjunto de openTotal)
            overdueCount: 1,
            dueNext30DaysTotal: Money(43959), // R$ 439,59 a vencer
            awaitingAmountCount: 0,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CashFlowThermometerCard(
                  summary: syntheticSummary,
                  obscure: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Total correto de Saídas & Compromissos: R$ 959,88 (sem inflar para R$ 1.480,17)
        expect(find.text('Saídas & Compromissos'), findsOneWidget);
        expect(find.text(r'R$ 959,88'), findsOneWidget);

        // 2. Alerta de insuficiência com entradas e saldo controlados:
        // totalInflow (0) - totalOutflow (959,88) = déficit de R$ 959,88
        expect(find.text(r'Atenção: vai faltar R$ 959,88'), findsOneWidget);
      },
    );
  });
}
