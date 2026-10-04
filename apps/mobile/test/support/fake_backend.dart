import 'dart:async';
import 'dart:convert';

import 'package:bigdevz_finance/core/token_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemorySessionStorage implements SessionStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// API em memória com o mesmo contrato JSON da API Laravel.
class FakeBackend {
  final List<http.Request> requests = [];

  /// Respostas a segurar até o teste liberar (simula rede lenta).
  final Map<String, Completer<void>> holds = {};

  /// Respostas fixas por "MÉTODO caminho".
  final Map<String, http.Response Function(http.Request)> overrides = {};

  String validToken = 'token-valido';

  Map<String, Object?> summary(String balance, String receivable) => {
    'data': {
      'space': {},
      'balance': balance,
      'accounts_count': 1,
      'agreements_count': 1,
      'received_total': '0.00',
      'receivable_remaining': receivable,
      'overdue_installments': 0,
    },
  };

  late final Map<String, Object?> routes = {
    'GET /me': {
      'data': {'id': 1, 'name': 'Pessoa Teste', 'email': 'teste@example.com'},
    },
    'GET /spaces': {
      'data': [
        {'id': 1, 'kind': 'PF', 'name': 'Pessoal'},
        {'id': 2, 'kind': 'PJ', 'name': 'Empresa'},
      ],
    },
    'GET /spaces/1/summary': summary('1000.00', '24000.00'),
    'GET /spaces/2/summary': summary('5000.00', '0.00'),
  };

  MockClient get client => MockClient((request) async {
    requests.add(request);
    final route =
        '${request.method} ${request.url.path.replaceFirst('/api', '')}';
    if (holds[route] case final hold?) await hold.future;
    if (overrides[route] case final override?) return override(request);
    if (route == 'POST /auth/login') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['password'] != 'senha-certa') {
        return _json({
          'message': 'E-mail ou senha inválidos.',
          'errors': {
            'email': ['E-mail ou senha inválidos.'],
          },
        }, 422);
      }
      return _json({
        'token': validToken,
        'user': {'id': 1, 'name': 'Pessoa Teste', 'email': 'teste@example.com'},
      });
    }
    if (request.headers['Authorization'] != 'Bearer $validToken') {
      return _json({
        'message': 'Sessão expirada ou inválida. Entre novamente.',
      }, 401);
    }
    final body = routes[route];
    return body == null
        ? _json({'message': 'Registro não encontrado.'}, 404)
        : _json(body);
  });

  static http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  static http.Response json(Object body, [int status = 200]) =>
      _json(body, status);
}
