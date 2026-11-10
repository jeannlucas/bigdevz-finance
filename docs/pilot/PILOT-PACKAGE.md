# Pacote Executivo de Piloto Controlado: BigDev.Z Finance

> **Autoridade:** Padrão Oficial de Engenharia BigDev.Z de Jeann Lucas  
> **Comissão de Release:** Release Manager, Customer Success Lead, QA Lead e SRE  
> **Estado Atual:** **PREPARADO E HOMOLOGADO (Aguardando Autorização Explícita do Proprietário)**

---

## 1. Visão Geral e Estratégia do Piloto Controlado

O Piloto Controlado do **BigDev.Z Finance** tem como objetivo validar a estabilidade, integridade patrimonial (Zero Float), usabilidade das baixas parciais, robustez da conciliação bancária OFX e controle de alçadas em ambientes reais de clientes durante **14 dias consecutivos**, sob monitoramento ativo e sem risco de contaminação cruzada ou incidentes críticos (P0/P1).

---

## 2. Recomendação de Quantidade Máxima Inicial de Clientes

> **RECOMENDAÇÃO TÉCNICA E OPERACIONAL:** **Entre 3 e 5 Organizações Selecionadas (Máximo 5).**

### Justificativa:
1. **Atendimento Hiper-Assistido:** Permite ao Customer Success Lead e ao SRE acompanhar 100% dos uploads OFX e das conciliações nos primeiros 7 dias com SLA de resposta imediata (< 15 minutos).
2. **Diversidade de Extratos Bancários:** 3 a 5 clientes cobrem os principais bancos brasileiros (Itaú, Bradesco, Santander, Banco do Brasil, Inter, Nubank) em cenários reais de SGML e XML.
3. **Carga Segura de Infraestrutura:** Mantém a latência do banco de dados abaixo de 10ms e a taxa de concorrência sob estrita previsibilidade matemática no cluster local/VPS.
4. **Isolamento de Risco:** Caso qualquer anomalia seja detectada, o raio de contenção é mínimo e o suporte personalizado resolve a situação no mesmo ciclo operacional.

---

## 3. Matriz de Instrumentos do Piloto (Índice de Documentos)

| Instrumento Operacional | Finalidade | Localização |
| :--- | :--- | :--- |
| **Checklist de Entrada (Onboarding)** | Triagem de elegibilidade, carga do marco zero, backup prévio e alinhamento de SLAs. | [`docs/pilot/CLIENT-ONBOARDING-CHECKLIST.md`](CLIENT-ONBOARDING-CHECKLIST.md) |
| **Guia de Treinamento do Cliente** | Capacitação completa em 8 módulos (PF/PJ, Baixas Parciais, OFX, Fluxo de Caixa, RBAC, Auditoria). | [`docs/pilot/CUSTOMER-TRAINING-GUIDE.md`](CUSTOMER-TRAINING-GUIDE.md) |
| **Painel Diário de Operações** | Acompanhamento diário de erros, latência, conciliações, estornos e bloqueios contábeis. | [`docs/pilot/DAILY-OPERATIONAL-REPORT-TEMPLATE.md`](DAILY-OPERATIONAL-REPORT-TEMPLATE.md) |
| **Livro de Registro de Incidentes** | Formulário estruturado de incidentes (P0 a P3) com RCA, rastreamento por `X-Request-ID` e mitigação. | [`docs/pilot/INCIDENT-REGISTER.md`](INCIDENT-REGISTER.md) |
| **Checklist de Saída (Exit Gate)** | Régua de aprovação formal para transição do piloto para produção ampla. | [`docs/pilot/PILOT-EXIT-CHECKLIST.md`](PILOT-EXIT-CHECKLIST.md) |
| **Procedimento de Backup & DR** | Scripts e comandos de dump comprimido (`-Fc`), restauração e contingência forense. | [`docs/operations/backup-and-restore.md`](../operations/backup-and-restore.md) |
| **Runbook Operacional & Rollback** | Protocolo de manutenção, liveness/readiness em `/api/health` e reversão determinística. | [`docs/operations/pilot-runbook.md`](../operations/pilot-runbook.md) |

---

## 4. Riscos Conhecidos e Medidas de Contenção

| Risco Conhecido | Impacto Potencial | Medida de Contenção Implementada |
| :--- | :---: | :--- |
| **Arquivos OFX com caracteres especiais ou codificação ANSI/ISO-8859-1.** | Erro de decodificação na prévia. | Parser converte automaticamente encodings legados para UTF-8 válido e descarta tags corruptas sem gravar no banco. |
| **Usuário tentar cadastrar lançamentos com data anterior à abertura da conta.** | Inconsistência contábil de saldo. | O motor financeiro rejeita com `HTTP 422` qualquer lançamento anterior ao `opening_balance_date`. |
| **Membro com perfil de operador tentar cancelar títulos ou reabrir períodos.** | Quebra de alçada de controle interno. | O sistema bloqueia via RBAC rigoroso com `HTTP 403 Forbidden` e oculta botões sensíveis na interface Flutter. |
| **Tentativa de injeção de fórmulas maliciosas em planilhas (CSV Injection).** | Execução de comandos no Excel do contador. | Todas as células com `=`, `+`, `-`, `@`, `\t` ou `\r` recebem prefixo de apóstrofo `'` no stream de saída. |

---

## 5. Status de Prontidão e Próximos Passos

- [x] Quality Gate automatizado (`make check` / `./scripts/check.sh --full`) aprovado com 100% de sucesso (ZERO erros e ZERO warnings).
- [x] Suíte de 172 testes de feature da API Laravel (1.708 asserções) verde.
- [x] Suíte de 248 testes de widgets e fluxos Flutter verde.
- [x] 13 testes de domínio financeiro puro verdes.
- [x] Observabilidade ativa com `X-Request-ID` e endpoint de liveness/readiness em `/api/health`.
- [x] Roteiro de treinamento, checklists e procedimentos operacionais finalizados.

> **DECISÃO OPERACIONAL:** O pacote de piloto está **100% PRONTO E HOMOLOGADO**. Nenhuma ação externa irreversível foi realizada. O início do piloto e a seleção dos 3 a 5 participantes aguardam a autorização expressa de Jeann Lucas.
