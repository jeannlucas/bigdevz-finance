import '../../core/money.dart';

class OfxSuggestedMatch {
  const OfxSuggestedMatch({
    required this.type,
    required this.id,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.confidence,
  });

  factory OfxSuggestedMatch.fromJson(Map<String, dynamic> json) =>
      OfxSuggestedMatch(
        type: json['type'] as String,
        id: json['id'] as int,
        title: json['title'] as String,
        amount: json['amount'] as String,
        dueDate: json['due_date'] as String,
        confidence: json['confidence'] as String,
      );

  final String type; // 'payable' ou 'installment'
  final int id;
  final String title;
  final String amount;
  final String dueDate;
  final String confidence;
}

class OfxTransactionItem {
  OfxTransactionItem({
    required this.fitid,
    required this.type,
    required this.amountCents,
    required this.amount,
    required this.postedAt,
    required this.memo,
    required this.alreadyReconciled,
    this.suggestedMatch,
    this.selectedAction,
  });

  factory OfxTransactionItem.fromJson(Map<String, dynamic> json) {
    return OfxTransactionItem(
      fitid: json['fitid'] as String,
      type: json['type'] as String,
      amountCents: json['amount_cents'] as int,
      amount: Money(json['amount_cents'] as int),
      postedAt: json['posted_at'] as String,
      memo: json['memo'] as String? ?? '',
      alreadyReconciled: json['already_reconciled'] as bool? ?? false,
      suggestedMatch: json['suggested_match'] != null
          ? OfxSuggestedMatch.fromJson(
              json['suggested_match'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  final String fitid;
  final String type; // 'credit' ou 'debit'
  final int amountCents;
  final Money amount;
  final String postedAt;
  final String memo;
  final bool alreadyReconciled;
  final OfxSuggestedMatch? suggestedMatch;

  /// 'match_payable', 'match_installment', 'new_movement', 'ignore'
  String? selectedAction;
}

class OfxParseResult {
  const OfxParseResult({
    required this.accountId,
    required this.accountName,
    required this.transactionsCount,
    required this.alreadyReconciledCount,
    required this.transactions,
  });

  factory OfxParseResult.fromJson(Map<String, dynamic> json) {
    final account = json['account'] as Map<String, dynamic>? ?? {};
    final txList = (json['transactions'] as List? ?? const [])
        .map((e) => OfxTransactionItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return OfxParseResult(
      accountId: account['id'] as int? ?? 0,
      accountName: account['name'] as String? ?? '',
      transactionsCount: json['transactions_count'] as int? ?? txList.length,
      alreadyReconciledCount: json['already_reconciled_count'] as int? ?? 0,
      transactions: txList,
    );
  }

  final int accountId;
  final String accountName;
  final int transactionsCount;
  final int alreadyReconciledCount;
  final List<OfxTransactionItem> transactions;
}
