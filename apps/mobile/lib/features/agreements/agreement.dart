import '../../core/money.dart';

class Agreement {
  const Agreement({
    required this.id,
    required this.description,
    required this.total,
    required this.installmentCount,
    required this.received,
    required this.remaining,
    required this.paidInstallments,
    required this.overdueInstallments,
    required this.nextDueDate,
    required this.installments,
  });

  factory Agreement.fromJson(Map<String, dynamic> json) => Agreement(
    id: json['id'] as int,
    description: json['description'] as String,
    total: Money.parse(json['total'] as String),
    installmentCount: json['installment_count'] as int,
    received: Money.parse(json['received'] as String),
    remaining: Money.parse(json['remaining'] as String),
    paidInstallments: json['paid_installments'] as int,
    overdueInstallments: json['overdue_installments'] as int,
    nextDueDate: json['next_due_date'] as String?,
    installments: (json['installments'] as List? ?? const [])
        .map((item) => Installment.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  final int id;
  final String description;
  final Money total;
  final int installmentCount;
  final Money received;
  final Money remaining;
  final int paidInstallments;
  final int overdueInstallments;
  final String? nextDueDate;
  final List<Installment> installments;
}

enum InstallmentStatus {
  pending('Pendente'),
  partial('Parcial'),
  paid('Quitada');

  const InstallmentStatus(this.label);

  final String label;

  static InstallmentStatus parse(String value) => switch (value) {
    'paid' => paid,
    'partial' => partial,
    _ => pending,
  };
}

class Installment {
  const Installment({
    required this.id,
    required this.agreementId,
    required this.number,
    required this.dueDate,
    required this.amount,
    required this.received,
    required this.remaining,
    required this.status,
    required this.overdue,
    this.agreementDescription,
    this.installmentCount,
    this.receipts = const [],
  });

  factory Installment.fromJson(Map<String, dynamic> json) {
    final agreement = json['agreement'] as Map<String, dynamic>?;
    return Installment(
      id: json['id'] as int,
      agreementId: json['agreement_id'] as int,
      number: json['number'] as int,
      dueDate: json['due_date'] as String,
      amount: Money.parse(json['amount'] as String),
      received: Money.parse(json['received'] as String),
      remaining: Money.parse(json['remaining'] as String),
      status: InstallmentStatus.parse(json['status'] as String),
      overdue: json['overdue'] as bool,
      agreementDescription: agreement?['description'] as String?,
      installmentCount: agreement?['installment_count'] as int?,
      receipts: (json['receipts'] as List? ?? const [])
          .map((item) => Receipt.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final int id;
  final int agreementId;
  final int number;
  final String dueDate;
  final Money amount;
  final Money received;
  final Money remaining;
  final InstallmentStatus status;
  final bool overdue;
  final String? agreementDescription;
  final int? installmentCount;
  final List<Receipt> receipts;
}

class Receipt {
  const Receipt({
    required this.id,
    required this.accountId,
    required this.amount,
    required this.receivedOn,
    this.reversal,
    this.replacesReceiptId,
  });

  factory Receipt.fromJson(Map<String, dynamic> json) => Receipt(
    id: json['id'] as int,
    accountId: json['account_id'] as int,
    amount: Money.parse(json['amount'] as String),
    receivedOn: json['received_on'] as String,
    reversal: json['reversal'] == null
        ? null
        : ReceiptReversal.fromJson(json['reversal'] as Map<String, dynamic>),
    replacesReceiptId: json['replaces_receipt_id'] as int?,
  );

  final int id;
  final int accountId;
  final Money amount;
  final String receivedOn;

  /// Estorno deste recebimento; o original continua no histórico.
  final ReceiptReversal? reversal;

  /// Recebimento que este substituiu numa correção.
  final int? replacesReceiptId;

  bool get isReversed => reversal != null;
}

/// Estorno (sem substituto) ou correção (com substituto) de um recebimento.
class ReceiptReversal {
  const ReceiptReversal({
    required this.id,
    required this.receiptId,
    required this.reason,
    required this.reversedAt,
    this.replacementReceiptId,
  });

  factory ReceiptReversal.fromJson(Map<String, dynamic> json) =>
      ReceiptReversal(
        id: json['id'] as int,
        receiptId: json['receipt_id'] as int,
        reason: json['reason'] as String,
        reversedAt: json['reversed_at'] as String?,
        replacementReceiptId: json['replacement_receipt_id'] as int?,
      );

  final int id;
  final int receiptId;
  final String reason;
  final String? reversedAt;
  final int? replacementReceiptId;

  bool get isCorrection => replacementReceiptId != null;
}

/// Resposta do registro de recebimento, já com os valores recalculados.
class ReceiptResult {
  const ReceiptResult({
    required this.receipt,
    required this.installment,
    required this.agreementRemaining,
    required this.accountBalance,
    required this.replayed,
  });

  final Receipt receipt;
  final Installment installment;
  final Money agreementRemaining;
  final Money accountBalance;
  final bool replayed;
}

/// Resposta de estorno ou correção, já com os valores recalculados.
class ReceiptFixResult {
  const ReceiptFixResult({
    required this.reversal,
    required this.original,
    required this.installment,
    required this.accountBalances,
    required this.replayed,
    this.replacement,
  });

  final ReceiptReversal reversal;
  final Receipt original;
  final Receipt? replacement;
  final Installment installment;

  /// Saldos das contas afetadas, por id.
  final Map<int, Money> accountBalances;
  final bool replayed;
}
