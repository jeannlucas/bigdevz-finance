import '../../core/api_client.dart';
import '../../core/money.dart';
import '../payables/payable.dart';
import 'agreement.dart';

enum ReceiptKind { total, partial }

/// Operação financeira sobre uma parcela.
enum ReceiptOperation {
  /// Novo recebimento.
  receipt,

  /// Estorno de um recebimento confirmado, sem substituto.
  reversal,

  /// Estorno com recebimento substituto, numa única operação.
  correction,

  /// Pagamento de uma obrigação a pagar.
  payment,

  /// Estorno de um pagamento, sem substituto.
  paymentReversal,

  /// Estorno de pagamento com substituto, numa única operação.
  paymentCorrection;

  bool get isPayment =>
      this == payment || this == paymentReversal || this == paymentCorrection;
}

/// Estados de uma tentativa.
enum ReceiptAttemptState {
  /// Revisada no app; nada foi guardado nem enviado.
  ready,

  /// Guardada no aparelho e em envio à API.
  sending,

  /// Guardada; a API não deu resposta conclusiva. Pode ter sido gravada.
  uncertain,

  /// A API confirmou: criada agora ou já existente com a mesma chave.
  confirmed,

  /// A API registrou a recusa desta chave: nunca produzirá efeito.
  rejected,
}

/// Motivo de uma tentativa continuar incerta.
enum UncertainReason {
  /// Sem conexão, tempo esgotado ou conexão encerrada.
  network,

  /// 5xx, status inesperado ou recusa sem decisão registrada.
  server,

  /// Resposta 2xx fora do contrato: a gravação pode ter ocorrido.
  unreadable,

  /// Sessão expirada (401).
  unauthorized,

  /// Espaço, parcela ou recebimento inacessível (403/404).
  inaccessible,

  /// Chave já usada com outro conteúdo (409).
  conflict,

  /// Tentativa anterior desta parcela ainda não verificada.
  unresolved,
}

/// Classifica uma falha que não é recusa registrada para a chave.
UncertainReason uncertainReasonFor(ApiException error) =>
    switch (error.status) {
      null => UncertainReason.network,
      401 => UncertainReason.unauthorized,
      403 || 404 => UncertainReason.inaccessible,
      409 => UncertainReason.conflict,
      _ => UncertainReason.server,
    };

/// Só a recusa registrada para a mesma chave é definitiva: a API devolve essa
/// decisão em qualquer repetição. Um 422 sem ela (ou outro status) não prova
/// que um envio original atrasado não será aceito.
bool isRecordedRejection(ApiException error) =>
    error.status == 422 && error.rejectionRecorded;

/// Tentativa enviada (ou prestes a ser enviada) à API. É guardada no
/// armazenamento seguro antes do primeiro envio, com a chave e o conteúdo
/// exatos, vinculada a usuário, espaço e parcela. Só sai de lá com
/// confirmação da API ou recusa registrada para a chave.
///
/// Recebimento e correção: conta, valor e data são os dados enviados.
/// Estorno: são os do recebimento estornado, só para exibição.
class ReceiptAttempt {
  const ReceiptAttempt({
    required this.userId,
    required this.spaceId,
    required this.installmentId,
    required this.idempotencyKey,
    required this.accountId,
    required this.accountName,
    required this.amount,
    required this.receivedOn,
    this.kind,
    this.operation = ReceiptOperation.receipt,
    this.targetReceiptId,
    this.reason,
    this.originalAmount,
    this.originalAccountName,
    this.originalReceivedOn,
    this.payableId,
  });

  factory ReceiptAttempt.fromJson(Map<String, dynamic> json) => ReceiptAttempt(
    userId: json['user_id'] as int,
    spaceId: json['space_id'] as int,
    installmentId: json['installment_id'] as int,
    idempotencyKey: json['idempotency_key'] as String,
    accountId: json['account_id'] as int,
    accountName: json['account_name'] as String,
    amount: Money.parse(json['amount'] as String),
    receivedOn: json['received_on'] as String,
    kind: json['kind'] == null
        ? null
        : ReceiptKind.values.byName(json['kind'] as String),
    // Registros anteriores ao estorno não têm operação: são recebimentos.
    operation: ReceiptOperation.values.byName(
      json['operation'] as String? ?? 'receipt',
    ),
    targetReceiptId: json['target_receipt_id'] as int?,
    reason: json['reason'] as String?,
    originalAmount: json['original_amount'] == null
        ? null
        : Money.parse(json['original_amount'] as String),
    originalAccountName: json['original_account_name'] as String?,
    originalReceivedOn: json['original_received_on'] as String?,
    payableId: json['payable_id'] as int?,
  );

  final int userId;
  final int spaceId;
  final int installmentId;
  final String idempotencyKey;
  final int accountId;
  final String accountName;
  final Money amount;
  final String receivedOn;
  final ReceiptKind? kind;
  final ReceiptOperation operation;

  /// Recebimento estornado ou corrigido.
  final int? targetReceiptId;
  final String? reason;
  final Money? originalAmount;
  final String? originalAccountName;
  final String? originalReceivedOn;

  /// Obrigação a pagar (operações de pagamento); 0 em [installmentId].
  final int? payableId;

  Map<String, Object?> toJson() => {
    'user_id': userId,
    'space_id': spaceId,
    'installment_id': installmentId,
    'idempotency_key': idempotencyKey,
    'account_id': accountId,
    'account_name': accountName,
    'amount': amount.toApi(),
    'received_on': receivedOn,
    'kind': kind?.name,
    'operation': operation.name,
    'target_receipt_id': targetReceiptId,
    'reason': reason,
    'original_amount': originalAmount?.toApi(),
    'original_account_name': originalAccountName,
    'original_received_on': originalReceivedOn,
    'payable_id': payableId,
  };

