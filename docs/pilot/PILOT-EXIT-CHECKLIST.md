# Checklist de Saída do Piloto para Produção Ampla (Exit Gate)

> **Produto:** BigDev.Z Finance  
> **Objetivo:** Estabelecer a régua formal, auditável e inegociável de critérios que autorizam a transição do Piloto Controlado para Produção Ampla.

---

## 1. Critérios de Estabilidade Operacional e Confiabilidade

| Critério de Avaliação | Requisito Obrigatório | Evidência / Registro | Resultado |
| :--- | :--- | :--- | :---: |
| **Tempo de Operação Contínua** | Mínimo de 14 dias ininterruptos de operação real em ambiente monitorado. | Diários operacionais de Dia 1 a Dia 14 consolidados em [`docs/pilot/DAILY-OPERATIONAL-REPORT-TEMPLATE.md`](DAILY-OPERATIONAL-REPORT-TEMPLATE.md). | [ ] Aprovado |
| **Zero Incidentes P0 (Críticos)** | ZERO ocorrências de divergência de saldos, vazamento IDOR ou corrupção de dados. | Livro de incidentes em [`docs/pilot/INCIDENT-REGISTER.md`](INCIDENT-REGISTER.md) sem registros P0. | [ ] Aprovado |
| **Zero Incidentes P1 Não Resolvidos** | ZERO incidentes P1 abertos; qualquer P1 ocorrido deve ter sido mitigado em < 4h com causa raiz eliminada. | Livro de incidentes com 100% de resoluções e testes de regressão aprovados. | [ ] Aprovado |
| **Disponibilidade Global (SLA)** | SLA >= 99.9% durante todo o período do piloto. | Relatório de health checks e logs do container da API. | [ ] Aprovado |

---

## 2. Integridade Matemática e Patrimonial dos Dados

| Verificação Contábil | Verificação Técnica | Método de Prova | Resultado |
| :--- | :--- | :--- | :---: |
| **Precisão de Centavos (Zero Float)** | Nenhum lançamento com dízima ou arredondamento incorreto. | Varredura SQL: 100% dos saldos e movimentos conferem em centavos inteiros (`BIGINT`). | [ ] Aprovado |
| **Fechamento Contábil Íntegro** | Nenhuma mutação registrada em datas menores ou iguais a `closed_until`. | Validação de restrição de período contábil no PostgreSQL. | [ ] Aprovado |
| **Imutabilidade de Auditoria** | Tabela `obligation_changes` sem exclusões físicas (`DELETE`) ou updates. | Trilha de auditoria 100% preservada e consistente com o extrato bancário. | [ ] Aprovado |
| **Deduplicação de Extratos OFX** | Zero duplicidades de FITIDs por conta/espaço no banco de dados. | Chave única `(space_id, account_id, fitid)` 100% respeitada. | [ ] Aprovado |

---

## 3. Experiência e Feedback do Cliente (CSAT / NPS)

- [ ] **Entrevista de Checkpoint Final Realizada:**
  - Data da Sessão: `____/____/2026`
  - Participantes: Responsável Operacional do Cliente + Customer Success Lead (Jeann Lucas).
- [ ] **Índice de Satisfação (CSAT):** Mínimo de 85% de satisfação com as rotinas financeiras.
  - *Nota obtida:* `____ / 10`
- [ ] **Usabilidade das Baixas Parciais e OFX:**
  - O cliente validou que as baixas parciais refletem com clareza o valor restante devido.
  - O cliente validou que a prévia de conciliação OFX evitou erros de digitação e duplicidades.
- [ ] **Feedback do Contador / Fiscal:**
  - O contador parceiro do cliente confirmou o recebimento das exportações CSV sem distorções de fórmulas.

---

## 4. Garantia de Disaster Recovery e Continuidade

- [ ] **Backup Final de Encerramento do Piloto:** Dump completo realizado via `pg_dump -Fc` com geração de hash SHA-256.
- [ ] **Simulação de Restauração em DR:** Restauração executada com sucesso em ambiente isolado, validando 100% das 32 tabelas e constraints.
- [ ] **Tempo de Recuperação Comprovado:** RTO < 15 minutos e RPO < 1 hora atingidos na simulação.

---

## 5. Parecer de Conclusão e Autorização de Produção Ampla

> **PARECER FINAL DA COMISSÃO DE RELEASE:**
> [ ] **APROVADO PARA PRODUÇÃO AMPLA:** Todos os critérios de estabilidade, integridade matemática, satisfação e segurança foram estritamente satisfeitos.  
> [ ] **PRORROGAÇÃO DO PILOTO:** Necessário estender o piloto por mais `[ ] 7 dias` devido a pendências de adaptação ou incidentes menores.  
> [ ] **BLOQUEADO:** Identificado risco estrutural impeditivo que demanda refatoração do motor financeiro.

---

### Assinaturas de Homologação Final

- **Customer Success Lead:** _________________________________________________ Data: ___/___/______
- **QA & SRE Lead:** _________________________________________________________ Data: ___/___/______
- **Autoridade Máxima de Release (Jeann Lucas):** _____________________________ Data: ___/___/______
