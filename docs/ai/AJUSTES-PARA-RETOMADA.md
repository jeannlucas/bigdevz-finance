# Ajustes para retomada — BigDev.Z Finance

Data-base: 15/10/2026. Estado: **DOCUMENTADO; AJUSTES NÃO EXECUTADOS**.

Solicitação: preparar a retomada pontual do projeto, alinhamento global e plano de infraestrutura segura no Mac e, quando aplicável, VPS; identificar legado para avaliação humana. Este arquivo não autoriza implementação, exclusão, commit, integração, publicação ou acesso remoto.

## Estado e evidências de partida

- **FATO VERIFICADO:** branch `dev`, HEAD `0f49606bf5ee`, 10 entradas no status antes desta entrega (diretórios não rastreados podem agrupar arquivos).
- Stack inspecionada: API Laravel 13/Sanctum, PostgreSQL e aplicativo Flutter; domínio monetário em PHP puro e Actions.
- Fonte: auditoria estática de repositório real em 15/10/2026 e reconferência de Git/manifests nesta preparação. Nenhum fetch, teste, build, migration ou diagnóstico remoto foi executado.
- **FATO VERIFICADO** descreve fonte lida; **HIPÓTESE** precisa de reprodução; **REGISTRO DOCUMENTAL** comprova apenas a existência do relato; **NÃO VERIFICADO** não pode ser tratado como aprovado. P0 emergência comprovada; P1 antes de release/ampliação de uso; P2 retomada; P3 manutenção.


## Pendências específicas priorizadas

| ID | Prioridade e certeza | Evidência | Ajuste a tratar | Critério de aceite |
|---|---|---|---|---|
| R01 | P2 · FATO VERIFICADO | `apps/mobile/lib/features/summary/summary_tab.dart; apps/mobile/test/features/summary_test.dart` | Há alterações locais da aba Resumo e teste ainda não consolidado. | Concluir regressão PF/PJ, acessibilidade e sincronização com API simulada; separar iOS de Android. |
| R02 | P2 · FATO VERIFICADO | `apps/api/composer.json; Makefile` | Pint e testes existem; não foi identificado PHPStan no manifesto inspecionado. | Avaliar análise estática PHP proporcional sem criar baseline para ocultar novos erros. |
| R03 | P2 · FATO VERIFICADO | `apps/api/composer.json` | composer setup inclui criação de ambiente e migration. | Não usar setup como comando de QA; escolher apenas verificações previamente inspecionadas. |

## Infraestrutura específica e situação por ambiente

Mac: banco em loopback 5440; API usa bind padrão loopback e porta padrão 8000 (`docker-compose.yml:11,39`), potencialmente concorrente com EBS. Registro central propõe API 8002, ainda não reservada. Atualizar URLs do iOS e emulador Android quando a porta for aprovada. VPS: existência/topologia efetiva NÃO VERIFICADAS; não criar deploy ou exposição LAN por inferência.

## Princípios de infraestrutura para Mac e VPS

A paridade desejada é de arquitetura, versões compatíveis, contratos e controles de segurança. Não significa copiar arquivos reais de ambiente, dados, credenciais ou portas publicadas de um host para outro. As versões/imagens atuais devem ser inventariadas; atualização não faz parte desta documentação.

