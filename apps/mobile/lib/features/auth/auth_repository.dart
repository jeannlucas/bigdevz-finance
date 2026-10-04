import '../../core/api_client.dart';
import 'auth_models.dart';

class AuthRepository {
  const AuthRepository(this._api);

  final ApiClient _api;

  /// Devolve o token emitido pela API (Sanctum).
  Future<(String, AppUser)> login(String email, String password) async {
    final json = await _api.post('/auth/login', {
      'email': email,
      'password': password,
      'device_name': 'app-mobile',
    });
    return (
      json['token'] as String,
      AppUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Future<void> logout() => _api.post('/auth/logout', {});

  Future<AppUser> me() async =>
      AppUser.fromJson((await _api.get('/me'))['data'] as Map<String, dynamic>);

  Future<List<Space>> spaces() async =>
      ((await _api.get('/spaces'))['data'] as List)
          .map((item) => Space.fromJson(item as Map<String, dynamic>))
          .toList();
}
