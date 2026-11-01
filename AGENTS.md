# BigDev.Z Finance — Instruções Locais de Governança e Engenharia

> **Autoridade:** Padrão Oficial de Engenharia BigDev.Z de Jeann Lucas.<br>
> **Filosofia Central:** A máquina dá o primeiro NÃO antes de qualquer humano inspecionar (*Backpressure*). O código responde a contratos duradouros (*Spec-Anchored*).<br>
> **Governança Canônica:** As diretrizes permanentes deste repositório estão consolidadas em [`docs/project-guidelines.md`](docs/project-guidelines.md), nos ADRs em [`docs/decisions/`](docs/decisions/), nas especificações permanentes em [`specs/`](specs/) e nas instruções deste arquivo.

---

## 1. Identidade e Domínio do Produto

- **Estado:** DESENVOLVIMENTO ATIVO.
- **Produto:** BigDev.Z Finance — Sistema financeiro patrimonial pessoal e empresarial (multi-espaço PF/PJ) de alta integridade e exatidão matemática.
- **Arquitetura:**
  - **Mobile:** Flutter / Dart por funcionalidades em `apps/mobile/` (`features/accounts`, `payables`, `agreements`, `summary`).
  - **Backend:** Monólito modular em Laravel 13 em `apps/api/` com Actions dedicadas (`ReceiveInstallment`, `ReverseReceipt`, `PayPayable`, `ReversePayment`, `AdjustAccountOpening`).
  - **Banco de Dados:** PostgreSQL com restrições compostas `(id, space_id)` e locks transacionais consultivos para concorrência e idempotência. Acessível somente pelo backend.
- **Idioma e Formato:** Respostas, documentação e mensagens de commit em pt-BR. Sem co-autores (não adicionar linhas `Co-Authored-By`). Licença MIT formalizada ([LICENSE](LICENSE)). Nenhum deploy de produção automatizado.

---

## 2. Regras Financeiras Inegociáveis (Núcleo de Negócio)

1. **Dinheiro Exato (Zero Float):** É expressamente proibido o uso de `float` ou `double` para cálculo, manipulação ou armazenamento de dinheiro. Strings decimais canônicas com duas casas na API (`"2000.00"`), centavos inteiros de 64 bits no núcleo (`200000`) e limite individual de `999999999999.99` (`Money::MAX_CENTS`). Totais agregados utilizam `Money::formatAggregate()` sem truncamento. Ler ADR `0002` antes de qualquer intervenção monetária.
2. **Compromissos Previstos não Alteram Saldo Disponível:** Contas a pagar em aberto, parcelas vincendas, faturas futuras e recorrências programadas representam projeção orçamentária e jamais alteram o saldo disponível da conta bancária. O saldo disponível é a soma algébrica de abertura com movimentações liquidadas.
3. **Isolamento Multi-Tenant por Espaço (PF/PJ):** Toda operação valida obrigatoriamente usuário autenticado, espaço (`space_id`) e integridade relacional entre entidades. Prevenção ativa contra vulnerabilidades IDOR/BOLA (tentativas de acesso indevido respondem `404 Not Found`).
4. **Atomicidade e Proteção sob Concorrência:** Recebimento/pagamento e movimentação de conta ocorrem estritamente na mesma transação de banco de dados, protegidos por locks pessimistas ordenados (`lockForUpdate`).
5. **Idempotência Persistida por Chave:** Mutações financeiras exigem cabeçalho `Idempotency-Key` único por espaço. Replay de sucesso devolve estado atualizado; payload divergente para a mesma chave gera `409 Conflict`.
6. **Divisão Determinística e Preservação de Vencimento:** Distribuição de centavos restantes de parcelas ocorre nas primeiras parcelas; preservação do dia de referência de vencimento em meses curtos e bissextos.
7. **Imutabilidade Contábil:** Lançamentos financeiros liquidados nunca sofrem exclusão física (`DELETE`). Correções e compensações utilizam estornos com contra-movimentação algébrica inversa preservando auditoria.
8. **Segregação de Bancos:** Ambientes de desenvolvimento e teste operam em bancos distintos (`bigdevz_finance` vs. `bigdevz_finance_test`). Jamais execute reset ou drop manual de banco.

---

## 3. Soberania Humana e Governança de Git

1. **Autoridade Exclusiva:** Commits, pushes e merges para qualquer branch são de autoridade exclusiva de Jeann Lucas. Nenhuma IA faz push ou merge sem autorização prévia, específica e explícita do mantenedor.
2. **Estratégia Obrigatória de Branches:**
   - `main`: Branch de **PRODUÇÃO** (estável, auditada e protegida). Proibido desenvolvimento direto nela.
   - `dev`: Branch de **DESENVOLVIMENTO** e integração contínua.
   - `feature/<nome>` ou `fix/<nome>`: Toda nova tarefa cria uma branch dedicada a partir da `dev` (preferencialmente via Git Worktree) e faz merge de volta para a `dev` após testes 100% verdes e aprovação humana.
3. **Prevenção de Force Push:** Proibido o uso de `git push --force` ou reescrita destrutiva de histórico remoto.
4. **Verificação Prévia:** Antes de intervir no repositório, conferir status (`git status`), branches (`git branch -a`) e histórico (`git log -n 5`).

---

## 4. Auditoria de Segurança Docker e Gestão de Portas Locais

1. **Gestão Preventiva de Portas (Zero Conflitos no Mac):**
   - Antes de iniciar qualquer container (`docker compose up`) ou dev server local, o agente DEVE verificar se a porta pretendida no host está livre usando `lsof -i :<porta>` ou `docker ps`.
   - Se houver colisão de porta com outros projetos ativos no Mac, sugira portas livres alternativas parametrizadas via variáveis de ambiente, sem derrubar containers de terceiros.
