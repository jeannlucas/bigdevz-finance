import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';

class SpaceSummary {
  const SpaceSummary({
    required this.balance,
    required this.receivableRemaining,
    required this.receivedTotal,
    required this.accountsCount,
    required this.agreementsCount,
    required this.overdueInstallments,
    this.archivedAccountsCount = 0,
    this.payables = PayablesSummary.empty,
    this.categories = CategoriesSummary.empty,
  });

  factory SpaceSummary.fromJson(Map<String, dynamic> json) => SpaceSummary(
    balance: Money.parse(json['balance'] as String),
    receivableRemaining: Money.parse(json['receivable_remaining'] as String),
    receivedTotal: Money.parse(json['received_total'] as String),
    accountsCount: json['accounts_count'] as int,
    agreementsCount: json['agreements_count'] as int,
    overdueInstallments: json['overdue_installments'] as int,
    archivedAccountsCount: json['archived_accounts_count'] as int? ?? 0,
    payables: json['payables'] == null
        ? PayablesSummary.empty
        : PayablesSummary.fromJson(json['payables'] as Map<String, dynamic>),
    categories: json['categories_summary'] == null
        ? CategoriesSummary.empty
        : CategoriesSummary.fromJson(
            json['categories_summary'] as Map<String, dynamic>,
          ),
  );

  final Money balance;
  final Money receivableRemaining;
  final Money receivedTotal;
  final int accountsCount;
  final int agreementsCount;
  final int overdueInstallments;

  /// Contas arquivadas: o saldo delas continua em [balance].
  final int archivedAccountsCount;

  /// A pagar: previsto e realizado, separados do saldo.
  final PayablesSummary payables;

  /// Distribuição analítica por categoria (receitas e despesas).
  final CategoriesSummary categories;
}

class PayablesSummary {
  const PayablesSummary({
    required this.openTotal,
    required this.overdueTotal,
    required this.overdueCount,
    required this.dueNext30DaysTotal,
    required this.paidTotal,
    required this.awaitingAmountCount,
  });

  factory PayablesSummary.fromJson(Map<String, dynamic> json) =>
      PayablesSummary(
        openTotal: Money.parse(json['open_total'] as String),
        overdueTotal: Money.parse(json['overdue_total'] as String),
        overdueCount: json['overdue_count'] as int,
        dueNext30DaysTotal: Money.parse(
          json['due_next_30_days_total'] as String,
        ),
        paidTotal: Money.parse(json['paid_total'] as String),
        awaitingAmountCount: json['awaiting_amount_count'] as int,
      );

  static const empty = PayablesSummary(
    openTotal: Money(0),
    overdueTotal: Money(0),
    overdueCount: 0,
    dueNext30DaysTotal: Money(0),
    paidTotal: Money(0),
    awaitingAmountCount: 0,
  );

  final Money openTotal;
  final Money overdueTotal;
  final int overdueCount;
  final Money dueNext30DaysTotal;
  final Money paidTotal;
  final int awaitingAmountCount;
}

class SummaryRepository {
  const SummaryRepository(this._api);

  final ApiClient _api;

  Future<SpaceSummary> load(int spaceId) async => SpaceSummary.fromJson(
    (await _api.get('/spaces/$spaceId/summary'))['data']
        as Map<String, dynamic>,
  );
}

class CategorySummaryItem {
  const CategorySummaryItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.total,
    required this.totalCents,
  });

  factory CategorySummaryItem.fromJson(Map<String, dynamic> json) =>
      CategorySummaryItem(
        id: json['id'] as int,
        name: json['name'] as String,
        icon: json['icon'] as String? ?? 'category',
        color: json['color'] as String? ?? '#6B7280',
        total: Money.parse(json['total'] as String),
        totalCents: json['total_cents'] as int,
      );

  final int id;
  final String name;
  final String icon;
  final String color;
  final Money total;
  final int totalCents;

  Color get colorValue {
    try {
      final hex = color.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } catch (_) {}
    return const Color(0xFF6B7280);
  }
}

class CategoriesSummary {
  const CategoriesSummary({this.expenses = const [], this.incomes = const []});

  factory CategoriesSummary.fromJson(Map<String, dynamic> json) =>
      CategoriesSummary(
        expenses: (json['expenses'] as List? ?? const [])
            .map(
              (item) =>
                  CategorySummaryItem.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        incomes: (json['incomes'] as List? ?? const [])
            .map(
              (item) =>
                  CategorySummaryItem.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );

  static const empty = CategoriesSummary();

  final List<CategorySummaryItem> expenses;
  final List<CategorySummaryItem> incomes;
}
