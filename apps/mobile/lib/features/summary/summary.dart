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
  });

  factory SpaceSummary.fromJson(Map<String, dynamic> json) => SpaceSummary(
        balance: Money.parse(json['balance'] as String),
        receivableRemaining: Money.parse(json['receivable_remaining'] as String),
        receivedTotal: Money.parse(json['received_total'] as String),
        accountsCount: json['accounts_count'] as int,
        agreementsCount: json['agreements_count'] as int,
        overdueInstallments: json['overdue_installments'] as int,
      );

  final Money balance;
  final Money receivableRemaining;
  final Money receivedTotal;
  final int accountsCount;
  final int agreementsCount;
  final int overdueInstallments;
}

class SummaryRepository {
  const SummaryRepository(this._api);

  final ApiClient _api;

  Future<SpaceSummary> load(int spaceId) async =>
      SpaceSummary.fromJson((await _api.get('/spaces/$spaceId/summary'))['data'] as Map<String, dynamic>);
}