- **Portas:** unicidade é por host, endereço, porta e protocolo; dois containers podem usar a mesma porta interna em redes isoladas. Dois serviços não podem disputar a mesma porta publicada no mesmo endereço do host. Domínios distintos não eliminam essa colisão.
- **Mac:** publicar apenas o indispensável, com loopback explícito. Acesso de dispositivo físico pela LAN exige exceção delimitada e autorizada; loopback de um container não é o loopback do Mac.
- **VPS:** preferir bancos, caches e serviços internos sem publicação no host. Somente o proxy de entrada precisa de exposição pública; upstream pode usar rede Docker compartilhada controlada ou porta exclusiva em loopback. Reutilizar o proxy existente quando aplicável; não criar um por aplicação disputando 80/443.
- **Registro por host:** consultar o inventário de portas do host local (ou registro de governança de portas corporativo) para o Mac e inventariar separadamente a VPS, com autorização de acesso. Reserva local não prova disponibilidade na VPS. Toda porta citada como PROPOSTA continua não reservada e não implementada.
- **Namespace:** planejar nome Compose por projeto e ambiente, com redes e volumes segregados. Antes de remover `container_name` ou alterar o nome do projeto, mapear nomes efetivos e montagens; mudar namespace pode ligar um volume vazio em vez do existente.
- **Dados:** separar dev, teste e produção; ensaiar com dados sintéticos e recursos descartáveis identificados. Nenhum teste pode atingir banco persistente por fallback silencioso.
- **Rede:** evitar `network_mode: host`, redes globais e sub-redes fixas sem necessidade comprovada. Considerar o histórico de saturação IPAM; rede interna não substitui autenticação e autorização.
- **Processos e permissões:** avaliar usuário sem privilégio, ausência de privileged/Docker socket, capabilities mínimas, healthchecks, limites de recursos e política de restart proporcionais à stack. Não marcar item como conforme sem evidência.
- **Imagens e builds:** registrar versões/digests reproduzíveis e dependências congeladas; revisar permissões, cache de build e ausência de segredos no artefato. Não atualizar imagem ou dependência por efeito de uma limpeza.
- **Segredos:** nunca abrir, criar, copiar ou editar `.env` real, Keychain, chaves privadas ou arquivo de acesso. Exemplos só com placeholders; variáveis públicas de frontend não guardam segredos. Validação de Compose deve usar entradas sintéticas, sem imprimir configuração resolvida sensível.
- **Continuidade:** inventariar volumes, binds, consumers, jobs, backups e restauração antes de propor migração. Nenhuma remoção de volume/rede/container/diretório, prune, down -v ou recriação forçada está autorizada por este arquivo.
- **VPS e publicação:** nada de SSH, execução de compose de produção, migrations, merge, commit, push ou deploy implícitos. Inspeção de manifesto local não comprova configuração ou saúde do servidor. Homologação local não libera produção.

## Alinhamento às regras globais

Referências canônicas: `AGENTS.md` local, `docs/ai/HANDOFF.md`, diretrizes em `docs/project-guidelines.md` e, em ambientes corporativos BigDev.Z com governança local instalada, as diretrizes de engenharia e QA em `~/.agents/governanca/`. A disponibilidade dessas fontes em outra máquina deve ser conferida; não presumir que estão presentes na VPS nem exigir dependências privadas de colaboradores externos.

O ponteiro em AGENTS torna esta lista encontrável. Isso NÃO comprova conformidade integral de código, hooks ou infraestrutura. Na retomada, conferir:

- [ ] Resolver divergências entre instruções locais antigas e regras globais, preservando decisões de domínio. Autorização histórica registrada em documento não autoriza operação hoje.
- [ ] Confirmar `dev` como base de desenvolvimento quando aplicável; produção `main`, exceto `master` em site-bigdevz. Projetos documentais e referências externas exigem tratamento proporcional. Não criar/trocar branch agora.
- [ ] Inspecionar hooks efetivos, scripts de instalação/prepare, CI e efeitos de merge antes de executá-los. Nenhum comando de promoção listado em instrução é autorização para push.
- [ ] Conferir ignore de ambientes e nomes rastreados sem abrir conteúdo sensível; preservar proteção de segredos nos agentes.
- [ ] Comprovar lint, tipagem e testes realmente cobrindo os componentes tocados; não confundir Pint com análise semântica, tipagem com lint, nem CI de segurança com suíte funcional.
- [ ] Revisar dependências com lockfile e SCA em tarefa segura; nenhuma ausência atual de CVEs foi comprovada nesta etapa.
- [ ] Aplicar testes comportamentais e de segurança proporcionais ao risco, sem refatoração em massa ou camadas artificiais.
- [ ] Atualizar documentação afetada e evidências reais; testes antigos e declarações de terceiros não são execução atual.

