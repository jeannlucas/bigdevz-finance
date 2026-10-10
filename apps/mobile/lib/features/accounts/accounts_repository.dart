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
    required Money openingBalance,
    required String date,
  }) async => Account.fromJson(
    (await _api.post('/spaces/$spaceId/accounts', {
          'name': name,
          'opening_balance': openingBalance.toApi(),
          'opening_balance_date': date,
        }))['data']
        as Map<String, dynamic>,
  );

  Future<Account> find(int spaceId, int accountId) async => Account.fromJson(
    (await _api.get('/spaces/$spaceId/accounts/$accountId'))['data']
        as Map<String, dynamic>,
  );

  /// Só identificação: a abertura tem fluxo próprio ([adjustOpening]).
  Future<Account> rename(int spaceId, int accountId, String name) async =>
      Account.fromJson(
        (await _api.patch('/spaces/$spaceId/accounts/$accountId', {
              'name': name,
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
