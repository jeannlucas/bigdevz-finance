import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/token_storage.dart';
import 'agreement.dart';
import '../payables/payable.dart';
import '../payables/payables_repository.dart';
import 'agreements_repository.dart';
import 'receipt_attempt.dart';

export 'receipt_attempt.dart';

/// Envia recebimentos, estornos e correções sem permitir duplicação por
/// resultado incerto.
///
/// A verificação reenvia a mesma chave com o mesmo conteúdo: a API serializa
/// a chave e devolve a decisão já tomada (o registro criado ou a recusa) ou
/// a toma uma única vez. Uma consulta "não encontrado" não provaria nada com
/// o original ainda em curso; por isso não há endpoint de consulta.
///
/// Só uma recusa com `idempotency.status = rejected` para a mesma chave
/// libera correção: a API guarda essa decisão e a devolve em qualquer
/// repetição, mesmo que um estorno reabra a parcela depois.
class ReceiptAttempts {
  ReceiptAttempts({
    required this._repository,
    required this._storage,
    this._payables,
    Random? random,
  }) : _random = random ?? Random.secure();

  final AgreementsRepository _repository;

  /// Pagamentos usam a mesma infraestrutura com chaves e registros próprios.
  final PayablesRepository? _payables;
  final SessionStorage _storage;
  final Random _random;

  /// Envios em andamento por chave: toques e telas repetidos compartilham a
  /// mesma requisição.
  final Map<String, Future<ReceiptAttemptOutcome>> _running = {};

  /// Tentativa pendente desta parcela para este usuário e espaço, se houver.
  Future<ReceiptAttempt?> pending(
    int userId,
    int spaceId,
    int installmentId,
  ) async {
    final raw = await _storage.read(
      ReceiptAttempt.storageKey(userId, spaceId, installmentId),
    );
    if (raw == null) return null;
    final attempt = ReceiptAttempt.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    // O registro só vale para o contexto em que foi criado.
    if (attempt.userId != userId ||
        attempt.spaceId != spaceId ||
        attempt.installmentId != installmentId) {
      return null;
    }
    return attempt;
  }

  /// Tentativa pendente de pagamento desta obrigação, se houver.
  Future<ReceiptAttempt?> pendingPayment(
    int userId,
    int spaceId,
    int payableId,
  ) async {
    final raw = await _storage.read(
      ReceiptAttempt.paymentStorageKey(userId, spaceId, payableId),
    );
    if (raw == null) return null;
    final attempt = ReceiptAttempt.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    return attempt.userId == userId &&
            attempt.spaceId == spaceId &&
            attempt.payableId == payableId
        ? attempt
        : null;
  }

  /// Guarda um pagamento e o envia. Ver [_start].
  Future<ReceiptAttemptOutcome> submitPayment({
    required int userId,
    required int spaceId,
    required int payableId,
    required int accountId,
    required String accountName,
    required Money amount,
    required String paidOn,
  }) => _start(
    ReceiptAttempt(
      userId: userId,
      spaceId: spaceId,
      installmentId: 0,
      payableId: payableId,
      idempotencyKey: _newKey(),
      operation: ReceiptOperation.payment,
      accountId: accountId,
      accountName: accountName,
      amount: amount,
      receivedOn: paidOn,
    ),
  );

  /// Guarda um estorno (sem [replacement]) ou correção de pagamento e envia.
  Future<ReceiptAttemptOutcome> submitPaymentFix({
    required int userId,
    required int spaceId,
    required int payableId,
    required Payment original,
    required String originalAccountName,
    required String reason,
    ({int accountId, String accountName, Money amount, String receivedOn})?
    replacement,
  }) => _start(
    ReceiptAttempt(
      userId: userId,
      spaceId: spaceId,
      installmentId: 0,
      payableId: payableId,
      idempotencyKey: _newKey(),
      operation: replacement == null
          ? ReceiptOperation.paymentReversal
          : ReceiptOperation.paymentCorrection,
      targetReceiptId: original.id,
      reason: reason,
      accountId: replacement?.accountId ?? original.accountId,
      accountName: replacement?.accountName ?? originalAccountName,
      amount: replacement?.amount ?? original.amount,
      receivedOn: replacement?.receivedOn ?? original.paidOn,
      originalAmount: original.amount,
      originalAccountName: originalAccountName,
      originalReceivedOn: original.paidOn,
    ),
  );

  /// Guarda um novo recebimento e o envia. Ver [_start].
  Future<ReceiptAttemptOutcome> submit({
    required int userId,
    required int spaceId,
    required int installmentId,
    required int accountId,
    required String accountName,
    required Money amount,
    required String receivedOn,
    required ReceiptKind kind,
  }) => _start(
    ReceiptAttempt(
      userId: userId,
      spaceId: spaceId,
      installmentId: installmentId,
      idempotencyKey: _newKey(),
      accountId: accountId,
      accountName: accountName,
      amount: amount,
      receivedOn: receivedOn,
      kind: kind,
    ),
  );

