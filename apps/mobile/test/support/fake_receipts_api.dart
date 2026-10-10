import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Como a próxima requisição de escrita se comporta.
enum Delivery {
  /// Processa e responde normalmente.
  normal,

  /// A conexão cai antes de chegar à API: nada é gravado.
  dropBeforeServer,

  /// A API grava, mas a resposta se perde no caminho.
  loseResponse,

  /// Erro 500 sem gravar.
  serverError,

  /// Grava e responde 2xx com corpo ilegível.
  unreadable,

  /// Respostas sem processar a operação.
  unauthorized,
  notFound,
  conflict,

  /// 422 sem decisão registrada (como um proxy ou versão antiga da API).
  unrecordedRejection,
}

/// Recebimento gravado pela API simulada.
class FakeReceipt {
  FakeReceipt(this.key, this.accountId, this.amountCents, this.date, {int? id})
    : id = id ?? 0;

  /// Chave do pedido; nula para substitutos de correção.
  final String? key;
  final int accountId;
  final int amountCents;
  final String date;
  int id;
  String? reversalReason;
  int? replacementId;
  int? replacesId;

  bool get reversed => reversalReason != null;
}

/// API em memória para UMA parcela (id 22, espaço 1), com a regra da API
/// Laravel: cada chave do espaço tem uma decisão guardada (concluída ou
/// recusada) devolvida em qualquer repetição com o mesmo conteúdo; conteúdo
/// diferente é 409. Estorno e correção compensam sem apagar o original.
/// Simula efeitos; não comprova persistência nem concorrência reais.
class FakeReceiptsApi {
  FakeReceiptsApi({this.installmentCents = 200000, this.balanceCents = 100000});

  final int installmentCents;

  /// Saldo da conta 7; a conta 8 começa em zero.
  int balanceCents;
  int reserveCents = 0;

  /// Estado das contas 7 e 8 (abertura, nome, arquivamento, correções).
  final Map<int, FakeAccount> accounts = {
    7: FakeAccount(7, 'Banco PF', 100000),
    8: FakeAccount(8, 'Reserva PF', 0),
  };
  final List<FakeReceipt> receipts = [];
  final List<http.Request> requests = [];

  /// Decisões por chave: impressão do conteúdo e resposta guardada.
  final Map<String, ({String fingerprint, int status, Object body})> decisions =
      {};

  /// Comportamento das próximas escritas, em ordem.
  final List<Delivery> script = [];

  /// Se definido, a próxima escrita espera este sinal antes de ser
  /// processada (simula a API ainda gravando).
  Completer<void>? hold;

  List<FakeReceipt> get active => receipts.where((r) => !r.reversed).toList();
  int get receivedCents => active.fold(0, (t, r) => t + r.amountCents);
  int get remainingCents => installmentCents - receivedCents;
  List<http.Request> get receiptRequests =>
      requests.where((request) => request.method == 'POST').toList();

  MockClient get client => MockClient(handle);

  /// Grava um recebimento direto (dados anteriores ao teste).
  FakeReceipt seed(int accountId, int cents, String date) {
    final receipt = FakeReceipt(null, accountId, cents, date)
      ..id = 100 + receipts.length;
    receipts.add(receipt);
    _credit(accountId, cents);
    return receipt;
  }

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path.replaceFirst('/api', '');
    if (request.method == 'GET' && path == '/spaces/1/installments/22') {
      return _json({'data': installmentJson(withReceipts: true)});
    }
    if (request.method == 'GET' && path == '/spaces/1/accounts') {
      return _json({
        'data': [for (final id in accounts.keys) accountJson(id)],
      });
    }
    final accountPath = RegExp(
      r'^/spaces/1/accounts/(\d+)(/archive|/unarchive|/opening-adjustment)?$',
    ).firstMatch(path);
    final account = accountPath == null
        ? null
        : accounts[int.parse(accountPath.group(1)!)];
    if (accountPath != null && account == null) {
      return _json({'message': 'Registro não encontrado.'}, 404);
    }
    final action = accountPath?.group(2);
    if (account != null && action == null) {
      if (request.method == 'PATCH') {
        account.name = (jsonDecode(request.body) as Map)['name'] as String;
      }
      return _json({'data': accountJson(account.id, detail: true)});
    }
    if (account != null && action != '/opening-adjustment') {
      account.archived = action == '/archive';
      return _json({'data': accountJson(account.id, detail: true)});
    }
    final fix = RegExp(r'^/spaces/1/receipts/(\d+)/(reversal|correction)$')
        .firstMatch(path);
    final isReceipt = path == '/spaces/1/installments/22/receipts';
    if (request.method != 'POST' ||
        (!isReceipt && fix == null && account == null)) {
      return _json({'message': 'Registro não encontrado.'}, 404);
    }

