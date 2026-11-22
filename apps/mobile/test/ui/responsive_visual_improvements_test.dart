import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/accounts/account_card.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/categories/category.dart';
import 'package:bigdevz_finance/features/categories/category_badge.dart';
import 'package:bigdevz_finance/features/summary/dashboard_charts.dart';
import 'package:bigdevz_finance/features/summary/summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const pfSpace = Space(id: 1, kind: 'PF', name: 'Pessoal');

void main() {
  group('Melhorias Visuais e Responsividade (375px mobile e 1200px desktop)', () {
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

    testWidgets('CategoryBadge contrasta e renderiza em tema claro e escuro', (
      tester,
    ) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const Scaffold(
              body: Column(
                children: [
                  CategoryBadge(category: parentCat),
                  CategoryBadge(category: childCat, showFullPath: true),
                  CategoryBadge(category: childCat, compact: true),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('MORADIA'), findsOneWidget);
        expect(find.text('MORADIA > ENERGIA'), findsOneWidget);
        expect(find.byIcon(Icons.bolt_rounded), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
      'CategoryDistributionDonutCard renderiza em 375px e 1200px sem overflow',
      (tester) async {
        final summary = CategoriesSummary(
          expenses: [
            CategorySummaryItem(
              id: 10,
              name: 'Moradia',
              icon: 'home',
              color: '#1E5BB8',
              total: const Money(8000),
              totalCents: 8000,
              hasChildren: true,
              composition: [
                CategorySummaryItem(
                  id: 10,
                  name: 'Moradia',
                  icon: 'home',
                  color: '#1E5BB8',
                  total: const Money(3000),
                  totalCents: 3000,
                  isDirect: true,
                ),
                CategorySummaryItem(
                  id: 11,
                  name: 'Energia',
                  icon: 'bolt',
                  color: '#D97706',
                  total: const Money(5000),
                  totalCents: 5000,
                ),
              ],
            ),
          ],
        );

        for (final width in [375.0, 1200.0]) {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: CategoryDistributionDonutCard(
                    key: ValueKey(width),
                    categories: summary,
                    obscure: false,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('MORADIA'), findsOneWidget);
          expect(find.text('R\$ 80,00'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Expande composição clicando na categoria
          await tester.tap(find.text('MORADIA'));
          await tester.pumpAndSettle();

          expect(find.text('MORADIA (DIRETO)'), findsOneWidget);
          expect(find.text('ENERGIA'), findsOneWidget);
          expect(find.text('R\$ 50,00'), findsOneWidget);
          expect(find.text('R\$ 30,00'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('AccountCard exibe Wise e DUCZ Benefícios em 375px e 1200px', (
      tester,
    ) async {
      const wiseAccount = Account(
        id: 1,
        name: 'Wise Global',
        openingBalance: Money(10000),
        openingBalanceDate: '2026-01-01',
        balance: Money(6410),
      );

      const duczAccount = Account(
        id: 2,
        name: 'DUCZ Benefícios Alimentação',
        openingBalance: Money(50000),
        openingBalanceDate: '2026-01-01',
        balance: Money(50000),
      );

      for (final width in [375.0, 1200.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    AccountCard(space: pfSpace, account: wiseAccount),
                    AccountCard(space: pfSpace, account: duczAccount),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('WISE GLOBAL'), findsOneWidget);
        expect(find.text('DUCZ BENEFÍCIOS ALIMENTAÇÃO'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
