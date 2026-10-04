import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/token_storage.dart';
import 'auth_models.dart';
import 'auth_repository.dart';

enum SessionStatus { restoring, unreachable, signedOut, signedIn }

/// Sessão autenticada e espaço ativo. Trocar de espaço ou confirmar uma
/// gravação incrementa [dataVersion], e as telas recarregam da API.
class SessionController extends ChangeNotifier {
  SessionController({required this._api, required this._auth, required this._storage}) {
    _api.onUnauthorized = _expire;
  }

  static const _tokenKey = 'auth_token';
  static const _spaceKey = 'active_space_id';

  final ApiClient _api;
  final AuthRepository _auth;
  final SessionStorage _storage;

  SessionStatus status = SessionStatus.restoring;
  AppUser? user;
  List<Space> spaces = const [];
  Space? activeSpace;
  int dataVersion = 0;
  String? message;

  Future<void> restore() async {
    status = SessionStatus.restoring;
    notifyListeners();
    final token = await _storage.read(_tokenKey);
    if (token == null) return _signOutLocally();
    _api.token = token;
    try {
      user = await _auth.me();
      await _loadSpaces();
      status = SessionStatus.signedIn;
      message = null;
    } on ApiException catch (error) {
      if (error.isUnauthorized) return _signOutLocally(notice: 'Sua sessão expirou. Entre novamente.');
      status = SessionStatus.unreachable;
      message = error.message;
    } catch (_) {
      // Resposta fora do contrato: não descarta o token, permite tentar de novo.
      status = SessionStatus.unreachable;
      message = 'Não foi possível abrir a sessão. Tente novamente.';
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final (token, loggedUser) = await _auth.login(email, password);
    _api.token = token;
    await _storage.write(_tokenKey, token);
    user = loggedUser;
    await _loadSpaces();
    status = SessionStatus.signedIn;
    message = null;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _auth.logout();
    } on ApiException {
      // O token local é descartado mesmo se a API estiver fora do ar.
    }
    await _signOutLocally();
  }

  Future<void> selectSpace(Space space) async {
    if (space.id == activeSpace?.id) return;
    activeSpace = space;
    dataVersion++;
    notifyListeners();
    await _storage.write(_spaceKey, '${space.id}');
  }

  /// Chamado depois que a API confirma uma gravação.
  void dataChanged() {
    dataVersion++;
    notifyListeners();
  }

  Future<void> _loadSpaces() async {
    spaces = await _auth.spaces();
    final saved = int.tryParse(await _storage.read(_spaceKey) ?? '');
    activeSpace = spaces.where((space) => space.id == saved).firstOrNull ??
        spaces.where((space) => space.isPf).firstOrNull ??
        spaces.firstOrNull;
    dataVersion++;
  }

  void _expire() {
    if (status == SessionStatus.signedIn) _signOutLocally(notice: 'Sua sessão expirou. Entre novamente.');
  }

  Future<void> _signOutLocally({String? notice}) async {
    _api.token = null;
    user = null;
    spaces = const [];
    activeSpace = null;
    dataVersion++;
    status = SessionStatus.signedOut;
    message = notice;
    notifyListeners();
    await _storage.delete(_tokenKey);
  }
}
