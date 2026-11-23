import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/categories/categories_repository.dart';
import 'package:bigdevz_finance/features/categories/category_picker_field.dart';

void main() {
  final syntheticCategories = [
    {
      'id': 10,
      'space_id': 1,
      'parent_id': null,
      'parent_name': null,
      'name': 'Transporte',
      'type': 'expense',
      'icon': 'directions_car',
      'color': '#4F46E5',
    },
    {
      'id': 11,
      'space_id': 1,
      'parent_id': 10,
      'parent_name': 'Transporte',
      'name': 'Combustível',
      'type': 'expense',
      'icon': 'local_gas_station',
      'color': '#EF4444',
    },
    {
      'id': 12,
      'space_id': 1,
      'parent_id': 10,
      'parent_name': 'Transporte',
      'name': 'Outros',
      'type': 'expense',
      'icon': 'directions_car',
      'color': '#4F46E5',
    },
    {
      'id': 20,
      'space_id': 1,
      'parent_id': null,
      'parent_name': null,
      'name': 'Alimentação',
      'type': 'expense',
      'icon': 'restaurant',
      'color': '#EA580C',
    },
    {
      'id': 21,
      'space_id': 1,
      'parent_id': 20,
      'parent_name': 'Alimentação',
      'name': 'Restaurante',
      'type': 'expense',
      'icon': 'restaurant',
      'color': '#EA580C',
    },
    {
      'id': 22,
      'space_id': 1,
      'parent_id': 20,
      'parent_name': 'Alimentação',
      'name': 'Outros',
      'type': 'expense',
      'icon': 'restaurant',
      'color': '#EA580C',
    },
    {
      'id': 30,
      'space_id': 1,
      'parent_id': null,
      'parent_name': null,
      'name': 'Empréstimos e Financiamentos',
      'type': 'expense',
      'icon': 'credit_card',
      'color': '#6366F1',
    },
    {
      'id': 31,
      'space_id': 1,
      'parent_id': 30,
      'parent_name': 'Empréstimos e Financiamentos',
      'name': 'Mercado Pago Linha de Crédito Empresarial PJ Especial',
      'type': 'expense',
      'icon': 'credit_card',
      'color': '#6366F1',
    },
    {
      'id': 40,
      'space_id': 1,
      'parent_id': null,
      'parent_name': null,
      'name': 'Água e Saneamento',
      'type': 'expense',
      'icon': 'water_drop',
      'color': '#06B6D4',
    },
  ];

  Widget buildTestWidget({int? selectedId, ValueChanged<int?>? onChanged}) {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'data': syntheticCategories}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repo = CategoriesRepository(
      ApiClient(baseUrl: 'http://localhost', client: client),
    );

    return MaterialApp(
      home: Scaffold(
        body: Provider<CategoriesRepository>.value(
          value: repo,
          child: CategoryPickerField(
            spaceId: 1,
            type: 'expense',
            selectedCategoryId: selectedId,
            onChanged: onChanged ?? (_) {},
          ),
        ),
      ),
    );
  }

  group('CategoryPickerField Hierarquia em Árvore (AC-CAT-012)', () {
    testWidgets(
      'ordena itens em árvore: pais alfabéticos seguidos de suas filhas com recuo de 20px',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        final dropdown = tester.widget<DropdownButton<int?>>(
          find.byType(DropdownButton<int?>),
        );

        final items = dropdown.items!;
        final itemValues = items.map((i) => i.value).toList();

        // Ordem esperada na árvore:
        // null: Sem categoria
        // 40: Água e Saneamento (Pai)
        // 20: Alimentação (Pai)
        // 22: Outros (Filha de Alimentação)
        // 21: Restaurante (Filha de Alimentação)
        // 30: Empréstimos e Financiamentos (Pai)
        // 31: Mercado Pago... (Filha de Empréstimos)
        // 10: Transporte (Pai)
        // 11: Combustível (Filha de Transporte)
        // 12: Outros (Filha de Transporte)
        expect(
          itemValues,
          equals([null, 40, 20, 22, 21, 30, 31, 10, 11, 12]),
          reason: 'Os itens devem estar agrupados por pai e ordenados alfabeticamente',
        );

        // Verifica que filhas exibem recuo visual de 20px
        // Encontra o item 11 (Combustível)
        final combustivelItem = items.firstWhere((i) => i.value == 11);
        final combustivelRow = combustivelItem.child as Row;
        // Deve conter SizedBox(width: 20) para recuo de 20px
        final has20pxIndent = combustivelRow.children.any(
          (c) => c is SizedBox && c.width == 20.0,
        );
        expect(has20pxIndent, isTrue, reason: 'Filhas devem ter recuo de 20px');

        // Verifica que filha exibe seu nome próprio sem poluir repetindo o nome do pai
        final expandedText = combustivelRow.children
            .whereType<Expanded>()
            .first;
        final textWidget = expandedText.child as Text;
        expect(textWidget.data, contains('COMBUSTÍVEL'));
        expect(
          textWidget.data,
          isNot(contains('TRANSPORTE > COMBUSTÍVEL')),
          reason: 'No menu em árvore, a filha não deve poluir repetindo o nome do pai',
        );
      },
    );

    testWidgets(
      'seleção de filhas homônimas grava ID correto e mantém distinção',
      (tester) async {
        int? selected;
        await tester.pumpWidget(
          buildTestWidget(onChanged: (id) => selected = id),
        );
        await tester.pumpAndSettle();

        // Abre o dropdown
        await tester.tap(find.byType(DropdownButtonFormField<int?>));
        await tester.pumpAndSettle();

        // Encontra os itens "OUTROS" (existem dois: id 22 e id 12)
        // Toca no primeiro "OUTROS" (Alimentação, id 22)
        await tester.tap(
          find
              .byWidgetPredicate(
                (w) => w is DropdownMenuItem<int?> && w.value == 22,
              )
              .last,
        );
        await tester.pumpAndSettle();

        expect(selected, equals(22));

        // Reabre o dropdown e seleciona o segundo "OUTROS" (Transporte, id 12)
        await tester.tap(find.byType(DropdownButtonFormField<int?>));
        await tester.pumpAndSettle();

        await tester.tap(
          find
              .byWidgetPredicate(
                (w) => w is DropdownMenuItem<int?> && w.value == 12,
              )
              .last,
        );
        await tester.pumpAndSettle();

        expect(selected, equals(12));
      },
    );

    testWidgets(
      'campo fechado com filha selecionada exibe nome da filha com destaque e pai como secundário',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(selectedId: 31));
        await tester.pumpAndSettle();

        // O DropdownButtonFormField deve usar selectedItemBuilder
        final dropdown = tester.widget<DropdownButton<int?>>(
          find.byType(DropdownButton<int?>),
        );
        expect(
          dropdown.selectedItemBuilder,
          isNotNull,
          reason: 'Deve usar selectedItemBuilder para formatar o campo fechado elegantemente',
        );

        // Deve conter o nome da filha em destaque
        expect(
          find.textContaining('MERCADO PAGO LINHA DE CRÉDITO'),
          findsOneWidget,
        );
        // E conter o nome do pai como informação contextual secundária
        expect(
          find.textContaining('EMPRÉSTIMOS E FINANCIAMENTOS'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'reabertura de formulário preserva seleção existente e opção sem categoria',
      (tester) async {
        // Com seleção de categoria pai
        await tester.pumpWidget(buildTestWidget(selectedId: 10));
        await tester.pumpAndSettle();

        final dropdown1 = tester.widget<DropdownButtonFormField<int?>>(
          find.byType(DropdownButtonFormField<int?>),
        );
        expect(dropdown1.initialValue, equals(10));

        // Sem categoria
        await tester.pumpWidget(buildTestWidget(selectedId: null));
        await tester.pumpAndSettle();

        final dropdown2 = tester.widget<DropdownButtonFormField<int?>>(
          find.byType(DropdownButtonFormField<int?>),
        );
        expect(dropdown2.initialValue, isNull);
        expect(find.text('Sem categoria'), findsOneWidget);
      },
    );
  });
}
