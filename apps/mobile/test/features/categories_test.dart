import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/categories/categories_repository.dart';
import 'package:bigdevz_finance/features/categories/category.dart';
import 'package:bigdevz_finance/features/categories/category_badge.dart';
import 'package:bigdevz_finance/features/categories/category_picker_field.dart';
import 'package:bigdevz_finance/features/summary/dashboard_charts.dart';
import 'package:bigdevz_finance/features/summary/summary.dart';
import 'package:provider/provider.dart';

void main() {
  group('Category Model', () {
    test('parses json correctly and handles color / icon fallback', () {
      final json = {
        'id': 10,
        'space_id': 1,
        'name': 'Alimentação',
        'type': 'expense',
        'icon': 'restaurant',
        'color': '#E57373',
        'is_default': true,
      };

      final cat = Category.fromJson(json);
      expect(cat.id, 10);
      expect(cat.spaceId, 1);
      expect(cat.name, 'Alimentação');
      expect(cat.type, 'expense');
      expect(cat.isExpense, isTrue);
      expect(cat.isIncome, isFalse);
      expect(cat.icon, 'restaurant');
      expect(cat.color, '#E57373');
      expect(cat.isDefault, isTrue);
      expect(cat.iconData, Icons.restaurant_rounded);
      expect(cat.colorValue, const Color(0xFFE57373));

      final serialized = cat.toJson();
      expect(serialized['id'], 10);
      expect(serialized['name'], 'Alimentação');
    });

    test('handles fallback colors and icons', () {
      final fallbackCat = Category.fromJson({
        'id': 20,
        'name': 'Outros',
        'type': 'income',
      });

      expect(fallbackCat.isIncome, isTrue);
      expect(fallbackCat.iconData, Icons.category_rounded);
      expect(fallbackCat.colorValue, isA<Color>());
    });
  });

  group('CategoriesRepository', () {
    test('list fetches categories for space and filters by type', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/spaces/1/categories');
        expect(request.url.queryParameters['type'], 'expense');
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 1,
                'space_id': 1,
                'name': 'Moradia',
                'type': 'expense',
                'icon': 'home',
                'color': '#1E5BB8',
                'is_default': true,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(baseUrl: 'http://test', client: client);
      final repo = CategoriesRepository(api);

      final list = await repo.list(1, type: 'expense');
      expect(list.length, 1);
      expect(list.first.name, 'Moradia');
      expect(list.first.icon, 'home');
    });

    test('create sends payload and returns new category', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/spaces/1/categories');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], 'Freelance');
        expect(body['type'], 'income');
        return http.Response(
          jsonEncode({
            'data': {
              'id': 50,
              'space_id': 1,
              'name': 'Freelance',
              'type': 'income',
              'icon': 'work',
              'color': '#0F8A5F',
              'is_default': false,
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(baseUrl: 'http://test', client: client);
      final repo = CategoriesRepository(api);

      final created = await repo.create(
        1,
        name: 'Freelance',
        type: 'income',
        icon: 'work',
        color: '#0F8A5F',
      );
      expect(created.id, 50);
      expect(created.name, 'Freelance');
    });

    test('delete calls DELETE endpoint', () async {
      final client = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/spaces/1/categories/50');
        return http.Response(jsonEncode({'message': 'Ok'}), 200);
      });

      final api = ApiClient(baseUrl: 'http://test', client: client);
      final repo = CategoriesRepository(api);

      await expectLater(repo.delete(1, 50), completes);
    });
  });

  group('Category Widgets', () {
    testWidgets('CategoryBadge renders category name and icon', (tester) async {
      const cat = Category(
        id: 1,
        spaceId: 1,
        name: 'Transporte',
        type: 'expense',
        icon: 'directions_car',
        color: '#D97706',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CategoryBadge(category: cat)),
        ),
      );

      expect(find.text('Transporte'), findsOneWidget);
      expect(find.byIcon(Icons.directions_car_rounded), findsOneWidget);
    });

    testWidgets('CategoryBadge renders in compact mode', (tester) async {
      const cat = Category(
        id: 2,
        spaceId: 1,
        name: 'Salário',
        type: 'income',
        icon: 'work',
        color: '#0F8A5F',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CategoryBadge(category: cat, compact: true)),
        ),
      );

      expect(find.text('Salário'), findsOneWidget);
      expect(find.byIcon(Icons.work_rounded), findsOneWidget);
    });

    testWidgets('CategoryPickerField loads and displays categories', (
      tester,
    ) async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 101,
                'space_id': 1,
                'name': 'Alimentação',
                'type': 'expense',
                'icon': 'restaurant',
                'color': '#E57373',
                'is_default': true,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(baseUrl: 'http://test', client: client);
      final repo = CategoriesRepository(api);

      int? selectedId;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Provider<CategoriesRepository>.value(
              value: repo,
              child: CategoryPickerField(
                spaceId: 1,
                type: 'expense',
                selectedCategoryId: selectedId,
                onChanged: (id) => selectedId = id,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Categoria (opcional)'), findsOneWidget);
      expect(find.text('Sem categoria'), findsOneWidget);
    });

    testWidgets('CategoryDistributionDonutCard renders and toggles types', (
      tester,
    ) async {
      const summary = CategoriesSummary(
        expenses: [
          CategorySummaryItem(
            id: 1,
            name: 'Moradia',
            icon: 'home',
            color: '#1E5BB8',
            total: Money(150000),
            totalCents: 150000,
          ),
          CategorySummaryItem(
            id: 2,
            name: 'Alimentação',
            icon: 'restaurant',
            color: '#E57373',
            total: Money(80000),
            totalCents: 80000,
          ),
        ],
        incomes: [
          CategorySummaryItem(
            id: 3,
            name: 'Salário',
            icon: 'work',
            color: '#0F8A5F',
            total: Money(500000),
            totalCents: 500000,
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CategoryDistributionDonutCard(
                categories: summary,
                obscure: false,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Distribuição por Categoria'), findsOneWidget);
      expect(find.text('Moradia'), findsOneWidget);
      expect(find.text('Alimentação'), findsOneWidget);
      expect(find.text('R\$ 1.500,00'), findsOneWidget);

      // Alterna para Receitas
      await tester.tap(find.text('Receitas'));
      await tester.pumpAndSettle();

      expect(find.text('Salário'), findsOneWidget);
      expect(find.text('R\$ 5.000,00'), findsOneWidget);
    });
  });
}
