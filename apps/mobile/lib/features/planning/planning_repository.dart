import '../../core/api_client.dart';
import 'planning_models.dart';

class PlanningRepository {
  const PlanningRepository(this._api);

  final ApiClient _api;

  Future<CashFlowResponse> fetchCashFlow({
    required int spaceId,
    int days = 30,
    String view = 'cash',
    int? accountId,
    int? categoryId,
  }) async {
    final params = <String, String>{'days': days.toString(), 'view': view};
    if (accountId != null) params['account_id'] = accountId.toString();
    if (categoryId != null) params['category_id'] = categoryId.toString();

    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final json = await _api.get('/spaces/$spaceId/cash-flow?$query');
    final data = json['data'] as Map<String, dynamic>;
    return CashFlowResponse.fromJson(data);
  }
}
