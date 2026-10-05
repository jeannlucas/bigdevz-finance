# BigDev.Z Finance

Controle financeiro pessoal e empresarial, com espaços PF e PJ separados.
Repositório público em desenvolvimento; **licença em definição**.

## Estado real em 05/10/2026

Checkpoint 1 concluído: login, espaços PF/PJ, contas com saldo inicial,
acordo a receber parcelado, recebimentos totais e parciais persistidos no
PostgreSQL e app Flutter integrado à API Laravel.

| Validação | Situação |
| --- | --- |
| Núcleo PHP de dinheiro/parcelas | 8 testes (`make test-domain`) |
| API + PostgreSQL real | 19 testes, incluindo isolamento, rollback e concorrência entre processos (`make test-api`) |
| Roteiro HTTP contra a API no Docker | `make smoke-api` |
| App Flutter | 19 testes Dart (`make test-mobile`), `flutter analyze` sem avisos |
| iOS | Build e teste de integração no **Simulador** iPhone 17 Pro (iOS 26.5) contra a API real |
| iPhone físico | Teste de integração e roteiro manual no iPhone 17 Pro Max (iOS 27.0.1) contra a API real |
| Android | Build debug e teste de integração no **emulador** Android 16 (API 36, arm64) contra a API real; aparelho Android não testado |

Detalhes, evidências e pendências: `HANDOFF.md`. Escopo completo:
`financeiro-pf-pj-escopo-e-prompt-inicial.md`.

## Requisitos

PHP 8.3 (64 bits) com `pdo_pgsql` e Composer 2; Docker com Compose; Flutter
3.47.6 stable; Xcode para iOS; Android SDK (compileSdk 36, NDK
28.2.13676358) para Android.

O Makefile usa o `flutter` do PATH; sem ele, tenta `~/development/flutter`.
Outro local: `make test-mobile FLUTTER=/caminho/flutter/bin/flutter`.

O Compose fixa a sub-rede `10.88.231.0/24` para a rede do projeto. Se ela
colidir com sua rede local ou com outra rede Docker, defina outra em
`BIGDEVZ_SUBNET` (ver `.env.example`); nada na configuração global do Docker
precisa mudar.

## Executar

```bash
make up        # PostgreSQL 18 + API em http://127.0.0.1:8000 (docker compose)
make migrate   # aplica migrations no banco de desenvolvimento
make seed      # usuário e contas fictícios (recusado em produção)
make smoke-api # roteiro HTTP do cenário principal
```

Usuário fictício do seed, só para desenvolvimento local:
`demo@example.com` / `demo-bigdevz-local`.

Testes (o banco `bigdevz_finance_test` precisa estar de pé via `make up`):

```bash
make test          # núcleo PHP + suíte da API
make lint-api      # Pint
make mobile-deps && make analyze-mobile && make test-mobile
```

`make down` só para os containers; volumes e dados são preservados.
Variáveis opcionais do Compose (porta, senha local, sub-rede): `.env.example`.

## Abrir o app

```bash
xcrun simctl boot "iPhone 17 Pro"   # ignora o erro se já estiver ligado
make run-ios DEVICE="iPhone 17 Pro"
```

No Xcode 27 não existe mais `Simulator.app`: a janela do simulador fica no
**Device Hub** (`open -a DeviceHub`). Para focar um aparelho:
`open "devices://manage/select?id=<UDID>"` (UDID em
`xcrun simctl list devices booted`).

Endereço da API (`--dart-define=API_BASE_URL=...`):

| Onde o app roda | URL |
| --- | --- |
| Simulador iOS | `http://127.0.0.1:8000/api` (padrão) |
| Emulador Android | `http://10.0.2.2:8000/api` |
| Aparelho físico | `http://IP-do-Mac:8000/api`, subindo a API com `BIGDEVZ_API_BIND=0.0.0.0 make up` |

No aparelho físico, `localhost` é o próprio telefone. Use apenas em rede
confiável: a API de desenvolvimento roda com debug ativo e HTTP sem TLS.

Teste de integração no simulador (usa a API real e o seed):

```bash
cd apps/mobile && flutter test integration_test -d "iPhone 17 Pro" \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

### iPhone físico (validado; usar só quando o simulador não bastar)

1. No Xcode, *Settings → Apple Accounts*: entre com seu Apple ID. Em
   `apps/mobile/ios/Runner.xcworkspace`, alvo Runner, *Signing &
   Capabilities*, filtro **All**: escolha o time. Não commite o
   `DEVELOPMENT_TEAM` gravado no `project.pbxproj`.
2. No iPhone: Modo de Desenvolvedor ativo e, após a primeira instalação,
   *Ajustes → Geral → VPN e Gerenciamento de Dispositivo → Confiar*.
3. API na rede local: `BIGDEVZ_API_BIND=0.0.0.0 make up`; ao terminar, `make up`
   volta para `127.0.0.1`.
4. Instale e abra o app uma vez e **permita a rede local**:
   `flutter build ios --release --dart-define=API_BASE_URL=http://IP-do-Mac:8000/api`
   e `xcrun devicectl device install app --device <id> build/ios/iphoneos/Runner.app`.
5. Só então rode o teste de integração com `-d <id>` e a mesma URL. O
   `flutter test` desinstala o app ao final; numa instalação nova o iOS pede
   a permissão de novo e o primeiro login falha enquanto o pedido está na tela.
   Mantenha o aparelho desbloqueado: bloqueado, o app não abre.

### Android (validado em emulador)

SDK em `~/Library/Android/sdk`, que o Flutter detecta sozinho. Com as
command-line tools oficiais e o Java do Android Studio (`JAVA_HOME` apontando
para o `jbr` do app):

```bash
sdkmanager --licenses   # aceite interativo, feito por você
sdkmanager "platform-tools" "emulator" "platforms;android-36" \
  "build-tools;36.0.0" "ndk;28.2.13676358" \
  "system-images;android-36;google_apis;arm64-v8a"
avdmanager create avd -n bigdevz_api36 \
  -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_8
emulator -avd bigdevz_api36 &
cd apps/mobile && flutter test integration_test -d emulator-5554 \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

No emulador, `10.0.2.2` é o `127.0.0.1` do Mac: a API não precisa sair do
loopback. A primeira compilação baixa o Gradle e o CMake e leva cerca de 12 min.

## Roteiro manual

1. Entrar com o usuário fictício; o espaço PF abre por padrão.
2. **Contas → Nova conta**: R$ 1.000,00 com data anterior aos recebimentos.
3. **A receber → Novo acordo**: "Venda de veículo", R$ 24.000,00, 12 parcelas.
   O resumo continua com o mesmo saldo (previsto não entra no saldo).
4. Parcela 1 → **Registrar recebimento** de R$ 2.000,00 na conta nova: saldo
   +R$ 2.000,00, acordo com R$ 22.000,00 pendentes.
5. Parcela 2 → R$ 500,00: parcela "Parcial" com R$ 1.500,00 faltando, acordo
   com R$ 21.500,00.
6. Trocar para **PJ**: nada do PF aparece; a conta PF não é oferecida.
7. Fechar e reabrir o app: sessão, espaço e valores voltam da API.

## Documentação

`docs/api.md` (contrato), `docs/architecture.md`, `docs/decisions/`,
`ROADMAP.md`, `CONTRIBUTING.md`, `AGENTS.md` (instruções para IAs).

## Pendências

Licença (nenhuma concessão criada), identidade visual e ícone, aparelho
Android físico, hospedagem/HTTPS, estornos. Dados reais nunca entram no
repositório: seeds, testes e exemplos são fictícios.
