import 'package:http/http.dart' as http;

/// Somente para o teste de integração: repassa tudo à API real e, quando
/// [armed], descarta UMA resposta de cadastro, recebimento, pagamento, estorno ou correção depois
/// que a API terminou de respondê-la (gravação feita, resposta perdida).
class LoseResponseClient extends http.BaseClient {
  LoseResponseClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;
  bool armed = false;
  int lost = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (armed &&
        request.method == 'POST' &&
        (request.url.path.endsWith('/receipts') ||
            request.url.path.endsWith('/payments') ||
            request.url.path.endsWith('/payables') ||
            request.url.path.endsWith('/reversal') ||
            request.url.path.endsWith('/correction'))) {
      armed = false;
      await response.stream.drain<void>();
      lost++;
      throw http.ClientException('Resposta descartada pelo teste', request.url);
    }
    return response;
  }
}
