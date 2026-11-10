import '../../core/api_client.dart';
import '../auth/auth_models.dart';
import 'space_member_models.dart';

class SpaceMembersRepository {
  const SpaceMembersRepository({required this.api});

  final ApiClient api;

  Future<List<SpaceMember>> list({required Space space}) async {
    final response = await api.get('/spaces/${space.id}/members');
    final data = (response['data'] as List<dynamic>?) ?? const [];

    return data
        .map((item) => SpaceMember.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<SpaceMember> saveMember({
    required Space space,
    required String email,
    required String role,
  }) async {
    final response = await api.post('/spaces/${space.id}/members', {
      'email': email,
      'role': role,
    });

    final data = (response['data'] as Map<String, dynamic>?) ?? const {};
    return SpaceMember.fromJson(data);
  }

  Future<void> removeMember({
    required Space space,
    required int memberId,
  }) async {
    await api.delete('/spaces/${space.id}/members/$memberId');
  }
}
