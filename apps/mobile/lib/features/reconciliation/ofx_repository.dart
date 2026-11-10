import '../../core/api_client.dart';
import 'ofx_models.dart';

class OfxRepository {
  const OfxRepository(this._api);

  final ApiClient _api;

  Future<OfxParseResult> parseOfx({
    required int spaceId,
    required int accountId,
    required String ofxContent,
  }) async {
    final res = await _api.post('/spaces/$spaceId/ofx/parse', {
      'account_id': accountId,
      'ofx_content': ofxContent,
    });
    final data = res['data'] as Map<String, dynamic>;
    return OfxParseResult.fromJson(data);
  }

  Future<Map<String, dynamic>> reconcile({
    required int spaceId,
    required int accountId,
    required List<Map<String, dynamic>> transactions,
  }) async {
    final res = await _api.post('/spaces/$spaceId/ofx/reconcile', {
      'account_id': accountId,
      'transactions': transactions,
    });
    return (res['data'] as Map<String, dynamic>?) ?? {};
  }
}
