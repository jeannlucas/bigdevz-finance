import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.status, this.fieldErrors = const {}});

  /// Nulo quando a API não respondeu (rede, tempo esgotado).
  final int? status;
  final String message;
  final Map<String, String> fieldErrors;

  bool get isNetwork => status == null;
  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Cliente JSON da API Laravel. Única porta do app para dados financeiros.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  String? token;

  /// Chamado quando a API recusa o token (sessão expirada ou revogada).
  void Function()? onUnauthorized;

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, Object?> body, {
    String? idempotencyKey,
  }) => _send('POST', path, body: body, idempotencyKey: idempotencyKey);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? idempotencyKey,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        'Idempotency-Key': ?idempotencyKey,
      });
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      );
    } on TimeoutException {
      throw const ApiException(
        'A API demorou para responder. Tente novamente.',
      );
    } on SocketException {
      throw const ApiException(
        'Sem conexão com a API. Verifique a rede e o endereço configurado.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Sem conexão com a API. Verifique a rede e o endereço configurado.',
      );
    }

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : _decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    if (response.statusCode == 401) onUnauthorized?.call();
    final errors = <String, String>{};
    final raw = decoded['errors'];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is List && value.isNotEmpty) {
          errors['$key'] = '${value.first}';
        }
      });
    }
    final message =
        decoded['message'] is String &&
            (decoded['message'] as String).isNotEmpty
        ? errors.values.firstOrNull ?? decoded['message'] as String
        : 'Não foi possível concluir a operação (${response.statusCode}).';
    throw ApiException(
      message,
      status: response.statusCode,
      fieldErrors: errors,
    );
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : {'data': value};
    } on FormatException {
      return {};
    }
  }
}
