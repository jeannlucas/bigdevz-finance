import '../../core/money.dart';

class CashFlowSummary {
  const CashFlowSummary({
    required this.realizedInflow,
    required this.realizedOutflow,
    required this.projectedInflow,
    required this.projectedOutflow,
    required this.finalProjectedBalance,
  });

  factory CashFlowSummary.fromJson(Map<String, dynamic> json) =>
      CashFlowSummary(
        realizedInflow: Money(json['realized_inflow_cents'] as int? ?? 0),
        realizedOutflow: Money(json['realized_outflow_cents'] as int? ?? 0),
        projectedInflow: Money(json['projected_inflow_cents'] as int? ?? 0),
        projectedOutflow: Money(json['projected_outflow_cents'] as int? ?? 0),
        finalProjectedBalance: Money(
          json['final_projected_balance_cents'] as int? ?? 0,
        ),
      );

  final Money realizedInflow;
  final Money realizedOutflow;
  final Money projectedInflow;
  final Money projectedOutflow;
  final Money finalProjectedBalance;
}

class CashFlowDaily {
  const CashFlowDaily({
    required this.date,
    required this.realizedInflow,
    required this.realizedOutflow,
    required this.projectedInflow,
    required this.projectedOutflow,
    required this.projectedBalance,
    required this.itemsCount,
  });

  factory CashFlowDaily.fromJson(Map<String, dynamic> json) => CashFlowDaily(
    date: json['date'] as String,
    realizedInflow: Money(json['realized_inflow_cents'] as int? ?? 0),
    realizedOutflow: Money(json['realized_outflow_cents'] as int? ?? 0),
    projectedInflow: Money(json['projected_inflow_cents'] as int? ?? 0),
    projectedOutflow: Money(json['projected_outflow_cents'] as int? ?? 0),
    projectedBalance: Money(json['projected_balance_cents'] as int? ?? 0),
    itemsCount: json['items_count'] as int? ?? 0,
  );

  final String date;
  final Money realizedInflow;
  final Money realizedOutflow;
  final Money projectedInflow;
  final Money projectedOutflow;
  final Money projectedBalance;
  final int itemsCount;
}

class CashFlowResponse {
  const CashFlowResponse({
    required this.initialBalance,
    required this.periodDays,
    required this.view,
    required this.startDate,
    required this.endDate,
    required this.summary,
    required this.daily,
  });

  factory CashFlowResponse.fromJson(Map<String, dynamic> json) {
    final dailyList = (json['daily'] as List? ?? const [])
        .map((e) => CashFlowDaily.fromJson(e as Map<String, dynamic>))
        .toList();

    return CashFlowResponse(
      initialBalance: Money(json['initial_balance_cents'] as int? ?? 0),
      periodDays: json['period_days'] as int? ?? 30,
      view: json['view'] as String? ?? 'cash',
      startDate: json['start_date'] as String? ?? '',
      endDate: json['end_date'] as String? ?? '',
      summary: CashFlowSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const {},
      ),
      daily: dailyList,
    );
  }

  final Money initialBalance;
  final int periodDays;
  final String view;
  final String startDate;
  final String endDate;
  final CashFlowSummary summary;
  final List<CashFlowDaily> daily;
}
