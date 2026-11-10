class AuditItem {
  const AuditItem({
    required this.id,
    required this.subject,
    required this.subjectId,
    required this.action,
    required this.isCritical,
    this.userName,
    this.userEmail,
    this.before = const {},
    this.after = const {},
    this.diff = const {},
    this.reason,
    this.createdAt,
  });

  factory AuditItem.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    DateTime? parsedDate;
    if (json['created_at'] != null) {
      parsedDate = DateTime.tryParse(json['created_at'] as String);
    }

    return AuditItem(
      id: json['id'] as int,
      subject: (json['subject'] as String?) ?? '',
      subjectId: (json['subject_id'] as int?) ?? 0,
      action: (json['action'] as String?) ?? '',
      isCritical: (json['is_critical'] as bool?) ?? false,
      userName: user?['name'] as String?,
      userEmail: user?['email'] as String?,
      before: (json['before'] as Map<String, dynamic>?) ?? const {},
      after: (json['after'] as Map<String, dynamic>?) ?? const {},
      diff: (json['diff'] as Map<String, dynamic>?) ?? const {},
      reason: json['reason'] as String?,
      createdAt: parsedDate,
    );
  }

  final int id;
  final String subject;
  final int subjectId;
  final String action;
  final bool isCritical;
  final String? userName;
  final String? userEmail;
  final Map<String, dynamic> before;
  final Map<String, dynamic> after;
  final Map<String, dynamic> diff;
  final String? reason;
  final DateTime? createdAt;

  String get humanSubject => matchHumanSubject(subject);
  String get humanAction => matchHumanAction(action);

  static String matchHumanSubject(String sub) {
    switch (sub) {
      case 'payable':
        return 'Conta a pagar';
      case 'agreement':
        return 'Conta a receber';
      case 'receipt':
        return 'Recebimento';
      case 'payment':
        return 'Pagamento';
      case 'transfer':
        return 'Transferência';
      case 'account':
        return 'Conta bancária';
      case 'period_closing':
        return 'Período contábil';
      case 'card':
        return 'Cartão de crédito';
      case 'recurrence':
        return 'Recorrência';
      default:
        return 'Lançamento financeiro';
    }
  }

  static String matchHumanAction(String act) {
    switch (act) {
      case 'create':
      case 'created':
        return 'Criação de lançamento';
      case 'receive':
      case 'received':
        return 'Recebimento de parcela';
      case 'payment':
      case 'paid':
        return 'Pagamento de conta';
      case 'edit':
      case 'updated':
        return 'Alteração de dados';
      case 'cancel':
      case 'cancelled':
        return 'Cancelamento de lançamento';
      case 'reverse':
      case 'reversed':
        return 'Estorno financeiro';
      case 'close':
      case 'closed':
        return 'Fechamento de período contábil';
      case 'reopen':
      case 'reopened':
        return 'Reabertura de período contábil';
      case 'adjust_opening':
        return 'Ajuste de saldo inicial';
      case 'archive':
        return 'Arquivamento';
      case 'unarchive':
        return 'Desarquivamento';
      default:
        return 'Operação financeira';
    }
  }
}
