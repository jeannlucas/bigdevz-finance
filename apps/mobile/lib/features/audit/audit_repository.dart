import '../../core/api_client.dart';
import '../auth/auth_models.dart';
import 'audit_models.dart';

class AuditRepository {
  const AuditRepository({required this.api});

  final ApiClient api;

  Future<List<AuditItem>> list({
    required Space space,
    String? subject,
    int? subjectId,
    bool? criticalOnly,
    int limit = 100,
  }) async {
    final params = <String, String>{'limit': '$limit'};

    if (subject != null && subject.isNotEmpty) {
      params['subject'] = subject;
    }
    if (subjectId != null) {
      params['subject_id'] = '$subjectId';
    }
    if (criticalOnly != null && criticalOnly) {
      params['critical_only'] = 'true';
    }

    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    final path = '/spaces/${space.id}/audit${query.isEmpty ? '' : '?$query'}';
    final response = await api.get(path);
    final data = (response['data'] as List<dynamic>?) ?? const [];

    return data
        .map((item) => AuditItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
