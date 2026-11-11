import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../widgets.dart' show StatusTone;

/// Grupos temporais padronizados para visualização financeira.
enum FinancialDueDateGroup {
  overdue('Vencidas', Icons.warning_amber_rounded, Color(0xFFE53935)),
  today('Hoje', Icons.today_rounded, Color(0xFFF57C00)),
  next7Days(
    'Próximos 7 dias',
    Icons.calendar_view_week_rounded,
    Color(0xFF1E88E5),
  ),
  thisMonth('Este mês', Icons.calendar_month_rounded, Color(0xFF43A047)),
  future('Futuras', Icons.update_rounded, Color(0xFF757575)),
  settled('Concluídas', Icons.task_alt_rounded, Color(0xFF546E7A));

  const FinancialDueDateGroup(this.label, this.icon, this.accentColor);

  final String label;
  final IconData icon;
  final Color accentColor;
}

/// Contrato mínimo de apresentação compartilhada entre Contas a Pagar e a Receber.
/// Não acopla os domínios e expõe apenas campos necessários para ordenação, busca,
/// agrupamento e renderização de tabelas e cards.
abstract class FinancialItemView {
  int get id;
  String get title;
  String? get counterparty;
  String get dueDate;
  Object? get category;
  String get kindLabel;
  String get statusLabel;
  StatusTone get statusTone;
  Money? get pendingAmount;
  Money? get totalAmount;
  bool get isOverdue;
  bool get isAwaitingAmount;
  bool get isSettled;
  bool get isEligibleForBatch;
  int? get categoryId => null;
  Money? get paidAmount => null;
  bool get isPartial => false;
  String? get amountLabel => null;
}

/// Resumo com contagem e total monetário exato de um grupo temporal.
class FinancialGroupSummary<T extends FinancialItemView> {
  const FinancialGroupSummary({
    required this.group,
    required this.items,
    required this.total,
  });

  final FinancialDueDateGroup group;
  final List<T> items;
  final Money total;

  int get count => items.length;
}

/// Classifica uma data de vencimento (YYYY-MM-DD) no grupo temporal correspondente.
/// Cálculo estritamente sem float/double.
FinancialDueDateGroup classifyDueDate(
  String dueDateStr, {
  DateTime? refDate,
  bool isSettled = false,
}) {
  if (isSettled) {
    return FinancialDueDateGroup.settled;
  }

  final now = refDate ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dueRaw = parseApiDate(dueDateStr);
  final due = DateTime(dueRaw.year, dueRaw.month, dueRaw.day);

  if (due.isBefore(today)) {
    return FinancialDueDateGroup.overdue;
  }

  if (due.isAtSameMomentAs(today)) {
    return FinancialDueDateGroup.today;
  }

  // Próximos 7 dias (inclusive)
  final in7Days = today.add(const Duration(days: 7));
  if (!due.isAfter(in7Days)) {
    return FinancialDueDateGroup.next7Days;
  }

  // Último dia do mês corrente
  final endOfMonth = DateTime(today.year, today.month + 1, 0);
  if (!due.isAfter(endOfMonth)) {
    return FinancialDueDateGroup.thisMonth;
  }

  return FinancialDueDateGroup.future;
}

/// Agrupa itens financeiros em grupos temporais ordenados e soma valores exatos.
Map<FinancialDueDateGroup, FinancialGroupSummary<T>> groupFinancialItems<
  T extends FinancialItemView
>(List<T> items, {DateTime? refDate}) {
  final Map<FinancialDueDateGroup, List<T>> buckets = {
    for (final group in FinancialDueDateGroup.values) group: <T>[],
  };

  for (final item in items) {
    final group = classifyDueDate(
      item.dueDate,
      refDate: refDate,
      isSettled: item.isSettled,
    );
    buckets[group]!.add(item);
  }

  final Map<FinancialDueDateGroup, FinancialGroupSummary<T>> result = {};
  for (final group in FinancialDueDateGroup.values) {
    final groupItems = buckets[group]!;
    int totalCents = 0;
    for (final it in groupItems) {
      if (it.pendingAmount != null) {
        totalCents += it.pendingAmount!.cents;
      }
    }
    result[group] = FinancialGroupSummary<T>(
      group: group,
      items: groupItems,
      total: Money(totalCents),
    );
  }

  return result;
}
