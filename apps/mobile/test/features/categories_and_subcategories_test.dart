import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/categories/category.dart';
import 'package:bigdevz_finance/features/categories/category_style_catalog.dart';
import 'package:bigdevz_finance/features/summary/dashboard_charts.dart';
import 'package:bigdevz_finance/features/summary/summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Melhoria 1 & 2: Categorias, Subcategorias e Identidade Visual (Ícones/Cores)', () {
    test('Modelo Category com parentId, parentName e fullName', () {
      const parent = Category(
        id: 10,
        spaceId: 1,
        name: 'Moradia',
        type: 'expense',
        icon: 'home',
        color: '#2563EB',
      );
      expect(parent.isSubcategory, isFalse);
      expect(parent.fullName, 'Moradia');

      const child = Category(
        id: 11,
        spaceId: 1,
        parentId: 10,
        parentName: 'Moradia',
        name: 'Energia',
        type: 'expense',
        icon: 'bolt',
        color: '#D97706',
      );
      expect(child.isSubcategory, isTrue);
      expect(child.parentId, 10);
      expect(child.fullName, 'Moradia > Energia');

      // Parsing JSON com hierarquia
      final jsonChild = Category.fromJson({
        'id': 12,
        'space_id': 1,
        'parent_id': 10,
        'parent_name': 'Moradia',
        'name': 'Água',
        'type': 'expense',
        'icon': 'water_drop',
        'color': '#0891B2',
      });
      expect(jsonChild.isSubcategory, isTrue);
      expect(jsonChild.fullName, 'Moradia > Água');
    });

    test('CategoryStyleCatalog: mapeamento estável de ícone e cor padrão', () {
      // Cores predefinidas da especificação
      expect(
        CategoryStyleCatalog.getDefaultColorHex('home'),
        '#1E5BB8',
      ); // Moradia - azul
      expect(
        CategoryStyleCatalog.getDefaultColorHex('bolt'),
        '#D97706',
      ); // Energia - âmbar
      expect(
        CategoryStyleCatalog.getDefaultColorHex('water_drop'),
        '#06B6D4',
      ); // Água - ciano
      expect(
        CategoryStyleCatalog.getDefaultColorHex('shopping_cart'),
        '#10B981',
      ); // Mercado - verde
      expect(
        CategoryStyleCatalog.getDefaultColorHex('restaurant'),
        '#EA580C',
      ); // Alimentação fora - laranja
      expect(
        CategoryStyleCatalog.getDefaultColorHex('directions_car'),
        '#4F46E5',
      ); // Transporte - índigo
      expect(
        CategoryStyleCatalog.getDefaultColorHex('medical_services'),
        '#0D9488',
      ); // Saúde - turquesa
      expect(
        CategoryStyleCatalog.getDefaultColorHex('groups'),
        '#7C3AED',
      ); // Folha de pagamento - violeta
      expect(
        CategoryStyleCatalog.getDefaultColorHex('description'),
        '#B45309',
      ); // Tributos - ocre
      expect(
        CategoryStyleCatalog.getDefaultColorHex('computer'),
        '#0891B2',
      ); // Software - azul-petróleo

      // Fallback para ícone desconhecido
      final fallbackIcon = CategoryStyleCatalog.getIcon('desconhecido_xyz');
      expect(fallbackIcon, Icons.category);
      expect(
        CategoryStyleCatalog.getIconInfo('desconhecido_xyz').label,
        'Outros / Geral',
      );
    });

    test(
      'CategoryStyleCatalog: contraste adaptativo em temas claro e escuro',
      () {
        // Âmbar #D97706 no tema claro deve ter contraste adequado
        final amber = CategoryStyleCatalog.colorFromHex('#D97706');
        final readable = CategoryStyleCatalog.readableOnLight(amber);
        expect(readable, isNotNull);
        expect(readable.computeLuminance() <= 0.45, isTrue);
      },
    );

    testWidgets(
      'Composição do relatório: Moradia R\$ 30,00 e Moradia > Energia R\$ 50,00 somam R\$ 80,00 sem duplicidade',
      (tester) async {
        final summaryItems = [
          const CategorySummaryItem(
            id: 10,
            name: 'Moradia',
            color: '#2563EB',
            icon: 'home',
            total: Money(8000), // R$ 80,00 total do grupo
            totalCents: 8000,
            hasChildren: true,
            composition: [
              CategorySummaryItem(
                id: 10,
                name: 'Moradia',
                total: Money(3000), // R$ 30,00
                totalCents: 3000,
                isDirect: true,
                color: '#2563EB',
                icon: 'home',
              ),
              CategorySummaryItem(
                id: 11,
                name: 'Energia',
                total: Money(5000), // R$ 50,00
                totalCents: 5000,
                isDirect: false,
                color: '#D97706',
                icon: 'bolt',
              ),
            ],
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CategoryDistributionDonutCard(
                  categories: CategoriesSummary(
                    expenses: summaryItems,
                    incomes: const [],
                  ),
                  obscure: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Card principal exibe grupo e total R$ 80,00
        expect(find.text('MORADIA'), findsOneWidget);
        expect(find.text(r'R$ 80,00'), findsWidgets);

        // Clicar na categoria expande a composição com subcategorias
        await tester.tap(find.text('MORADIA'));
        await tester.pumpAndSettle();

        // Detalhamento exibe diretamente e filha Energia R$ 50,00
        expect(find.text('MORADIA (DIRETO)'), findsOneWidget);
        expect(find.text(r'R$ 30,00'), findsOneWidget);
        expect(find.text('ENERGIA'), findsOneWidget);
        expect(find.text(r'R$ 50,00'), findsOneWidget);
      },
    );
  });
}
