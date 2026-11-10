import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/planning/planning_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('PlanningRepository: fetchCashFlow envia parâmetros e faz parse de resposta', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/spaces/1/cash-flow');
      expect(request.url.queryParameters['days'], '60');
      expect(request.url.queryParameters['view'], 'cash');
      expect(request.url.queryParameters['category_id'], '12');

      final fakeData = {
        'data': {
          'initial_balance_cents': 500000,
          'period_days': 60,
          'view': 'cash',
          'start_date': '2026-11-09',
          'end_date': '2027-01-07',
          'summary': {
            'realized_inflow_cents': 200000,
            'realized_outflow_cents': 100000,
            'projected_inflow_cents': 800000,
            'projected_outflow_cents': 400000,
            'final_projected_balance_cents': 1000000,
          },
          'daily': [
            {
              'date': '2026-11-09',
              'realized_inflow_cents': 50000,
              'realized_outflow_cents': 20000,
              'projected_inflow_cents': 0,
              'projected_outflow_cents': 0,
              'projected_balance_cents': 530000,
              'items_count': 2,
            },
          ],
        },
      };

      return http.Response(
        jsonEncode(fakeData),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = ApiClient(baseUrl: 'http://example.com/api', client: client);
    final repo = PlanningRepository(api);

    final res = await repo.fetchCashFlow(
      spaceId: 1,
      days: 60,
      view: 'cash',
      categoryId: 12,
    );

    expect(res.initialBalance.cents, 500000);
    expect(res.periodDays, 60);
    expect(res.summary.realizedInflow.cents, 200000);
    expect(res.summary.projectedInflow.cents, 800000);
    expect(res.summary.finalProjectedBalance.cents, 1000000);
    expect(res.daily.length, 1);
    expect(res.daily.first.date, '2026-11-09');
    expect(res.daily.first.projectedBalance.cents, 530000);
  });
}
