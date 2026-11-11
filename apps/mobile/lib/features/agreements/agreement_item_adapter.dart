import '../../core/money.dart';
import '../../core/text_formatters.dart';
import '../../ui/financial/financial_item_view.dart';
import '../../ui/widgets.dart';
import 'agreement.dart';

/// Adaptador de apresentação para o contrato/acordo consolidado [Agreement].
class AgreementItemAdapter implements FinancialItemView {
  const AgreementItemAdapter(this.agreement);

  final Agreement agreement;

  @override
  int get id => agreement.id;

  @override
  String get title => toFinancialUpper(agreement.description);

  @override
  String? get counterparty => null;

  @override
  String get dueDate =>
      agreement.nextDueDate ??
      (agreement.installments.isNotEmpty
          ? agreement.installments.first.dueDate
          : '2099-12-31');

  @override
  Object? get category => agreement.category;

  @override
  int? get categoryId => agreement.categoryId ?? agreement.category?.id;

  @override
  String get kindLabel =>
      '${agreement.paidInstallments}/${agreement.installmentCount} parcelas';

  @override
  String get statusLabel {
    if (agreement.isCancelled) return 'Cancelada';
    if (agreement.overdueInstallments > 0) {
      return agreement.overdueInstallments == 1
          ? '1 vencida'
          : '${agreement.overdueInstallments} vencidas';
    }
    if (agreement.remaining.isZero) return 'Quitada';
    return 'Em aberto';
  }

  @override
  StatusTone get statusTone {
    if (agreement.isCancelled) return StatusTone.neutral;
    if (agreement.overdueInstallments > 0) return StatusTone.danger;
    if (agreement.remaining.isZero) return StatusTone.success;
    return StatusTone.neutral;
  }

  @override
  Money? get pendingAmount =>
      agreement.isCancelled ? null : agreement.remaining;

  @override
  Money? get totalAmount => agreement.total;

  @override
  bool get isOverdue =>
      !agreement.isCancelled && agreement.overdueInstallments > 0;

  @override
  bool get isAwaitingAmount => false;

  @override
  bool get isSettled => agreement.isCancelled || agreement.remaining.isZero;

  @override
  bool get isEligibleForBatch => false;

  @override
  Money? get paidAmount => agreement.received;

  @override
  bool get isPartial =>
      !agreement.received.isZero && !agreement.remaining.isZero;

  @override
  String? get amountLabel =>
      agreement.remaining.isZero ? 'Total recebido' : 'Restante a receber';
}

/// Adaptador de apresentação para parcelas individuais de um [Agreement].
class AgreementInstallmentItemAdapter implements FinancialItemView {
  const AgreementInstallmentItemAdapter({
    required this.agreement,
    required this.installment,
  });

  final Agreement agreement;
  final Installment installment;

  @override
  int get id => installment.id;

  @override
  String get title => toFinancialUpper(agreement.description);

  @override
  String? get counterparty => null;

  @override
  String get dueDate => installment.dueDate;

  @override
  Object? get category => agreement.category;

  @override
  int? get categoryId => agreement.categoryId ?? agreement.category?.id;

  @override
  String get kindLabel =>
      'Parcela ${installment.number}/${agreement.installmentCount}';

  @override
  String get statusLabel {
    if (agreement.isCancelled) return 'Cancelada';
    if (installment.overdue && installment.status != InstallmentStatus.paid) {
      return installment.status == InstallmentStatus.partial
          ? 'Parcial · vencida'
          : 'Vencida';
    }
    return installment.detailedStatusLabel;
  }

  @override
  StatusTone get statusTone {
    if (agreement.isCancelled) return StatusTone.neutral;
    if (installment.overdue && installment.status != InstallmentStatus.paid) {
      return StatusTone.danger;
    }
    return switch (installment.status) {
      InstallmentStatus.paid => StatusTone.success,
      InstallmentStatus.partial => StatusTone.warning,
      InstallmentStatus.pending => StatusTone.neutral,
    };
  }

  @override
  Money? get pendingAmount {
    if (agreement.isCancelled) return null;
    if (installment.status == InstallmentStatus.paid) {
      return installment.received;
    }
    return installment.remaining;
  }

  @override
  Money? get totalAmount => installment.amount;

  @override
  bool get isOverdue =>
      !agreement.isCancelled &&
      installment.overdue &&
      !installment.remaining.isZero;

  @override
  bool get isAwaitingAmount => false;

  @override
  bool get isSettled =>
      agreement.isCancelled ||
      installment.status == InstallmentStatus.paid ||
      installment.remaining.isZero;

  @override
  bool get isEligibleForBatch => false;

  @override
  Money? get paidAmount => installment.received;

  @override
  bool get isPartial => installment.status == InstallmentStatus.partial;

  @override
  String? get amountLabel => installment.status == InstallmentStatus.paid
      ? 'Total recebido'
      : 'Restante a receber';
}
