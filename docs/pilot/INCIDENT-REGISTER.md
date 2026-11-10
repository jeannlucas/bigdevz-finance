# Registro Estruturado de Incidentes do Piloto (Incident Log)

> **Produto:** BigDev.Z Finance  
> **Autoridade:** SRE Lead, QA Lead e Release Manager  
> **Matriz de Gravidade:** P0 (Crítico), P1 (Alto), P2 (Médio), P3 (Baixo)

---

## 1. Classificação Canônica de Incidentes

| Nível | Definição | Critério de Acionamento | Impacto no Piloto |
| :---: | :--- | :--- | :--- |
| **P0** | **Crítico / Inegociável** | Divergência monetária em saldos, perda de dados, vazamento multi-tenant (IDOR) ou indisponibilidade total de banco. | **Pausa imediata do piloto.** Reset da contagem de 14 dias após correção. |
| **P1** | **Alto** | Falha em fluxo principal sem alternativa viável (ex.: falha de conciliação de extrato com trava de UI, falha na baixa de parcela). | Mitigação em < 4h. Se afetar integridade contábil, pausa o piloto. |
| **P2** | **Médio** | Comportamento inesperado com contorno (ex.: filtro de categoria não atualiza na hora, lentidão esporádica). | Correção no ciclo de manutenção da branch sem pausar piloto. |
| **P3** | **Baixo** | Inconsistência cosmética, erro de concordância em mensagem ou sugestão de melhoria. | Backlog regular de refinamento. |

---

## 2. Formulário Padrão de Registro de Incidente

```markdown
### Incidente: [INC-YYYYMMDD-00X] — [Título Resumido]

- **Data e Hora:** AAAA-MM-DD HH:MM:SS (Fuso America/Sao_Paulo)
- **Gravidade:** [P0 / P1 / P2 / P3]
- **Status:** [Aberto / Em Investigação / Mitigado / Resolvido / Fechado]
- **Cliente / Espaço Afetado:** [ID do Espaço ou Razão Social]
- **Identificador de Tracing:** `X-Request-ID: <uuid>`

#### 1. Impacto no Negócio e no Usuário
- [Descrever o que o usuário tentou fazer e qual mensagem/comportamento ocorreu]

#### 2. Causa Raiz Técnica (Root Cause Analysis)
- [Causa primária identificada no código, banco, rede ou dados importados]

#### 3. Mitigação Imediata (Contenção)
- [Ação emergencial aplicada para restabelecer a operação segura]

#### 4. Correção Definitiva e Testes de Regressão
- [Arquivos alterados, teste automatizado criado no padrão TDD e evidência de aprovação no quality gate]

#### 5. Responsável e Linha do Tempo
- **Detectado por:** [Nome / Alerta de Monitoramento] às HH:MM
- **Mitigado por:** [Nome] às HH:MM (Tempo de Mitigação: X min)
- **Resolvido por:** [Nome] às HH:MM
- **Aprovação do Mantenedor (Jeann Lucas):** [Sim / Não]
```

---

## 3. Livro de Registro de Incidentes do Piloto

| ID | Data/Hora | Gravidade | Espaço / Cliente | Descrição Sintética | Causa Raiz | Status | Responsável |
| :--- | :---: | :---: | :--- | :--- | :--- | :---: | :--- |
| *INC-20261110-001* | *2026-11-10 10:15* | *P2* | *Espaço PJ Alpha* | *Arquivo OFX com caracteres acentuados gerou aviso de encoding.* | *Banco regional exportou arquivo sem header de codificação UTF-8.* | *Resolvido* | *Jeann Lucas* |
| *(Disponível para registros)* | | | | | | | |

---

## 4. Pós-Morte e Lições Aprendidas (Post-Mortem)
Para todo incidente P0 ou P1, é obrigatória a elaboração de documento de Post-Mortem técnico contendo:
1. Linha do tempo minuto a minuto.
2. Análise dos 5 Porquês (*5 Whys*).
3. Ações preventivas no pipeline de CI/CD para que a falha seja impossível de ocorrer novamente.
