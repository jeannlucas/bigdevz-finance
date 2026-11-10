import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/reconciliation/ofx_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('OfxRepository: parseOfx envia conteúdo e processa prévia com correspondências', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/spaces/1/ofx/parse');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['account_id'], 10);
      expect(body['ofx_content'], contains('<STMTTRN>'));

      final fakeResponse = {
        'data': {
          'account': {'id': 10, 'name': 'Banco Conciliado'},
          'transactions_count': 1,
          'already_reconciled_count': 0,
          'transactions': [
            {
              'fitid': 'TX-999',
              'type': 'debit',
              'amount_cents': 35000,
              'amount': '350.00',
              'posted_at': '2026-11-10',
              'memo': 'FATURA ENERGIA',
              'already_reconciled': false,
              'suggested_match': {
                'type': 'payable',
                'id': 42,
                'title': 'Conta de Luz',
                'amount': '350.00',
                'due_date': '2026-11-10',
                'confidence': 'high',
              },
            },
          ],
        },
      };

      return http.Response(
        jsonEncode(fakeResponse),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = ApiClient(baseUrl: 'http://example.com/api', client: client);
    final repo = OfxRepository(api);

    final res = await repo.parseOfx(
      spaceId: 1,
      accountId: 10,
      ofxContent: '<STMTTRN><TRNAMT>-350.00</STMTTRN>',
    );

    expect(res.accountName, 'Banco Conciliado');
    expect(res.transactions.length, 1);
    final tx = res.transactions.first;
    expect(tx.fitid, 'TX-999');
    expect(tx.type, 'debit');
    expect(tx.amount.cents, 35000);
    expect(tx.alreadyReconciled, isFalse);
    expect(tx.suggestedMatch, isNotNull);
    expect(tx.suggestedMatch!.title, 'Conta de Luz');
  });

  test('OfxRepository: reconcile envia confirmação com transações', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/spaces/1/ofx/reconcile');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['account_id'], 10);
      final txs = body['transactions'] as List;
      expect(txs.length, 1);
      expect(txs.first['fitid'], 'TX-999');

      return http.Response(
        jsonEncode({
          'data': {'reconciled_count': 1, 'ignored_count': 0},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = ApiClient(baseUrl: 'http://example.com/api', client: client);
    final repo = OfxRepository(api);

    final res = await repo.reconcile(
      spaceId: 1,
      accountId: 10,
      transactions: [
        {
          'fitid': 'TX-999',
          'action': 'match_payable',
          'amount_cents': 35000,
          'posted_at': '2026-11-10',
        },
      ],
    );

    expect(res['reconciled_count'], 1);
  });
}
