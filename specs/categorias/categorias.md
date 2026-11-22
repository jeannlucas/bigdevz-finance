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

- **AC-CAT-007 [Subcategorias de 1 Nível e Validação de Espaço/Tipo]:**
  - Permite criar uma categoria principal (`parent_id = null`) e exatamente um nível de subcategorias (`parent_id` preenchido).
  - Validações estritas de integridade relacional:
    1. Pai e filha devem pertencer rigorosamente ao mesmo `space_id`;
    2. Pai e filha devem possuir o mesmo `type` (`income` ou `expense`);
    3. Chave estrangeira composta `FOREIGN KEY (parent_id, space_id) REFERENCES categories (id, space_id) ON DELETE RESTRICT`.
  - Exclusão de categoria principal que contenha subcategorias vinculadas é bloqueada com HTTP 422 e mensagem clara (`Não é possível excluir uma categoria que possui subcategorias.`), protegendo a hierarquia.

- **AC-CAT-008 [Prevenção de Ciclos, Autorreferência e Terceiro Nível]:**
  - É expressamente proibido criar terceiro nível: uma categoria com `parent_id` preenchido jamais pode ser definida como pai de outra categoria.
  - É proibida autorreferência (`parent_id == id`).
  - Uma categoria principal que já possua filhas não pode ser atualizada para possuir `parent_id`.
  - Tentativas de violar essas regras respondem com HTTP 422 Unprocessable Entity.

- **AC-CAT-009 [Agregação Hierárquica em Relatórios e Resumo]:**
  - Despesas e receitas podem ser classificadas diretamente na categoria principal, em uma subcategoria filha ou deixadas sem categoria (`category_id = null`).
  - Na visualização agrupada de relatórios e no Resumo (`SpaceController::summary`), o total do grupo é consolidado pela categoria principal somando os lançamentos diretos e os lançamentos em suas subcategorias filhas.
  - Cada despesa ou receita é computada exatamente uma única vez no total consolidado do espaço (zero dupla contagem).
  - A interface permite abrir e inspecionar a composição da categoria principal, discriminando o valor classificado diretamente nela e o valor de cada subcategoria individualmente (ex.: R$ 30,00 direto em Moradia + R$ 50,00 em Moradia > Energia = Grupo R$ 80,00, Filha R$ 50,00, Total do Espaço R$ 80,00).

- **AC-CAT-010 [Catálogo de Ícones, Paletas Predefinidas e Seletor Visual]:**
  - Mapeamento centralizado de identificadores estáveis para Material Icons oficiais:
    - Moradia: casa em azul (`home`).
    - Energia: raio em âmbar de alto contraste (`bolt`).
    - Água: gota em ciano (`water_drop`).
    - Mercado: carrinho em verde (`shopping_cart`).
    - Alimentação fora de casa: talheres em laranja (`restaurant`).
    - Transporte: veículo em índigo (`directions_car`).
    - Saúde: símbolo médico em turquesa (`medical_services`).
    - Folha de pagamento: pessoas em violeta (`groups`).
    - Tributos: documento em ocre (`description`).
    - Software e assinaturas: monitor em azul-petróleo (`computer`).
  - O seletor visual exibe símbolo, nome amigável em pt-BR e prévia da cor. A seleção do ícone preenche automaticamente a cor padrão recomendada, preservando a cor customizada caso o usuário a personalize.
  - Fallback gracioso para categorias antigas ou identificadores desconhecidos sem estourar erros.
  - Contraste verificado nos temas claro e escuro (inclusive para âmbar sobre fundo claro).

---

## 3. Matriz de Rastreabilidade (Spec ↔ Código ↔ Testes)

| Critério | Implementação Backend / Mobile | Testes Automatizados |
| :--- | :--- | :--- |
| **AC-CAT-001** | `Category.php`, migrations, `CategoryController.php` | `CategoriesTest.php` |
| **AC-CAT-002** | `Category.php`, restrição check SQL `type` | `CategoriesTest.php` |
| **AC-CAT-003** | `CategorySeeder.php`, `SpaceController.php` | `CategoriesTest.php` |
| **AC-CAT-004** | Migrations FK composta `(category_id, space_id)` | `CategoriesTest.php`, `PayablesTest.php` |
| **AC-CAT-005** | `CategoryController::destroy` (`is_default` check) | `CategoriesTest.php` |
| **AC-CAT-006** | `category_picker_field.dart`, `category_badge.dart` | `payable_category_edit_widget_test.dart` |
| **AC-CAT-007** | `Category.php`, migration `parent_id`, `CategoryController` | `SubcategoriesTest.php` |
| **AC-CAT-008** | Validações em `CategoryController` (ciclo/nível) | `SubcategoriesTest.php` |
| **AC-CAT-009** | `SpaceController::expenseCategoriesSummary`, Flutter summary | `SubcategoriesTest.php`, `summary_test.dart` |
| **AC-CAT-010** | `category_style_catalog.dart`, `CategoryIconColorPicker` | `category_icon_color_picker_test.dart` |
