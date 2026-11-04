import '../../core/money.dart';

class Loan {
  const Loan({
    required this.id,
    required this.spaceId,
    required this.kind,
    required this.title,
    required this.counterparty,
    required this.principal,
    required this.total,
    required this.interest,
    required this.paidOrReceived,
    required this.remaining,
    required this.installmentCount,
    required this.firstDueDate,
    this.disbursementAccountId,
    this.disbursedAt,
    required this.status,
    this.notes,
    this.installments = const [],
  });

  factory Loan.fromJson(Map<String, dynamic> json) => Loan(
    id: json['id'] as int,
    spaceId: json['space_id'] as int,
    kind: json['kind'] as String,
    title: json['title'] as String,
    counterparty: json['counterparty'] as String,
    principal: Money.parse(json['principal'] as String),
    total: Money.parse(json['total'] as String),
    interest: Money.parse(json['interest'] as String),
    paidOrReceived: Money.parse(json['paid_or_received'] as String),
    remaining: Money.parse(json['remaining'] as String),
    installmentCount: json['installment_count'] as int,
    firstDueDate: json['first_due_date'] as String,
    disbursementAccountId: json['disbursement_account_id'] as int?,
    disbursedAt: json['disbursed_at'] as String?,
    status: json['status'] as String,
    notes: json['notes'] as String?,
    installments: (json['installments'] as List? ?? const [])
        .map((item) => LoanInstallment.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  final int id;
  final int spaceId;
  final String kind;
  final String title;
  final String counterparty;
  final Money principal;
  final Money total;
  final Money interest;
  final Money paidOrReceived;
  final Money remaining;
  final int installmentCount;
  final String firstDueDate;
  final int? disbursementAccountId;
  final String? disbursedAt;
  final String status;
  final String? notes;
  final List<LoanInstallment> installments;

  bool get isTaken => kind == 'taken';
  bool get isGranted => kind == 'granted';
  bool get isSettled => status == 'settled';

  double get progress {
    if (total.cents == 0) return 0;
    final ratio = paidOrReceived.cents / total.cents;
    return ratio.clamp(0.0, 1.0);
  }
}

class LoanInstallment {
  const LoanInstallment({
    required this.number,
    required this.amount,
    required this.settled,
    required this.dueDate,
    required this.status,
  });

  factory LoanInstallment.fromJson(Map<String, dynamic> json) =>
      LoanInstallment(
        number: json['number'] as int,
        amount: Money.parse(json['amount'] as String),
        settled: Money.parse(json['settled'] as String),
        dueDate: json['due_date'] as String,
        status: json['status'] as String,
      );

  final int number;
  final Money amount;
  final Money settled;
  final String dueDate;
  final String status;

  bool get isPaid => status == 'paid';
}
