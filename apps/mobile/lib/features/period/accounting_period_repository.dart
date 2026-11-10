import '../../core/api_client.dart';
import '../auth/auth_models.dart';

class AccountingPeriodRepository {
  const AccountingPeriodRepository({required this.api});

  final ApiClient api;

  Future<Map<String, dynamic>> getStatus({required Space space}) async {
    final response = await api.get('/spaces/${space.id}/closing');
    return (response['data'] as Map<String, dynamic>?) ?? const {};
  }

  Future<void> closePeriod({
    required Space space,
    required String closedUntil,
    String? reason,
  }) async {
    await api.post('/spaces/${space.id}/closing', {
      'closed_until': closedUntil,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  Future<void> reopenPeriod({
    required Space space,
    required String reason,
    String? closedUntil,
  }) async {
    await api.post('/spaces/${space.id}/reopen', {
      'reason': reason,
      if (closedUntil != null && closedUntil.isNotEmpty)
        'closed_until': closedUntil,
    });
  }
}
