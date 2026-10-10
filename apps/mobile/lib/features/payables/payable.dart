import '../../core/money.dart';

enum PayableStatus {
  open('Em aberto'),
  partial('Parcial'),
  paid('Paga'),
  cancelled('Cancelada'),
  awaitingAmount('Valor a informar');

  const PayableStatus(this.label);

  final String label;

  static PayableStatus parse(String value) => switch (value) {
    'partial' => partial,
    'paid' => paid,
    'cancelled' => cancelled,
    'awaiting_amount' => awaitingAmount,
    _ => open,
  };
}

/// Obrigação a pagar. Não altera saldo; só pagamentos movimentam contas.
class Payable {
  const Payable({
    required this.id,
    required this.kind,
    required this.description,
    required this.amount,
    required this.paid,
    required this.remaining,
    required this.dueDate,
    required this.status,
    required this.overdue,
    this.payee,
    this.installmentNumber,
    this.installmentCount,
    this.recurrenceId,
    this.cardName,
    this.cancelReason,
    this.payments = const [],
    this.changes = const [],
  });

  factory Payable.fromJson(Map<String, dynamic> json, {List? changes}) {
    final plan = json['plan'] as Map<String, dynamic>?;
    final card = json['card'] as Map<String, dynamic>?;
    return Payable(
      id: json['id'] as int,
      kind: json['kind'] as String,
      description: json['description'] as String,
      payee: json['payee'] as String?,
      amount: json['amount'] == null
          ? null
          : Money.parse(json['amount'] as String),
      paid: Money.parse(json['paid'] as String),
      remaining: json['remaining'] == null
          ? null
          : Money.parse(json['remaining'] as String),
      dueDate: json['due_date'] as String,
      status: PayableStatus.parse(json['status'] as String),
      overdue: json['overdue'] as bool,
      installmentNumber: plan?['installment_number'] as int?,
      installmentCount: plan?['installment_count'] as int?,
      recurrenceId: json['recurrence_id'] as int?,
      cardName: card?['name'] as String?,
      cancelReason: json['cancel_reason'] as String?,
      payments: (json['payments'] as List? ?? const [])
          .map((item) => Payment.fromJson(item as Map<String, dynamic>))
          .toList(),
      changes: (changes ?? const [])
          .map((item) => PayableChange.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final int id;

  /// single, installment, recurring ou card_bill.
  final String kind;
  final String description;
  final String? payee;

  /// Nulo em fatura sem total ("valor a informar"), nunca R$ 0,00.
  final Money? amount;
  final Money paid;
  final Money? remaining;
  final String dueDate;
  final PayableStatus status;
  final bool overdue;
  final int? installmentNumber;
  final int? installmentCount;
  final int? recurrenceId;
  final String? cardName;
  final String? cancelReason;
  final List<Payment> payments;
  final List<PayableChange> changes;

  bool get isCardBill => kind == 'card_bill';
  bool get isCancelled => status == PayableStatus.cancelled;
  bool get canPay =>
      !isCancelled && amount != null && (remaining?.cents ?? 0) > 0;

  String get kindLabel => switch (kind) {
    'installment' =>
      'Parcela ${installmentNumber ?? '?'}/${installmentCount ?? '?'}',
    'recurring' => 'Recorrente',
    'card_bill' => 'Fatura${cardName == null ? '' : ' · $cardName'}',
    _ => 'Avulsa',
  };
}

class Payment {
  const Payment({
    required this.id,
    required this.accountId,
    required this.amount,
    required this.paidOn,
    this.reversalReason,
    this.isCorrected = false,
    this.replacesPaymentId,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    final reversal = json['reversal'] as Map<String, dynamic>?;
    return Payment(
      id: json['id'] as int,
      accountId: json['account_id'] as int,
      amount: Money.parse(json['amount'] as String),
      paidOn: json['paid_on'] as String,
      reversalReason: reversal?['reason'] as String?,
      isCorrected: reversal?['kind'] == 'correction',
      replacesPaymentId: json['replaces_payment_id'] as int?,
    );
  }

  final int id;
  final int accountId;
  final Money amount;
  final String paidOn;
  final String? reversalReason;
  final bool isCorrected;
  final int? replacesPaymentId;

  bool get isReversed => reversalReason != null;
}

class PayableChange {
  const PayableChange({required this.action, this.reason, this.changedAt});

  factory PayableChange.fromJson(Map<String, dynamic> json) => PayableChange(
    action: json['action'] as String,
    reason: json['reason'] as String?,
    changedAt: json['changed_at'] as String?,
  );

  final String action;
  final String? reason;
  final String? changedAt;

  String get label => switch (action) {
    'cancel' => 'Cancelada',
    _ => 'Editada',
  };
}

class PayableCard {
  const PayableCard({
    required this.id,
    required this.name,
    required this.dueDay,
    required this.archived,
  });

  factory PayableCard.fromJson(Map<String, dynamic> json) => PayableCard(
    id: json['id'] as int,
    name: json['name'] as String,
    dueDay: json['due_day'] as int,
    archived: json['archived_at'] != null,
  );

  final int id;
  final String name;
  final int dueDay;
  final bool archived;
}

class Recurrence {
  const Recurrence({
    required this.id,
    required this.description,
    required this.amount,
    required this.startDate,
    this.payee,
    this.endDate,
  });

  factory Recurrence.fromJson(Map<String, dynamic> json) => Recurrence(
    id: json['id'] as int,
    description: json['description'] as String,
    payee: json['payee'] as String?,
    amount: Money.parse(json['amount'] as String),
    startDate: json['start_date'] as String,
    endDate: json['end_date'] as String?,
  );

  final int id;
  final String description;
  final String? payee;
  final Money amount;
  final String startDate;
  final String? endDate;
}

/// Parcela da prévia de cronograma (mesmo núcleo do cadastro, na API).
typedef ScheduleItem = ({int number, Money amount, String dueDate});

/// Resposta de pagamento, já com os valores recalculados.
class PaymentResult {
  const PaymentResult({
    required this.payment,
    required this.payable,
    required this.accountBalance,
    required this.replayed,
  });

  final Payment payment;
  final Payable payable;
  final Money accountBalance;
  final bool replayed;
}

/// Resposta de estorno ou correção de pagamento.
class PaymentFixResult {
  const PaymentFixResult({
    required this.original,
    required this.payable,
    required this.accountBalances,
    required this.replayed,
    this.replacement,
  });

  final Payment original;
  final Payment? replacement;
  final Payable payable;
  final Map<int, Money> accountBalances;
  final bool replayed;
}

/// Período que o cadastro de uma recorrência vai gerar, revisado antes de
/// confirmar. [approvedUntil] volta no cadastro: o conjunto criado é esse.
class RecurrencePreview {
  const RecurrencePreview({
    required this.referenceDay,
    required this.horizon,
    required this.approvedUntil,
    required this.firstDueDate,
    required this.lastDueDate,
    required this.count,
    required this.pastCount,
    required this.pastTotal,
    required this.total,
    required this.items,
    this.endDate,
  });

  factory RecurrencePreview.fromJson(Map<String, dynamic> json) =>
      RecurrencePreview(
        referenceDay: json['reference_day'] as int,
        endDate: json['end_date'] as String?,
        horizon: json['horizon'] as String,
        approvedUntil: json['approved_until'] as String,
        firstDueDate: json['first_due_date'] as String,
        lastDueDate: json['last_due_date'] as String,
        count: json['count'] as int,
        pastCount: json['past_count'] as int,
        pastTotal: Money.parse(json['past_total'] as String),
        total: Money.parse(json['total'] as String),
        items: [
          for (final item in json['items'] as List)
            (
              dueDate: (item as Map<String, dynamic>)['due_date'] as String,
              past: item['past'] as bool,
            ),
        ],
      );

  final int referenceDay;
  final String? endDate;
  final String horizon;
  final String approvedUntil;
  final String firstDueDate;
  final String lastDueDate;
  final int count;
  final int pastCount;
  final Money pastTotal;
  final Money total;

  /// Primeiros itens; os totais cobrem o período inteiro.
  final List<({String dueDate, bool past})> items;
}
