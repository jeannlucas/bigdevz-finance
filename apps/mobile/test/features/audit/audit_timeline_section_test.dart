import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/audit/audit_timeline_section.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';

class _FakeAuditApiClient extends ApiClient {
  _FakeAuditApiClient(this.response) : super(baseUrl: 'http://localhost');

  final Map<String, dynamic> response;

  @override
  Future<Map<String, dynamic>> get(String path) async => response;
}

void main() {
  testWidgets(
    'AuditTimelineSection exibe eventos de auditoria retornados pela API',
    (tester) async {
      final api = _FakeAuditApiClient({
        'data': [
          {
            'id': 1,
            'subject': 'account',
            'subject_id': 10,
            'action': 'updated',
            'is_critical': false,
            'user': {
              'id': 1,
              'name': 'Jeann Lucas',
              'email': 'jeann@bigdevz.com',
            },
            'before': {'name': 'Conta Antiga'},
            'after': {'name': 'Conta Nova'},
            'diff': {
              'name': {'before': 'Conta Antiga', 'after': 'Conta Nova'},
            },
            'reason': 'Ajuste de nomenclatura',
            'created_at': '2026-11-26T14:30:00Z',
          },
        ],
      });

      const space = Space(id: 1, name: 'Pessoal', kind: 'pf');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditTimelineSection(
              api: api,
              space: space,
              subject: 'account',
              subjectId: 10,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Histórico de Auditoria'), findsOneWidget);
      expect(find.text('Alteração de dados'), findsOneWidget);
      expect(find.text('Por Jeann Lucas'), findsOneWidget);
      expect(find.text('Ajuste de nomenclatura'), findsOneWidget);
    },
  );

  testWidgets(
    'AuditTimelineSection exibe estado vazio quando não há registros',
    (tester) async {
      final api = _FakeAuditApiClient({'data': []});
      const space = Space(id: 1, name: 'Pessoal', kind: 'pf');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditTimelineSection(
              api: api,
              space: space,
              subject: 'payable',
              subjectId: 99,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Histórico de Auditoria'), findsOneWidget);
      expect(
        find.text('Nenhum registro de auditoria para este item.'),
        findsOneWidget,
      );
    },
  );
}
