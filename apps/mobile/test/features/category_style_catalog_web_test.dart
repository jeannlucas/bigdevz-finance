import 'package:bigdevz_finance/features/categories/category_icon_color_picker.dart';
import 'package:bigdevz_finance/features/categories/category_style_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AC-CAT-011: Renderização Universal de Glifos e Visibilidade Completa do Seletor', () {
    test('Todos os 20 ícones do catálogo utilizam identificadores universais do Material Icons (sem *_rounded)', () {
      final expectedUniversalIcons = <String, IconData>{
        'home': Icons.home,
        'bolt': Icons.bolt,
        'water_drop': Icons.water_drop,
        'shopping_cart': Icons.shopping_cart,
        'restaurant': Icons.restaurant,
        'directions_car': Icons.directions_car,
        'medical_services': Icons.medical_services,
        'groups': Icons.groups,
        'description': Icons.description,
        'computer': Icons.computer,
        'work': Icons.work,
        'trending_up': Icons.trending_up,
        'savings': Icons.savings,
        'credit_card': Icons.credit_card,
        'school': Icons.school,
        'pets': Icons.pets,
        'local_gas_station': Icons.local_gas_station,
        'fitness_center': Icons.fitness_center,
        'receipt': Icons.receipt,
        'category': Icons.category,
      };

      expect(CategoryStyleCatalog.icons.length, equals(20));

      for (final entry in expectedUniversalIcons.entries) {
        final iconInfo = CategoryStyleCatalog.getIconInfo(entry.key);
        expect(
          iconInfo.iconData,
          equals(entry.value),
          reason:
              'O ícone [${entry.key}] deve utilizar o IconData universal [${entry.value}] para garantir renderização no Flutter Web',
        );

        final resolvedIcon = CategoryStyleCatalog.getIcon(entry.key);
        expect(
          resolvedIcon,
          equals(entry.value),
          reason:
              'CategoryStyleCatalog.getIcon("${entry.key}") deve resolver para o IconData universal correspondente',
        );
      }
    });

    testWidgets(
      'CategoryIconColorPicker renderiza os 20 ícones com mainAxisExtent previsível e seleção funcional',
      (tester) async {
        String selectedIcon = 'home';
        String selectedColor = '#1E5BB8';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return CategoryIconColorPicker(
                    selectedIcon: selectedIcon,
                    selectedColor: selectedColor,
                    onIconChanged: (newIcon) {
                      setState(() => selectedIcon = newIcon);
                    },
                    onColorChanged: (newColor) {
                      setState(() => selectedColor = newColor);
                    },
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verifica que o GridView utiliza mainAxisExtent para garantir altura previsível
        final gridView = tester.widget<GridView>(find.byType(GridView));
        final delegate = gridView.gridDelegate;
        expect(delegate, isA<SliverGridDelegateWithFixedCrossAxisCount>());
        final fixedDelegate =
            delegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(
          fixedDelegate.mainAxisExtent,
          equals(52.0),
          reason: 'O grid deve usar mainAxisExtent: 52 para evitar distorção e corte da segunda linha no desktop',
        );

        // Clica no ícone de energia elétrica ('bolt')
        final boltFinder = find.byTooltip('Energia elétrica');
        expect(boltFinder, findsOneWidget);
        await tester.tap(boltFinder);
        await tester.pumpAndSettle();

        expect(selectedIcon, equals('bolt'));
        expect(
          selectedColor,
          equals('#D97706'),
        ); // Aplica automaticamente a cor padrão da energia

        // Clica no ícone de software ('computer')
        final computerFinder = find.byTooltip('Software e assinaturas');
        expect(computerFinder, findsOneWidget);
        await tester.tap(computerFinder);
        await tester.pumpAndSettle();

        expect(selectedIcon, equals('computer'));
        expect(
          selectedColor,
          equals('#0891B2'),
        ); // Aplica automaticamente a cor padrão de software
      },
    );
  });
}
