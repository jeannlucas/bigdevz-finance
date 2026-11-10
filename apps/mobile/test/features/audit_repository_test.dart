import 'package:flutter_test/flutter_test.dart';
import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/audit/audit_models.dart';
import 'package:bigdevz_finance/features/audit/audit_repository.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dart:convert';

void main() {
  group('AuditRepository and AuditItem Tests', () {
    const space = Space(
      id: 1,
      kind: 'PJ',
      name: 'Empresa Teste',
      role: 'administrador',
    );

    test('AuditItem parses JSON correctly with human translations', () {
      final json = {
        'id': 101,
        'subject': 'payable',
        'subject_id': 55,
        'action': 'cancel',
        'is_critical': true,
        'user': {'id': 1, 'name': 'Jeann Lucas', 'email': 'jeann@bigdevz.com'},
        'before': {'amount_cents': 25000, 'status': 'pending'},
        'after': {'amount_cents': 25000, 'status': 'cancelled'},
        'diff': {
          'status': {'before': 'pending', 'after': 'cancelled'},
        },
        'reason': 'Serviço cancelado pelo fornecedor',
        'created_at': '2026-11-09T17:30:00Z',
      };

      final item = AuditItem.fromJson(json);

      expect(item.id, equals(101));
      expect(item.subject, equals('payable'));
      expect(item.action, equals('cancel'));
      expect(item.isCritical, isTrue);
      expect(item.userName, equals('Jeann Lucas'));
      expect(item.userEmail, equals('jeann@bigdevz.com'));
      expect(item.reason, equals('Serviço cancelado pelo fornecedor'));
      expect(item.humanSubject, equals('Conta a pagar'));
      expect(item.humanAction, equals('Cancelamento de lançamento'));
    });

    test('AuditRepository fetches audit items and handles filters', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/spaces/1/audit'));
        expect(request.url.queryParameters['critical_only'], equals('true'));

        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 201,
                'subject': 'agreement',
                'subject_id': 88,
                'action': 'cancel',
                'is_critical': true,
                'user': {
                  'id': 2,
                  'name': 'Financeiro User',
                  'email': 'fin@test.com',
                },
                'before': {'total_cents': 50000},
                'after': {'total_cents': 50000},
                'diff': {
                  'status': {'before': 'active', 'after': 'cancelled'},
                },
                'reason': 'Distrato comercial',
                'created_at': '2026-11-09T18:00:00Z',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final repo = AuditRepository(api: apiClient);

      final items = await repo.list(space: space, criticalOnly: true);

      expect(items.length, equals(1));
      expect(items.first.humanSubject, equals('Conta a receber'));
      expect(items.first.humanAction, equals('Cancelamento de lançamento'));
      expect(items.first.isCritical, isTrue);
    });
  });
}