2. **Segurança de Variáveis de Ambiente (.env):**
   - **Zero Credenciais Rastreadas:** Nunca criar, ler, editar ou commitar arquivos `.env` reais. Toda configuração utiliza exclusivamente `.env.example` com placeholders seguros.
   - Variáveis sensíveis e segredos nunca são impressos em logs, artefatos ou terminais.
3. **Segurança de Containers:**
   - `.dockerignore`: Bloqueia `.env*` permitindo apenas `!.env.example`.
   - `Dockerfile`: Multi-stage build com execução exclusiva sob usuário não-root (`USER appuser`), sem senhas gravadas em camadas da imagem.
   - `docker-compose.yml`: Mapeamento de portas com bind local seguro (`127.0.0.1`), portas customizáveis por variáveis de ambiente e **zero senhas utilizáveis embutidas em fallbacks**.

---

## 5. Fidelidade à Stack e Proibição de Alucinação de APIs

1. **Zero Invenção de Métodos:** É expressamente proibido supor métodos, parâmetros ou inventar assinaturas de funções inexistentes na stack ou em bibliotecas.
2. **Consulta Obrigatória à Versão Real:** O agente DEVE verificar as versões instaladas (`composer.lock`, `pubspec.lock`) e inspecionar os arquivos de definição de tipos ou documentação oficial antes de escrever código.
3. **Sem Dependências Não Solicitadas (YAGNI):** Proibido instalar pacotes, bibliotecas ou dependências novas no `composer.json` ou `pubspec.yaml` sem autorização prévia e explícita de Jeann Lucas. Priorize sempre o núcleo da linguagem e as dependências já instaladas.

---

## 6. As Camadas de Contexto, Specs (L2) e Continuidade (Handoff)

- **L1 (Operacional):** As diretrizes deste arquivo e o ecossistema de engenharia do repositório.
- **L2 (Contratos de Negócio - Specs Permanentes):** Toda funcionalidade relevante responde a uma especificação permanente em `specs/<capability>/<capability>.md`, estruturada com critérios de aceite numerados (`AC-FIN-001`, `AC-FIN-002`, etc.) e matriz de rastreabilidade.
- **L3 (Planos Efêmeros):** Planos de trabalho pontuais que guiam a sessão imediata e são descartados ou consolidados após a entrega.
- **Continuidade Operacional (Handoff):**
  - Ao iniciar qualquer intervenção, consulte obrigatoriamente [`docs/ai/HANDOFF.md`](docs/ai/HANDOFF.md) para retomar exatamente do checkpoint onde o trabalho anterior parou.
  - Ao pausar a sessão ou atingir limites de contexto, atualize [`docs/ai/HANDOFF.md`](docs/ai/HANDOFF.md) registrando estado, comandos executados, branches, commits e próximos passos imediatos. O arquivo [`HANDOFF.md`](HANDOFF.md) na raiz permanece como registro histórico consolidado.

---

## 7. O Ciclo de Desenvolvimento e Backpressure Pré-Push

1. **Delta Provado:** Antes de implementar qualquer correção ou feature, comprove no terminal a falha ou ausência da funcionalidade (teste vermelho, log de erro ou resposta de rota).
2. **Desenvolvimento Guiado por Testes (TDD):**
   - Escreva o teste primeiro ancorado no Critério de Aceite da spec (`AC-XXX-00X`).
   - Escreva o código mínimo necessário para tornar o teste verde.
   - Refatore eliminando complexidade desnecessária (Clean Code / DRY / YAGNI).
3. **Espelhamento Fiel do GitHub CI:**
   - O comando local de qualidade é `make check` (ou `./scripts/check.sh --full`).
   - Ele espelha 100% das checagens executadas no `.github/workflows/ci.yml`:
     1. Domínio financeiro PHP (`php tests/domain.php` - 13 testes de precisão e datas).
     2. Linter e Estilo PHP (`vendor/bin/pint --test`).
     3. Análise Estática Dart (`flutter analyze`).
     4. Formatação Dart (`dart format --output=none --set-exit-if-changed`).
     5. Suíte Flutter (`flutter test` - 162 testes de widgets e fluxos).
     6. Suíte de Integração da API Laravel (`php artisan test` em PostgreSQL `bigdevz_finance_test` real descartável, validando concorrência, idempotência e isolamento).
4. **REGRA INEGOCIÁVEL DE PRÉ-PUSH:**
   - Nenhum push para o GitHub pode ser sugerido ou solicitado sem que `make check` tenha sido executado e passado com **ZERO erros** no terminal do Mac.
   - Se qualquer verificação falhar, o agente deve corrigir o problema no loop interno antes de apresentar o trabalho a Jeann Lucas.

---

## 8. Formato Obrigatório de Entrega

Toda entrega de implementação, refatoração ou configuração deve ser apresentada a Jeann Lucas estruturada obrigatoriamente no seguinte formato:

1. **O que foi feito?** — Resumo executivo em tópicos claros e objetivos explicando o que foi implementado ou configurado.
2. **Critérios de Aceite Atendidos** — Lista dos critérios da spec (`AC-FIN-00X`, etc.) que foram satisfeitos com links para as evidências.
3. **Arquivos Alterados** — Tabela ou lista de arquivos criados ou modificados.
4. **Comprovação de Backpressure** — Comando de verificação executado e o log comprovando 100% de sucesso (zero erros).
5. **Evidência Visual (se envolver Frontend)** — Screenshots e relatórios de interface/acessibilidade comprovando conformidade visual e ausência de erros no console.
