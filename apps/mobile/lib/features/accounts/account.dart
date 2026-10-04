import '../../core/money.dart';

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.openingBalance,
    required this.openingBalanceDate,
    required this.balance,
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as int,
    name: json['name'] as String,
    openingBalance: Money.parse(json['opening_balance'] as String),
    openingBalanceDate: json['opening_balance_date'] as String,
    balance: Money.parse(json['balance'] as String),
  );

  final int id;
  final String name;
  final Money openingBalance;
  final String openingBalanceDate;

  /// Saldo efetivado: marco inicial mais recebimentos confirmados.
  final Money balance;
}
