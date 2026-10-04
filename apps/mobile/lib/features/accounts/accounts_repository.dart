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
}
