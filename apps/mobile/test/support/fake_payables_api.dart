import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_receipts_api.dart' show Delivery;

class FakePayment {
  FakePayment(this.id, this.accountId, this.cents, this.date);

  final int id;
  final int accountId;
  final int cents;
  final String date;
  String? reversalReason;
  int? replacementId;
  int? replacesId;

  bool get reversed => reversalReason != null;
}

class FakePayable {
  FakePayable(
    this.id,
    this.description,
    this.amountCents, {
    this.kind = 'single',
  });

  final int id;
  final String kind;
  String description;
  int? amountCents;
  String dueDate = '2026-03-20';
  String? cancelReason;
  final List<FakePayment> payments = [];

  int get paidCents =>
      payments.where((p) => !p.reversed).fold(0, (t, p) => t + p.cents);
}

/// API em memória de A pagar no espaço 1, com a regra da API Laravel: cada
/// chave tem decisão guardada (concluída ou recusada) devolvida em repetições;
/// conteúdo diferente é 409. Pagamento sai da conta; estorno devolve.
/// Simula efeitos; não comprova persistência nem concorrência reais.
class FakePayablesApi {
  FakePayablesApi() {
    payables[40] = FakePayable(40, 'Conserto', 30000);
  }

  final Map<int, FakePayable> payables = {};
  final Map<int, int> balances = {7: 100000, 8: 0};
  final Map<int, String> names = {7: 'Banco PF', 8: 'Reserva PF'};
  final List<http.Request> requests = [];
  final List<Delivery> script = [];
  final Map<String, ({String fingerprint, int status, Object body})> decisions =
      {};
  int _nextPayment = 500;

  /// "Hoje" e horizonte da API simulada.
  String today = '2026-03-15';
  String horizon = '2027-03-01';

  /// Vencimentos mensais (dia do início, limitado a 28 nesta simulação) até [until].
  static List<String> recurrenceCycles(String start, String until) {
    final day = int.parse(start.substring(8))
        .clamp(1, 28)
        .toString()
        .padLeft(2, '0');
    var year = int.parse(start.substring(0, 4));
    var month = int.parse(start.substring(5, 7));
    final dates = <String>[];
    while ('$year-${month.toString().padLeft(2, '0')}-01'.compareTo(until) <=
        0) {
      dates.add('$year-${month.toString().padLeft(2, '0')}-$day');
      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
    }
    return dates;
  }

  int _nextPayable = 41;

  /// Se definido, a próxima escrita espera este sinal antes de ser
  /// processada (simula a API ainda gravando).
  Completer<void>? hold;

  List<http.Request> get writes =>
      requests.where((r) => r.method != 'GET').toList();
  List<FakePayment> get allPayments => [
    for (final p in payables.values) ...p.payments,
  ];

  MockClient get client => MockClient(handle);

