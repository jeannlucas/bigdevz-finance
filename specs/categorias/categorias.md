# Especificação Permanente da Capability de Categorias Financeiras

> **Capability:** `categorias`<br>
> **Status:** Ativo / Canônico<br>
> **Referência de Governança:** `~/AGENTS.md`, `specs/README.md`, `specs/financeiro/financeiro.md`, ADRs `0001` a `0006`.<br>
> **Regra de Ouro:** O código e os testes respondem a esta especificação; qualquer divergência (*drift*) é considerada defeito de primeira classe.

---

## 1. Visão Geral da Capability

A capability **Categorias Financeiras** permite a classificação semântica de receitas e despesas tanto em espaços de Pessoa Física (PF) quanto Pessoa Jurídica (PJ). A categorização é opcional em lançamentos, preserva 100% o isolamento multi-tenant por espaço (`space_id`), provê categorias padrão prontas para uso imediato, permite a criação de categorias personalizadas e alimenta os gráficos analíticos de distribuição no Dashboard.

---

## 2. Critérios de Aceite Numerados (AC-CAT)

### 2.1. Regras Fundamentais e Invariantes de Dados

- **AC-CAT-001 [Isolamento Multi-Tenant Estrito e Prevenção IDOR]:**
  - Toda categoria pertence estritamente a um espaço (`space_id`).
  - Restrição de unicidade composta no banco: `UNIQUE (id, space_id)`.
  - Tentativas de consultar, atualizar ou vincular categorias de outro espaço retornam `404 Not Found`.
  - Nomes de categoria são únicos dentro do mesmo espaço e tipo: `UNIQUE (space_id, type, name)`.

- **AC-CAT-002 [Tipos Semânticos, Cores e Ícones]:**
  - Toda categoria possui tipo obrigatório: `'income'` (receita) ou `'expense'` (despesa), garantido por restrição de verificação no banco (`CHECK (type IN ('income', 'expense'))`).
  - Possui um identificador de ícone (`icon`, ex: `'shopping_cart'`, `'home'`, `'work'`, `'restaurant'`) e uma cor hexadecimal (`color`, ex: `'#1E5BB8'`, `'#0F8A5F'`, `'#E57373'`).

- **AC-CAT-003 [Seed Automático de Categorias Padrão PF e PJ]:**
  - O sistema provê categorias padrão iniciais com `is_default = true`:
    - **PF Receitas:** Salário, Rendimentos / Investimentos, Vendas, Outras Receitas.
    - **PF Despesas:** Moradia, Alimentação, Transporte, Saúde, Educação, Lazer, Outras Despesas.
    - **PJ Receitas:** Vendas de Produtos, Prestação de Serviços, Rendimentos, Outras Receitas.
    - **PJ Despesas:** Folha / Pró-labore, Fornecedores, Impostos, Aluguel / Infraestrutura, Marketing, Outras Despesas.

- **AC-CAT-004 [Vínculo Relacional Seguro]:**
  - `agreements`, `payables`, `payable_plans`, `recurrences` e `account_movements` aceitam `category_id` (opcional / nullable).
  - A integridade relacional entre `category_id` e a entidade utiliza chave composta `FOREIGN KEY (category_id, space_id) REFERENCES categories (id, space_id) ON DELETE SET NULL`.

- **AC-CAT-005 [Proteção de Integridade Contábil]:**
  - Categorias padrão (`is_default = true`) não podem ser excluídas pelo usuário.
  - Se uma categoria personalizada for excluída, os lançamentos existentes mantêm sua integridade contábil e passam a ter `category_id = null`.

- **AC-CAT-006 [Visualização Gráfica e Badges no Frontend]:**
  - Telas de cadastro e edição de contas a pagar e receber exibem seletor de categoria com ícone e cor.
  - Cards de contas e extrato exibem badges semânticos da categoria associada.
  - O Dashboard apresenta gráfico analítico de distribuição de gastos e entradas por categoria.
