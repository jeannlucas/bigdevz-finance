import '../../core/money.dart';

enum StatementDirection {
  credit,
  debit;

  bool get isCredit => this == StatementDirection.credit;
  bool get isDebit => this == StatementDirection.debit;
}

class StatementEntry {
  const StatementEntry({
    required this.id,
    required this.accountId,
    required this.accountName,
    required this.effectiveDate,
    required this.amount,
    required this.rawAmountCents,
    required this.direction,
    required this.type,
    required this.description,
    this.createdAt,
  });

  factory StatementEntry.fromJson(Map<String, dynamic> json) => StatementEntry(
    id: json['id'] as int,
    accountId: json['account_id'] as int,
    accountName: (json['account_name'] as String?) ?? 'Conta',
    effectiveDate: json['effective_date'] as String,
    amount: Money.parse(json['amount'] as String),
    rawAmountCents: json['raw_amount_cents'] as int,
    direction: json['direction'] == 'credit'
        ? StatementDirection.credit
        : StatementDirection.debit,
    type: (json['type'] as String?) ?? 'movement',
    description: (json['description'] as String?) ?? 'Movimentação',
    createdAt: json['created_at'] as String?,
  );

  final int id;
  final int accountId;
  final String accountName;
  final String effectiveDate;
  final Money amount;
  final int rawAmountCents;
  final StatementDirection direction;
  final String type;
  final String description;
  final String? createdAt;
}
