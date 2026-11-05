# Web Desktop Layout & Extrato Unificado Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar o layout adaptativo para Web/Desktop com Sidebar lateral elegante e a capability de Extrato Unificado (Timeline de movimentações financeiras) no BigDev.Z Finance.

**Architecture:** 
- **Backend:** Endpoint `GET /api/spaces/{space}/statement` que consulta a tabela `account_movements` vinculada às contas do espaço ativo (`space_id`), com enriquecimento semântico de relacionamentos polimórficos (`receipt`, `payment`, `transfer`, `reversals`, `loan`), filtros opcionais por conta, direção e período, serializado via `StatementResource`.
- **Frontend Flutter:** Modelo `StatementEntry`, repositório `StatementRepository`, aba `StatementTab` com listagem cronológica agrupada por data, badges coloridos, filtros dinâmicos e privacidade financeira (`obscureValues`); e refatoração adaptativa de `HomeShell` para exibir uma Sidebar lateral rica em viewports $\ge 840$pt e `NavigationBar` em telas menores.

**Tech Stack:** Laravel 13, PostgreSQL 18, Flutter 3.x / Dart 3.x, Docker Compose.

**Spec:** [`specs/extrato/extrato.md`](../../specs/extrato/extrato.md)

---

## Global Constraints

- Proibição estrita de float/double para valores monetários (AC-EXT-005, ADR 0002).
- Isolamento multi-tenant estrito por `space_id` com proteção IDOR (404 Not Found para recursos de terceiros) (AC-EXT-004).
- Acessibilidade e reflow responsivo com suporte a texto ampliado até 200% sem overflow (AC-EXT-007).
- Preservação da privacidade financeira (`obscureValues`) em conformidade com fail-closed (AC-EXT-007).
- Suíte `scripts/check.sh --full` 100% verde com ZERO erros antes de submeter ao mantenedor.

---

## Tasks

### Task 1: Backend Statement API & Tests (TDD)
- [ ] Criar teste de integração `apps/api/tests/Feature/StatementTest.php` cobrindo:
  - Movimentações de recebimento, pagamento, estorno, transferência e empréstimo com classificação correta de direção (`credit`/`debit`).
  - Ordenação cronológica decrescente (`effective_date DESC, id DESC`).
  - Filtro por `account_id` válido e proteção IDOR (404 para conta alheia).
  - Filtros por `direction` e intervalo de datas `from`/`to`.
  - Isolamento multi-tenant entre PF e PJ.
- [ ] Implementar `StatementResource.php` em `apps/api/app/Http/Resources/`.
- [ ] Implementar `StatementController.php` em `apps/api/app/Http/Controllers/Api/` com injeção de espaço e consultas otimizadas com eager loading (`account`, `receipt.agreement`, `payment.payable`, `transfer.sourceAccount`, `transfer.destinationAccount`, `loanDisbursement`).
- [ ] Registrar rota `GET /api/spaces/{space}/statement` em `apps/api/routes/api.php`.
- [ ] Executar testes de integração com `docker compose exec api php artisan test --filter=StatementTest` e validar com Laravel Pint.

### Task 2: Flutter Statement Model & Repository
- [ ] Criar testes unitários em `apps/mobile/test/features/statement_test.dart` validando parsing JSON de `StatementEntry` (direção, valor, datas, conta, tipo).
- [ ] Criar entidade e enum `StatementDirection` em `apps/mobile/lib/features/statement/statement_entry.dart`.
- [ ] Implementar `StatementRepository` em `apps/mobile/lib/features/statement/statement_repository.dart` consumindo `GET /api/spaces/{space}/statement`.

### Task 3: Flutter Statement Tab (UI & Filtros)
- [ ] Criar testes de widget em `apps/mobile/test/features/statement_tab_test.dart` cobrindo:
  - Renderização da lista de movimentações com badges de entrada (verde) e saída (vermelho).
  - Mascaramento semântico com `PreferencesController.obscureValues`.
  - Estado vazio amigável quando não houver movimentações.
  - Filtro interativo por conta e por tipo (Todos, Entradas, Saídas).
- [ ] Implementar `StatementTab` em `apps/mobile/lib/features/statement/statement_tab.dart`.

### Task 4: Adaptive HomeShell & Desktop Sidebar (Web/Desktop)
- [ ] Criar testes de widget em `apps/mobile/test/features/home_shell_test.dart` cobrindo:
  - Renderização de Sidebar lateral em largura $\ge 840$pt com os 5 destinos (Resumo, Extrato, A Receber, A Pagar, Contas).
  - Renderização de `NavigationBar` inferior em largura $< 840$pt.
  - Alternância de abas e preservação de estado.
- [ ] Atualizar `HomeShell` em `apps/mobile/lib/features/home/home_shell.dart` para renderizar layout responsivo com `AppSidebar` quando `MediaQuery.sizeOf(context).width >= 840`.

### Task 5: Validação do Backpressure & Subida do Ambiente Local
- [ ] Executar suíte completa: `bash scripts/check.sh --full`.
- [ ] Verificar ausência de erros no Pint, Dart format, Flutter analyze, testes de domínio e testes de integração.
- [ ] Subir o dev server Flutter Web localmente na porta 8085 (`flutter run -d web-server --web-port=8085`) para validação humana de Jeann Lucas.
