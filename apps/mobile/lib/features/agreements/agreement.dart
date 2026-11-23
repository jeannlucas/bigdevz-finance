import '../../core/money.dart';
import '../categories/category.dart';

class Agreement {
  const Agreement({
    required this.id,
    required this.description,
    this.kind = 'installment',
    this.isVariable = false,
    this.total,
    this.installmentCount,
    this.amount,
    this.estimatedAmount,
    this.startDate,
    this.referenceDay,
    this.endDate,
    required this.received,
    required this.remaining,
    required this.paidInstallments,
    required this.overdueInstallments,
    this.nextDueDate,
    required this.installments,
    this.categoryId,
    this.category,
    this.isCancelled = false,
    this.cancelReason,
    this.cancelledAt,
    this.editedAt,
  });

  factory Agreement.fromJson(Map<String, dynamic> json) => Agreement(
    id: json['id'] as int,
    description: json['description'] as String,
    kind: (json['kind'] as String?) ?? 'installment',
    isVariable: (json['is_variable'] as bool?) ?? false,
    total: json['total'] != null ? Money.parse(json['total'] as String) : null,
    installmentCount: json['installment_count'] as int?,
    amount: json['amount'] != null
        ? Money.parse(json['amount'] as String)
        : null,
    estimatedAmount: json['estimated_amount'] != null
        ? Money.parse(json['estimated_amount'] as String)
        : null,
    startDate: json['start_date'] as String?,
    referenceDay: json['reference_day'] as int?,
    endDate: json['end_date'] as String?,
    received: Money.parse(json['received'] as String),
    remaining: json['remaining'] != null
        ? Money.parse(json['remaining'] as String)
        : Money.zero,
    paidInstallments: json['paid_installments'] as int,
    overdueInstallments: json['overdue_installments'] as int,
    nextDueDate: json['next_due_date'] as String?,
    categoryId: json['category_id'] as int?,
    category: json['category'] != null
        ? Category.fromJson(json['category'] as Map<String, dynamic>)
        : null,
    isCancelled: (json['is_cancelled'] as bool?) ?? false,
    cancelReason: json['cancel_reason'] as String?,
    cancelledAt: json['cancelled_at'] as String?,
    editedAt: json['edited_at'] as String?,
    installments: (json['installments'] as List? ?? const [])
        .map((item) => Installment.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  final int id;
  final String description;
  final String kind;
  final bool isVariable;
  final Money? total;
  final int? installmentCount;
  final Money? amount;
  final Money? estimatedAmount;
  final String? startDate;
  final int? referenceDay;
  final String? endDate;
  final Money received;
  final Money remaining;
  final int paidInstallments;
  final int overdueInstallments;
  final String? nextDueDate;
  final int? categoryId;
  final Category? category;
  final bool isCancelled;
  final String? cancelReason;
  final String? cancelledAt;
  final String? editedAt;
  final List<Installment> installments;

  bool get isRecurring => kind == 'recurring';
}

enum InstallmentStatus {
  pending('Pendente'),
  partial('Parcial'),
  paid('Quitada'),
  awaitingAmount('Aguardando valor');

  const InstallmentStatus(this.label);

  final String label;

  static InstallmentStatus parse(String value) => switch (value) {
    'paid' => paid,
    'partial' => partial,
    'awaiting_amount' => awaitingAmount,
    _ => pending,
  };
}

class Installment {
  const Installment({
    required this.id,
    required this.agreementId,
    required this.number,
    required this.dueDate,
    this.cycle,
    this.amount,
    this.estimatedAmount,
    required this.received,
    this.remaining = Money.zero,
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
      cycle: json['cycle'] as String?,
      amount: json['amount'] != null
          ? Money.parse(json['amount'] as String)
          : null,
      estimatedAmount: json['estimated_amount'] != null
          ? Money.parse(json['estimated_amount'] as String)
          : null,
      received: Money.parse(json['received'] as String),
      remaining: json['remaining'] != null
          ? Money.parse(json['remaining'] as String)
          : Money.zero,
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
  final String? cycle;
  final Money? amount;
  final Money? estimatedAmount;
  final Money received;
  final Money remaining;
  final InstallmentStatus status;
  final bool overdue;
  final String? agreementDescription;
  final int? installmentCount;
  final List<Receipt> receipts;

  bool get isAwaitingAmount =>
      status == InstallmentStatus.awaitingAmount || amount == null;

  String get detailedStatusLabel => switch (status) {
    InstallmentStatus.partial => 'Parcialmente recebido',
    InstallmentStatus.paid => 'Quitada',
    InstallmentStatus.awaitingAmount => 'Aguardando valor',
    InstallmentStatus.pending => overdue ? 'Vencida' : 'Pendente',
  };
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
