import '../../core/api_client.dart';
import '../../core/money.dart';
import 'payable.dart';

class PayablesRepository {
  const PayablesRepository(this._api);

  final ApiClient _api;

  /// [status]: all, open, overdue, paid, cancelled ou awaiting_amount.
  Future<List<Payable>> list(int spaceId, {String status = 'all'}) async =>
      ((await _api.get('/spaces/$spaceId/payables?status=$status'))['data']
              as List)
          .map((item) => Payable.fromJson(item as Map<String, dynamic>))
          .toList();

  Future<Payable> find(int spaceId, int payableId) async {
    final json = await _api.get('/spaces/$spaceId/payables/$payableId');
    return Payable.fromJson(
      json['data'] as Map<String, dynamic>,
      changes: json['changes'] as List?,
    );
  }

  Future<List<ScheduleItem>> preview(
    int spaceId, {
    required Money total,
    required int count,
    required String firstDueDate,
  }) async =>
      ((await _api.post('/spaces/$spaceId/payables/preview', {
                'total': total.toApi(),
                'installment_count': count,
                'first_due_date': firstDueDate,
              }))['data']
              as List)
          .map((item) {
            final map = item as Map<String, dynamic>;
            return (
              number: map['number'] as int,
              amount: Money.parse(map['amount'] as String),
              dueDate: map['due_date'] as String,
            );
          })
          .toList();

  /// Cadastro com chave: repetir a mesma chave não duplica (inclusive
  /// parcelas e ocorrências) e devolve o conjunto original.
  Future<({List<Payable> payables, bool replayed})> create(
    int spaceId,
    Map<String, Object?> body, {
    required String idempotencyKey,
  }) async {
    final data =
        (await _api.post(
              '/spaces/$spaceId/payables',
              body,
              idempotencyKey: idempotencyKey,
            ))['data']
            as Map<String, dynamic>;
    return (
      payables: (data['payables'] as List)
          .map((item) => Payable.fromJson(item as Map<String, dynamic>))
          .toList(),
      replayed: data['replayed'] as bool,
    );
  }

  /// Prévia da recorrência (sem gravar), com as regras da geração.
  Future<RecurrencePreview> recurrencePreview(
    int spaceId, {
    required Money amount,
    required String startDate,
    String? endDate,
  }) async => RecurrencePreview.fromJson(
    (await _api.post('/spaces/$spaceId/payables/recurrence-preview', {
          'amount': amount.toApi(),
          'start_date': startDate,
          'end_date': endDate,
        }))['data']
        as Map<String, dynamic>,
  );

  /// Esta obrigação. Em fatura, [amount] informa ou corrige o total.
  Future<Payable> update(
    int spaceId,
    int payableId,
    Map<String, Object?> body,
  ) async {
    final json = await _api.patch('/spaces/$spaceId/payables/$payableId', body);
    return Payable.fromJson(
      json['data'] as Map<String, dynamic>,
      changes: json['changes'] as List?,
    );
  }

  Future<Payable> cancel(int spaceId, int payableId, String reason) async {
    final json = await _api.post(
      '/spaces/$spaceId/payables/$payableId/cancel',
      {'reason': reason},
    );
    return Payable.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<List<PayableCard>> cards(int spaceId) async =>
      ((await _api.get('/spaces/$spaceId/cards'))['data'] as List)
          .map((item) => PayableCard.fromJson(item as Map<String, dynamic>))
          .toList();

  Future<PayableCard> createCard(int spaceId, String name, int dueDay) async =>
      PayableCard.fromJson(
        (await _api.post('/spaces/$spaceId/cards', {
              'name': name,
              'due_day': dueDay,
            }))['data']
            as Map<String, dynamic>,
      );

  Future<void> setCardArchived(int spaceId, int cardId, bool archived) =>
      _api.post(
        '/spaces/$spaceId/cards/$cardId/${archived ? 'archive' : 'unarchive'}',
        const {},
      );

  Future<List<Recurrence>> recurrences(int spaceId) async =>
      ((await _api.get('/spaces/$spaceId/recurrences'))['data'] as List)
          .map((item) => Recurrence.fromJson(item as Map<String, dynamic>))
          .toList();

  /// Futuras: só ocorrências de hoje em diante sem pagamento e não editadas.
  Future<void> updateRecurrence(
    int spaceId,
    int recurrenceId,
    Map<String, Object?> body,
  ) => _api.patch('/spaces/$spaceId/recurrences/$recurrenceId', body);

  Future<void> endRecurrence(int spaceId, int recurrenceId, String endDate) =>
      _api.post('/spaces/$spaceId/recurrences/$recurrenceId/end', {
        'end_date': endDate,
      });

  Future<PaymentResult> pay(
    int spaceId,
    int payableId, {
    required int accountId,
    required Money amount,
    required String paidOn,
    required String idempotencyKey,
  }) async {
    final data =
        (await _api.post('/spaces/$spaceId/payables/$payableId/payments', {
              'account_id': accountId,
              'amount': amount.toApi(),
              'paid_on': paidOn,
            }, idempotencyKey: idempotencyKey))['data']
            as Map<String, dynamic>;
    return PaymentResult(
      payment: Payment.fromJson(data['payment'] as Map<String, dynamic>),
      payable: Payable.fromJson(data['payable'] as Map<String, dynamic>),
      accountBalance: Money.parse(
        (data['account'] as Map<String, dynamic>)['balance'] as String,
      ),
      replayed: data['replayed'] as bool,
    );
  }

  /// Estorno (sem [replacement]) ou correção de um pagamento.
  Future<PaymentFixResult> fixPayment(
    int spaceId,
    int paymentId, {
    required String reason,
    required String idempotencyKey,
    ({int accountId, Money amount, String paidOn})? replacement,
  }) async {
    final data =
        (await _api.post(
              '/spaces/$spaceId/payments/$paymentId/'
              '${replacement == null ? 'reversal' : 'correction'}',
              {
                'reason': reason,
                if (replacement != null) ...{
                  'account_id': replacement.accountId,
                  'amount': replacement.amount.toApi(),
                  'paid_on': replacement.paidOn,
                },
              },
              idempotencyKey: idempotencyKey,
            ))['data']
            as Map<String, dynamic>;
    final replacementJson = data['replacement'] as Map<String, dynamic>?;
    return PaymentFixResult(
      original: Payment.fromJson(data['original'] as Map<String, dynamic>),
      replacement: replacementJson == null
          ? null
          : Payment.fromJson(replacementJson),
      payable: Payable.fromJson(data['payable'] as Map<String, dynamic>),
      accountBalances: {
        for (final account in data['accounts'] as List)
          (account as Map<String, dynamic>)['id'] as int: Money.parse(
            account['balance'] as String,
          ),
      },
      replayed: data['replayed'] as bool,
    );
  }
}
