# Guia e Roteiro de Treinamento Operacional: BigDev.Z Finance

> **Público-Alvo:** Gestores Financeiros, Operadores de Caixa, Contadores e Proprietários (PF/PJ)  
> **Objetivo:** Capacitar os participantes do piloto no uso seguro, preciso e eficiente de todas as funcionalidades patrimoniais do sistema.

---

## Módulo 1: Espaços Pessoal (PF) e Empresarial (PJ)
- **O Conceito de Multi-Espaço:** Finanças da pessoa física e da pessoa jurídica nunca se misturam. Cada espaço possui suas próprias contas bancárias, obrigações, categorias e membros.
- **Identidade Visual e Alternância:**
  - **Espaço Pessoal (PF):** Tema Azul Profundo, voltado ao orçamento doméstico e patrimônio individual.
  - **Espaço Empresarial (PJ):** Tema Verde Esmeralda, voltado à operação corporativa, alçadas e controle de equipe.
- **Como Alternar:** Clique no seletor de espaços na barra superior ou no menu lateral. A alternância é instantânea e isolada.

---

## Módulo 2: Contas a Pagar e Contas a Receber
- **Contas a Pagar:**
  - *Avulsa (Single):* Despesas pontuais (ex.: conta de luz, taxa).
  - *Parcelada (Installment):* Compras a prazo (ex.: 10x de maquinário). Divisão determinística sem centavos perdidos.
  - *Recorrente (Recurring):* Assinaturas e contratos mensais (ex.: aluguel, software).
  - *Fatura de Cartão (Card Invoice):* Fatura consolidada com data de fechamento e vencimento.
- **Contas a Receber (Acordos e Parcelas):**
  - Registro de contratos de prestação de serviços ou vendas a prazo.
  - Preservação do dia de vencimento em meses curtos (ex.: dia 31 em fevereiro ou abril).

---

## Módulo 3: Baixas Parciais e Controle de Saldo Residual
- **O que é:** Pagamento ou recebimento fracionado de um compromisso.
- **Como realizar:**
  1. Abra o modal da conta a pagar ou da parcela do acordo.
  2. Clique em **Dar Baixa / Pagar**.
  3. No campo de valor, digite o valor amortizado (ex.: R$ 150,00 de um total de R$ 500,00).
  4. O sistema valida na hora que o valor não ultrapassa o saldo restante.
  5. Ao confirmar, o título exibe o badge **"Parcial"** e o status detalhado **"Parcialmente pago"** / **"Parcialmente recebido"**.
  6. O saldo devedor/credor restante (`R$ 350,00`) permanece aberto para liquidações futuras.
- **Estorno Parcial:** Se uma baixa de R$ 150,00 foi realizada por engano, você pode estornar exclusivamente essa baixa. O saldo restante volta exatamente ao valor anterior, sem afetar outras amortizações.

---

## Módulo 4: Importação e Conferência Bancária via OFX
- **O que é o OFX:** Arquivo de extrato padrão disponibilizado pelo seu internet banking (Itaú, Bradesco, Santander, Inter, Nubank, etc.).
- **Passo a Passo de Conciliação:**
  1. No menu **Configurações**, acesse **Conciliação Bancária OFX**.
  2. Selecione a **Conta Bancária** correspondente no sistema.
  3. Clique em **Selecionar Arquivo OFX** ou cole o texto do arquivo.
  4. Clique em **Processar Prévia do Extrato**.
- **Regras de Segurança na Prévia:**
  - *Nenhum lançamento é gravado antes da sua confirmação expressa.*
  - *Correspondência Inteligente:* O sistema busca automaticamente contas a pagar e parcelas a receber com o mesmo valor e vencimento próximo (+/- 7 dias) e sugere o vínculo.
  - *Proteção contra Duplicidade:* Transações que já foram importadas anteriormente exibem o selo cinza **"Já Conciliado"** e ficam protegidas contra duplicação.
  - *Ações por Transação:* Para cada item, selecione:
    - **Vincular à Conta a Pagar / Parcela Sugerida;**
    - **Novo Lançamento Avulso (com Categoria);**
    - **Ignorar (não contabilizar no sistema).**
  5. Clique em **Concluir Conciliação** para liquidar as operações simultaneamente.

---

## Módulo 5: Planejamento e Fluxo de Caixa (Realizado vs. Previsto)
- **Horizontes Temporais:** Visualize o caixa projetado para **30, 60 ou 90 dias**.
- **Visão de Caixa vs. Visão de Competência:**
  - *Visão de Caixa:* Agrupa lançamentos pela data efetiva de pagamento/recebimento e vencimentos futuros.
  - *Visão de Competência:* Agrupa lançamentos pela data de emissão/competência contábil.
- **Composição Matemática do Saldo Projetado:**
  - *Marco Zero:* Saldo real disponível nas contas bancárias no início do período.
  - *Evolução Diária:* Entradas realizadas (+) Entradas previstas (-) Saídas realizadas (-) Saídas previstas = Saldo final acumulado dia a dia.
- **Filtros Avançados:** Filtre por conta bancária específica ou por categoria para identificar gargalos de despesas.

---

## Módulo 6: Fechamento Contábil e Bloqueio de Mutações Retroativas
- **Para que serve:** Garante que dados de meses já fechados com o contador nunca sejam alterados acidentalmente.
- **Como Funciona:**
  1. Em **Configurações > Fechamento Contábil**, selecione a data limite (ex.: `31/03/2026`).
  2. Clique em **Fechar Período Contábil**.
  3. A partir desse momento, qualquer tentativa de criar, editar, pagar, receber ou cancelar lançamentos com data menor ou igual a essa data será estritamente bloqueada pelo sistema.
- **Reabertura Justificada:** Apenas o Administrador pode reabrir um período fechado, sendo obrigatório preencher uma justificativa detalhada que fica registrada permanentemente na auditoria do gestor.

---

## Módulo 7: Gestão de Membros e Perfis de Acesso (RBAC)
Espaços empresariais (PJ) suportam 4 perfis bem definidos:

| Perfil | O que pode fazer | O que NÃO pode fazer |
| :--- | :--- | :--- |
| **Administrador** | Autoridade total: gerencia membros, fecha/reabre períodos, altera saldos iniciais, estorna e cancela. | Não pode se remover se for o único administrador. |
| **Financeiro** | Operação completa: cria contas, efetua baixas, concilia OFX, cancela e estorna lançamentos. | Não gerencia membros da organização nem reabre período fechado. |
| **Operador** | Rotina do dia a dia: cadastra despesas, registra pagamentos e baixas parciais de rotina. | **Bloqueado:** Não pode cancelar títulos, estornar pagamentos nem alterar saldos de abertura. |
| **Contador** | Acesso de fiscalização: consulta extratos, visualiza fluxo de caixa e exporta relatórios. | **Bloqueado:** Não pode realizar nenhuma alteração de valor, baixa ou mutação financeira. |

---

## Módulo 8: Trilha de Auditoria e Exportação para a Contabilidade
- **Trilha de Auditoria Indelével:**
  - Acesse em **Configurações > Trilha de Auditoria**.
  - Todo estorno, cancelamento, alteração cadastral e reabertura contábil é registrado com data, hora, autor e comparativo visual (Antes vs. Depois).
  - Registros são imutáveis (impossível excluir ou editar histórico de auditoria).
- **Exportação Segura em CSV:**
  - Exportação direta de extrato e fluxo de caixa.
  - O arquivo CSV gerado possui sanitização automática contra injeção de fórmulas, abrindo com total segurança no Microsoft Excel ou LibreOffice Calc.
