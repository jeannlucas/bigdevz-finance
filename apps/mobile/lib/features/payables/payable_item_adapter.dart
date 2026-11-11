import '../../core/money.dart';
import '../../core/text_formatters.dart';
import '../../ui/financial/financial_item_view.dart';
import '../../ui/widgets.dart';
import 'payable.dart';

/// Adaptador de apresentação para [Payable].
class PayableItemAdapter implements FinancialItemView {
  const PayableItemAdapter(this.payable);

  final Payable payable;

  @override
  int get id => payable.id;

  @override
  String get title => toFinancialUpper(payable.description);

  @override
  String? get counterparty =>
      payable.payee != null && payable.payee!.trim().isNotEmpty
      ? toFinancialUpper(payable.payee)
      : null;

  @override
  String get dueDate => payable.dueDate;

  @override
  Object? get category => payable.category;

  @override
  int? get categoryId => payable.categoryId ?? payable.category?.id;

  @override
  String get kindLabel => payable.kindLabel;

  @override
  String get statusLabel => payable.overdue
      ? (payable.status == PayableStatus.partial
            ? 'Parcial · vencida'
            : 'Vencida')
      : payable.status.label;

  @override
  StatusTone get statusTone => switch (payable.status) {
    _ when payable.overdue => StatusTone.danger,
    PayableStatus.paid => StatusTone.success,
    PayableStatus.partial || PayableStatus.awaitingAmount => StatusTone.warning,
    _ => StatusTone.neutral,
  };

  @override
  Money? get pendingAmount => payable.status == PayableStatus.paid
      ? payable.paid
      : (payable.remaining ?? payable.amount);

  @override
  Money? get totalAmount => payable.amount;

  @override
  bool get isOverdue => payable.overdue;

  @override
  bool get isAwaitingAmount =>
      payable.status == PayableStatus.awaitingAmount ||
      (payable.remaining == null && payable.amount == null);

  @override
  bool get isSettled =>
      payable.status == PayableStatus.paid ||
      payable.status == PayableStatus.cancelled;

  @override
  bool get isEligibleForBatch =>
      !isSettled &&
      !isAwaitingAmount &&
      payable.remaining != null &&
      payable.remaining!.cents > 0;

  @override
  Money? get paidAmount => payable.paid;

  @override
  bool get isPartial => payable.status == PayableStatus.partial;

  @override
  String? get amountLabel => payable.status == PayableStatus.paid
      ? 'Total pago'
      : (payable.status == PayableStatus.cancelled
            ? 'Valor cancelado'
            : 'Restante a pagar');
}