    final delivery = script.isEmpty ? Delivery.normal : script.removeAt(0);
    final gate = hold;
    hold = null;
    switch (delivery) {
      case Delivery.dropBeforeServer:
        throw http.ClientException('Connection closed before full header');
      case Delivery.serverError:
        return _json({'message': 'Server Error'}, 500);
      case Delivery.unauthorized:
        return _json({
          'message': 'Sessão expirada ou inválida. Entre novamente.',
        }, 401);
      case Delivery.notFound:
        return _json({'message': 'Registro não encontrado.'}, 404);
      case Delivery.conflict:
        return _json({'message': 'Esta chave já foi usada.'}, 409);
      case Delivery.unrecordedRejection:
        return _json({
          'message': 'Recusado.',
          'errors': {
            'amount': ['Recusado.'],
          },
        }, 422);
      case Delivery.normal:
      case Delivery.loseResponse:
      case Delivery.unreadable:
        break;
    }
    if (gate != null) await gate.future;
    final key = request.headers['Idempotency-Key']!;
    final fingerprint = '$path|${request.body}';
    final response = _decide(key, fingerprint, () {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (account != null) return _adjustOpening(account, body);
      return fix == null
          ? _receive(key, body)
          : _fix(int.parse(fix.group(1)!), fix.group(2)!, body);
    });
    if (delivery == Delivery.loseResponse) {
      throw http.ClientException('Connection reset by peer');
    }
    if (delivery == Delivery.unreadable && response.statusCode < 300) {
      return http.Response('<html>proxy</html>', 200);
    }
    return response;
  }

  /// Executa uma vez por chave; repetições devolvem a decisão guardada.
  http.Response _decide(
    String key,
    String fingerprint,
    (int, Object) Function() work,
  ) {
    final previous = decisions[key];
    if (previous != null) {
      if (previous.fingerprint != fingerprint) {
        return _json({'message': 'Esta chave já foi usada.'}, 409);
      }
      return _json(
        _withDecision(previous.body, key, previous.status, replayed: true),
        previous.status == 201 ? 200 : previous.status,
      );
    }
    final (status, body) = work();
    decisions[key] = (fingerprint: fingerprint, status: status, body: body);
    return _json(_withDecision(body, key, status, replayed: false), status);
  }

  Map<String, Object?> _withDecision(
    Object body,
    String key,
    int status, {
    required bool replayed,
  }) {
    final map = Map<String, Object?>.from(body as Map);
    if (map['data'] is Map) {
      map['data'] = {...(map['data'] as Map), 'replayed': replayed};
    }
    return {
      ...map,
      'idempotency': {
        'key': key,
        'status': status == 422 ? 'rejected' : 'completed',
        'replayed': replayed,
      },
    };
  }

  (int, Object) _receive(String key, Map<String, dynamic> body) {
    if (accounts[body['account_id']]?.archived ?? false) {
      return _rejection(
        'account_id',
        'Esta conta está arquivada. Escolha uma conta ativa.',
      );
    }
    final cents = _cents(body['amount'] as String);
    if (cents > remainingCents) {
      return _rejection(
        'amount',
        'O valor excede o restante da parcela (${_money(remainingCents)}).',
      );
    }
    final receipt = FakeReceipt(
      key,
      body['account_id'] as int,
      cents,
      body['received_on'] as String,
    )..id = 100 + receipts.length;
    receipts.add(receipt);
    _credit(receipt.accountId, cents);
    return (
      201,
      {
        'data': {
          'receipt': receiptJson(receipt),
          'installment': installmentJson(),
          'agreement': {'remaining': _money(remainingCents)},
          'account': {'balance': _money(_balance(receipt.accountId))},
        },
      },
    );
  }

  (int, Object) _fix(int id, String kind, Map<String, dynamic> body) {
    final original = receipts.where((r) => r.id == id).firstOrNull;
    if (original == null) return (404, {'message': 'Registro não encontrado.'});
    if (original.reversed) {
      return _rejection('receipt', 'Este recebimento já foi estornado.');
    }
    FakeReceipt? replacement;
    if (kind == 'correction') {
      if (accounts[body['account_id']]?.archived ?? false) {
        return _rejection(
          'account_id',
          'Esta conta está arquivada. Escolha uma conta ativa.',
        );
      }
      final cents = _cents(body['amount'] as String);
      final available = remainingCents + original.amountCents;
      if (cents > available) {
        return _rejection(
          'amount',
          'O valor excede o restante da parcela após o estorno (${_money(available)}).',
        );
      }
      replacement = FakeReceipt(
        null,
        body['account_id'] as int,
        cents,
        body['received_on'] as String,
      )..replacesId = original.id;
    }
    original.reversalReason = body['reason'] as String;
    _credit(original.accountId, -original.amountCents);
    if (replacement != null) {
      replacement.id = 100 + receipts.length;
      receipts.add(replacement);
      original.replacementId = replacement.id;
      _credit(replacement.accountId, replacement.amountCents);
    }
    return (
      201,
      {
        'data': {
          'reversal': _reversalJson(original),
          'original': receiptJson(original),
          'replacement': replacement == null ? null : receiptJson(replacement),
          'installment': installmentJson(),
          'agreement': {'remaining': _money(remainingCents)},
          'accounts': [
            for (final accountId in {
              original.accountId,
              ?replacement?.accountId,
            })
              {'id': accountId, 'balance': _money(_balance(accountId))},
          ],
        },
      },
    );
  }

  (int, Object) _rejection(String field, String message) => (
    422,
    {
      'message': message,
      'errors': {
        field: [message],
      },
    },
  );

  void _credit(int accountId, int cents) =>
      accountId == 7 ? balanceCents += cents : reserveCents += cents;
  int _balance(int accountId) => accountId == 7 ? balanceCents : reserveCents;

  Map<String, Object?> receiptJson(FakeReceipt receipt) => {
    'id': receipt.id,
    'installment_id': 22,
    'account_id': receipt.accountId,
    'amount': _money(receipt.amountCents),
    'received_on': receipt.date,
    'status': receipt.reversed ? 'reversed' : 'active',
    'reversal': receipt.reversed ? _reversalJson(receipt) : null,
    'replaces_receipt_id': receipt.replacesId,
  };

  Map<String, Object?> _reversalJson(FakeReceipt receipt) => {
    'id': 500 + receipt.id,
    'kind': receipt.replacementId == null ? 'reversal' : 'correction',
    'receipt_id': receipt.id,
    'replacement_receipt_id': receipt.replacementId,
    'reason': receipt.reversalReason,
    'user_id': 1,
    'reversed_at': '2026-03-10T12:00:00-03:00',
  };

  Map<String, Object?> installmentJson({bool withReceipts = false}) => {
    'id': 22,
    'agreement_id': 5,
    'number': 2,
    'due_date': '2026-03-10',
    'amount': _money(installmentCents),
    'received': _money(receivedCents),
    'remaining': _money(remainingCents),
    'status': remainingCents == 0
        ? 'paid'
        : receivedCents > 0
        ? 'partial'
        : 'pending',
    'overdue': false,
    'agreement': {'description': 'Venda de veículo', 'installment_count': 12},
    if (withReceipts) 'receipts': [for (final r in receipts) receiptJson(r)],
  };

  Map<String, Object?> accountJson(int id, {bool detail = false}) {
    final account = accounts[id]!;
    final dates = receipts.where((r) => r.accountId == id).map((r) => r.date);
    return {
      'id': id,
      'name': account.name,
      'opening_balance': _money(account.openingCents),
      'opening_balance_date': account.openingDate,
      'balance': _money(_balance(id)),
      'archived_at': account.archived ? '2026-03-11T10:00:00-03:00' : null,
      'first_movement_date': dates.isEmpty
          ? null
          : (dates.toList()..sort()).first,
      if (detail) 'opening_adjustments': account.adjustments.reversed.toList(),
    };
  }

  (int, Object) _adjustOpening(FakeAccount account, Map<String, dynamic> body) {
    final cents = _cents(body['opening_balance'] as String);
    final date = body['opening_balance_date'] as String;
    final first = accountJson(account.id)['first_movement_date'] as String?;
    if (first != null && date.compareTo(first) > 0) {
      return _rejection(
        'opening_balance_date',
        'A abertura não pode ficar depois da primeira movimentação da conta.',
      );
    }
    final adjustment = {
      'id': account.adjustments.length + 1,
      'account_id': account.id,
      'previous_opening_balance': _money(account.openingCents),
      'previous_opening_balance_date': account.openingDate,
      'new_opening_balance': _money(cents),
      'new_opening_balance_date': date,
      'reason': body['reason'],
      'user_id': 1,
      'adjusted_at': '2026-03-11T10:00:00-03:00',
    };
    _credit(account.id, cents - account.openingCents);
    account
      ..openingCents = cents
      ..openingDate = date
      ..adjustments.add(adjustment);
    return (
      201,
      {
        'data': {'adjustment': adjustment, 'account': accountJson(account.id)},
      },
    );
  }

  static int _cents(String amount) => int.parse(amount.replaceAll('.', ''));

  static String _money(int cents) =>
      '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';

  static http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// Conta da API simulada.
class FakeAccount {
  FakeAccount(this.id, this.name, this.openingCents);

  final int id;
  String name;
  int openingCents;
  String openingDate = '2026-01-01';
  bool archived = false;
  final List<Map<String, Object?>> adjustments = [];
}
