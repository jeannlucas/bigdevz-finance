# 0001 — Base solicitada e decisões ainda pendentes

Data: 04/10/2026. Estado: registro de requisitos; implantação bloqueada.

- Produto: BigDev.Z Finance; pacote pretendido `bigdevz_finance`.
- Stack solicitada: Flutter/Dart, Laravel e PostgreSQL; versões ainda não fixadas.
- Docker Compose pretendido: `bigdevz-finance`.
- Plataforma: iOS e Android; web como evolução futura.
- Dinheiro: exato, sem float; escolher uma convenção única de transporte antes
  de implementar API e Flutter. `NUMERIC(19,2)` é proposta do escopo.
- Datas: vencimento de calendário; dia 31 em mês curto usa último dia válido,
  preservando referência nos meses seguintes; sem ajuste automático por feriado.
- Centavos: distribuição determinística; estratégia será registrada com teste
  de R$ 100,00 em três parcelas antes de afirmar comportamento implementado.
- Autenticação e armazenamento seguro: pendentes de configuração e verificação.
- Estado e navegação Flutter: pendentes; não há dependências selecionadas.
- Licenciamento: pendente. Não foi criada concessão definitiva de licença.
- Publicação: repositório público autorizado via CLI, proprietário a confirmar.

Não usar este registro para afirmar que qualquer regra já está implementada.
Atualização: dinheiro, centavos e cronograma foram definidos e implementados
no núcleo durante a retomada; a decisão 0002 substitui essas pendências.
