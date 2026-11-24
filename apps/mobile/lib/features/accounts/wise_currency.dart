class WiseCurrency {
  const WiseCurrency(this.code, this.balance, {this.brlRate, this.quotedOn});

  factory WiseCurrency.fromJson(Map<String, dynamic> json) => WiseCurrency(
    json['currency'] as String,
    json['balance'] as String,
    brlRate: json['brl_rate'] as String?,
    quotedOn: json['quoted_on'] as String?,
  );

  static const scales = {
    'BRL': 2,
    'AUD': 2,
    'CAD': 2,
    'CHF': 2,
    'CNY': 2,
    'EUR': 2,
    'GBP': 2,
    'HKD': 2,
    'JPY': 0,
    'KRW': 0,
    'KWD': 3,
    'MXN': 2,
    'NZD': 2,
    'PLN': 2,
    'SGD': 2,
    'USD': 2,
  };

  final String code;
  final String balance;
  final String? brlRate;
  final String? quotedOn;

  String get label => '$code ${balance.replaceFirst('.', ',')}';
  bool get hasBalance =>
      BigInt.parse(balance.replaceFirst('.', '')) != BigInt.zero;

  /// Todas as parcelas usam 11 casas antes do arredondamento para centavos.
  BigInt get scaledEstimate {
    final rate = brlRate!;
    final rateDigits = rate.contains('.') ? rate.split('.').last.length : 0;
    return BigInt.parse(balance.replaceFirst('.', '')) *
        BigInt.parse(rate.replaceFirst('.', '')) *
        BigInt.from(10).pow(11 - scales[code]! - rateDigits);
  }

  static String? normalize(String code, String input) {
    final parts = input.trim().replaceFirst(',', '.').split('.');
    final scale = scales[code]!;
    if (parts.length > 2 ||
        !RegExp(r'^\d+$').hasMatch(parts.first) ||
        parts.first.length > 14 - scale) {
      return null;
    }
    final fraction = parts.length == 2 ? parts.last : '';
    if ((scale == 0 && parts.length > 1) ||
        fraction.length > scale ||
        !RegExp(r'^\d*$').hasMatch(fraction)) {
      return null;
    }
    return scale == 0
        ? parts.first
        : '${parts.first}.${fraction.padRight(scale, '0')}';
  }

  static String estimatedBrl(Iterable<WiseCurrency> currencies, int brlCents) {
    final divisor = BigInt.from(10).pow(9);
    final sum = currencies.fold(
      BigInt.from(brlCents) * divisor,
      (total, row) => total + row.scaledEstimate,
    );
    final cents = (sum.abs() + divisor ~/ BigInt.two) ~/ divisor;
    final digits = cents.toString().padLeft(3, '0');
    return '${sum.isNegative && cents != BigInt.zero ? '-' : ''}R\$ ${digits.substring(0, digits.length - 2)},${digits.substring(digits.length - 2)}';
  }
}