## Avaliação de material antigo sem excluir

Um arquivo antigo não está automaticamente sem uso. Para cada candidato: localizar imports, scripts, CI, hooks, jobs, links e consumers externos; conferir Git e conteúdo único; identificar substituto; avaliar impacto; apresentar a decisão ao Jeann. Resultado pode ser **MANTER**, **CORRIGIR RESUMO**, **ROTULAR HISTÓRICO**, **ARQUIVAR COM AUTORIZAÇÃO** ou **CANDIDATO À EXCLUSÃO**. Exclusão só após autorização específica, nunca por esta lista.

Arquivos de ambiente reais, volumes, worktrees protegidos, evidências únicas e histórico de decisões não são descartáveis. Não executar git clean, exclusão recursiva, prune ou atualizações de snapshots para fazer verificação passar.


### Itens específicos a avaliar

| Material | Situação observada | Avaliação necessária e proteção |
|---|---|---|
| `HANDOFF.md` | Histórico da raiz referenciado pelo handoff canônico. | Preservar e manter ponteiro; não tratar como instrução mais recente. |
| `design/screenshots/ e prints/` | Evidências históricas e oficiais distintas. | Inventariar por cenário/resolução antes de propor substituição; não apagar. |
| `apps/mobile/ios/Runner.xcodeproj/project.pbxproj e apps/mobile/ios/Runner/Info.plist` | Configurações locais de máquina já modificadas. | Revisar separadamente de correções de produto; preservar assinatura local. |

## Verificações disponíveis e próximo incremento

Makefile: `make test-domain`, `make test-api`, `make lint-api`, `make analyze-mobile`, `make test-mobile`. Smoke e integração mobile acessam API real: dependem de ambiente seguro comprovado.

Próximo incremento recomendado: Terminar a aba Resumo e regressão financeira em banco descartável, antes de ampliar escopo.

## Roteiro da próxima sessão e aceite

1. Ler AGENTS, esta lista e o handoff da árvore correta. Registrar branch, HEAD, status, staged/unstaged e worktrees; preservar tudo que já existia. Fetch só na sessão de desenvolvimento autorizada, sem transformar consulta em pull/merge.
2. Escolher UM item e revalidar suas evidências: os caminhos/linhas e o estado abaixo são um retrato de 15/10/2026 e podem ter mudado. Definir escopo e critérios de aceite antes de implementar.
3. Para infraestrutura, apresentar inventário Mac/VPS separadamente, portas atuais/propostas, consumidores, dados a preservar, alterações mínimas e rollback sem perda de dados. Reserva de porta e acesso remoto dependem de autorização própria.
4. Implementar somente a tarefa solicitada. Exposição de credencial, segurança ou operação destrutiva continua sujeita às regras globais; não copiar valores para provar achado.
5. Executar verificações proporcionais em ambiente seguro. Para concorrência, testar disputas reais; para interface, demonstrar aplicação e evidências sintéticas. Não afirmar PASS por código presente ou resultado histórico.
6. Atualizar cada item para INVESTIGADO, IMPLEMENTADO, TESTADO ou VALIDADO TECNICAMENTE apenas com evidências. Mudança visual segue AGUARDANDO_APROVACAO até aceite exclusivo do Jeann. Commit/merge/push/deploy são autorizações separadas.

Aceite desta entrega documental: arquivo por projeto, fonte e critério em cada pendência, infraestrutura por ambiente, avaliação de legado sem remoção, ponteiro nas instruções e continuidade registrada. Nenhuma correção funcional ou de infraestrutura foi executada; nenhum teste/build foi rodado e nenhuma porta foi reservada.

## Registro de execução futura

Preencher ao retomar: item escolhido; evidência revalidada; arquivos alterados; testes e resultados; demonstração quando aplicável; risco residual; aprovação humana; próximo passo. Não marcar checklist retroativamente como executado.
