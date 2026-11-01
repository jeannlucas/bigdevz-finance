# Especificação Permanente da Capability [Nome da Capability]

> **Capability:** `[nome-em-kebab-case]`<br>
> **Status:** [Rascunho | Proposta | Ativo / Canônico | Descontinuado]<br>
> **Referência de Governança:** `AGENTS.md`, `specs/README.md`<br>
> **Regra de Ouro:** O código e os testes respondem a esta especificação; qualquer divergência (*drift*) é considerada defeito de primeira classe.

---

## 1. Visão Geral da Capability

[Descrição de alto nível do que esta capability resolve, quais módulos do sistema ela engloba e seu valor para o produto e para o negócio.]

---

## 2. Critérios de Aceite Numerados (AC-[SIGLA])

### 2.1. Regras Fundamentais e Invariantes de Negócio

- **AC-[SIGLA]-001 [Título do Critério]:**
  - [Descrição detalhada, precisa e determinística da regra.]
  - [Comportamento esperado com exemplos de entrada e saída.]

- **AC-[SIGLA]-002 [Título do Critério]:**
  - [Descrição detalhada da regra.]

### 2.2. Isolamento, Segurança e Integridade

- **AC-[SIGLA]-003 [Isolamento de Espaço (Multi-tenant) e Autenticação]:**
  - [Como o acesso é segregado por usuário/espaço PF/PJ e proteção contra IDOR.]

### 2.3. Idempotência e Tratamento de Falhas

- **AC-[SIGLA]-004 [Idempotência e Concorrência]:**
  - [Como requisições repetidas, reenvios de rede ou concorrência são tratados deterministicamente.]

---

## 3. Casos de Borda e Validações

| Cenário de Borda | Entrada | Comportamento Esperado | Código HTTP / Exceção |
| :--- | :--- | :--- | :--- |
| Exemplo 1 | Dados vazios / inválidos | Rejeição sem mutação de estado | `422 Unprocessable Entity` |
| Exemplo 2 | Chave reutilizada com payload divergente | Conflito explícito | `409 Conflict` |
| Exemplo 3 | Recurso de outro usuário/espaço | Não expor existência | `404 Not Found` |

---

## 4. Matriz de Rastreabilidade (Spec ↔ Código ↔ Testes)

| Critério de Aceite | Implementação (Backend / Mobile) | Testes Automatizados |
| :--- | :--- | :--- |
| **AC-[SIGLA]-001** | `caminho/para/arquivo.ext` | `caminho/para/teste.ext` |
| **AC-[SIGLA]-002** | `caminho/para/arquivo.ext` | `caminho/para/teste.ext` |
