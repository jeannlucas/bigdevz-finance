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
