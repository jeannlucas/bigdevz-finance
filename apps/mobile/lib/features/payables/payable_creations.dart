import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../core/api_client.dart';
import '../../core/token_storage.dart';
import '../agreements/receipt_attempt.dart'
    show
        ReceiptAttemptState,
        UncertainReason,
        isRecordedRejection,
        uncertainReasonFor;
import 'payable.dart';
import 'payables_repository.dart';

/// Cadastro de A pagar enviado (ou prestes a ser enviado): chave e conteúdo
/// exatos guardados no armazenamento seguro antes do envio, por usuário e
/// espaço. O rascunho (formulário) não é guardado; a partir do envio, a
/// tentativa só sai daqui com confirmação ou recusa registrada pela API.
class PendingCreation {
  const PendingCreation({
    required this.userId,
    required this.spaceId,
    required this.idempotencyKey,
    required this.body,
  });

  factory PendingCreation.fromJson(Map<String, dynamic> json) =>
      PendingCreation(
        userId: json['user_id'] as int,
        spaceId: json['space_id'] as int,
        idempotencyKey: json['idempotency_key'] as String,
        body: Map<String, Object?>.from(json['body'] as Map),
      );

  final int userId;
  final int spaceId;
  final String idempotencyKey;

  /// Conteúdo exato enviado à API (inclui o período aprovado da recorrência).
  final Map<String, Object?> body;

  String get description => body['description'] as String? ?? '';

  String get kindLabel => switch (body['kind']) {
    'installment' => 'Parcelada (${body['installment_count']} parcelas)',
    'recurring' => 'Recorrente',
    _ => 'Avulsa',
  };

  Map<String, Object?> toJson() => {
    'user_id': userId,
    'space_id': spaceId,
    'idempotency_key': idempotencyKey,
    'body': body,
  };

  /// Um cadastro pendente por espaço: bloqueia iniciar outro até verificar.
  static String storageKey(int userId, int spaceId) =>
      'pending_payable_create.$userId.$spaceId';
}

class CreationOutcome {
  const CreationOutcome(
    this.state,
    this.pending, {
    this.payables = const [],
    this.replayed = false,
    this.error,
    this.reason,
  });

  final ReceiptAttemptState state;
  final PendingCreation pending;

  /// Conjunto original criado (o mesmo num reenvio).
  final List<Payable> payables;
  final bool replayed;
  final ApiException? error;
  final UncertainReason? reason;

  String get message => switch (state) {
    ReceiptAttemptState.confirmed =>
      '${replayed ? 'Cadastro já estava registrado' : 'Cadastro confirmado'}: '
          '${pending.description}, ${payables.length} '
          '${payables.length == 1 ? 'obrigação' : 'obrigações'}.',
    ReceiptAttemptState.rejected =>
      'A API recusou o cadastro e nada foi gravado. Revise os dados.',
    _ => switch (reason) {
      UncertainReason.unauthorized =>
        'Sua sessão expirou. Entre novamente com o mesmo usuário para '
            'verificar; o cadastro continua guardado neste aparelho.',
      UncertainReason.conflict =>
        'A API informa que esta identificação já foi usada com outros dados. '
            'O cadastro continua pendente.',
      _ =>
        '${error?.isNetwork == true ? '${error!.message} ' : ''}Ainda não '
            'conseguimos confirmar este cadastro. Verifique antes de '
            'cadastrar outro.',
    },
  };
}

/// Envia cadastros de A pagar sem duplicar por resposta perdida. Verificar
/// reenvia a mesma chave e conteúdo: a API devolve o conjunto já criado ou
/// conclui o cadastro uma única vez.
class PayableCreations {
  PayableCreations({
    required this._repository,
    required this._storage,
    Random? random,
  }) : _random = random ?? Random.secure();

  final PayablesRepository _repository;
  final SessionStorage _storage;
  final Random _random;
  final Map<String, Future<CreationOutcome>> _running = {};

  Future<PendingCreation?> pending(int userId, int spaceId) async {
    final raw = await _storage.read(
      PendingCreation.storageKey(userId, spaceId),
    );
    if (raw == null) return null;
    final pending = PendingCreation.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    return pending.userId == userId && pending.spaceId == spaceId
        ? pending
        : null;
  }

  /// Guarda e envia. Com cadastro pendente no espaço, nada é enviado e ele é
  /// devolvido como incerto. Falha ao guardar propaga: nada foi enviado.
  Future<CreationOutcome> submit(
    int userId,
    int spaceId,
    Map<String, Object?> body,
  ) async {
    final existing = await pending(userId, spaceId);
    if (existing != null) {
      return _running[existing.idempotencyKey] ??
          CreationOutcome(
            ReceiptAttemptState.uncertain,
            existing,
            reason: UncertainReason.unresolved,
          );
    }
    final creation = PendingCreation(
      userId: userId,
      spaceId: spaceId,
      idempotencyKey: List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      body: body,
    );
    await _storage.write(
      PendingCreation.storageKey(userId, spaceId),
      jsonEncode(creation.toJson()),
    );
    return _send(creation);
  }

  Future<CreationOutcome> resolve(PendingCreation creation) => _send(creation);

  Future<CreationOutcome> _send(PendingCreation creation) {
    final key = creation.idempotencyKey;
    return _running[key] ??= _deliver(creation).whenComplete(() {
      _running.remove(key);
    });
  }

  Future<CreationOutcome> _deliver(PendingCreation creation) async {
    final ({List<Payable> payables, bool replayed}) result;
    try {
      result = await _repository.create(
        creation.spaceId,
        creation.body,
        idempotencyKey: creation.idempotencyKey,
      );
    } on ApiException catch (error) {
      if (isRecordedRejection(error)) {
        await _forget(creation);
        return CreationOutcome(
          ReceiptAttemptState.rejected,
          creation,
          error: error,
        );
      }
      return CreationOutcome(
        ReceiptAttemptState.uncertain,
        creation,
        error: error,
        reason: uncertainReasonFor(error),
      );
    } catch (_) {
      return CreationOutcome(
        ReceiptAttemptState.uncertain,
        creation,
        reason: UncertainReason.unreadable,
      );
    }
    // Se a limpeza falhar (ou o app fechar antes), a próxima verificação
    // repete a chave e a API devolve o mesmo conjunto.
    await _forget(creation);
    return CreationOutcome(
      ReceiptAttemptState.confirmed,
      creation,
      payables: result.payables,
      replayed: result.replayed,
    );
  }

  Future<void> _forget(PendingCreation creation) async {
    try {
      await _storage.delete(
        PendingCreation.storageKey(creation.userId, creation.spaceId),
      );
    } catch (_) {
      // Mantido: a verificação seguinte resolve pela mesma chave.
    }
  }
}
