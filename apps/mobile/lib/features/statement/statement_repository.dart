import '../../core/api_client.dart';
import 'statement_entry.dart';

class StatementRepository {
  const StatementRepository(this._api);

  final ApiClient _api;

  Future<List<StatementEntry>> list(
    int spaceId, {
    int? accountId,
    String? from,
    String? to,
    String? direction,
    int? categoryId,
  }) async {
    final queryParams = <String>[];
    if (accountId != null) {
      queryParams.add('account_id=$accountId');
    }
    if (from != null && from.isNotEmpty) {
      queryParams.add('from=$from');
    }
    if (to != null && to.isNotEmpty) {
      queryParams.add('to=$to');
    }
    if (direction != null && direction.isNotEmpty && direction != 'all') {
      queryParams.add('direction=$direction');
    }
    if (categoryId != null) {
      queryParams.add('category_id=$categoryId');
    }

    final qs = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final response = await _api.get('/spaces/$spaceId/statement$qs');
    final data = (response['data'] as List)
        .map((item) => StatementEntry.fromJson(item as Map<String, dynamic>))
        .toList();
    return data;
  }
}
