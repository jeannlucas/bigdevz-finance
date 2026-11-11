import 'package:flutter_test/flutter_test.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/ui/widgets.dart';
import 'package:bigdevz_finance/ui/financial/financial_item_view.dart';

void main() {
  group('FinancialDueDateGroup e classifyDueDate', () {
    final refDate = DateTime(2026, 3, 10); // 10 de Março de 2026 (terça-feira)

    test('classifica vencidas com vencimento anterior a hoje', () {
      expect(
        classifyDueDate('2026-03-09', refDate: refDate),
        FinancialDueDateGroup.overdue,
      );
      expect(
        classifyDueDate('2026-02-28', refDate: refDate),
        FinancialDueDateGroup.overdue,
      );
      expect(
        classifyDueDate('2025-12-31', refDate: refDate),
        FinancialDueDateGroup.overdue,
      );
    });

    test('classifica hoje quando vencimento é exatamente igual a hoje', () {
      expect(
        classifyDueDate('2026-03-10', refDate: refDate),
        FinancialDueDateGroup.today,
      );
    });

    test('classifica próximos 7 dias (hoje + 1 até hoje + 7 dias)', () {
      // 10 + 1 = 11 até 10 + 7 = 17 de março
      expect(
        classifyDueDate('2026-03-11', refDate: refDate),
        FinancialDueDateGroup.next7Days,
      );
      expect(
        classifyDueDate('2026-03-17', refDate: refDate),
        FinancialDueDateGroup.next7Days,
      );
    });

    test(
      'classifica este mês (após 7 dias e até o último dia do mês corrente)',
      () {
        // 18 de março até 31 de março
        expect(
          classifyDueDate('2026-03-18', refDate: refDate),
          FinancialDueDateGroup.thisMonth,
        );
        expect(
          classifyDueDate('2026-03-31', refDate: refDate),
          FinancialDueDateGroup.thisMonth,
        );
      },
    );

    test('classifica futuras (após o fim do mês corrente)', () {
      expect(
        classifyDueDate('2026-04-01', refDate: refDate),
        FinancialDueDateGroup.future,
      );
      expect(
        classifyDueDate('2026-12-31', refDate: refDate),
        FinancialDueDateGroup.future,
      );
      expect(
        classifyDueDate('2027-01-15', refDate: refDate),
        FinancialDueDateGroup.future,
      );
    });

    test('classifica como concluída/histórico quando isSettled é true independente da data', () {
      expect(
        classifyDueDate('2026-03-05', refDate: refDate, isSettled: true),
        FinancialDueDateGroup.settled,
      );
      expect(
        classifyDueDate('2026-03-10', refDate: refDate, isSettled: true),
        FinancialDueDateGroup.settled,
      );
      expect(
        classifyDueDate('2026-04-20', refDate: refDate, isSettled: true),
        FinancialDueDateGroup.settled,
      );
    });

    test('respeita ano bissexto (29 de fevereiro de 2028)', () {
      final leapYearDate = DateTime(2028, 2, 20);
      // Próximos 7 dias: 21 a 27 de fevereiro
      expect(
        classifyDueDate('2028-02-25', refDate: leapYearDate),
        FinancialDueDateGroup.next7Days,
      );
      // Este mês: 28 e 29 de fevereiro
      expect(
        classifyDueDate('2028-02-28', refDate: leapYearDate),
        FinancialDueDateGroup.thisMonth,
      );
      expect(
        classifyDueDate('2028-02-29', refDate: leapYearDate),
        FinancialDueDateGroup.thisMonth,
      );
      // Futuras: 1 de março em diante
      expect(
        classifyDueDate('2028-03-01', refDate: leapYearDate),
        FinancialDueDateGroup.future,
      );
    });

    test('respeita virada de ano (31 de dezembro)', () {
      final endOfYearDate = DateTime(2026, 12, 28);
      // Hoje: 28/12.
      // Próximos 7 dias vai até 04/01/2027, porém "este mês" é até 31/12/2026.
      // 29, 30, 31 de dezembro estão dentro dos próximos 7 dias.
      expect(
        classifyDueDate('2026-12-31', refDate: endOfYearDate),
        FinancialDueDateGroup.next7Days,
      );
      // 01/01/2027 também está nos próximos 7 dias (28/12 + 7 = 04/01/2027)
      expect(
        classifyDueDate('2027-01-02', refDate: endOfYearDate),
        FinancialDueDateGroup.next7Days,
      );
      // 10/01/2027 é futura (> 7 dias e > fim do mês de dezembro)
      expect(
        classifyDueDate('2027-01-10', refDate: endOfYearDate),
        FinancialDueDateGroup.future,
      );
    });
  });

  group('FinancialDueDateGrouper e agrupamento de itens', () {
    final refDate = DateTime(2026, 3, 10);

    test('calcula contagem e soma exata de Money sem float', () {
      final items = [
        TestFinancialItem(
          id: 1,
          title: 'Aluguel',
          dueDate: '2026-03-05',
          pendingAmount: const Money(150050), // 1.500,50
          isSettled: false,
        ),
        TestFinancialItem(
          id: 2,
          title: 'Energia',
          dueDate: '2026-03-08',
          pendingAmount: const Money(32025), // 320,25
          isSettled: false,
        ),
        TestFinancialItem(
          id: 3,
          title: 'Internet',
          dueDate: '2026-03-10',
          pendingAmount: const Money(12000), // 120,00
          isSettled: false,
        ),
      ];

      final grouped = groupFinancialItems(items, refDate: refDate);

      // Vencidas: 2 itens (Aluguel + Energia) = 1.820,75
      final overdueGroup = grouped[FinancialDueDateGroup.overdue]!;
      expect(overdueGroup.items.length, 2);
      expect(overdueGroup.total.cents, 182075);
      expect(overdueGroup.total.brl, 'R\$ 1.820,75');

      // Hoje: 1 item (Internet) = 120,00
      final todayGroup = grouped[FinancialDueDateGroup.today]!;
      expect(todayGroup.items.length, 1);
      expect(todayGroup.total.cents, 12000);
      expect(todayGroup.total.brl, 'R\$ 120,00');

      // Próximos 7 dias: vazio
      expect(grouped[FinancialDueDateGroup.next7Days]!.items, isEmpty);
      expect(grouped[FinancialDueDateGroup.next7Days]!.total.cents, 0);
    });
  });
}

class TestFinancialItem implements FinancialItemView {
  TestFinancialItem({
    required this.id,
    required this.title,
    required this.dueDate,
    this.pendingAmount,
    this.totalAmount,
    this.counterparty,
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
