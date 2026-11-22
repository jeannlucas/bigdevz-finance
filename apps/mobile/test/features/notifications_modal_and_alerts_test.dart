import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/alerts/alerts_repository.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/home/notifications_modal.dart';
import 'package:bigdevz_finance/features/summary/summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

const pfSpace = Space(id: 1, kind: 'PF', name: 'Pessoal');

void main() {
  group(
    'Melhoria 6: Sininho de Notificações, Leitura e Dispensa Auditáveis',
    () {
      test('AlertItem copyWith preserva integridade dos atributos', () {
        final alert = AlertItem(
          key: 'payable:10:overdue',
          targetId: 10,
          type: 'payable',
          title: 'ENERGIA ELETRICA',
          description: 'Vencida em 10/03/2026',
          amount: const Money(15000),
          amountCents: 15000,
          isCritical: true,
          isRead: false,
          isDismissed: false,
        );

        final readAlert = alert.copyWith(
          isRead: true,
          readAt: '2026-03-11T10:00:00Z',
        );
        expect(readAlert.isRead, isTrue);
        expect(readAlert.isDismissed, isFalse);
        expect(readAlert.readAt, '2026-03-11T10:00:00Z');

        final dismissedAlert = alert.copyWith(
          isDismissed: true,
          dismissedAt: '2026-03-11T10:05:00Z',
        );
        expect(dismissedAlert.isDismissed, isTrue);
        expect(dismissedAlert.isRead, isFalse);
      });

      testWidgets(
        'NotificationsModal exibe alertas ativos, permite marcar como lido e dispensar aviso',
        (tester) async {
          final backend = FakeBackend();
          final client = ApiClient(
            baseUrl: 'http://api.test/api',
            client: backend.client,
          );
          client.token = backend.validToken;

          backend.routes['GET /spaces/1/summary'] = {
            'data': {
              'balance': '1000.00',
              'receivable_remaining': '0.00',
              'received_total': '0.00',
              'accounts_count': 1,
              'agreements_count': 0,
              'overdue_installments': 0,
              'payables': {
                'open_total': '150.00',
                'overdue_total': '150.00',
                'overdue_count': 1,
                'due_next_30_days_total': '0.00',
                'paid_total': '0.00',
                'awaiting_amount_count': 0,
              },
            },
          };

          backend.routes['GET /spaces/1/alerts'] = {
            'data': [
              {
                'key': 'payable:42:overdue',
                'target_id': 42,
                'type': 'payable',
                'title': 'INTERNET FIBRA',
                'description': 'Conta vencida em 05/03/2026',
                'due_date': '2026-03-05',
                'amount': '150.00',
                'amount_cents': 15000,
                'is_critical': true,
                'is_read': false,
                'is_dismissed': false,
              },
            ],
            'meta': {'unread_active_count': 1, 'total_active_count': 1},
          };

          backend.routes['POST /spaces/1/alerts/payable:42:overdue/read'] = {
            'data': {'status': 'read'},
          };
          backend.routes['POST /spaces/1/alerts/payable:42:overdue/dismiss'] = {
            'data': {'status': 'dismissed'},
          };

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                Provider.value(value: SummaryRepository(client)),
                Provider.value(value: AlertsRepository(client)),
                ChangeNotifierProvider(
                  create: (_) =>
                      SessionController(
                          api: client,
                          auth: AuthRepository(client),
                          storage: MemorySessionStorage(),
                        )
                        ..user = const AppUser(
                          id: 1,
                          name: 'User',
                          email: 'u@test.com',
                        )
                        ..spaces = [pfSpace]
                        ..selectSpace(pfSpace),
                ),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () => showNotificationsModal(
                        context,
                        onNavigate: (_, {filter}) {},
                      ),
                      child: const Text('Abrir Notificações'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Abrir Notificações'));
          await tester.pumpAndSettle();

          expect(find.text('Notificações e Vencimentos'), findsOneWidget);
          expect(find.text('INTERNET FIBRA'), findsOneWidget);
          expect(find.text('Marcar como lido'), findsOneWidget);
          expect(find.byTooltip('Dispensar aviso'), findsOneWidget);

          // Marca como lido
          await tester.tap(find.text('Marcar como lido'));
          await tester.pumpAndSettle();

          // Confirma que a chamada para /read foi enviada
          final readReq = backend.requests.firstWhere(
            (r) => r.url.path == '/api/spaces/1/alerts/payable:42:overdue/read',
          );
          expect(readReq.method, 'POST');
          expect(find.text('Lido'), findsOneWidget);

          // Dispensa o aviso
          await tester.tap(find.byTooltip('Dispensar aviso'));
          await tester.pumpAndSettle();

          // Confirma que a chamada para /dismiss foi enviada
          final dismissReq = backend.requests.firstWhere(
            (r) =>
                r.url.path == '/api/spaces/1/alerts/payable:42:overdue/dismiss',
          );
          expect(dismissReq.method, 'POST');
        },
      );
    },
  );
}
