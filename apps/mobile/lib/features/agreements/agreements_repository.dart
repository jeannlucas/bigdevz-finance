import '../../core/api_client.dart';
import '../../core/money.dart';
import '../payables/payable.dart' show RecurrencePreview;
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
    int? categoryId,
  }) async {
    final query = <String>['status=$status'];
    if (categoryId != null) query.add('category_id=$categoryId');
    final response = await _api.get(
      '/spaces/$spaceId/agreements?${query.join('&')}',
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
    int? categoryId,
  }) async =>
      (await list(spaceId, status: status, categoryId: categoryId)).items;

  Future<Agreement> find(int spaceId, int agreementId) async =>
      Agreement.fromJson(
        (await _api.get('/spaces/$spaceId/agreements/$agreementId'))['data']
            as Map<String, dynamic>,
      );

  Future<RecurrencePreview> recurrencePreview(
    int spaceId, {
    Money? amount,
    required String startDate,
    String? endDate,
    bool isVariable = false,
    Money? estimatedAmount,
  }) async => RecurrencePreview.fromJson(
    (await _api.post('/spaces/$spaceId/agreements/recurrence-preview', {
          'amount': amount?.toApi(),
          'start_date': startDate,
          'end_date': endDate,
          'is_variable': isVariable,
          'estimated_amount': estimatedAmount?.toApi(),
        }))['data']
        as Map<String, dynamic>,
  );

  Future<Agreement> create(
    int spaceId, {
    required String description,
    Money? total,
    int? installmentCount,
    String? firstDueDate,
    int? categoryId,
    String kind = 'installment',
    bool isVariable = false,
    Money? amount,
    Money? estimatedAmount,
    String? startDate,
    String? endDate,
    String? approvedUntil,
    bool confirmPast = false,
    String? idempotencyKey,
  }) async {
    final body = <String, dynamic>{
      'kind': kind,
      'description': description,
      'category_id': ?categoryId,
    };
    if (kind == 'recurring') {
      body['is_variable'] = isVariable;
      if (amount != null) body['amount'] = amount.toApi();
      if (estimatedAmount != null) {
        body['estimated_amount'] = estimatedAmount.toApi();
      }
      body['start_date'] = startDate;
      if (endDate != null) body['end_date'] = endDate;
      body['approved_until'] = approvedUntil;
      body['confirm_past'] = confirmPast;
    } else {
      body['total'] = total?.toApi();
      body['installment_count'] = installmentCount;
      body['first_due_date'] = firstDueDate;
    }
    return Agreement.fromJson(
      (await _api.post(
            '/spaces/$spaceId/agreements',
            body,
            idempotencyKey: idempotencyKey,
          ))['data']
          as Map<String, dynamic>,
    );
  }

  Future<Installment> installment(int spaceId, int installmentId) async =>
      Installment.fromJson(
        (await _api.get('/spaces/$spaceId/installments/$installmentId'))['data']
            as Map<String, dynamic>,
      );

  Future<Agreement> update(
    int spaceId,
    int agreementId,
    Map<String, dynamic> data,
  ) async => Agreement.fromJson(
    (await _api.patch('/spaces/$spaceId/agreements/$agreementId', data))['data']
        as Map<String, dynamic>,
  );

  Future<Agreement> cancel(int spaceId, int agreementId, String reason) async =>
      Agreement.fromJson(
        (await _api.post('/spaces/$spaceId/agreements/$agreementId/cancel', {
              'reason': reason,
            }))['data']
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
