import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/ui/widgets.dart';
import 'package:bigdevz_finance/ui/financial/financial_item_view.dart';
import 'package:bigdevz_finance/ui/financial/financial_desktop_table.dart';

void main() {
  testWidgets('FinancialDesktopTable exibe colunas, dados e ação rápida', (
    tester,
  ) async {
    final item = TestItem(
      id: 1,
      title: 'Hospedagem AWS',
      counterparty: 'Amazon Web Services',
      dueDate: '2026-03-15',
      kindLabel: 'Recorrente',
      statusLabel: 'Em aberto',
      statusTone: StatusTone.neutral,
      pendingAmount: const Money(45000), // R$ 450,00
      totalAmount: const Money(45000),
      isOverdue: false,
    );

    bool actionCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1000,
              child: FinancialDesktopTable<TestItem>(
                items: [item],
                quickActionLabel: 'Pagar',
                onQuickAction: (it) => actionCalled = true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Cabeçalhos de coluna
    expect(find.text('Vencimento'), findsOneWidget);
    expect(find.text('Descrição / Favorecido'), findsOneWidget);
    expect(find.text('Categoria'), findsOneWidget);
    expect(find.text('Tipo / Parcela'), findsOneWidget);
    expect(find.text('Situação'), findsOneWidget);
    expect(find.text('Valor'), findsOneWidget);
    expect(find.text('Ações'), findsOneWidget);

    // Linha de dados
    expect(find.text('HOSPEDAGEM AWS'), findsOneWidget);
    expect(find.text('AMAZON WEB SERVICES'), findsOneWidget);
    expect(find.text('Recorrente'), findsOneWidget);
    expect(find.text('Em aberto'), findsOneWidget);
    expect(find.text('R\$ 450,00'), findsOneWidget);
    expect(find.text('15/03/2026'), findsOneWidget);

    // Botão de ação rápida
    final btn = find.widgetWithText(FilledButton, 'Pagar');
    expect(btn, findsOneWidget);
    await tester.tap(btn);
    expect(actionCalled, isTrue);
  });
}

class TestItem implements FinancialItemView {
  TestItem({
    required this.id,
    required this.title,
    required this.dueDate,
    this.counterparty,
    this.pendingAmount,
    this.totalAmount,
    this.category,
    this.kindLabel = 'Avulsa',
    this.statusLabel = 'Em aberto',
    this.statusTone = StatusTone.neutral,
    this.isOverdue = false,
    this.isAwaitingAmount = false,
    this.isSettled = false,
    this.isEligibleForBatch = true,
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
  final StatusTone statusTone;
  @override
  final Money? pendingAmount;
  @override
  final Money? totalAmount;
  @override
  final bool isOverdue;
  @override
  final bool isAwaitingAmount;
  @override
  final bool isSettled;
  @override
  final bool isEligibleForBatch;
  @override
  final int? categoryId = null;
  @override
  final Money? paidAmount = null;
  @override
  final bool isPartial = false;
  @override
  final String? amountLabel = null;
}
