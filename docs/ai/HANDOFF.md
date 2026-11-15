# BigDev.Z Finance — Transição Operacional (Handoff)

> **Data de Atualização:** 15/11/2026
> **Branch Atual:** `fix/seguranca-configuracao-ambientes-cache` (a partir da `dev`)
> **Status de Qualidade:** ✅ BACKPRESSURE 100% VERDE (`./scripts/check.sh --full` e `make check`)
> **Status do Incidente:** ✅ INCIDENTE CONTIDO E BLINDADO

---

## 1. Resumo Executivo da Resposta ao Incidente

Em resposta imediata à identificação de risco de contaminação cruzada de ambientes e cache de bundle web:

1. **Contenção Imediata em Produção (VPS):**
   - Usuário de desenvolvimento criado temporariamente em produção foi auditado, seus tokens Sanctum emitidos foram 100% revogados e o registro foi permanentemente removido via procedimento seguro do Eloquent.
   - Espaços e dados residuais foram completamente expurgados (`App\Models\User::count() == 0`, `PersonalAccessToken::count() == 0`).
   - Nenhuma conta legítima ou registro financeiro foi impactado.
2. **Correção de Configuração de Ambientes Web (`apps/mobile/lib/core/config.dart`):**
   - Implementado enum formal `AppEnvironment` (`local`, `staging`, `production`).
   - Implementada função de falha segura `resolveApiBaseUrl()` com validações estritas em tempo de execução:
     - Bloqueio estrito de vazamento: host local do navegador (`localhost`, `127.0.0.1`) é terminantemente proibido de chamar o domínio de produção (`finance.bigdevz.com`).
     - Build de produção (`APP_ENV=production`) é terminantemente proibido de utilizar transportes HTTP inseguros ou endereços de loopback (`localhost`, `127.0.0.1`, portas locais).
     - No Flutter Web em produção, a resolução deriva automaticamente a mesma origem segura (`/api`).
   - Adicionada tela executiva de contingência `EnvironmentConfigurationErrorApp` em `main.dart` para falhas seguras sem vazamento de dados.
3. **Identificação Visual Segura:**
   - Badge visual não sensível exibido na tela de login (`login_screen.dart`) e tela de configurações (`settings_screen.dart`), indicando claramente `DEV LOCAL` ou `HOMOLOGAÇÃO` quando fora de produção.
4. **Política Canônica de Cache Web (Caddy VPS & Meta Tags):**
   - Atualizado `apps/mobile/web/index.html` com meta tags anti-cache de ciclo de vida (`no-cache, no-store, must-revalidate`).
   - Atualizado `/etc/caddy/Caddyfile` na VPS com regras explícitas:
     - Documentos de entrada (`index.html`, `flutter_service_worker.js`, `version.json`, `manifest.json`): `Cache-Control: "no-cache, no-store, must-revalidate"`.
     - Assets estáticos (`/assets/*`, `/canvaskit/*`, `/icons/*`): `Cache-Control: "public, max-age=31536000, immutable"`.
5. **Script Canônico de Build Web (`scripts/build-web.sh`):**
   - Script parametrizado com `--env=local`, `--env=staging`, `--env=production` e validações pré-compilação para impedir a geração acidental de bundles apontando para ambientes trocados.
   - `scripts/deploy-production.sh` atualizado para consumir o script oficial com `--env=production`.

---

## 2. Instruções de Execução Local e Bootstrap Seguro

Para inicializar ou rodar o ambiente local com isolamento total:

1. **Subir containers locais:**
   ```bash
   docker compose up -d
   ```
2. **Executar migrações locais:**
   ```bash
   docker exec finance-api-dev php artisan migrate
   ```
3. **Criar ou atualizar usuário local com placeholders seguros:**
   ```bash
   docker exec finance-api-dev php artisan user:create <EMAIL_LOCAL> --name="<NOME_LOCAL>" --password="<SENHA_LOCAL>"
   ```
4. **Compilar e servir o frontend Web local:**
   ```bash
   ./scripts/build-web.sh --env=local
   python3 -m http.server 8085 --directory apps/mobile/build/web --bind 127.0.0.1
   ```

---

## 3. Resultado das Verificações Automatizadas (Quality Gate)

- **Domínio Financeiro PHP (`tests/domain.php`):** 14/14 testes aprovados.
- **Linter Laravel Pint (`apps/api`):** 161 arquivos conformes.
- **Análise Estática Dart (`flutter analyze`):** 0 issues (limpo).
- **Formatação Dart (`apps/mobile`):** 159 arquivos validados.
- **Suíte Flutter (`flutter test`):** 307 testes aprovados (0 falhas).
- **Suíte de Integração Laravel (`php artisan test`):** 195 testes aprovados (1821 asserções, 0 falhas).
