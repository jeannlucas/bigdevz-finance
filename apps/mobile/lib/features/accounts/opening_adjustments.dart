import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/token_storage.dart';
import '../agreements/receipt_attempt.dart'
    show
        ReceiptAttemptState,
        UncertainReason,
        isRecordedRejection,
        uncertainReasonFor;
import 'account.dart';
import 'accounts_repository.dart';

/// Correção de abertura enviada (ou prestes a ser enviada) à API, guardada
/// no armazenamento seguro antes do primeiro envio, por usuário, espaço e
/// conta. Mesmo protocolo dos recebimentos (estados de [ReceiptAttemptState]).
class OpeningAttempt {
  const OpeningAttempt({
    required this.userId,
    required this.spaceId,
    required this.accountId,
    required this.idempotencyKey,
    required this.openingBalance,
    required this.openingDate,
    required this.reason,
    required this.previousBalance,
    required this.previousDate,
  });

  factory OpeningAttempt.fromJson(Map<String, dynamic> json) => OpeningAttempt(
    userId: json['user_id'] as int,
    spaceId: json['space_id'] as int,
    accountId: json['account_id'] as int,
    idempotencyKey: json['idempotency_key'] as String,
    openingBalance: Money.parse(json['opening_balance'] as String),
    openingDate: json['opening_balance_date'] as String,
    reason: json['reason'] as String,
    previousBalance: Money.parse(json['previous_opening_balance'] as String),
    previousDate: json['previous_opening_balance_date'] as String,
  );

  final int userId;
  final int spaceId;
  final int accountId;
  final String idempotencyKey;
  final Money openingBalance;
  final String openingDate;
  final String reason;
  final Money previousBalance;
  final String previousDate;

  Map<String, Object?> toJson() => {
    'user_id': userId,
    'space_id': spaceId,
    'account_id': accountId,
    'idempotency_key': idempotencyKey,
    'opening_balance': openingBalance.toApi(),
    'opening_balance_date': openingDate,
    'reason': reason,
    'previous_opening_balance': previousBalance.toApi(),
    'previous_opening_balance_date': previousDate,
  };

  static String storageKey(int userId, int spaceId, int accountId) =>
      'pending_opening.$userId.$spaceId.$accountId';
}

class OpeningOutcome {
  const OpeningOutcome(
    this.state,
    this.attempt, {
    this.account,
    this.replayed = false,
    this.error,
    this.reason,
  });

  final ReceiptAttemptState state;
  final OpeningAttempt attempt;

  /// Conta atualizada pela API (confirmed).
  final Account? account;
  final bool replayed;
  final ApiException? error;
  final UncertainReason? reason;

  String get message => switch (state) {
    ReceiptAttemptState.confirmed =>
      replayed
          ? 'Correção da abertura já estava registrada.'
          : 'Abertura corrigida.',
    ReceiptAttemptState.rejected =>
      'A API recusou a correção e nada foi gravado. Revise os dados.',
    _ => switch (reason) {
      UncertainReason.unauthorized =>
        'Sua sessão expirou. Entre novamente para verificar; a correção '
            'continua guardada neste aparelho.',
      UncertainReason.conflict =>
        'A API informa que esta identificação já foi usada com outros dados. '
            'A correção continua pendente.',
      _ =>
        '${error?.isNetwork == true ? '${error!.message} ' : ''}Ainda não '
            'conseguimos confirmar esta correção da abertura. Verifique antes '
            'de fazer outra.',
    },
  };
}

/// Envia correções de abertura sem aplicá-las duas vezes. A verificação
/// reenvia a mesma chave e conteúdo; só a recusa registrada libera.
class OpeningAdjustments {
  OpeningAdjustments({
    required this._repository,
    required this._storage,
    Random? random,
  }) : _random = random ?? Random.secure();

  final AccountsRepository _repository;
  final SessionStorage _storage;
  final Random _random;
  final Map<String, Future<OpeningOutcome>> _running = {};

  Future<OpeningAttempt?> pending(
    int userId,
    int spaceId,
    int accountId,
  ) async {
    final raw = await _storage.read(
      OpeningAttempt.storageKey(userId, spaceId, accountId),
    );
    if (raw == null) return null;
    final attempt = OpeningAttempt.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    return attempt.userId == userId &&
            attempt.spaceId == spaceId &&
            attempt.accountId == accountId
        ? attempt
        : null;
  }

  /// Guarda e envia. Com correção pendente na conta, nada é enviado e ela é
  /// devolvida como incerta. Falha ao guardar propaga: nada foi enviado.
  Future<OpeningOutcome> submit({
    required int userId,
    required int spaceId,
    required Account account,
    required Money openingBalance,
    required String openingDate,
    required String reason,
  }) async {
    final existing = await pending(userId, spaceId, account.id);
    if (existing != null) {
      return _running[existing.idempotencyKey] ??
          OpeningOutcome(
            ReceiptAttemptState.uncertain,
            existing,
            reason: UncertainReason.unresolved,
          );
    }
    final attempt = OpeningAttempt(
      userId: userId,
      spaceId: spaceId,
      accountId: account.id,
      idempotencyKey: List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      openingBalance: openingBalance,
      openingDate: openingDate,
      reason: reason,
      previousBalance: account.openingBalance,
      previousDate: account.openingBalanceDate,
    );
    await _storage.write(
      OpeningAttempt.storageKey(userId, spaceId, account.id),
      jsonEncode(attempt.toJson()),
    );
    return _send(attempt);
  }

  Future<OpeningOutcome> resolve(OpeningAttempt attempt) => _send(attempt);

  Future<OpeningOutcome> _send(OpeningAttempt attempt) {
    final key = attempt.idempotencyKey;
    return _running[key] ??= _deliver(attempt).whenComplete(() {
      _running.remove(key);
    });
  }

  Future<OpeningOutcome> _deliver(OpeningAttempt attempt) async {
    final ({Account account, OpeningAdjustment adjustment, bool replayed})
    result;
    try {
      result = await _repository.adjustOpening(
        attempt.spaceId,
        attempt.accountId,
        openingBalance: attempt.openingBalance,
        openingDate: attempt.openingDate,
        reason: attempt.reason,
        idempotencyKey: attempt.idempotencyKey,
      );
    } on ApiException catch (error) {
      if (isRecordedRejection(error)) {
        await _forget(attempt);
        return OpeningOutcome(
          ReceiptAttemptState.rejected,
          attempt,
          error: error,
        );
      }
      return OpeningOutcome(
        ReceiptAttemptState.uncertain,
        attempt,
        error: error,
        reason: uncertainReasonFor(error),
      );
    } catch (_) {
      return OpeningOutcome(
        ReceiptAttemptState.uncertain,
        attempt,
        reason: UncertainReason.unreadable,
      );
    }
    await _forget(attempt);
    return OpeningOutcome(
      ReceiptAttemptState.confirmed,
      attempt,
      account: result.account,
      replayed: result.replayed,
    );
  }

  Future<void> _forget(OpeningAttempt attempt) async {
    try {
      await _storage.delete(
        OpeningAttempt.storageKey(
          attempt.userId,
          attempt.spaceId,
          attempt.accountId,
        ),
      );
    } catch (_) {
      // Mantido: a verificação seguinte resolve pela mesma chave.
    }
  }
}