  /// Guarda um estorno (sem [replacement]) ou uma correção e envia. Ver
  /// [_start].
  Future<ReceiptAttemptOutcome> submitFix({
    required int userId,
    required int spaceId,
    required int installmentId,
    required Receipt original,
    required String originalAccountName,
    required String reason,
    ({int accountId, String accountName, Money amount, String receivedOn})?
    replacement,
  }) => _start(
    ReceiptAttempt(
      userId: userId,
      spaceId: spaceId,
      installmentId: installmentId,
      idempotencyKey: _newKey(),
      operation: replacement == null
          ? ReceiptOperation.reversal
          : ReceiptOperation.correction,
      targetReceiptId: original.id,
      reason: reason,
      accountId: replacement?.accountId ?? original.accountId,
      accountName: replacement?.accountName ?? originalAccountName,
      amount: replacement?.amount ?? original.amount,
      receivedOn: replacement?.receivedOn ?? original.receivedOn,
      originalAmount: original.amount,
      originalAccountName: originalAccountName,
      originalReceivedOn: original.receivedOn,
    ),
  );

  /// Reenvia exatamente a tentativa guardada (mesma chave e conteúdo).
  Future<ReceiptAttemptOutcome> resolve(ReceiptAttempt attempt) =>
      _send(attempt);

  /// Se a parcela já tem tentativa pendente, nada é enviado e ela é
  /// devolvida como incerta para resolução. Falha ao guardar propaga a
  /// exceção: nesse caso nada foi enviado.
  Future<ReceiptAttemptOutcome> _start(ReceiptAttempt attempt) async {
    final existing = attempt.operation.isPayment
        ? await pendingPayment(
            attempt.userId,
            attempt.spaceId,
            attempt.payableId!,
          )
        : await pending(attempt.userId, attempt.spaceId, attempt.installmentId);
    if (existing != null) {
      return _running[existing.idempotencyKey] ??
          ReceiptAttemptOutcome(
            ReceiptAttemptState.uncertain,
            existing,
            reason: UncertainReason.unresolved,
          );
    }
    await _storage.write(attempt.storageKeyValue, jsonEncode(attempt.toJson()));
    return _send(attempt);
  }

  Future<ReceiptAttemptOutcome> _send(ReceiptAttempt attempt) {
    final key = attempt.idempotencyKey;
    // O callback não pode devolver o Future removido: whenComplete esperaria
    // por ele mesmo.
    return _running[key] ??= _deliver(attempt).whenComplete(() {
      _running.remove(key);
    });
  }

  Future<ReceiptAttemptOutcome> _deliver(ReceiptAttempt attempt) async {
    ReceiptResult? result;
    ReceiptFixResult? fix;
    PaymentResult? payment;
    PaymentFixResult? paymentFix;
    try {
      if (attempt.operation == ReceiptOperation.payment) {
        payment = await _payables!.pay(
          attempt.spaceId,
          attempt.payableId!,
          accountId: attempt.accountId,
          amount: attempt.amount,
          paidOn: attempt.receivedOn,
          idempotencyKey: attempt.idempotencyKey,
        );
      } else if (attempt.operation.isPayment) {
        paymentFix = await _payables!.fixPayment(
          attempt.spaceId,
          attempt.targetReceiptId!,
          reason: attempt.reason!,
          idempotencyKey: attempt.idempotencyKey,
          replacement: attempt.operation == ReceiptOperation.paymentCorrection
              ? (
                  accountId: attempt.accountId,
                  amount: attempt.amount,
                  paidOn: attempt.receivedOn,
                )
              : null,
        );
      } else if (attempt.operation == ReceiptOperation.receipt) {
        result = await _repository.receive(
          attempt.spaceId,
          attempt.installmentId,
          accountId: attempt.accountId,
          amount: attempt.amount,
          receivedOn: attempt.receivedOn,
          idempotencyKey: attempt.idempotencyKey,
        );
      } else {
        fix = await _repository.fix(
          attempt.spaceId,
          attempt.targetReceiptId!,
          reason: attempt.reason!,
          idempotencyKey: attempt.idempotencyKey,
          replacement: attempt.operation == ReceiptOperation.correction
              ? (
                  accountId: attempt.accountId,
                  amount: attempt.amount,
                  receivedOn: attempt.receivedOn,
                )
              : null,
        );
      }
    } on ApiException catch (error) {
      if (isRecordedRejection(error)) {
        await _forget(attempt);
        return ReceiptAttemptOutcome(
          ReceiptAttemptState.rejected,
          attempt,
          error: error,
        );
      }
      return ReceiptAttemptOutcome(
        ReceiptAttemptState.uncertain,
        attempt,
        error: error,
        reason: uncertainReasonFor(error),
      );
    } catch (_) {
      return ReceiptAttemptOutcome(
        ReceiptAttemptState.uncertain,
        attempt,
        reason: UncertainReason.unreadable,
      );
    }
    // Se o registro local não puder ser apagado (ou o app fechar antes), a
    // próxima verificação repete a mesma chave e a API responde "já
    // registrado", sem duplicar.
    await _forget(attempt);
    return ReceiptAttemptOutcome(
      ReceiptAttemptState.confirmed,
      attempt,
      result: result,
      fix: fix,
      payment: payment,
      paymentFix: paymentFix,
    );
  }

  Future<void> _forget(ReceiptAttempt attempt) async {
    try {
      await _storage.delete(attempt.storageKeyValue);
    } catch (_) {
      // Mantido: a verificação seguinte resolve pela mesma chave.
    }
  }

  String _newKey() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