  /// Onde a tentativa fica guardada: uma por parcela ou por obrigação.
  String get storageKeyValue => operation.isPayment
      ? paymentStorageKey(userId, spaceId, payableId!)
      : storageKey(userId, spaceId, installmentId);

  /// Nome da operação com artigo ("este recebimento", "esta correção").
  String get subject => switch (operation) {
    ReceiptOperation.receipt => 'este recebimento',
    ReceiptOperation.reversal => 'este estorno',
    ReceiptOperation.correction ||
    ReceiptOperation.paymentCorrection => 'esta correção',
    ReceiptOperation.payment => 'este pagamento',
    ReceiptOperation.paymentReversal => 'este estorno',
  };

  /// Uma tentativa por parcela: enquanto pendente, bloqueia recebimentos,
  /// estornos e correções nela.
  static String storageKey(int userId, int spaceId, int installmentId) =>
      'pending_receipt.$userId.$spaceId.$installmentId';

  /// Uma tentativa por obrigação a pagar: bloqueia pagamentos, estornos e
  /// correções nela enquanto pendente.
  static String paymentStorageKey(int userId, int spaceId, int payableId) =>
      'pending_payment.$userId.$spaceId.$payableId';
}

/// Resultado de um envio ou de uma verificação.
class ReceiptAttemptOutcome {
  const ReceiptAttemptOutcome(
    this.state,
    this.attempt, {
    this.result,
    this.fix,
    this.payment,
    this.paymentFix,
    this.error,
    this.reason,
  });

  final ReceiptAttemptState state;
  final ReceiptAttempt attempt;

  /// Recebimento confirmado.
  final ReceiptResult? result;

  /// Estorno ou correção confirmados.
  final ReceiptFixResult? fix;

  /// Pagamento confirmado.
  final PaymentResult? payment;

  /// Estorno ou correção de pagamento confirmados.
  final PaymentFixResult? paymentFix;

  /// Recusa (rejected) ou detalhe da falha (uncertain).
  final ApiException? error;

  /// Presente quando [state] é uncertain.
  final UncertainReason? reason;

  bool get replayed =>
      result?.replayed ??
      fix?.replayed ??
      payment?.replayed ??
      paymentFix?.replayed ??
      false;

  /// Explicação para a pessoa, sem afirmar sucesso ou falha sem evidência.
  String get message => switch (state) {
    ReceiptAttemptState.confirmed => _confirmed(),
    ReceiptAttemptState.rejected =>
      'A API recusou a tentativa e nada foi gravado. Corrija os dados e '
          'revise de novo.',
    _ => switch (reason) {
      UncertainReason.unauthorized =>
        'Sua sessão expirou. Entre novamente para verificar; a tentativa '
            'continua guardada neste aparelho.',
      UncertainReason.inaccessible =>
        'A parcela não está acessível agora. A tentativa continua pendente.',
      UncertainReason.conflict =>
        'A API informa que esta identificação já foi usada com outros dados. '
            'A tentativa continua pendente: confira os recebimentos da parcela '
            'antes de registrar outro.',
      UncertainReason.unreadable =>
        'A resposta da API não pôde ser lida. Ainda não conseguimos confirmar '
            '${attempt.subject}.',
      _ =>
        '${error?.isNetwork == true ? '${error!.message} ' : ''}Ainda não '
            'conseguimos confirmar ${attempt.subject}. ${_resolveHint()}',
    },
  };

  String _resolveHint() => switch (attempt.operation) {
    ReceiptOperation.receipt =>
      'Verifique a tentativa anterior antes de registrar outro para esta '
          'parcela.',
    ReceiptOperation.payment =>
      'Verifique a tentativa anterior antes de registrar outro pagamento '
          'nesta obrigação.',
    ReceiptOperation.paymentReversal || ReceiptOperation.paymentCorrection =>
      'Verifique a tentativa anterior antes de fazer outra operação nesta '
          'obrigação.',
    _ =>
      'Verifique a tentativa anterior antes de fazer outra operação nesta '
          'parcela.',
  };

  String _confirmed() {
    final a = attempt;
    return switch (a.operation) {
      ReceiptOperation.receipt =>
        replayed
            ? 'Recebimento já estava registrado: ${a.amount.brl} em ${a.accountName}.'
            : 'Recebimento confirmado: ${a.amount.brl} em ${a.accountName}.',
      ReceiptOperation.reversal =>
        replayed
            ? 'Estorno já estava registrado: ${a.amount.brl} de ${a.accountName}.'
            : 'Estorno confirmado: ${a.amount.brl} retirados de ${a.accountName}.',
      ReceiptOperation.correction =>
        replayed
            ? 'Correção já estava registrada: ${a.amount.brl} em ${a.accountName}.'
            : 'Correção confirmada: ${a.amount.brl} em ${a.accountName}.',
      ReceiptOperation.payment =>
        replayed
            ? 'Pagamento já estava registrado: ${a.amount.brl} de ${a.accountName}.'
            : 'Pagamento confirmado: ${a.amount.brl} de ${a.accountName}.',
      ReceiptOperation.paymentReversal =>
        replayed
            ? 'Estorno do pagamento já estava registrado: ${a.amount.brl} para ${a.accountName}.'
            : 'Estorno do pagamento confirmado: ${a.amount.brl} devolvidos a ${a.accountName}.',
      ReceiptOperation.paymentCorrection =>
        replayed
            ? 'Correção do pagamento já estava registrada: ${a.amount.brl} de ${a.accountName}.'
            : 'Correção do pagamento confirmada: ${a.amount.brl} de ${a.accountName}.',
    };
  }
}
