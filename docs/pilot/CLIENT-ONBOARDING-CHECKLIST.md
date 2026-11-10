# Checklist de Entrada de Cliente no Piloto Controlado (Onboarding)

> **Produto:** BigDev.Z Finance  
> **Objetivo:** Garantir a entrada segura, assistida e monitorada de participantes no piloto de 14 dias sem risco de corrupção contábil ou desalinhamento operacional.

---

## 1. Perfil e Elegibilidade do Cliente

| Critério | Requisito de Elegibilidade | Status de Verificação |
| :--- | :--- | :---: |
| **Porte da Organização** | Micro ou Pequena Empresa (PJ) ou Gestão Patrimonial Familiar (PF/PJ combinados). | [ ] Sim [ ] Não |
| **Volume de Lançamentos** | Entre 30 e 500 transações/mês durante os 14 dias de piloto. | [ ] Sim [ ] Não |
| **Estrutura de Equipe** | Possui no mínimo 1 gestor (Administrador/Financeiro) e opcionalmente 1 Operador e 1 Contador. | [ ] Sim [ ] Não |
| **Compatibilidade Bancária** | Exporta extratos no padrão OFX (.ofx) dos bancos parceiros (Itaú, Bradesco, BB, Santander, Inter, Nubank). | [ ] Sim [ ] Não |
| **Disponibilidade para Feedback** | Compromisso formal de participar de 2 reuniões rápidas de checkpoint (Dia 7 e Dia 14). | [ ] Sim [ ] Não |

---

## 2. Responsáveis e Ponto Focal

- **Organização / Razão Social:** `________________________________________________`
- **Nome do Responsável Operacional:** `________________________________________`
- **Papel na Empresa:** `[ ] Proprietário / Sócio  [ ] Diretor Financeiro  [ ] Gestor / Analista`
- **E-mail Institucional:** `________________________________________________`
- **Canal de Comunicação Direto (WhatsApp / Telegram / Slack):** `____________________`
- **Lead SRE / Customer Success BigDev.Z:** `Jeann Lucas`

---

## 3. Carga Inicial de Dados e Marco Zero Contábil

- [ ] **Definição da Data de Abertura (Marco Zero):**
  - Data inicial estipulada (ex.: primeiro dia do mês corrente ou anterior).
  - *Regra inegociável:* Nenhuma movimentação pode ter data anterior à data de abertura das contas.
- [ ] **Cadastro das Contas Bancárias:**
  - Nome da instituição bancária (ex.: Itaú Conta Principal, Inter PJ).
  - Saldo inicial auditado na data de abertura cadastrado em centavos inteiros (Zero Float).
- [ ] **Estrutura de Categorias de Despesas e Receitas:**
  - Categorias essenciais configuradas por tipo (`expense` / `income`).
- [ ] **Contas a Pagar e Receber Iniciais:**
  - Importação/cadastro dos compromissos abertos no horizonte imediato (avulsos e parcelados).

---

## 4. Treinamento Pré-Operacional Concluído
O responsável operacional e os operadores concluíram o roteiro oficial de treinamento:
- [ ] **Módulo 1:** Alternância segura entre Espaço Pessoal (PF) e Empresarial (PJ).
- [ ] **Módulo 2:** Cadastro de contas a pagar, parcelamentos e contas a receber.
- [ ] **Módulo 3:** Baixas parciais e controle automático do saldo residual em centavos.
- [ ] **Módulo 4:** Importação, prévia, conferência humana e deduplicação de extratos OFX.
- [ ] **Módulo 5:** Planejamento de Fluxo de Caixa (30, 60 e 90 dias — Caixa vs. Competência).
- [ ] **Módulo 6:** Fechamento e reabertura de período contábil com justificativa auditada.
- [ ] **Módulo 7:** Gestão de membros, papéis de acesso (RBAC) e auditoria do gestor.
- [ ] **Módulo 8:** Exportação protegida para o contador (prevenção contra CSV Injection).

---

## 5. Garantia Técnica Pré-Operacional (SRE & Backup)
- [ ] **Snapshot / Backup de Base Limpa:** Dump completo realizado e verificado antes da inserção dos dados reais do cliente.
- [ ] **Health Check 100% OK:** Endpoint `/api/health` respondendo 200 com latência de banco < 20ms.
- [ ] **Monitoramento de Logs Rastreáveis:** Validada a injeção do cabeçalho `X-Request-ID` em todas as rotas da sessão.
- [ ] **Isolamento de Segurança IDOR:** Testado o bloqueio rigoroso (404/403) para dados de outros espaços.

---

## 6. Canal de Suporte e SLAs durante o Piloto

| Nível de Incidente | Definição | Canal de Acionamento | SLA de Primeira Resposta | SLA de Mitigação |
| :--- | :--- | :--- | :---: | :---: |
| **P0 (Crítico)** | Erro contábil em saldo, bloqueio total de acesso ou indisponibilidade de banco. | Telefone / Mensagem direta de urgência | **15 minutos** | **2 horas** |
| **P1 (Alto)** | Falha no upload/parsing de arquivo OFX ou falha em fluxo de baixa parcial. | Canal prioritário dedicado | **30 minutos** | **4 horas** |
| **P2 (Médio)** | Dúvida de usabilidade ou comportamento inesperado de filtros em telas. | Canal regular de suporte | **2 horas** | **12 horas** |
| **P3 (Baixo)** | Sugestão de melhoria ou solicitação de ajuste visual. | Registro em backlog | **4 horas** | Próximo ciclo |

---

## 7. Critérios de Sucesso do Cliente (Success Metrics)
1. **Confiança Operacional:** 100% dos saldos bancários no sistema batem com os extratos reais dos bancos.
2. **Tempo Economizado:** Redução de no mínimo 50% no tempo gasto na conciliação financeira manual.
3. **Zero Desvios:** Nenhuma parcela baixada indevidamente ou saldo residual divergente.
4. **Avaliação CSAT/NPS:** Nota mínima de 9/10 na avaliação de usabilidade e segurança ao término dos 14 dias.

---

### Assinatura de Aprovação de Entrada

- **Responsável Operacional do Cliente:** ______________________________________ Data: ___/___/______
- **Release Manager / Jeann Lucas:** ___________________________________________ Data: ___/___/______
