import '../../core/api_client.dart';
import '../../core/money.dart';
import 'account.dart';

class AccountsRepository {
  const AccountsRepository(this._api);

  final ApiClient _api;

  Future<List<Account>> list(int spaceId) async =>
      ((await _api.get('/spaces/$spaceId/accounts'))['data'] as List)
          .map((item) => Account.fromJson(item as Map<String, dynamic>))
          .toList();

  Future<Account> create(
    int spaceId, {
    required String name,
    String? bankId,
    required Money openingBalance,
    required String date,
  }) async => Account.fromJson(
    (await _api.post('/spaces/$spaceId/accounts', {
          'name': name,
          'bank_id': ?bankId,
          'opening_balance': openingBalance.toApi(),
          'opening_balance_date': date,
        }))['data']
        as Map<String, dynamic>,
  );

  Future<Account> find(int spaceId, int accountId) async => Account.fromJson(
    (await _api.get('/spaces/$spaceId/accounts/$accountId'))['data']
        as Map<String, dynamic>,
  );

  Future<void> saveWiseOperation(
    int spaceId,
    int accountId,
    String route,
    Map<String, Object?> payload,
    String key,
  ) async {
    await _api.post(
      '/spaces/$spaceId/accounts/$accountId/wise/$route',
      payload,
      idempotencyKey: key,
    );
  }

  Future<void> saveWiseQuote(
    int spaceId,
    int accountId,
    String currency,
    String rate,
    String date,
  ) async {
    await _api.patch(
      '/spaces/$spaceId/accounts/$accountId/wise/currencies/$currency/quote',
      {'brl_rate': rate, 'quoted_on': date},
    );
  }

  Future<({List<Map<String, dynamic>> entries, bool hasNext})> wiseHistory(
    int spaceId,
    int accountId,
    int page,
  ) async {
    final json = await _api.get(
      '/spaces/$spaceId/accounts/$accountId/wise/conversions?page=$page',
    );
    return (
      entries: (json['data'] as List).cast<Map<String, dynamic>>(),
      hasNext: json['next_page_url'] != null,
    );
  }

  /// Só identificação: a abertura tem fluxo próprio ([adjustOpening]).
  Future<Account> rename(
    int spaceId,
    int accountId,
    String name, {
    String? bankId,
  }) async => Account.fromJson(
    (await _api.patch('/spaces/$spaceId/accounts/$accountId', {
          'name': name,
          'bank_id': ?bankId,
        }))['data']
        as Map<String, dynamic>,
  );

  /// Arquivar não muda dinheiro; repetir o pedido não muda nada.
  Future<Account> setArchived(
    int spaceId,
    int accountId, {
    required bool archived,
  }) async => Account.fromJson(
    (await _api.post(
          '/spaces/$spaceId/accounts/$accountId/'
          '${archived ? 'archive' : 'unarchive'}',
          const {},
        ))['data']
        as Map<String, dynamic>,
  );

  /// Realiza uma transferência atômica entre contas (do mesmo espaço ou entre espaços distintos).
  Future<({int id, bool replayed})> transfer(
    int spaceId, {
    int? destinationSpaceId,
    required int sourceAccountId,
    required int destinationAccountId,
    required Money amount,
    required String date,
    String? notes,
    required String idempotencyKey,
  }) async {
    final response = await _api.post('/spaces/$spaceId/transfers', {
      if (destinationSpaceId != null && destinationSpaceId != spaceId)
        'destination_space_id': destinationSpaceId,
      'source_account_id': sourceAccountId,
      'destination_account_id': destinationAccountId,
      'amount': amount.toApi(),
      'transferred_at': date,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    }, idempotencyKey: idempotencyKey);
    final data = response['data'] as Map<String, dynamic>;
    final replayed = response['replayed'] == true;
    return (id: data['id'] as int, replayed: replayed);
  }

  /// Estorna uma transferência bilateral de forma coordenada e auditada.
  Future<({int id, bool replayed})> reverseTransfer(
    int spaceId,
    int transferId, {
    required String reason,
    required String idempotencyKey,
  }) async {
    final response = await _api.post(
      '/spaces/$spaceId/transfers/$transferId/reversal',
      {'reason': reason.trim()},
      idempotencyKey: idempotencyKey,
    );
    final data = response['data'] as Map<String, dynamic>;
    final replayed = response['replayed'] == true;
    return (id: data['id'] as int, replayed: replayed);
  }

  /// Correção auditada da abertura. A mesma [idempotencyKey] repete a
  /// correção sem aplicá-la de novo.
  Future<({Account account, OpeningAdjustment adjustment, bool replayed})>
  adjustOpening(
    int spaceId,
    int accountId, {
    required Money openingBalance,
    required String openingDate,
    required String reason,
    required String idempotencyKey,
  }) async {
    final data =
        (await _api.post(
              '/spaces/$spaceId/accounts/$accountId/opening-adjustment',
              {
                'opening_balance': openingBalance.toApi(),
                'opening_balance_date': openingDate,
                'reason': reason,
              },
              idempotencyKey: idempotencyKey,
            ))['data']
            as Map<String, dynamic>;
    return (
      account: Account.fromJson(data['account'] as Map<String, dynamic>),
      adjustment: OpeningAdjustment.fromJson(
        data['adjustment'] as Map<String, dynamic>,
      ),
      replayed: data['replayed'] as bool,
    );
  }
}
