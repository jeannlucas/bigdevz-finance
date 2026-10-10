import 'dart:async';
import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/agreements/agreement.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/receipt_attempts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';
import '../support/fake_receipts_api.dart';

/// Armazenamento que pode falhar ao apagar (app fechado antes da limpeza).
class FlakyStorage extends MemorySessionStorage {
  bool failDeletes = false;
  bool failWrites = false;

  @override
  Future<void> delete(String key) async {
    if (failDeletes) throw StateError('app encerrado');
    return super.delete(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('armazenamento indisponível');
    return super.write(key, value);
  }
}

// Efeitos financeiros medidos na API simulada (mesma regra de chave da API
// Laravel). Persistência e concorrência reais: testes PHP em PostgreSQL.
void main() {
  late FakeReceiptsApi api;
  late FlakyStorage storage;

  ReceiptAttempts service({Duration timeout = const Duration(seconds: 15)}) =>
      ReceiptAttempts(
        repository: AgreementsRepository(
          ApiClient(
            baseUrl: 'http://api.test/api',
            client: api.client,
            timeout: timeout,
          ),
        ),
        storage: storage,
      );

  Future<ReceiptAttemptOutcome> submit(
    ReceiptAttempts attempts, {
    String amount = '500.00',
    int accountId = 7,
    String date = '2026-03-10',
    int userId = 1,
  }) => attempts.submit(
    userId: userId,
    spaceId: 1,
    installmentId: 22,
    accountId: accountId,
    accountName: accountId == 7 ? 'Banco PF' : 'Reserva PF',
    amount: Money.parse(amount),
    receivedOn: date,
    kind: ReceiptKind.partial,
  );

  Set<String?> keys() =>
      api.receiptRequests.map((r) => r.headers['Idempotency-Key']).toSet();
  Set<String> bodies() => api.receiptRequests.map((r) => r.body).toSet();

  setUp(() {
    // Parcela de R$ 2.000,00: dois recebimentos de R$ 500,00 caberiam, então
    // o limite da parcela não mascara uma duplicação.
    api = FakeReceiptsApi(installmentCents: 200000, balanceCents: 100000);
    storage = FlakyStorage();
  });

  test('guarda chave e conteúdo exatos antes do primeiro envio', () async {
    final gate = api.hold = Completer<void>();
    final attempts = service();
    final sending = submit(attempts);
    await pumpEventQueue();

    final stored = await attempts.pending(1, 1, 22);
    expect(api.receiptRequests, hasLength(1), reason: 'já em envio');
    expect(stored, isNotNull, reason: 'guardada antes da resposta');
    expect(
      stored!.idempotencyKey,
      api.receiptRequests.single.headers['Idempotency-Key'],
    );
    expect(jsonDecode(api.receiptRequests.single.body), {
      'account_id': 7,
      'amount': '500.00',
      'received_on': '2026-03-10',
    });

    gate.complete();
    expect((await sending).state, ReceiptAttemptState.confirmed);
    expect(await attempts.pending(1, 1, 22), isNull);
  });

  test('falha ao guardar não envia nada', () async {
    storage.failWrites = true;
    await expectLater(submit(service()), throwsStateError);
    expect(api.requests, isEmpty);
  });

  test(
    'resposta perdida após gravar: outra tentativa na parcela não é enviada; '
    'a verificação usa a chave original e não duplica',
    () async {
      api.script.add(Delivery.loseResponse);
      final attempts = service();
      final first = await submit(attempts);
      expect(first.state, ReceiptAttemptState.uncertain);
      expect(api.receipts, hasLength(1), reason: 'a API gravou');

      // Outro valor, conta e data para a mesma parcela: nada sai.
      final other = await submit(
        attempts,
        amount: '400.00',
        accountId: 8,
        date: '2026-03-09',
      );
      expect(other.state, ReceiptAttemptState.uncertain);
      expect(other.attempt.idempotencyKey, first.attempt.idempotencyKey);
      expect(api.receiptRequests, hasLength(1));

      final resolved = await attempts.resolve(other.attempt);
      expect(resolved.state, ReceiptAttemptState.confirmed);
      expect(resolved.result!.replayed, isTrue);
      expect(keys(), hasLength(1));
      expect(bodies(), hasLength(1));
      expect(api.receipts, hasLength(1));
      expect(api.receivedCents, 50000);
      expect(api.balanceCents, 150000, reason: 'saldo muda uma única vez');
      expect(await attempts.pending(1, 1, 22), isNull);
    },
  );

  test(
    'chamada que não chegou à API: a verificação conclui uma única operação',
    () async {
      api.script.add(Delivery.dropBeforeServer);
      final attempts = service();
      final first = await submit(attempts);
      expect(first.state, ReceiptAttemptState.uncertain);
      expect(api.receipts, isEmpty);

      final resolved = await attempts.resolve(first.attempt);
      expect(resolved.state, ReceiptAttemptState.confirmed);
      expect(resolved.result!.replayed, isFalse);
      expect(keys(), hasLength(1));
      expect(api.receipts, hasLength(1));
      expect(api.balanceCents, 150000);
    },
  );

  test(
    'primeira chamada ainda em processamento: verificação e original resultam '
    'em um único recebimento',
    () async {
      api.hold = Completer<void>();
      final attempts = service(timeout: const Duration(milliseconds: 50));
      final first = await submit(attempts);
      expect(first.state, ReceiptAttemptState.uncertain);
      expect(first.reason, UncertainReason.network);
      final original = api.hold;
      expect(original, isNull, reason: 'o original consumiu a espera');

      // Verificação enquanto o original segue retido na API.
      final resolved = await attempts.resolve(first.attempt);
      expect(resolved.state, ReceiptAttemptState.confirmed);
      expect(api.receipts, hasLength(1));

      // O original termina depois: encontra a chave e não grava de novo.
      await pumpEventQueue();
      expect(api.receipts, hasLength(1));
      expect(api.balanceCents, 150000);
      expect(keys(), hasLength(1));
    },
  );

  test('verificação que falha de novo mantém a tentativa pendente', () async {
    api.script.addAll([
      Delivery.loseResponse,
      Delivery.serverError,
      Delivery.dropBeforeServer,
    ]);
    final attempts = service();
    final first = await submit(attempts);

    final again = await attempts.resolve(first.attempt);
    expect(again.state, ReceiptAttemptState.uncertain);
    expect(again.reason, UncertainReason.server);
    final third = await attempts.resolve(first.attempt);
    expect(third.state, ReceiptAttemptState.uncertain);
    expect(third.reason, UncertainReason.network);

    expect(await attempts.pending(1, 1, 22), isNotNull);
    expect(
      (await submit(attempts, amount: '100.00')).attempt.idempotencyKey,
      first.attempt.idempotencyKey,
    );
    expect(keys(), hasLength(1));
    expect(api.receipts, hasLength(1));
  });

  test('401, 404, 409 e resposta ilegível não liberam nova operação', () async {
    api.script.addAll([
      Delivery.unreadable,
      Delivery.unauthorized,
      Delivery.notFound,
      Delivery.conflict,
    ]);
    final attempts = service();
    final first = await submit(attempts);
    expect(first.reason, UncertainReason.unreadable);
    expect(api.receipts, hasLength(1), reason: 'gravou antes da resposta');

    for (final reason in [
      UncertainReason.unauthorized,
      UncertainReason.inaccessible,
      UncertainReason.conflict,
    ]) {
      final outcome = await attempts.resolve(first.attempt);
      expect(outcome.state, ReceiptAttemptState.uncertain);
      expect(outcome.reason, reason);
      expect(await attempts.pending(1, 1, 22), isNotNull);
    }

    final resolved = await attempts.resolve(first.attempt);
    expect(resolved.result!.replayed, isTrue);
    expect(api.receipts, hasLength(1));
    expect(api.balanceCents, 150000);
    expect(keys(), hasLength(1));
  });

  test(
    'recusa 422 prova que nada foi gravado e libera nova tentativa',
    () async {
      final attempts = service();
      final refused = await submit(attempts, amount: '2000.01');
      expect(refused.state, ReceiptAttemptState.rejected);
      expect(refused.error!.fieldErrors['amount'], contains('excede'));
      expect(api.receipts, isEmpty);
      expect(await attempts.pending(1, 1, 22), isNull);

      final fixed = await submit(attempts, amount: '500.00');
      expect(fixed.state, ReceiptAttemptState.confirmed);
      expect(keys(), hasLength(2), reason: 'nova operação, nova chave');
      expect(api.receipts, hasLength(1));
      expect(api.balanceCents, 150000);
    },
  );

  test('app recriado restaura a tentativa só para o mesmo usuário, espaço e parcela', () async {
    api.script.add(Delivery.loseResponse);
    final first = await submit(service());

    final reopened = service();
    expect(await reopened.pending(2, 1, 22), isNull, reason: 'outro usuário');
    expect(await reopened.pending(1, 2, 22), isNull, reason: 'outro espaço');
    expect(await reopened.pending(1, 1, 23), isNull, reason: 'outra parcela');
    final restored = await reopened.pending(1, 1, 22);
    expect(restored!.idempotencyKey, first.attempt.idempotencyKey);
    expect(restored.toJson(), first.attempt.toJson());

    final resolved = await reopened.resolve(restored);
    expect(resolved.result!.replayed, isTrue);
    expect(bodies(), hasLength(1));
    expect(api.receipts, hasLength(1));
  });

  test('app fechado após sucesso remoto e antes da limpeza local', () async {
    storage.failDeletes = true;
    final first = await submit(service());
    expect(first.state, ReceiptAttemptState.confirmed);
    expect(api.receipts, hasLength(1));

    storage.failDeletes = false;
    final reopened = service();
    final restored = await reopened.pending(1, 1, 22);
    expect(restored, isNotNull, reason: 'a limpeza não aconteceu');

    final resolved = await reopened.resolve(restored!);
    expect(resolved.state, ReceiptAttemptState.confirmed);
    expect(resolved.result!.replayed, isTrue);
    expect(api.receipts, hasLength(1));
    expect(api.balanceCents, 150000);
    expect(await reopened.pending(1, 1, 22), isNull);
  });

  test('verificações simultâneas compartilham uma única requisição', () async {
    api.script.add(Delivery.loseResponse);
    final attempts = service();
    final first = await submit(attempts);

    final gate = api.hold = Completer<void>();
    final a = attempts.resolve(first.attempt);
    final b = attempts.resolve(first.attempt);
    final c = submit(attempts, amount: '300.00');
    await pumpEventQueue();
    gate.complete();
    final outcomes = await Future.wait([a, b, c]);

    expect(
      api.receiptRequests,
      hasLength(2),
      reason: 'original + uma verificação',
    );
    expect(outcomes.map((o) => o.state).toSet(), {
      ReceiptAttemptState.confirmed,
    });
    expect(api.receipts, hasLength(1));
  });

  test(
    'depois de resolvida, nova operação usa o restante atualizado',
    () async {
      api.script.add(Delivery.loseResponse);
      final attempts = service();
      final first = await submit(attempts);
      await attempts.resolve(first.attempt);
      expect(api.remainingCents, 150000);

      final next = await submit(attempts, amount: '1500.00');
      expect(next.state, ReceiptAttemptState.confirmed);
      expect(next.attempt.idempotencyKey, isNot(first.attempt.idempotencyKey));
      expect(api.receipts.map((r) => r.amountCents), [50000, 150000]);
      expect(api.remainingCents, 0);
      expect(api.balanceCents, 300000);
    },
  );

  group('estorno e correção', () {
    Future<ReceiptAttemptOutcome> fix(
      ReceiptAttempts attempts,
      FakeReceipt original, {
      String reason = 'Lançado por engano',
      ({int accountId, String accountName, Money amount, String receivedOn})?
      replacement,
      int userId = 1,
    }) => attempts.submitFix(
      userId: userId,
      spaceId: 1,
      installmentId: 22,
      original: Receipt(
        id: original.id,
        accountId: original.accountId,
        amount: Money(original.amountCents),
        receivedOn: original.date,
      ),
      originalAccountName: 'Banco PF',
      reason: reason,
      replacement: replacement,
    );

    test('422 sem decisão registrada não libera: continua pendente', () async {
      api.script.add(Delivery.unrecordedRejection);
      final attempts = service();
      final outcome = await submit(attempts);
      expect(outcome.state, ReceiptAttemptState.uncertain);
      expect(await attempts.pending(1, 1, 22), isNotNull);
    });

    test(
      'chave recusada continua recusada depois que um estorno reabre a parcela',
      () async {
        final paid = api.seed(7, 200000, '2026-03-10');
        final attempts = service();
        final refused = await submit(attempts, amount: '100.00');
        expect(refused.state, ReceiptAttemptState.rejected);
        final key = refused.attempt.idempotencyKey;

        expect(
          (await fix(attempts, paid)).state,
          ReceiptAttemptState.confirmed,
        );
        expect(api.remainingCents, 200000);

        // Repetição atrasada da chave recusada: a decisão guardada prevalece.
        final late = await attempts.resolve(refused.attempt);
        expect(late.state, ReceiptAttemptState.rejected);
        expect(api.receipts.where((r) => r.key == key), isEmpty);
      },
    );

    test(
      'estorno com resposta perdida: verificação aplica uma única vez',
      () async {
        final original = api.seed(7, 50000, '2026-03-10');
        api.script.add(Delivery.loseResponse);
        final attempts = service();
        final first = await fix(attempts, original);
        expect(first.state, ReceiptAttemptState.uncertain);
        expect(original.reversed, isTrue, reason: 'a API aplicou');
        expect(api.balanceCents, 100000);

        final resolved = await attempts.resolve(first.attempt);
        expect(resolved.state, ReceiptAttemptState.confirmed);
        expect(resolved.replayed, isTrue);
        expect(resolved.message, startsWith('Estorno já estava registrado'));
        expect(api.balanceCents, 100000, reason: 'compensação uma vez');
        expect(keys(), hasLength(1));
        expect(bodies(), hasLength(1));
      },
    );

    test(
      'correção com resposta perdida: um substituto, saldos uma vez',
      () async {
        final original = api.seed(7, 50000, '2026-03-10');
        api.script.add(Delivery.loseResponse);
        final attempts = service();
        final first = await fix(
          attempts,
          original,
          reason: 'Conta errada',
          replacement: (
            accountId: 8,
            accountName: 'Reserva PF',
            amount: Money.parse('500.00'),
            receivedOn: '2026-03-10',
          ),
        );
        expect(first.state, ReceiptAttemptState.uncertain);
        expect(jsonDecode(api.receiptRequests.single.body), {
          'reason': 'Conta errada',
          'account_id': 8,
          'amount': '500.00',
          'received_on': '2026-03-10',
        });

        final resolved = await attempts.resolve(first.attempt);
        expect(resolved.fix!.replacement!.accountId, 8);
        expect(resolved.message, startsWith('Correção já estava registrada'));
        expect(api.receipts, hasLength(2));
        expect(api.active.single.accountId, 8);
        expect(api.balanceCents, 100000);
        expect(api.reserveCents, 50000);
        expect(api.remainingCents, 150000);
      },
    );

    test(
      'operação pendente bloqueia recebimento, estorno e correção na parcela',
      () async {
        final original = api.seed(7, 50000, '2026-03-10');
        api.script.add(Delivery.loseResponse);
        final attempts = service();
        final pending = await fix(attempts, original);

        final receipt = await submit(attempts, amount: '100.00');
        final again = await fix(attempts, original, reason: 'Outro motivo');
        expect(receipt.attempt.idempotencyKey, pending.attempt.idempotencyKey);
        expect(again.attempt.idempotencyKey, pending.attempt.idempotencyKey);
        expect(api.receiptRequests, hasLength(1), reason: 'nada mais saiu');
      },
    );

    test(
      'correção pendente restaurada após reabrir, só no mesmo contexto',
      () async {
        final original = api.seed(7, 50000, '2026-03-10');
        api.script.add(Delivery.dropBeforeServer);
        final first = await fix(
          service(),
          original,
          reason: 'Valor errado',
          replacement: (
            accountId: 7,
            accountName: 'Banco PF',
            amount: Money.parse('400.00'),
            receivedOn: '2026-03-10',
          ),
        );

        final reopened = service();
        expect(await reopened.pending(2, 1, 22), isNull);
        expect(await reopened.pending(1, 2, 22), isNull);
        final restored = (await reopened.pending(1, 1, 22))!;
        expect(restored.toJson(), first.attempt.toJson());
        expect(restored.operation, ReceiptOperation.correction);
        expect(restored.targetReceiptId, original.id);
        expect(restored.originalAmount?.cents, 50000);

        final resolved = await reopened.resolve(restored);
        expect(resolved.replayed, isFalse, reason: 'o primeiro não chegou');
        expect(api.balanceCents, 140000, reason: '−R\$ 100,00 líquido');
        expect(api.remainingCents, 160000);
      },
    );

    test('registro antigo, sem operação, é lido como recebimento', () async {
      await storage.write(
        'pending_receipt.1.1.22',
        jsonEncode({
          'user_id': 1,
          'space_id': 1,
          'installment_id': 22,
          'idempotency_key': 'abc',
          'account_id': 7,
          'account_name': 'Banco PF',
          'amount': '500.00',
          'received_on': '2026-03-10',
          'kind': 'partial',
        }),
      );
      final restored = (await service().pending(1, 1, 22))!;
      expect(restored.operation, ReceiptOperation.receipt);
      expect(restored.kind, ReceiptKind.partial);
    });
  });
}
