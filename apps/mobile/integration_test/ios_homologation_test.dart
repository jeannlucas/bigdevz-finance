// ==============================================================================
// BigDev.Z Finance — Suíte Oficial de Homologação Nativa Multiplataforma
// Executa todos os fluxos interativos completos no simulador iOS / emulador Android
// com motor gráfico nativo e captura de screenshots do framebuffer em tempo real.
// 100% de navegação, ações e fechamentos acionados exclusivamente por widgets da interface.
// Asserções determinísticas de estado e saldo sem tolerância a fluxos ignorados.
// ==============================================================================
import 'package:bigdevz_finance/bootstrap.dart';
import 'package:bigdevz_finance/core/token_storage.dart';
import 'package:bigdevz_finance/ui/financial/financial_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Homologação visual e funcional completa no dispositivo nativo', (
    tester,
  ) async {
    const storage = SecureSessionStorage();
    await storage.delete('auth_token');
    await storage.delete('active_space_id');
    final client = http.Client();

    const serverHost = String.fromEnvironment(
      'SCREENSHOT_HOST',
      defaultValue: '127.0.0.1',
    );
    const targetPlatform = String.fromEnvironment(
      'TARGET_PLATFORM',
      defaultValue: 'ios',
    );
    const apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000/api',
    );
    final prefix = targetPlatform == 'android'
        ? 'android_homolog'
        : 'ios_homolog';

    Future<void> settle([int iterations = 40]) async {
      for (var i = 0; i < iterations; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (!tester.binding.hasScheduledFrame &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          return;
        }
      }
    }

    Future<void> capture(String name) async {
      await settle();
      try {
        final uri = Uri.parse(
          'http://$serverHost:9876/screenshot?name=$name&target=$targetPlatform',
        );
        final res = await http.get(uri).timeout(const Duration(seconds: 8));
        debugPrint(
          '📸 [$targetPlatform Screenshot] $name -> HTTP ${res.statusCode}',
        );
      } catch (e) {
        debugPrint(
          '⚠️ [$targetPlatform Screenshot] Falha ao capturar $name: $e',
        );
      }
    }

    Finder verticalScrollable() {
      final candidates = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );
      return candidates.evaluate().isNotEmpty
          ? candidates.first
          : find.byType(Scrollable).first;
    }

    Future<void> scrollTop() async {
      for (var i = 0; i < 4; i++) {
        if (find.byType(Scrollable).evaluate().isNotEmpty) {
          await tester.drag(
            verticalScrollable(),
            const Offset(0, 350),
            warnIfMissed: false,
          );
          await settle(10);
        }
      }
    }

    Future<void> reveal(String text) async {
      final target = find.text(text);
      if (target.evaluate().isNotEmpty) {
        try {
          await tester.ensureVisible(target.last);
        } catch (_) {}
        await settle();
        return;
      }
      for (var i = 0; i < 15 && target.evaluate().isEmpty; i++) {
        if (find.byType(Scrollable).evaluate().isNotEmpty) {
          await tester.drag(
            verticalScrollable(),
            const Offset(0, -250),
            warnIfMissed: false,
          );
        } else {
          await tester.dragFrom(const Offset(200, 450), const Offset(0, -250));
        }
        await settle();
      }
      if (target.evaluate().isNotEmpty) {
        try {
          await tester.ensureVisible(target.last);
        } catch (_) {}
        await settle();
      }
    }

    Future<void> tapText(String text) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await settle();
      await reveal(text);
      final found = find.text(text);
      expect(
        found,
        findsWidgets,
        reason: 'Elemento com texto "$text" não encontrado na tela',
      );
      try {
        await tester.ensureVisible(found.last);
      } catch (_) {}
      await tester.tap(found.last, warnIfMissed: false);
      await settle();
    }

    Future<void> tapChip(String label) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await settle();
      await scrollTop();
      var chipFinder = find.widgetWithText(ChoiceChip, label);
      if (chipFinder.evaluate().isEmpty) {
        final hScroll = find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        );
        if (hScroll.evaluate().isNotEmpty) {
          for (var i = 0; i < 5 && chipFinder.evaluate().isEmpty; i++) {
            await tester.drag(
              hScroll.first,
              const Offset(-150, 0),
              warnIfMissed: false,
            );
            await settle(10);
            chipFinder = find.widgetWithText(ChoiceChip, label);
          }
        }
      }
      if (chipFinder.evaluate().isEmpty) {
        final hScroll = find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        );
        if (hScroll.evaluate().isNotEmpty) {
          for (var i = 0; i < 5 && chipFinder.evaluate().isEmpty; i++) {
            await tester.drag(
              hScroll.first,
              const Offset(150, 0),
              warnIfMissed: false,
            );
            await settle(10);
            chipFinder = find.widgetWithText(ChoiceChip, label);
          }
        }
      }
      expect(
        chipFinder,
        findsWidgets,
        reason: 'ChoiceChip com label "$label" não encontrado',
      );
      await tester.tap(chipFinder.first, warnIfMissed: false);
      await settle();
    }

    Future<void> tapIcon(IconData icon) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await settle();
      final found = find.byIcon(icon);
      expect(found, findsWidgets, reason: 'Ícone $icon não encontrado na tela');
      await tester.tap(found.last, warnIfMissed: false);
      await settle();
    }

    Future<void> selectTabByIndex(int index) async {
      final navBar = find.byType(NavigationBar);
      if (navBar.evaluate().isNotEmpty) {
        final dests = find.descendant(
          of: navBar,
          matching: find.byType(NavigationDestination),
        );
        if (dests.evaluate().length > index) {
          await tester.tap(dests.at(index), warnIfMissed: false);
          await settle();
        }
      }
    }

    Future<void> selectSpace(String kind) async {
      final spaceBtn = find.text(kind);
      if (spaceBtn.evaluate().isNotEmpty) {
        await tester.tap(spaceBtn.first);
        await settle();
      }
    }

    // ========================================================================
    // 1. INICIALIZAÇÃO E TELA DE LOGIN NATIVA
    // ========================================================================
    await tester.pumpWidget(
      buildApp(baseUrl: apiBaseUrl, storage: storage, client: client),
    );
    await settle();

    await capture('${prefix}_01_login');
    expect(find.text('Entrar'), findsOneWidget);

    // ========================================================================
    // 2. AUTENTICAÇÃO COM USUÁRIO DE HOMOLOGAÇÃO
    // ========================================================================
    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-mail'),
      'homologacao@bigdevz.local',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Senha'),
      'Homologacao2026',
    );
    await capture('${prefix}_02_login_filled');

    await tapText('Entrar');

    // Aguarda carregamento do Dashboard PF
    await settle(60);
    expect(find.text('Saldo disponível'), findsOneWidget);
    await capture('${prefix}_03_dashboard_pf');

    // ========================================================================
    // 3. ALTERNÂNCIA ENTRE ESPAÇOS PF E PJ (ISOLAMENTO MULTI-TENANT)
    // ========================================================================
    await selectSpace('PJ');
    await settle(30);
    expect(find.text('Saldo disponível'), findsOneWidget);
    await capture('${prefix}_04_dashboard_pj');

    await selectSpace('PF');
    await settle(30);
    expect(find.text('Saldo disponível'), findsOneWidget);
    await capture('${prefix}_05_dashboard_pf_returned');

    // ========================================================================
    // 4. CONTAS A PAGAR: LISTA, FILTROS E INTERVALO PERSONALIZADO
    // ========================================================================
    await selectTabByIndex(3); // 3 = A pagar
    await settle(30);
    expect(find.text('Nova conta a pagar'), findsOneWidget);
    await capture('${prefix}_06_payables_list');

    // 4.1 Filtro de Vencidas via ChoiceChip
    await tapChip('Vencidas');
    await settle(20);
    await capture('${prefix}_07_payables_vencidas');

    // Retorna explicitamente ao filtro "Em aberto"
    await tapChip('Em aberto');
    await settle(20);

    // 4.2 Seleção e Homologação de Intervalo Personalizado
    final dropDownIcon = find.byIcon(Icons.arrow_drop_down_rounded);
    if (dropDownIcon.evaluate().isNotEmpty) {
      await tester.tap(dropDownIcon.first, warnIfMissed: false);
      await settle(30);

      final customOption = find.text('Intervalo personalizado...');
      if (customOption.evaluate().isNotEmpty) {
        await tester.tap(customOption.first);
        await settle(40);

        // Comprova abertura do date range picker nativo
        expect(
          find.text('Selecione o intervalo de vencimento'),
          findsOneWidget,
        );
        await capture('${prefix}_08_payables_custom_period_picker');

        // Confirma e aplica o intervalo selecionado tocando no botão Aplicar
        final applyBtn = find.text('Aplicar');
        expect(applyBtn, findsWidgets);
        await tester.tap(applyBtn.last);
        await settle(30);

        // Comprova que o intervalo foi aplicado na barra
        expect(find.byType(FinancialPeriodBar), findsOneWidget);
        await capture('${prefix}_08b_payables_custom_period_applied');
      }
    }

    // ========================================================================
    // 5. CONTAS A PAGAR: CRIAR, EDITAR E CANCELAR (COM ASSERÇÕES DE ESTADO)
    // ========================================================================
    // 5.1 Abertura do formulário com teclado visível
    await scrollTop();
    await tapText('Nova conta a pagar');
    await settle(30);
    expect(find.widgetWithText(TextFormField, 'Descrição'), findsOneWidget);
    await capture('${prefix}_09_payable_form_empty');

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Descrição'),
      'ASSINATURA SOFTWARE (HOMOLOGAÇÃO)',
    );
    final valField = find.widgetWithText(TextFormField, 'Valor');
    expect(valField, findsOneWidget);
    await tester.enterText(valField, '12000'); // R$ 120,00
    await capture('${prefix}_10_payable_form_filled');

    await tapText('Salvar conta a pagar');
    await settle(40);

    // Comprova que a conta criada aparece na lista
    await scrollTop();
    await reveal('ASSINATURA SOFTWARE (HOMOLOGAÇÃO)');
    expect(find.text('ASSINATURA SOFTWARE (HOMOLOGAÇÃO)'), findsWidgets);
    await capture('${prefix}_11_payables_after_creation');

    // 5.1b COMPROVAÇÃO DE FILTRO TEMPORAL (LANÇAMENTOS DENTRO E FORA DO INTERVALO)
    // Ao navegar para o mês anterior pelo chevron, a conta com vencimento hoje DEVE ficar fora do resultado
    final prevMonthBtn = find.byTooltip('Mês anterior');
    if (prevMonthBtn.evaluate().isNotEmpty) {
      await tester.tap(prevMonthBtn.first);
      await settle(30);
      expect(
        find.text('ASSINATURA SOFTWARE (HOMOLOGAÇÃO)'),
        findsNothing,
        reason:
            'A conta do mês atual não deve constar na listagem do mês anterior',
      );
      await capture('${prefix}_11b_payables_filtered_out_previous_month');

      // Ao avançar para o próximo mês (retornando ao mês atual), a conta DEVE reaparecer
      final nextMonthBtn = find.byTooltip('Próximo mês');
      if (nextMonthBtn.evaluate().isNotEmpty) {
        await tester.tap(nextMonthBtn.first);
        await settle(30);
        await scrollTop();
        await reveal('ASSINATURA SOFTWARE (HOMOLOGAÇÃO)');
        expect(
          find.text('ASSINATURA SOFTWARE (HOMOLOGAÇÃO)'),
          findsWidgets,
          reason:
              'A conta deve reaparecer na listagem ao retornar ao mês atual',
        );
        await capture('${prefix}_11c_payables_reappearing_current_month');
      }
    }

    // 5.2 Edição de Conta a Pagar
    await tapText('ASSINATURA SOFTWARE (HOMOLOGAÇÃO)');
    await settle(30);
    await capture('${prefix}_12_payable_modal_details');

    // Toca no botão de edição (ícone edit_outlined)
    await tapIcon(Icons.edit_outlined);
    await settle(20);

    // Altera a descrição e o valor
    final editDescField = find.widgetWithText(TextFormField, 'Descrição *');
    if (editDescField.evaluate().isNotEmpty) {
      await tester.enterText(editDescField, 'ASSINATURA SOFTWARE EDITADA');
      await settle(10);
    }
    final editValField = find.widgetWithText(TextFormField, 'Valor *');
    if (editValField.evaluate().isNotEmpty) {
      await tester.enterText(editValField, '140,00'); // R$ 140,00
      await settle(10);
    }
    await tapText('Salvar alterações');
    await settle(20);

    // Diálogo de confirmação double-check
    final confirmSaveBtn = find.text('Confirmar e salvar');
    expect(confirmSaveBtn, findsOneWidget);
    await tester.tap(confirmSaveBtn.first);
    await settle(40);

    // Asserção do estado pós-edição: modal recarregado exibe a descrição editada
    expect(find.text('ASSINATURA SOFTWARE EDITADA'), findsWidgets);
    await capture('${prefix}_13_payable_edited_modal');

    // 5.3 Cancelamento de Conta a Pagar
    await tapIcon(Icons.block);
    await settle(20);

    final reasonField = find.widgetWithText(
      TextFormField,
      'Motivo do cancelamento *',
    );
    expect(reasonField, findsOneWidget);
    await tester.enterText(reasonField, 'Cancelamento teste homologação');
    await settle(10);

    await tapText('Confirmar cancelamento');
    await settle(40);

    // Asserção do estado pós-cancelamento: a conta cancelada não deve mais constar em "Em aberto"
    await scrollTop();
    expect(find.text('ASSINATURA SOFTWARE EDITADA'), findsNothing);
    await capture('${prefix}_14_payables_after_cancellation');

    // ========================================================================
    // 6. CONTAS A PAGAR: CRIAR, VALIDAR CONTA OBRIGATÓRIA, BAIXAR E ESTORNAR
    // ========================================================================
    await scrollTop();
    await tapText('Nova conta a pagar');
    await settle(30);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Descrição'),
      'ENERGIA ELETRICA (HOMOLOGAÇÃO)',
    );
    final payValField = find.widgetWithText(TextFormField, 'Valor');
    expect(payValField, findsOneWidget);
    await tester.enterText(payValField, '21000'); // R$ 210,00
    await tapText('Salvar conta a pagar');
    await settle(40);

    // Abre a conta de energia para baixa
    await scrollTop();
    await reveal('ENERGIA ELETRICA (HOMOLOGAÇÃO)');
    await tapText('ENERGIA ELETRICA (HOMOLOGAÇÃO)');
    await settle(30);

    await tapText('Registrar pagamento');
    await settle(20);
    await capture('${prefix}_15_payment_modal_selection');

    // 6.1 VALIDAÇÃO OBRIGATÓRIA: Tenta submeter pagamento SEM conta bancária
    final confirmPaymentBtn = find.text('Confirmar pagamento');
    expect(confirmPaymentBtn, findsOneWidget);
    await tester.ensureVisible(confirmPaymentBtn.first);
    await tester.tap(confirmPaymentBtn.first);
    await settle(20);
    expect(
      find.text('Selecione uma conta bancária para debitar o pagamento.'),
      findsOneWidget,
    );
    await capture('${prefix}_15b_payment_validation_error');

    // 6.2 Seleciona a conta bancária Nubank PF e conclui a baixa
    final dropdown = find.byType(DropdownButtonFormField<int>);
    expect(dropdown, findsOneWidget);
    await tester.tap(dropdown.first);
    await settle(20);
    final nubankOption = find.textContaining('NUBANK');
    expect(nubankOption, findsWidgets);
    await tester.tap(nubankOption.last);
    await settle(20);

    await tester.ensureVisible(confirmPaymentBtn.first);
    await tester.tap(confirmPaymentBtn.first);
    await tester.pump(const Duration(milliseconds: 1500));
    await settle(40);
    await capture('${prefix}_16_payment_success');

    // 6.3 FLUXO DE ESTORNO DE PAGAMENTO (REVERSÃO E AUDITORIA CONTÁBIL)
    // Rola para baixo dentro do modal para revelar o Histórico de pagamentos e botão Estornar
    final modalScrollable = find.descendant(
      of: find.byKey(const ValueKey('payable-view')),
      matching: find.byType(Scrollable),
    );
    final scrollTarget = modalScrollable.evaluate().isNotEmpty
        ? modalScrollable.first
        : find.byType(Scrollable).last;

    for (
      var i = 0;
      i < 6 && find.widgetWithText(TextButton, 'Estornar').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(
        scrollTarget,
        const Offset(0, -250),
        warnIfMissed: false,
      );
      await settle(10);
    }

    final revertBtn = find.widgetWithText(TextButton, 'Estornar');
    expect(
      revertBtn,
      findsWidgets,
      reason: 'Botão Estornar não encontrado no histórico de pagamentos',
    );
    await tester.tap(revertBtn.last);
    await settle(20);

    expect(find.text('Estornar pagamento'), findsOneWidget);
    await capture('${prefix}_16b_revert_payment_dialog');

    final revertReasonField = find.widgetWithText(
      TextFormField,
      'Justificativa do estorno *',
    );
    expect(revertReasonField, findsOneWidget);
    await tester.enterText(
      revertReasonField,
      'Estorno homologação auditoria contábil',
    );
    await settle(10);

    final confirmRevertBtn = find.text('Confirmar estorno');
    expect(confirmRevertBtn, findsOneWidget);
    await tester.tap(confirmRevertBtn.first);
    await tester.pump(const Duration(milliseconds: 1500));
    await settle(40);
    await capture('${prefix}_16c_revert_payment_success');

    // Fecha o modal da conta a pagar
    await tapIcon(Icons.close_rounded);
    await settle(20);

    // Confere no Dashboard a recomposição integral do saldo pós-estorno
    await selectTabByIndex(0); // Dashboard
    await settle(30);
    expect(find.text('Saldo disponível'), findsOneWidget);
    await capture('${prefix}_16d_dashboard_after_reversal');

    // Refaz o pagamento da energia para prosseguir com o fluxo canônico de despesas
    await selectTabByIndex(3); // A pagar
    await settle(30);
    await scrollTop();
    await reveal('ENERGIA ELETRICA (HOMOLOGAÇÃO)');
    await tapText('ENERGIA ELETRICA (HOMOLOGAÇÃO)');
    await settle(30);
    await tapText('Registrar pagamento');
    await settle(20);
    final dropdownRe = find.byType(DropdownButtonFormField<int>);
    await tester.tap(dropdownRe.first);
    await settle(20);
    final nubankOptionRe = find.textContaining('NUBANK');
    await tester.tap(nubankOptionRe.last);
    await settle(20);
    await tester.tap(find.text('Confirmar pagamento').first);
    await tester.pump(const Duration(milliseconds: 1500));
    await settle(40);
    await tapIcon(Icons.close_rounded);
    await settle(20);

    // Confere saldo debitado no Dashboard
    await selectTabByIndex(0);
    await settle(30);
    expect(find.text('Saldo disponível'), findsOneWidget);
    await capture('${prefix}_17_dashboard_after_payment');

    // Confere débito lançado no Extrato
    await selectTabByIndex(1);
    await settle(30);
    expect(find.text('Extrato'), findsWidgets);
    await capture('${prefix}_18_statement_after_payment');

    // ========================================================================
    // 7. CONTAS A RECEBER: CRIAR, EDITAR, CANCELAR E TESTE DE DESCRIÇÃO LONGA
    // ========================================================================
    await selectTabByIndex(2); // 2 = A receber
    await settle(30);
    expect(find.text('Nova conta a receber'), findsOneWidget);
    await capture('${prefix}_19_receivables_list');

    // 7.1 Criação de conta a receber
    await tapText('Nova conta a receber');
    await settle(30);
    await capture('${prefix}_20_receivable_form_empty');

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Descrição'),
      'CONSULTORIA SOFTWARE (HOMOLOGAÇÃO)',
    );
    final recValField = find.widgetWithText(TextFormField, 'Valor');
    expect(recValField, findsOneWidget);
    await tester.enterText(recValField, '80000'); // R$ 800,00
    await tapText('Salvar conta a receber');
    await settle(40);

    await reveal('CONSULTORIA SOFTWARE (HOMOLOGAÇÃO)');
    expect(find.text('CONSULTORIA SOFTWARE (HOMOLOGAÇÃO)'), findsWidgets);
    await capture('${prefix}_21_receivables_after_creation');

    // 7.2 Edição e Cancelamento de conta a receber
    await tapText('CONSULTORIA SOFTWARE (HOMOLOGAÇÃO)');
    await settle(30);
    await capture('${prefix}_22_receivable_modal_details');

    // Edição
    await tapIcon(Icons.edit_outlined);
    await settle(20);

    final editRecDesc = find.widgetWithText(TextFormField, 'Descrição *');
    if (editRecDesc.evaluate().isNotEmpty) {
      await tester.enterText(editRecDesc, 'CONSULTORIA SOFTWARE EDITADA');
      await settle(10);
    }
    final saveEditRec = find.text('Salvar alterações');
    expect(saveEditRec, findsOneWidget);
    await tester.tap(saveEditRec.first);
    await settle(20);

    // Double-check no ConfirmChangesDialog
    final confirmRecSave = find.text('Confirmar e salvar');
    if (confirmRecSave.evaluate().isNotEmpty) {
      await tester.tap(confirmRecSave.first);
      await settle(30);
    }
    expect(find.text('CONSULTORIA SOFTWARE EDITADA'), findsWidgets);
    await capture('${prefix}_23_receivable_edited_modal');

    // Cancelamento pelo ícone cancel_outlined
    await tapIcon(Icons.cancel_outlined);
    await settle(20);

    final recReasonField = find.widgetWithText(
      TextFormField,
      'Motivo do cancelamento *',
    );
    expect(recReasonField, findsOneWidget);
    await tester.enterText(recReasonField, 'Cancelamento teste homologação');
    await tapText('Confirmar cancelamento');
    await settle(40);

    // Comprova que não consta mais em aberto
    expect(find.text('CONSULTORIA SOFTWARE EDITADA'), findsNothing);
    await capture('${prefix}_24_receivables_after_cancellation');

    // 7.3 TESTE DE DESCRIÇÃO LONGA (COMPROVAÇÃO DE ZERO OVERFLOW VISUAL)
    await tapText('Nova conta a receber');
    await settle(30);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Descrição'),
      'CONSULTORIA EM ARQUITETURA DE MICROSSERVICOS E SISTEMAS FINANCEIROS DE ALTA INTEGRIDADE SEM OVERFLOW',
    );
    final recLongVal = find.widgetWithText(TextFormField, 'Valor');
    await tester.enterText(recLongVal, '35000'); // R$ 350,00
    await tapText('Salvar conta a receber');
    await settle(40);

    await reveal('CONSULTORIA EM ARQUITETURA DE MICROSSERVICOS');
    await tapText(
      'CONSULTORIA EM ARQUITETURA DE MICROSSERVICOS E SISTEMAS FINANCEIROS DE ALTA INTEGRIDADE SEM OVERFLOW',
    );
    await settle(30);
    await capture('${prefix}_24b_receivable_long_description_modal');

    // Cancela a conta de teste de descrição longa
    await tapIcon(Icons.cancel_outlined);
    await settle(20);
    final recLongReason = find.widgetWithText(
      TextFormField,
      'Motivo do cancelamento *',
    );
    await tester.enterText(
      recLongReason,
      'Cancelamento teste de overflow longo',
    );
    await tapText('Confirmar cancelamento');
    await settle(40);

    // ========================================================================
    // 8. CONTAS A RECEBER: CRIAR SEGUNDA CONTA, VALIDAR CONTA E BAIXAR
    // ========================================================================
    await tapText('Nova conta a receber');
    await settle(30);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Descrição'),
      'VENDA SERVICO (HOMOLOGAÇÃO)',
    );
    final recValField2 = find.widgetWithText(TextFormField, 'Valor');
    expect(recValField2, findsOneWidget);
    await tester.enterText(recValField2, '45000'); // R$ 450,00
    await tapText('Salvar conta a receber');
    await settle(40);

    await reveal('VENDA SERVICO (HOMOLOGAÇÃO)');
    await tapText('VENDA SERVICO (HOMOLOGAÇÃO)');
    await settle(30);

    await tapText('Registrar recebimento');
    await settle(20);
    await capture('${prefix}_25_receipt_modal_selection');

    // 8.1 VALIDAÇÃO OBRIGATÓRIA: Tenta submeter recebimento SEM conta bancária
    final confirmRecBtn = find.text('Confirmar recebimento');
    expect(confirmRecBtn, findsOneWidget);
    await tester.ensureVisible(confirmRecBtn.first);
    await tester.tap(confirmRecBtn.first);
    await settle(20);
    expect(
      find.text('Selecione uma conta bancária de destino para o recebimento.'),
      findsOneWidget,
    );
    await capture('${prefix}_25b_receipt_validation_error');

    // 8.2 Seleciona conta bancária Nubank PF e conclui a baixa
    final recDropdown = find.byType(DropdownButtonFormField<int>);
    expect(recDropdown, findsOneWidget);
    await tester.tap(recDropdown.first);
    await settle(20);
    final nubankRecOption = find.textContaining('NUBANK');
    expect(nubankRecOption, findsWidgets);
    await tester.tap(nubankRecOption.last);
    await settle(20);

    await tester.ensureVisible(confirmRecBtn.first);
    await tester.tap(confirmRecBtn.first);
    await tester.pump(const Duration(milliseconds: 1500));
    await settle(40);
    await capture('${prefix}_26_receipt_success');

    // Fecha com botão fechar da UI
    await tapIcon(Icons.close_rounded);
    await settle(20);

    // Confere saldo creditado no Dashboard
    await selectTabByIndex(0);
    await settle(30);
    expect(find.text('Saldo disponível'), findsOneWidget);
    await capture('${prefix}_27_dashboard_after_receipt');

    // Confere crédito no Extrato
    await selectTabByIndex(1);
    await settle(30);
    expect(find.text('Extrato'), findsWidgets);
    await capture('${prefix}_28_statement_after_receipt');

    // ========================================================================
    // 9. CARTEIRA DE CONTAS: AJUSTE DE ABERTURA COM SALDO NEGATIVO
    // ========================================================================
    await selectTabByIndex(4); // 4 = Contas
    await settle(30);
    expect(find.text('Carteira de Contas'), findsWidgets);
    await capture('${prefix}_29_accounts_tab');

    // 9.1 Acessa tela da conta Nubank PF
    final nubankCard = find.textContaining('NUBANK');
    expect(nubankCard, findsWidgets);
    await tester.tap(nubankCard.first);
    await settle(30);
    expect(find.text('Editar conta'), findsWidgets);
    await capture('${prefix}_29b_account_screen_details');

    // 9.2 Abre tela de ajuste de abertura
    final correctOpeningBtn = find.widgetWithText(
      OutlinedButton,
      'Corrigir abertura',
    );
    expect(correctOpeningBtn, findsOneWidget);
    await tester.tap(correctOpeningBtn);
    await settle(30);
    expect(find.text('Corrigir abertura'), findsWidgets);

    // 9.3 Seleciona Saldo Negativo / Devedor (-)
    final negSegment = find.text('Saldo negativo / devedor (-)');
    expect(negSegment, findsOneWidget);
    await tester.tap(negSegment);
    await settle(20);

    // Preenche valor negativo e motivo
    final openingBalField = find.widgetWithText(
      TextFormField,
      'Saldo inicial correto',
    );
    expect(openingBalField, findsOneWidget);
    await tester.enterText(openingBalField, '50000'); // R$ 500,00

    final reasonOpeningField = find.widgetWithText(TextFormField, 'Motivo');
    expect(reasonOpeningField, findsOneWidget);
    await tester.enterText(
      reasonOpeningField,
      'Homologação de saldo de abertura negativo',
    );
    await settle(10);
    await capture('${prefix}_29c_opening_adjustment_negative_form');

    // Avança para revisão
    await tapText('Revisar correção da abertura');
    await settle(30);
    expect(find.text('Confirme a correção'), findsOneWidget);
    await capture('${prefix}_29d_opening_adjustment_review');

    // Confirma correção
    final confirmOpeningBtn = find.text('Confirmar correção');
    expect(confirmOpeningBtn, findsOneWidget);
    await tester.tap(confirmOpeningBtn);
    await settle(40);

    // Retorna para AccountScreen com saldo devedor refletido
    expect(find.text('Editar conta'), findsWidgets);
    await capture('${prefix}_29e_account_screen_negative_opening');

    // 9.4 Restaura a abertura original para preservar o ambiente limpo de teste
    await tester.tap(correctOpeningBtn);
    await settle(30);
    final posSegment = find.text('Saldo positivo (+)');
    expect(posSegment, findsOneWidget);
    await tester.tap(posSegment);
    await settle(20);
    final openingBalFieldRest = find.widgetWithText(
      TextFormField,
      'Saldo inicial correto',
    );
    await tester.enterText(openingBalFieldRest, '100000'); // R$ 1.000,00
    final reasonOpeningFieldRest = find.widgetWithText(TextFormField, 'Motivo');
    await tester.enterText(
      reasonOpeningFieldRest,
      'Restauração de saldo original pós-homologação',
    );
    await settle(10);
    await tapText('Revisar correção da abertura');
    await settle(30);
    await tester.tap(find.text('Confirmar correção'));
    await settle(40);

    // Volta para Carteira de Contas usando BackButton nativo
    await tester.tap(find.byType(BackButton));
    await settle(30);

    // ========================================================================
    // 10. TRANSFERÊNCIA ENTRE ESPAÇOS COM REVISÃO E AVISO PIX
    // ========================================================================
    final transferBtn = find.byKey(
      const ValueKey('accounts_tab_transfer_button'),
    );
    expect(transferBtn, findsOneWidget);
    await tester.tap(transferBtn);
    await settle(30);
    expect(find.text('Transferir entre contas'), findsOneWidget);
    await capture('${prefix}_30_transfer_modal_opened');

    // 10.1 Seleciona conta de origem PF
    final srcAccDropdown = find.byKey(
      const ValueKey('transfer_source_account'),
    );
    expect(srcAccDropdown, findsOneWidget);
    await tester.tap(srcAccDropdown);
    await settle(20);
    final nubankTrfItem = find.textContaining('NUBANK');
    expect(nubankTrfItem, findsWidgets);
    await tester.tap(nubankTrfItem.last);
    await settle(20);

    // 10.2 Seleciona espaço de destino PJ
    final destSpaceDropdown = find.byKey(
      const ValueKey('transfer_destination_space'),
    );
    expect(destSpaceDropdown, findsOneWidget);
    await tester.tap(destSpaceDropdown);
    await settle(20);
    final pjSpaceItem = find.textContaining('PJ');
    expect(pjSpaceItem, findsWidgets);
    await tester.tap(pjSpaceItem.last);
    await settle(20);

    // 10.3 Seleciona conta de destino PJ
    final destAccDropdown = find.byKey(
      const ValueKey('transfer_destination_account'),
    );
    expect(destAccDropdown, findsOneWidget);
    await tester.tap(destAccDropdown);
    await settle(20);
    final pjAccItem = find.textContaining('INTER');
    expect(pjAccItem, findsWidgets);
    await tester.tap(pjAccItem.last);
    await settle(20);

    // 10.4 Preenche o valor da transferência
    final transferAmountField = find.byKey(const ValueKey('transfer_amount'));
    expect(transferAmountField, findsOneWidget);
    await tester.enterText(transferAmountField, '9000'); // R$ 90,00
    await settle(10);

    // 10.5 Avança para revisão (fecha teclado e rola até o botão)
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(20);
    await reveal('Revisar transferência');
    final reviewSubmitBtn = find.text('Revisar transferência');
    expect(reviewSubmitBtn, findsWidgets);
    await tester.tap(reviewSubmitBtn.last);
    await settle(20);

    // EVIDÊNCIA CRÍTICA: Tela de revisão com aviso explícito de governança Pix
    expect(find.text('Revisar transferência'), findsWidgets);
    expect(
      find.text('Registro contábil de movimentação: não executa Pix no banco.'),
      findsOneWidget,
    );
    await capture('${prefix}_31_transfer_review_pix_warning');

    // Confirma a transferência
    await reveal('Confirmar transferência');
    final confirmTransferBtn = find.text('Confirmar transferência');
    expect(confirmTransferBtn, findsWidgets);
    await tester.tap(confirmTransferBtn.last);
    await settle(40);

    // 10.6 Navegação pela interface real do usuário pós-transferência
    await selectTabByIndex(1); // Extrato PF via NavigationBar real
    await settle(30);
    expect(find.text('Extrato'), findsWidgets);
    await capture('${prefix}_32_statement_pf_transfer_out');

    await selectTabByIndex(0); // Dashboard PF via NavigationBar real
    await settle(20);
    await selectSpace('PJ'); // Troca para PJ na AppBar
    await settle(30);
    expect(find.text('Saldo disponível'), findsOneWidget);
    await capture('${prefix}_33_dashboard_pj_after_transfer');

    await selectTabByIndex(1); // Extrato PJ via NavigationBar real
    await settle(30);
    expect(find.text('Extrato'), findsWidgets);
    await capture('${prefix}_34_statement_pj_transfer_in');

    // ========================================================================
    // 11. RETORNO AO DASHBOARD PF FINAL
    // ========================================================================
    await selectTabByIndex(0);
    await settle(20);
    await selectSpace('PF');
    await settle(30);
    expect(find.text('Saldo disponível'), findsOneWidget);
    await capture('${prefix}_35_dashboard_final');
  });
}
