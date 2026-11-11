import 'package:flutter_test/flutter_test.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/categories/category.dart';
import 'package:bigdevz_finance/ui/widgets.dart';
import 'package:bigdevz_finance/ui/financial/financial_item_view.dart';
import 'package:bigdevz_finance/ui/financial/financial_search_bar.dart';

void main() {
  group('filterAndSortFinancialItems', () {
    final catInfra = const Category(
      id: 10,
      spaceId: 1,
      name: 'Infra',
      type: 'expense',
      icon: 'folder',
      color: '#FF0000',
    );
    final catConsultoria = const Category(
      id: 20,
      spaceId: 1,
      name: 'Consultoria',
      type: 'expense',
      icon: 'folder',
      color: '#00FF00',
    );

    final item1 = TestItem(
      id: 1,
      title: 'Aluguel do Escritório',
      counterparty: 'Imobiliária Central',
      dueDate: '2026-03-05',
      pendingAmount: const Money(250000), // R$ 2.500,00
      category: catInfra,
    );

    final item2 = TestItem(
      id: 2,
      title: 'Conta de Luz',
      counterparty: 'Enel Energia',
      dueDate: '2026-03-12',
      pendingAmount: const Money(34050), // R$ 340,50
      category: catInfra,
    );

    final item3 = TestItem(
      id: 3,
      title: 'Consultoria Financeira',
      counterparty: 'João Silva ME',
      dueDate: '2026-03-01',
      pendingAmount: const Money(120000), // R$ 1.200,00
      category: catConsultoria,
    );

    final allItems = [item1, item2, item3];

    test('busca textual case-insensitive e normalizada por título', () {
      final res = filterAndSortFinancialItems(allItems, query: '   aluguel   ');
      expect(res.length, 1);
      expect(res.first.id, 1);
    });

    test('busca textual case-insensitive por fornecedor/pessoa', () {
      final res = filterAndSortFinancialItems(allItems, query: 'enel');
      expect(res.length, 1);
      expect(res.first.id, 2);
    });

    test('busca sem resultados retorna lista vazia', () {
      final res = filterAndSortFinancialItems(
        allItems,
        query: 'fornecedor inexistente',
      );
      expect(res, isEmpty);
    });

    test('ordenação por vencimento crescente (padrão)', () {
      final res = filterAndSortFinancialItems(
        allItems,
        sort: FinancialSortOption.dueDateAsc,
      );
      expect(res.map((i) => i.id).toList(), [3, 1, 2]); // 01/03, 05/03, 12/03
    });

    test('ordenação por vencimento decrescente', () {
      final res = filterAndSortFinancialItems(
        allItems,
        sort: FinancialSortOption.dueDateDesc,
      );
      expect(res.map((i) => i.id).toList(), [2, 1, 3]); // 12/03, 05/03, 01/03
    });

    test('ordenação por maior valor (amountDesc)', () {
      final res = filterAndSortFinancialItems(
        allItems,
        sort: FinancialSortOption.amountDesc,
      );
      expect(res.map((i) => i.id).toList(), [1, 3, 2]); // 2.500, 1.200, 340,50
    });

    test('ordenação por menor valor (amountAsc)', () {
      final res = filterAndSortFinancialItems(
        allItems,
        sort: FinancialSortOption.amountAsc,
      );
      expect(res.map((i) => i.id).toList(), [2, 3, 1]); // 340,50, 1.200, 2.500
    });

    test('ordenação por descrição A-Z', () {
      final res = filterAndSortFinancialItems(
        allItems,
        sort: FinancialSortOption.titleAsc,
      );
      expect(res.map((i) => i.id).toList(), [
        1,
        3,
        2,
      ]); // Aluguel, Consultoria, Conta
    });

    test(
      'filtro por período (matchesPeriod) identifica hoje, vencidas e futuros',
      () {
        final refDate = DateTime(2026, 3, 10); // Terça-feira, 10/03/2026
        expect(
          matchesPeriod('2026-03-05', FinancialPeriodFilter.overdue, refDate),
          isTrue,
        );
        expect(
          matchesPeriod('2026-03-10', FinancialPeriodFilter.today, refDate),
          isTrue,
        );
        expect(
          matchesPeriod('2026-03-12', FinancialPeriodFilter.next7Days, refDate),
          isTrue,
        );
        expect(
          matchesPeriod('2026-03-25', FinancialPeriodFilter.thisMonth, refDate),
          isTrue,
        );
        expect(
          matchesPeriod(
            '2026-03-31',
            FinancialPeriodFilter.next30Days,
            refDate,
          ),
          isTrue,
        );
        expect(
          matchesPeriod('2026-04-15', FinancialPeriodFilter.future, refDate),
          isTrue,
        );
      },
    );

    test('combinação unificada: busca + período + categoria + ordenação', () {
      final refDate = DateTime(2026, 3, 10);
      // Busca 'Conta' + categoria Infra (10) + período thisMonth
      final res = filterAndSortFinancialItems(
        allItems,
        query: 'Conta',
        categoryId: 10,
        period: FinancialPeriodFilter.thisMonth,
        sort: FinancialSortOption.amountAsc,
        now: refDate,
      );
      expect(res.length, 1);
      expect(res.first.id, 2); // Conta de Luz
    });

    test('combinação unificada: período incompatível exclui itens', () {
      final refDate = DateTime(2026, 3, 10);
      // Item 2 vence em 12/03 (futuro). Filtrando por vencidas deve retornar vazio.
      final res = filterAndSortFinancialItems(
        [item2],
        period: FinancialPeriodFilter.overdue,
        now: refDate,
      );
      expect(res, isEmpty);
    });

    test('normalização da busca: agua encontra Água', () {
      final itemAgua = TestItem(
        id: 10,
        title: 'Conta de Água e Saneamento',
        dueDate: '2026-03-10',
      );
      final res = filterAndSortFinancialItems([itemAgua], query: 'agua');
      expect(res.length, 1);
      expect(res.first.id, 10);
    });

    test('normalização da busca: JOAO encontra João', () {
      final itemJoao = TestItem(
        id: 11,
        title: 'Serviço Prestado',
        counterparty: 'João da Silva ME',
        dueDate: '2026-03-10',
      );
      final res = filterAndSortFinancialItems([itemJoao], query: 'JOAO');
      expect(res.length, 1);
      expect(res.first.id, 11);
    });

    test('normalização da busca: espaços excedentes "  mercado  " encontra Mercado', () {
      final itemMercado = TestItem(
        id: 12,
        title: 'Supermercado Central',
        dueDate: '2026-03-10',
      );
      final res = filterAndSortFinancialItems([
        itemMercado,
      ], query: '  mercado  ');
      expect(res.length, 1);
      expect(res.first.id, 12);
    });

    test('busca funciona tanto por título quanto por fornecedor/cliente com acentos', () {
      final item = TestItem(
        id: 13,
        title: 'Licença de Software Gestão',
        counterparty: 'Antônio Ferreira',
        dueDate: '2026-03-10',
      );
      // Busca pelo título sem acento
      expect(filterAndSortFinancialItems([item], query: 'gestao').length, 1);
      // Busca pelo favorecido sem acento e com maiúsculas
      expect(filterAndSortFinancialItems([item], query: 'ANTONIO').length, 1);
      // Busca por palavras separadas título + favorecido
      expect(
        filterAndSortFinancialItems([item], query: 'software antonio').length,
        1,
      );
    });

    test(
      'filtro de categoria isola itens corretamente via categoryId ou Category',
      () {
        final itemCat1 = TestItem(
          id: 14,
          title: 'Despesa A',
          dueDate: '2026-03-10',
          categoryId: 10,
        );
        final itemCat2 = TestItem(
          id: 15,
          title: 'Despesa B',
          dueDate: '2026-03-10',
          categoryId: 20,
        );

        final res10 = filterAndSortFinancialItems([
          itemCat1,
          itemCat2,
        ], categoryId: 10);
        expect(res10.length, 1);
        expect(res10.first.id, 14);

        final res20 = filterAndSortFinancialItems([
          itemCat1,
          itemCat2,
        ], categoryId: 20);
        expect(res20.length, 1);
        expect(res20.first.id, 15);

        final resAll = filterAndSortFinancialItems([itemCat1, itemCat2]);
        expect(resAll.length, 2);
      },
    );
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
    this.categoryId,
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
  final int? categoryId;
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
  final Money? paidAmount = null;
  @override
  final bool isPartial = false;
  @override
  final String? amountLabel = null;
}
