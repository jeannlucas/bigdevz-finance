# Relatório Operacional Diário do Piloto (Daily Operations Dashboard)

> **Produto:** BigDev.Z Finance  
> **Frequência:** Diária (Consolidação às 19:00 de cada dia do piloto)  
> **Responsáveis:** SRE Lead, QA Lead e Release Manager  
> **Objetivo:** Acompanhamento objetivo de saúde, segurança, conciliação e integridade durante os 14 dias de piloto.

---

## 1. Identificação do Dia Operacional

- **Data de Apuração:** `____/____/2026` (Dia `[  ] de 14` do ciclo de piloto)
- **Organizações Ativas no Piloto:** `____` espaços PJ / `____` espaços PF
- **Usuários Ativos no Dia:** `____` usuários únicos
- **Status Geral do Dia:** `[  ] VERDE (Sem intercorrências)   [  ] AMARELO (P2/P3 detectado)   [  ] VERMELHO (Incidente P0/P1)`

---

## 2. Indicadores de Infraestrutura e Disponibilidade (SLOs)

| Métrica | Meta / Limite de Alerta | Medição do Dia | Status |
| :--- | :---: | :---: | :---: |
| **Disponibilidade da API (`/api/health`)** | 99.9% (máx 1 min indisponível) | `____%` | [ ] OK [ ] Alerta |
| **Latência Média de Resposta (P95)** | < 80 ms | `____ ms` | [ ] OK [ ] Alerta |
| **Latência de Consulta ao Banco (PostgreSQL)** | < 15 ms | `____ ms` | [ ] OK [ ] Alerta |
| **Taxa de Erros 5xx na API** | 0.00% | `____%` | [ ] OK [ ] Alerta |
| **Status do Backup Diário Automatizado** | 100% íntegro com SHA-256 | `[ ] Sucesso  [ ] Falha` | [ ] OK [ ] Alerta |
| **Rotina de Restauração Periódica (Mock)** | Restauração sem perda de tabela | `[ ] Validada  [ ] Pendente` | [ ] OK [ ] Alerta |

---

## 3. Painel Financeiro e Operações do BigDev.Z Finance

| Indicador de Negócio / Funcionalidade | Contagem do Dia | Observações e Trilha de Auditoria |
| :--- | :---: | :--- |
| **Arquivos OFX Importados com Sucesso** | `____` | Arquivos parseados sem erro de encoding ou schema. |
| **Falhas de Importação OFX Rejeitadas (422)** | `____` | Arquivos vazios, sem STMTTRN ou datas inválidas. |
| **Transações OFX Conciliadas pelo Usuário** | `____` | Baixas confirmadas manualmente via prévia. |
| **FITIDs Duplicados Bloqueados (Deduplicação)** | `____` | Prevenção ativa contra duplicidade contábil. |
| **Conciliações OFX Pendentes de Decisão** | `____` | Transações em extrato aguardando ação humana. |
| **Baixas Parciais Executadas (`Payable`/`Installment`)** | `____` | Títulos com saldo residual mantido com precisão. |
| **Baixas Excedentes Bloqueadas (Validação 422)** | `____` | Tentativas de pagar acima do saldo residual. |
| **Pagamentos / Recebimentos Estornados** | `____` | Estornos auditados com registro em `obligation_changes`. |
| **Ações Bloqueadas por Período Fechado (`closed_until`)** | `____` | Mutações retroativas impedidas pelo motor contábil. |
| **Ações Bloqueadas por Alçada RBAC (HTTP 403)** | `____` | Tentativas de operadores/contadores sem permissão. |
| **Exportações de Fluxo de Caixa / Extrato (CSV)** | `____` | Relatórios gerados com proteção anti-CSV Injection. |
| **Divergências Fluxo Previsto vs. Realizado** | `____` | Diferenças analisadas entre projeção e liquidação. |

---

## 4. Registro de Incidentes e Exceções do Dia

| ID do Incidente | Gravidade | Horário | Impacto no Usuário | Causa Primária | `X-Request-ID` Associado | Status |
| :--- | :---: | :---: | :--- | :--- | :--- | :---: |
| *INC-001* | *P2* | *14:32* | *Arquivo OFX de banco cooperativo com tag não padrão.* | *Memo com caracteres especiais sem UTF-8.* | `a4b1c2-98...` | *Resolvido* |
| *(vazio)* | | | | | | |

---

## 5. Auditoria de Segurança e Privacidade
- [ ] **Sem Vazamento em Logs:** Verificado log bruto do container `api` — ZERO ocorrências de senhas, CPFs, tokens ou payloads completos de OFX.
- [ ] **Isolamento de Espaços (PF/PJ):** Verificado que nenhum relatório ou consulta expôs dados de outros clientes ou entre PF/PJ.
- [ ] **Integridade Contábil:** Validação de constraints compostas `(id, space_id)` sem nenhuma violação no banco de dados.

---

## 6. Parecer Operacional do Dia

- **Parecer SRE / QA Lead:** `[ ] DIA HOMOLOGADO COM SUCESSO   [ ] DIA COM RESSALVA   [ ] PILOTO PAUSADO`
- **Ações Imediatas para o Dia Seguinte:**
  1. `__________________________________________________________________________`
  2. `__________________________________________________________________________`
- **Assinatura do SRE / Release Manager:** `Jeann Lucas - Data: ____/____/2026`
