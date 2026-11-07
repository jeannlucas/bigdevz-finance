import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/statement/statement_entry.dart';
import 'package:bigdevz_finance/features/statement/statement_repository.dart';

void main() {
  group('StatementEntry', () {
    test('parses credit entry from JSON correctly', () {
      final json = {
        'id': 101,
        'account_id': 1,
        'account_name': 'Banco Inter',
        'effective_date': '2026-02-10',
        'amount': '1500.50',
        'raw_amount_cents': 150050,
        'direction': 'credit',
        'type': 'receipt',
        'description': 'Recebimento: Consultoria',
        'created_at': '2026-02-10T12:00:00Z',
      };

      final entry = StatementEntry.fromJson(json);

      expect(entry.id, 101);
      expect(entry.accountId, 1);
      expect(entry.accountName, 'Banco Inter');
      expect(entry.effectiveDate, '2026-02-10');
      expect(entry.amount.cents, 150050);
      expect(entry.amount.brl, 'R\$ 1.500,50');
      expect(entry.direction, StatementDirection.credit);
      expect(entry.direction.isCredit, isTrue);
      expect(entry.direction.isDebit, isFalse);
      expect(entry.type, 'receipt');
      expect(entry.description, 'Recebimento: Consultoria');
    });

    test('parses debit entry from JSON correctly', () {
      final json = {
        'id': 102,
        'account_id': 2,
        'account_name': 'Nubank PJ',
        'effective_date': '2026-02-15',
        'amount': '350.00',
        'raw_amount_cents': -35000,
        'direction': 'debit',
        'type': 'payment',
        'description': 'Pagamento: Hospedagem Caddy',
      };

      final entry = StatementEntry.fromJson(json);

      expect(entry.id, 102);
      expect(entry.direction, StatementDirection.debit);
      expect(entry.direction.isCredit, isFalse);
      expect(entry.direction.isDebit, isTrue);
      expect(entry.amount.cents, 35000);
      expect(entry.rawAmountCents, -35000);
    });
  });

  group('StatementRepository', () {
    test('fetches statement with filters and deserializes response', () async {
      late Uri requestedUri;

      final client = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 1,
                'account_id': 5,
                'account_name': 'Caixa',
                'effective_date': '2026-02-01',
                'amount': '250.00',
                'raw_amount_cents': 25000,
                'direction': 'credit',
                'type': 'receipt',
                'description': 'Recebimento Teste',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(baseUrl: 'http://test.local', client: client);
      final repo = StatementRepository(api);

      final entries = await repo.list(
        2,
        accountId: 5,
        from: '2026-02-01',
        to: '2026-02-28',
        direction: 'credit',
      );

      expect(requestedUri.path, '/spaces/2/statement');
      expect(requestedUri.queryParameters['account_id'], '5');
      expect(requestedUri.queryParameters['from'], '2026-02-01');
      expect(requestedUri.queryParameters['to'], '2026-02-28');
      expect(requestedUri.queryParameters['direction'], 'credit');
      expect(entries.length, 1);
      expect(entries.first.id, 1);
      expect(entries.first.amount.cents, 25000);
    });
  });
}
