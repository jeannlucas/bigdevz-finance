import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bigdevz_finance/ui/confirm_changes_dialog.dart';

void main() {
  testWidgets(
    'ConfirmChangesDialog exibe título, diffs e retorna true ao confirmar',
    (tester) async {
      bool? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  dialogResult = await showDialog<bool>(
                    context: context,
                    builder: (_) => const ConfirmChangesDialog(
                      changes: [
                        ChangeDifference(
                          label: 'Valor total',
                          oldValue: 'R\$ 1.000,00',
                          newValue: 'R\$ 1.500,00',
                        ),
                        ChangeDifference(
                          label: 'Descrição',
                          oldValue: 'Serviço A',
                          newValue: 'Serviço B',
                        ),
                      ],
                      warning: 'As parcelas em aberto serão recalculadas.',
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      // Abre o diálogo
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      // Verifica conteúdo
      expect(find.text('Deseja realmente salvar?'), findsOneWidget);
      expect(
        find.text('Confira as alterações que serão aplicadas:'),
        findsOneWidget,
      );
      expect(find.text('VALOR TOTAL'), findsOneWidget);
      expect(find.text('R\$ 1.000,00'), findsOneWidget);
      expect(find.text('R\$ 1.500,00'), findsOneWidget);
      expect(find.text('DESCRIÇÃO'), findsOneWidget);
      expect(find.text('Serviço A'), findsOneWidget);
      expect(find.text('Serviço B'), findsOneWidget);
      expect(
        find.text('As parcelas em aberto serão recalculadas.'),
        findsOneWidget,
      );

      // Clica em confirmar
      await tester.tap(find.text('Confirmar e salvar'));
      await tester.pumpAndSettle();

      expect(dialogResult, isTrue);
    },
  );

  testWidgets('ConfirmChangesDialog retorna false ao clicar em Revisar', (
    tester,
  ) async {
    bool? dialogResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                dialogResult = await showDialog<bool>(
                  context: context,
                  builder: (_) => const ConfirmChangesDialog(
                    changes: [
                      ChangeDifference(
                        label: 'Valor',
                        oldValue: 'R\$ 100,00',
                        newValue: 'R\$ 120,00',
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    expect(dialogResult, isFalse);
  });
}