  FakePayable addCardBill() {
    final bill = FakePayable(
      _nextPayable++,
      'Fatura Cartão 03/2026',
      null,
      kind: 'card_bill',
    );
    payables[bill.id] = bill;
    return bill;
  }

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path.replaceFirst('/api', '');
    if (request.method == 'GET' && path == '/spaces/1/accounts') {
      return _json({
        'data': [
          for (final id in balances.keys)
            {
              'id': id,
              'name': names[id],
              'opening_balance': id == 7 ? '1000.00' : '0.00',
              'opening_balance_date': '2026-01-01',
              'balance': _money(balances[id]!),
              'archived_at': null,
            },
        ],
      });
    }
    if (request.method == 'GET' && path == '/spaces/1/payables') {
      return _json({
        'data': [for (final p in payables.values) payableJson(p)],
      });
    }
    final one = RegExp(r'^/spaces/1/payables/(\d+)(/payments|/cancel)?$')
        .firstMatch(path);
    final fix = RegExp(r'^/spaces/1/payments/(\d+)/(reversal|correction)$')
        .firstMatch(path);
    if (one != null && payables[int.parse(one.group(1)!)] == null) {
      return _json({'message': 'Registro não encontrado.'}, 404);
    }
    final payable = one == null ? null : payables[int.parse(one.group(1)!)];
    if (payable != null && request.method == 'GET') {
      return _json({'data': payableJson(payable, detail: true), 'changes': []});
    }
    if (payable != null && request.method == 'PATCH') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['amount'] != null) {
        payable.amountCents = _cents(body['amount'] as String);
      }
      payable.description =
          body['description'] as String? ?? payable.description;
      return _json({'data': payableJson(payable, detail: true), 'changes': []});
    }
    if (payable != null && one!.group(2) == '/cancel') {
      if (payable.paidCents > 0) {
        return _rejectionResponse(
          'payable',
          'Estorne os pagamentos antes de cancelar.',
        );
      }
      payable.cancelReason =
          (jsonDecode(request.body) as Map)['reason'] as String;
      return _json({'data': payableJson(payable, detail: true)});
    }
    if (path == '/spaces/1/payables/recurrence-preview') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final cycles = recurrenceCycles(body['start_date'] as String, horizon);
      final amount = _cents(body['amount'] as String);
      final past = cycles.where((due) => due.compareTo(today) < 0).length;
      return _json({
        'data': {
          'start_date': body['start_date'],
          'reference_day': int.parse(
            (body['start_date'] as String).substring(8),
          ),
          'end_date': body['end_date'],
          'today': today,
          'horizon': horizon,
          'approved_until': '${cycles.last.substring(0, 7)}-01',
          'first_due_date': cycles.first,
          'last_due_date': cycles.last,
          'count': cycles.length,
          'past_count': past,
          'past_total': _money(past * amount),
          'total': _money(cycles.length * amount),
          'items': [
            for (final due in cycles.take(24))
              {
                'cycle': '${due.substring(0, 7)}-01',
                'due_date': due,
                'amount': _money(amount),
                'past': due.compareTo(today) < 0,
              },
          ],
          'items_shown': cycles.length < 24 ? cycles.length : 24,
        },
      });
    }
    if (path == '/spaces/1/payables/preview') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final total = _cents(body['total'] as String);
      final count = body['installment_count'] as int;
      return _json({
        'data': [
          for (var i = 0; i < count; i++)
            {
              'number': i + 1,
              'amount': _money(total ~/ count + (i < total % count ? 1 : 0)),
              'due_date': '2026-0${3 + i}-10',
            },
        ],
      });
    }

    final gate = hold;
    hold = null;
    final delivery = script.isEmpty ? Delivery.normal : script.removeAt(0);
    switch (delivery) {
      case Delivery.dropBeforeServer:
        throw http.ClientException('Connection closed before full header');
      case Delivery.serverError:
        return _json({'message': 'Server Error'}, 500);
      case Delivery.unauthorized:
        return _json({
          'message': 'Sessão expirada ou inválida. Entre novamente.',
        }, 401);
      case Delivery.conflict:
        return _json({'message': 'Esta chave já foi usada.'}, 409);
      case Delivery.unrecordedRejection:
        return _json({
          'message': 'Recusado.',
          'errors': {
            'amount': ['Recusado.'],
          },
        }, 422);
      default:
        break;
    }
    if (gate != null) await gate.future;
    final key = request.headers['Idempotency-Key']!;
    final response = _decide(key, '$path|${request.body}', () {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (path == '/spaces/1/payables') return _create(body);
      if (fix != null) {
        return _fix(int.parse(fix.group(1)!), fix.group(2)!, body);
      }
      return _pay(payable!, body);
    });
    if (delivery == Delivery.loseResponse) {
      throw http.ClientException('Connection reset by peer');
    }
    return response;
  }

  (int, Object) _create(Map<String, dynamic> body) {
    if (body['amount'] == '0.01') {
      return _rejection('amount', 'Valor recusado pelo teste.');
    }
    final created = <FakePayable>[];
    final count = body['kind'] == 'recurring'
        ? recurrenceCycles(
            body['start_date'] as String,
            body['approved_until'] as String,
          ).length
        : body['installment_count'] as int? ?? 1;
    final total = body['kind'] == 'recurring'
        ? _cents(body['amount'] as String) * count
        : _cents((body['total'] ?? body['amount']) as String);
    for (var i = 0; i < count; i++) {
      final item = FakePayable(
        _nextPayable++,
        body['description'] as String,
        total ~/ count + (i < total % count ? 1 : 0),
        kind: body['kind'] as String,
      );
      payables[item.id] = item;
      created.add(item);
    }
    return (
      201,
      {
        'data': {
          'payables': [for (final p in created) payableJson(p)],
          'recurrence': null,
        },
      },
    );
  }

  (int, Object) _pay(FakePayable payable, Map<String, dynamic> body) {
    final cents = _cents(body['amount'] as String);
    if (payable.amountCents == null) {
      return _rejection('payable', 'Informe o total da fatura antes de pagar.');
    }
    if (cents > payable.amountCents! - payable.paidCents) {
      return _rejection('amount', 'O valor excede o restante da obrigação.');
    }
    final payment = FakePayment(
      _nextPayment++,
      body['account_id'] as int,
      cents,
      body['paid_on'] as String,
    );
    payable.payments.add(payment);
    balances[payment.accountId] = balances[payment.accountId]! - cents;
    return (
      201,
      {
        'data': {
          'payment': _paymentJson(payment),
          'payable': payableJson(payable),
          'account': {'balance': _money(balances[payment.accountId]!)},
        },
      },
    );
  }

  (int, Object) _fix(int paymentId, String kind, Map<String, dynamic> body) {
    final payable = payables.values.firstWhere(
      (p) => p.payments.any((x) => x.id == paymentId),
    );
    final original = payable.payments.firstWhere((p) => p.id == paymentId);
    if (original.reversed) {
      return _rejection('payment', 'Este pagamento já foi estornado.');
    }
    original.reversalReason = body['reason'] as String;
    balances[original.accountId] =
        balances[original.accountId]! + original.cents;
    FakePayment? replacement;
    if (kind == 'correction') {
      replacement = FakePayment(
        _nextPayment++,
        body['account_id'] as int,
        _cents(body['amount'] as String),
        body['paid_on'] as String,
      )..replacesId = original.id;
      original.replacementId = replacement.id;
      payable.payments.add(replacement);
      balances[replacement.accountId] =
          balances[replacement.accountId]! - replacement.cents;
    }
    return (
      201,
      {
        'data': {
          'original': _paymentJson(original),
          'replacement': replacement == null ? null : _paymentJson(replacement),
          'payable': payableJson(payable),
          'accounts': [
            for (final id in {original.accountId, ?replacement?.accountId})
              {'id': id, 'balance': _money(balances[id]!)},
          ],
        },
      },
    );
  }

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

  (int, Object) _rejection(String field, String message) => (
    422,
    {
      'message': message,
      'errors': {
        field: [message],
      },
    },
  );

  http.Response _rejectionResponse(String field, String message) {
    final (status, body) = _rejection(field, message);
    return _json(body, status);
  }

  Map<String, Object?> payableJson(FakePayable p, {bool detail = false}) {
    final remaining = p.amountCents == null
        ? null
        : p.amountCents! - p.paidCents;
    return {
      'id': p.id,
      'space_id': 1,
      'kind': p.kind,
      'description': p.description,
      'payee': 'Oficina',
      'amount': p.amountCents == null ? null : _money(p.amountCents!),
      'paid': _money(p.paidCents),
      'remaining': remaining == null ? null : _money(remaining),
      'due_date': p.dueDate,
      'status': p.cancelReason != null
          ? 'cancelled'
          : p.amountCents == null
          ? 'awaiting_amount'
          : remaining == 0
          ? 'paid'
          : p.paidCents > 0
          ? 'partial'
          : 'open',
      'overdue': false,
      'plan': null,
      'recurrence_id': null,
      'card': p.kind == 'card_bill' ? {'id': 3, 'name': 'Cartão Azul'} : null,
      'cancel_reason': p.cancelReason,
      if (detail) 'payments': [for (final x in p.payments) _paymentJson(x)],
    };
  }

  Map<String, Object?> _paymentJson(FakePayment p) => {
    'id': p.id,
    'payable_id': 40,
    'account_id': p.accountId,
    'amount': _money(p.cents),
    'paid_on': p.date,
    'status': p.reversed ? 'reversed' : 'active',
    'reversal': p.reversed
        ? {
            'kind': p.replacementId == null ? 'reversal' : 'correction',
            'reason': p.reversalReason,
          }
        : null,
    'replaces_payment_id': p.replacesId,
  };

  static int _cents(String amount) => int.parse(amount.replaceAll('.', ''));

  static String _money(int cents) =>
      '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';

  static http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
