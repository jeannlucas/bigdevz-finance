import 'package:bigdevz_finance/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ApiClient', () {
    test('converte ClientException em ApiException de rede', () async {
      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:8000/api',
        client: MockClient(
          (_) async => throw http.ClientException('Falha de conexão'),
        ),
      );

      expect(
        () => client.get('/spaces'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isNetwork, 'isNetwork', isTrue)
              .having(
                (e) => e.message,
                'message',
                contains('Sem conexão com a API'),
              ),
        ),
      );
    });

    test('converte TimeoutException em ApiException de timeout', () async {
      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:8000/api',
        timeout: const Duration(milliseconds: 10),
        client: MockClient((_) async {
          await Future.delayed(const Duration(milliseconds: 50));
          return http.Response('{}', 200);
        }),
      );

      expect(
        () => client.get('/spaces'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isNetwork, 'isNetwork', isTrue)
              .having(
                (e) => e.message,
                'message',
                contains('A API demorou para responder'),
              ),
        ),
      );
    });

    test('invoca onUnauthorized em status 401', () async {
      var unauthorizedCalled = false;
      final client =
          ApiClient(
              baseUrl: 'http://127.0.0.1:8000/api',
              client: MockClient(
                (_) async =>
                    http.Response('{"message": "Sessão expirada."}', 401),
              ),
            )
            ..onUnauthorized = () {
              unauthorizedCalled = true;
            };

      await expectLater(
        client.get('/spaces'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
      expect(unauthorizedCalled, isTrue);
    });

    test('extrai primeiro erro de validação em status 422', () async {
      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:8000/api',
        client: MockClient(
          (_) async => http.Response(
            '{"message": "Dados inválidos.", "errors": {"amount": ["O valor é obrigatório."]}}',
            422,
          ),
        ),
      );

      await expectLater(
        client.post('/payables', {}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'O valor é obrigatório.',
          ),
        ),
      );
    });
  });
}
