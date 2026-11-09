# Modo de Entrada Flexível de Parcelas (Por Parcela vs. Valor Total) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir ao usuário alternar entre informar o valor da parcela individual ou o valor total do parcelamento nos formulários de Contas a Pagar e Contas a Receber, exibindo uma caixa de resumo discreta com a multiplicação/divisão exata em tempo real.

**Architecture:** Introduzir um seletor de modo (`_InstallmentAmountMode { byInstallment, byTotal }`) com `byInstallment` como padrão no parcelamento. Calcular o valor total em centavos inteiros via `Money` (`cents * count`) garantindo zero float. Exibir um card compacto com o resumo (`Nx de R$ X,XX • Total: R$ Y,YY`) e enviar o total calculado para a API.

**Tech Stack:** Flutter / Dart (3.x), Material 3, Widgets customizados (`SegmentedButton`, `AppTokens`, `Money`).

**Spec:** Especificação de design aprovada pelo usuário na sessão de 09/11/2026.

## Global Constraints
- **Zero Float:** Manipulação monetária estritamente em centavos inteiros de 64 bits (`Money`).
- **Compatibilidade de API:** A API Laravel espera `total` e `installment_count`; o frontend envia o total calculado exato.
- **Backpressure Pré-Push:** 100% verde em `flutter analyze`, `dart format` e `flutter test`.

---

### Task 1: Componente Reutilizável de Resumo de Parcelas
**Files:**
- Create: `apps/mobile/lib/ui/installment_summary_card.dart`
- Test: `apps/mobile/test/ui/installment_summary_card_test.dart`

- [x] **Passo 1.1:** Criar teste de widget para `InstallmentSummaryCard` verificando exibição de `Nx de R$ X,XX • Total: R$ Y,YY`.
- [x] **Passo 1.2:** Executar teste para verificar falha inicial (TDD).
- [x] **Passo 1.3:** Implementar `InstallmentSummaryCard` com estilo compacto, ícone suave e formatação em BRL.
- [x] **Passo 1.4:** Executar teste e validar sucesso.

### Task 2: Suporte a Modo de Parcela em Contas a Pagar (`PayableFormScreen`)
**Files:**
- Modify: `apps/mobile/lib/features/payables/payable_form_screen.dart`
- Test: `apps/mobile/test/features/payables_test.dart`

- [x] **Passo 2.1:** Adicionar teste unitário em `payables_test.dart` simulando preenchimento de 45 parcelas de R$ 505,02 no modo "Por parcela" e validando que o cronograma gerado envia o total de R$ 22.725,90.
- [x] **Passo 2.2:** Executar teste e comprovar falha.
- [x] **Passo 2.3:** Implementar o seletor `SegmentedButton` ("Valor da parcela" vs "Valor total"), cálculo reativo do total quando em modo parcela, e exibição do `InstallmentSummaryCard`.
- [x] **Passo 2.4:** Executar suíte de testes de `payables_test.dart` e garantir 100% verde.

### Task 3: Suporte a Modo de Parcela em Contas a Receber (`AgreementFormScreen`)
**Files:**
- Modify: `apps/mobile/lib/features/agreements/agreement_form_screen.dart`
- Test: `apps/mobile/test/features/agreement_form_screen_test.dart`

- [x] **Passo 3.1:** Adicionar teste unitário em `agreement_form_screen_test.dart` simulando criação de conta a receber por parcela e validando o envio do total calculado.
- [x] **Passo 3.2:** Executar teste e comprovar falha.
- [x] **Passo 3.3:** Implementar seletor e `InstallmentSummaryCard` em `AgreementFormScreen` quando parcelas > 1.
- [x] **Passo 3.4:** Executar testes e garantir aprovação.

### Task 4: Backpressure Completo e Validação Visual
- [x] **Passo 4.1:** Executar `dart format` e `flutter analyze` em `apps/mobile`.
- [x] **Passo 4.2:** Executar `./scripts/check.sh --fast` e validar suíte Flutter completa.
- [x] **Passo 4.3:** Realizar hot restart no Flutter Web (`task-2440`) e validar comportamento.
