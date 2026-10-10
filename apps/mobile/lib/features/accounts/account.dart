import '../../core/money.dart';

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.openingBalance,
    required this.openingBalanceDate,
    required this.balance,
    this.archivedAt,
    this.firstMovementDate,
    this.openingAdjustments = const [],
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as int,
    name: json['name'] as String,
    openingBalance: Money.parse(json['opening_balance'] as String),
    openingBalanceDate: json['opening_balance_date'] as String,
    balance: Money.parse(json['balance'] as String),
    archivedAt: json['archived_at'] as String?,
    firstMovementDate: json['first_movement_date'] as String?,
    openingAdjustments: (json['opening_adjustments'] as List? ?? const [])
        .map((item) => OpeningAdjustment.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  final int id;
  final String name;
  final Money openingBalance;
  final String openingBalanceDate;

  /// Saldo efetivado: marco inicial mais recebimentos confirmados.
  final Money balance;

  /// Arquivada: continua no histórico e nos totais, sem operações novas.
  final String? archivedAt;

  /// Data da primeira movimentação; a abertura não pode ficar depois dela.
  final String? firstMovementDate;

  /// Correções do saldo inicial/data de abertura, mais recentes primeiro.
  final List<OpeningAdjustment> openingAdjustments;

  bool get isArchived => archivedAt != null;
}

/// Correção auditada da abertura de uma conta.
class OpeningAdjustment {
  const OpeningAdjustment({
    required this.id,
    required this.previousBalance,
    required this.previousDate,
    required this.newBalance,
    required this.newDate,
    required this.reason,
    required this.adjustedAt,
  });

  factory OpeningAdjustment.fromJson(Map<String, dynamic> json) =>
      OpeningAdjustment(
        id: json['id'] as int,
        previousBalance: Money.parse(
          json['previous_opening_balance'] as String,
        ),
        previousDate: json['previous_opening_balance_date'] as String,
        newBalance: Money.parse(json['new_opening_balance'] as String),
        newDate: json['new_opening_balance_date'] as String,
        reason: json['reason'] as String,
        adjustedAt: json['adjusted_at'] as String?,
      );

  final int id;
  final Money previousBalance;
  final String previousDate;
  final Money newBalance;
  final String newDate;
  final String reason;
  final String? adjustedAt;
}
