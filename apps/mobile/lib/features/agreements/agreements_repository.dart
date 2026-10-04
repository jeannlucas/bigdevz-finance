import '../../core/api_client.dart';
import '../../core/money.dart';
import 'agreement.dart';

class AgreementsRepository {
  const AgreementsRepository(this._api);

  final ApiClient _api;

  Future<List<Agreement>> list(int spaceId) async =>
      ((await _api.get('/spaces/$spaceId/agreements'))['data'] as List)
          .map((item) => Agreement.fromJson(item as Map<String, dynamic>))
          .toList();

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
}
