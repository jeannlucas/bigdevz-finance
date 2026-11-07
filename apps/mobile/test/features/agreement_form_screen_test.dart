import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/agreements/agreement_form_screen.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

const pf = Space(id: 1, kind: 'PF', name: 'Pessoal');

void main() {
  late MemorySessionStorage storage;

  Widget buildScreen({Size size = const Size(375, 812)}) {
    final backend = FakeBackend();
    final api = ApiClient(
      baseUrl: 'http://example.test',
      client: backend.client,
    );
    storage = MemorySessionStorage();
    final auth = AuthRepository(api);
    final session = SessionController(api: api, auth: auth, storage: storage);

    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: MultiProvider(
          providers: [
            Provider<AgreementsRepository>(
              create: (_) => AgreementsRepository(api),
            ),
            ChangeNotifierProvider<SessionController>.value(value: session),
          ],
          child: const AgreementFormScreen(space: pf),
        ),
      ),
    );
  }

  testWidgets(
    'AgreementFormScreen: inicia com 1 parcela por padrão e botão "Salvar conta a receber"',
    (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Verifica valor inicial do campo de parcelas
      final countField = find.ancestor(
        of: find.text('Quantidade de parcelas'),
        matching: find.byType(TextFormField),
      );
      expect(countField, findsOneWidget);
      final countInput = tester.widget<TextFormField>(countField);
      expect(countInput.controller?.text, '1');

      // Botão inicial
      expect(find.text('Salvar conta a receber'), findsOneWidget);
      expect(
        find.text('Recebimento à vista ou parcela única.'),
        findsOneWidget,
      );

      // Altera para 3 parcelas
      await tester.enterText(countField, '3');
      await tester.pumpAndSettle();

      // Botão atualiza dinamicamente
      expect(find.text('Gerar parcelas'), findsOneWidget);
      expect(
        find.textContaining('As 3 parcelas somam o valor total'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'AgreementFormScreen: em desktop web (>= 640px) renderiza card centralizado com maxWidth',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildScreen(size: const Size(1280, 800)));
      await tester.pumpAndSettle();

      // Card executivo
      expect(find.byType(Card), findsOneWidget);

      // ConstrainedBox com maxWidth de 580
      final constrainedBox = tester.widget<ConstrainedBox>(
        find
            .ancestor(
              of: find.byType(Card),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(constrainedBox.constraints.maxWidth, 580);

      // Campos Parcelas e Primeiro vencimento em 2 colunas (Row)
      expect(
        find.ancestor(of: find.text('Parcelas'), matching: find.byType(Row)),
        findsWidgets,
      );
      expect(
        find.ancestor(
          of: find.text('Primeiro vencimento'),
          matching: find.byType(Row),
        ),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'showAgreementFormModal: abre Dialog em desktop com botão de fechar',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final backend = FakeBackend();
      final api = ApiClient(
        baseUrl: 'http://example.test',
        client: backend.client,
      );
      storage = MemorySessionStorage();
      final auth = AuthRepository(api);
      final session = SessionController(api: api, auth: auth, storage: storage);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1280, 800)),
          child: MaterialApp(
            home: MultiProvider(
              providers: [
                Provider<AgreementsRepository>(
                  create: (_) => AgreementsRepository(api),
                ),
                ChangeNotifierProvider<SessionController>.value(value: session),
              ],
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => showAgreementFormModal(context, space: pf),
                    child: const Text('Abrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Nova conta a receber'), findsOneWidget);
      expect(find.byTooltip('Fechar'), findsOneWidget);

      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    },
  );
}
