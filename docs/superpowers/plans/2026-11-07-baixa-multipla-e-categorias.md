# Baixa Múltipla e Categorias - Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar baixa múltipla (em lote) no modal de parcelas e nas listagens gerais (A Receber e A Pagar), e criar o módulo completo de Categorias financeiras (API Laravel + App Flutter + Gráficos no Dashboard).

**Architecture:** 
- **Baixa Múltipla:** No frontend, gerenciamento de estado de seleção (`Set<int> selectedIds`), cálculo de totais monetários em centavos com `Money`, barra flutuante de ações em lote, e formulário unificado de liquidação com liquidação sequencial atômica via chaves idempotentes (`ReceiptAttempts` / `PayPayable`).
- **Categorias:** No backend Laravel, tabela e Model `Category` multi-tenant por `space_id` com chaves estrangeiras em `agreements`, `payables` e `account_movements`, seeder padrão para PF/PJ, e endpoints RESTful. No frontend Flutter, `CategoriesRepository`, seletor de categorias com ícones/cores, badges semânticos nos cards/extrato, e gráfico donut de distribuição no Dashboard.

**Tech Stack:** Laravel 13 (Actions, PostgreSQL, Pest/PHPUnit), Flutter 3.24+ (Dart, Provider, CanvasKit).

---

## Global Constraints
- Dinheiro exato (zero float): centavos inteiros de 64 bits (`cents`), formatação canônica de duas casas.
- Isolamento multi-tenant por espaço (`space_id` obrigatório em toda consulta e operação).
- Prevenção IDOR/BOLA: recursos de outro espaço retornam `404 Not Found`.
- Preservação de auditoria contábil e idempotência via `Idempotency-Key`.
- Backpressure inegociável: `make check` (ou suíte completa) 100% verde antes de qualquer conclusão.
- Soberania de Git: commits e merges na `dev` são autorizados pelo mantenedor; zero push para o remoto sem permissão expressa.

---

## Fases de Execução

### Fase 1: Baixa Múltipla no Modal de Parcelas (Contas a Receber e A Pagar)
- **Tarefa 1.1:** Adicionar seleção múltipla de parcelas no `agreement_modal.dart` (checkbox por parcela, "Selecionar todas", barra inferior com total e botão "Baixar selecionadas").
- **Tarefa 1.2:** Formulário unificado de baixa para múltiplas parcelas (seleção de conta de destino, data única, submissão sequencial com indicador de progresso N/Total).
- **Tarefa 1.3:** Testes de widget e fluxo no Flutter.

### Fase 2: Baixa Múltipla na Listagem Geral (Contas a Receber e Contas a Pagar)
- **Tarefa 2.1:** Modo de seleção múltipla em `agreements_tab.dart` com checkboxes e barra inferior flutuante (`FloatingActionBar`).
- **Tarefa 2.2:** Modal executivo de liquidação em lote para Contas a Receber.
- **Tarefa 2.3:** Modo de seleção múltipla em `payables_tab.dart` com checkboxes e barra inferior flutuante.
- **Tarefa 2.4:** Modal executivo de liquidação em lote para Contas a Pagar (com seleção de conta de origem).
- **Tarefa 2.5:** Testes unitários e de widgets da seleção e liquidação em lote.

### Fase 3: Módulo de Categorias (Backend Laravel + Mobile Flutter + Gráficos)
- **Tarefa 3.1:** Migration e Model `Category` no Laravel (`space_id`, `name`, `icon`, `color`, `type`, `is_default`), com relacionamento em `agreements`, `payables` e `account_movements`.
- **Tarefa 3.2:** Seeder de Categorias padrão para PF e PJ.
- **Tarefa 3.3:** Controller e rotas da API: `GET /api/v1/spaces/{space}/categories`, `POST`, `PUT`, `DELETE`.
- **Tarefa 3.4:** Suíte de testes da API de Categorias no PostgreSQL (`bigdevz_finance_test`).
- **Tarefa 3.5:** Model Dart `Category` e `CategoriesRepository` no app Flutter.
- **Tarefa 3.6:** Seletor de Categoria nos formulários de Nova Conta a Receber e Nova Conta a Pagar.
- **Tarefa 3.7:** Badge de categoria nos cards de A Receber, A Pagar e no Extrato.
- **Tarefa 3.8:** Gráfico de Rosca/Donut de Distribuição por Categoria no Dashboard (`dashboard_charts.dart`).
- **Tarefa 3.9:** Backpressure completo (`make check`).
