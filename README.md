# BigDev.Z Finance

Controle financeiro pessoal e empresarial, com espaços PF e PJ separados.

## Estado real em 04/10/2026

Preparação inicial bloqueada pelo ambiente de execução. Não há aplicativo Flutter,
API Laravel, banco provisionado, autenticação, credenciais demonstrativas ou fluxo
financeiro implementado. Não há repositório Git local inicializado nem publicação
remota confirmada. Licença em definição; nenhuma concessão de licença foi criada.

O escopo original está em `financeiro-pf-pj-escopo-e-prompt-inicial.md`.
O diagnóstico e os passos de retomada estão em `HANDOFF.md`.

Na retomada foi implementado o núcleo PHP de dinheiro e geração de parcelas em
`apps/api/app/Domain/Receivables`. Ele ainda não está integrado a Laravel, banco
ou Flutter. Oito testes locais passaram; não comprovam o fluxo financeiro completo.

```bash
make test-domain
```

Requer PHP 8.3 de 64 bits. A convenção de valores e vencimentos está em
`docs/decisions/0002-dinheiro-e-parcelas.md`.

## Verificação local

Na pasta do projeto, execute:

```bash
sh scripts/check-environment.sh
```

A checagem não instala componentes, não altera autenticação, não acessa arquivos
de ambiente e não modifica containers ou bancos. Falhas retornam código 1.
Não é uma suíte de testes do produto.

Ainda não há comandos para subir o backend ou abrir o aplicativo. Eles serão
documentados depois da implementação e execução reais, com lockfiles gerados
pelos gerenciadores de dependências.

## Ambiente necessário para retomar

- CLI com escrita permitida em `.git`, acesso à rede e ao socket Docker local.
- Flutter stable com Dart, instalado conforme a documentação oficial.
- Android SDK para validação Android.
- GitHub CLI com identidade confirmada por `gh api user --jq '.login'`.
- Docker disponível para PostgreSQL de desenvolvimento e testes isolados.

PHP 8.3.31, Composer 2.10.1, Docker CLI 29.8.1, Compose v5.5.1, Git 2.54.0,
GitHub CLI 2.94.0 e Xcode 27.0 foram identificados. A presença dessas ferramentas
não comprova que os builds ou os serviços funcionem nesta sessão.

Referências: [Flutter stable](https://docs.flutter.dev/install/archive),
[Laravel](https://laravel.com/docs),
[autenticação GitHub CLI](https://cli.github.com/manual/gh_auth_login).

## Publicação autorizada e pendências

O destino autorizado é `bigdevz-finance`, público, na conta pessoal autenticada
confirmada via API. Proprietário, existência do destino, URL e visibilidade ainda
não foram confirmados. Não deduzir o proprietário a partir da conta armazenada.
Nenhum commit ou push foi feito. Não há deploy ou distribuição em lojas autorizados.

Licença, identidade visual definitiva, bancos reais, offline, empréstimo,
distribuição e hospedagem permanecem pendentes. Somente dados fictícios poderão
entrar no código, nos testes e nas demonstrações públicas.
