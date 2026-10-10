import '../../core/api_client.dart';
import '../../core/money.dart';
import 'agreement.dart';

class AgreementsListResult {
  const AgreementsListResult({required this.items, required this.totalCount});

  final List<Agreement> items;
  final int totalCount;
}

class AgreementsRepository {
  const AgreementsRepository(this._api);

  final ApiClient _api;

  Future<AgreementsListResult> list(
    int spaceId, {
    String status = 'open',
  }) async {
    final response = await _api.get(
      '/spaces/$spaceId/agreements?status=$status',
    );
    final data = (response['data'] as List)
        .map((item) => Agreement.fromJson(item as Map<String, dynamic>))
        .toList();
    final meta = response['meta'] as Map<String, dynamic>?;
    final totalCount = (meta?['total_count'] as int?) ?? data.length;
    return AgreementsListResult(items: data, totalCount: totalCount);
  }

  Future<List<Agreement>> listItems(
    int spaceId, {
    String status = 'open',
  }) async => (await list(spaceId, status: status)).items;

  Future<Agreement> find(int spaceId, int agreementId) async =>
      Agreement.fromJson(
        (await _api.get('/spaces/$spaceId/agreements/$agreementId'))['data']
            as Map<String, dynamic>,
      );

  Future<Agreement> create(
    int spaceId, {
    required String description,
    required Money total,
    required int installmentCount,
    required String firstDueDate,
  }) async => Agreement.fromJson(
    (await _api.post('/spaces/$spaceId/agreements', {
          'description': description,
          'total': total.toApi(),
          'installment_count': installmentCount,
          'first_due_date': firstDueDate,
        }))['data']
        as Map<String, dynamic>,
  );

  Future<Installment> installment(int spaceId, int installmentId) async =>
      Installment.fromJson(
        (await _api.get('/spaces/$spaceId/installments/$installmentId'))['data']
            as Map<String, dynamic>,
      );

  /// A mesma [idempotencyKey] deve ser reenviada em novas tentativas da mesma
  /// operação; assim a API não duplica o recebimento.
  Future<ReceiptResult> receive(
    int spaceId,
    int installmentId, {
    required int accountId,
    required Money amount,
    required String receivedOn,
    required String idempotencyKey,
  }) async {
    final json = await _api.post(
      '/spaces/$spaceId/installments/$installmentId/receipts',
      {
        'account_id': accountId,
        'amount': amount.toApi(),
        'received_on': receivedOn,
      },
      idempotencyKey: idempotencyKey,
    );
    final data = json['data'] as Map<String, dynamic>;
    return ReceiptResult(
      receipt: Receipt.fromJson(data['receipt'] as Map<String, dynamic>),
      installment: Installment.fromJson(
        data['installment'] as Map<String, dynamic>,
      ),
      agreementRemaining: Money.parse(
        (data['agreement'] as Map<String, dynamic>)['remaining'] as String,
      ),
      accountBalance: Money.parse(
        (data['account'] as Map<String, dynamic>)['balance'] as String,
      ),
      replayed: data['replayed'] as bool,
    );
  }

  /// Estorno (sem [replacement]) ou correção de um recebimento confirmado.
  /// A mesma [idempotencyKey] repete a operação sem aplicá-la de novo.
  Future<ReceiptFixResult> fix(
    int spaceId,
    int receiptId, {
    required String reason,
    required String idempotencyKey,
    ({int accountId, Money amount, String receivedOn})? replacement,
  }) async {
    final json = await _api.post(
      '/spaces/$spaceId/receipts/$receiptId/'
      '${replacement == null ? 'reversal' : 'correction'}',
      {
        'reason': reason,
        if (replacement != null) ...{
          'account_id': replacement.accountId,
          'amount': replacement.amount.toApi(),
          'received_on': replacement.receivedOn,
        },
      },
      idempotencyKey: idempotencyKey,
    );
    final data = json['data'] as Map<String, dynamic>;
    final replacementJson = data['replacement'] as Map<String, dynamic>?;
    return ReceiptFixResult(
      reversal: ReceiptReversal.fromJson(
        data['reversal'] as Map<String, dynamic>,
      ),
      original: Receipt.fromJson(data['original'] as Map<String, dynamic>),
      replacement: replacementJson == null
          ? null
          : Receipt.fromJson(replacementJson),
      installment: Installment.fromJson(
        data['installment'] as Map<String, dynamic>,
      ),
      accountBalances: {
        for (final account in data['accounts'] as List)
          (account as Map<String, dynamic>)['id'] as int: Money.parse(
            account['balance'] as String,
          ),
      },
      replayed: data['replayed'] as bool,
    );
  }
}
