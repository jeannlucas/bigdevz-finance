# Plano de Implementação — Suporte ao Flutter Web (BigDev.Z Finance)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Habilitar a execução e compilação do BigDev.Z Finance no navegador via Flutter Web, compartilhando a mesma API Laravel e integridade de dados do Mobile.

**Architecture:** Monólito modular Laravel 13 servindo endpoints REST com suporte a CORS e cabeçalho `Idempotency-Key`; cliente Flutter compilado para Web (`web/`) com armazenamento seguro compatível (`flutter_secure_storage` com Web Cryptography/IndexedDB) e cliente HTTP desacoplado de `dart:io`.

**Tech Stack:** Flutter 3.47.x / Dart 3.13.x, Laravel 13, PostgreSQL 18, `flutter_secure_storage`.

**Spec:** [`specs/financeiro/financeiro.md`](../../specs/financeiro/financeiro.md) e diretrizes em [`docs/project-guidelines.md`](../../docs/project-guidelines.md).

---

## Global Constraints

- Proibição estrita de `float`/`double` para dinheiro (`AC-FIN-001`).
- Preservação da suíte de 162 testes Flutter existentes e 13 testes de domínio PHP (100% verde).
- Governança de branch: criação de branch dedicada `feature/flutter-web` a partir de `dev`.
- Backpressure obrigatório: `bash scripts/check.sh --fast` deve passar com zero erros.
- Zero credenciais rastreadas ou segredos expostos.

---

## Review Focus

1. Compilação web sem referências a `dart:io`.
2. Resiliência do armazenamento de token e sessão no navegador (`IndexedDB`/`WebStorage`).
3. Autorização de cabeçalhos CORS (`Idempotency-Key`, `Authorization`, `Content-Type`) na API Laravel.
4. Preservação da máscara semântica de saldo e responsividade em resoluções de desktop.
5. Inexistência de regressão nos 162 testes mobile unitários e de widget.

---

## Tarefas de Implementação

### Tarefa 1: Desacoplar `api_client.dart` de `dart:io` para Compatibilidade Web
- [x] **1.1 Escrever teste reproduzível / verificar restrição de plataforma:**
  - Garantir que exceções de rede capturem tanto erros genéricos de cliente HTTP quanto desconexões sem depender de `SocketException` exclusivo de mobile/desktop.
- [x] **1.2 Refatorar [`apps/mobile/lib/core/api_client.dart`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/core/api_client.dart):**
  - Remover `import 'dart:io';`.
  - Capturar `http.ClientException`, `TimeoutException` e exceções de transporte comuns na Web, convertendo-as para `ApiException` de rede amigável.
- [x] **1.3 Validar suíte existente:**
  - Executar `flutter test apps/mobile/test/core/` e certificar que todos os testes de rede e formato continuam passando.

### Tarefa 2: Gerar os Arquivos do Target Web no Flutter
- [x] **2.1 Inicializar o scaffolding web:**
  - Executar `flutter create --platforms web .` dentro de `apps/mobile/`.
- [x] **2.2 Configurar metadados do Web (`index.html`, `manifest.json`):**
  - Ajustar título para `BigDev.Z Finance`.
  - Configurar cores do tema (Azul Profundo `#0A192F` / Verde Esmeralda `#064E3B`).
  - Associar o ícone da marca BigDev.Z ao favicon/manifest.

### Tarefa 3: Compatibilidade do `SessionStorage` no Navegador
- [x] **3.1 Validar inicialização do `FlutterSecureStorage` na Web:**
  - Garantir que `SecureSessionStorage` inicialize com opções web seguras (`webOptions: WebOptions(dbName: 'bigdevz_finance', publicKey: '...')` ou fallback padrão seguro).
- [x] **3.2 Testar persistência de sessão e privacidade:**
  - Validar leitura/gravação em testes unitários e no ciclo de vida do `SessionController`.

### Tarefa 4: Suporte a CORS na API Laravel
- [x] **4.1 Publicar ou configurar `cors.php` em `apps/api/config/cors.php`:**
  - Autorizar origens locais (`http://localhost:*`, `http://127.0.0.1:*`).
  - Autorizar métodos (`GET`, `POST`, `PATCH`, `DELETE`, `OPTIONS`).
  - Expor e autorizar cabeçalhos: `Content-Type`, `Accept`, `Authorization`, `Idempotency-Key`.
- [x] **4.2 Validar no Laravel:**
  - Testar preflight `OPTIONS` via curl/teste automatizado.

### Tarefa 5: Verificação de Build e Backpressure
- [x] **5.1 Testar compilação Web:**
  - Executar `flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:8000/api`.
- [x] **5.2 Executar Quality Gate completo:**
  - Rodar `bash scripts/check.sh --fast` e certificar 100% de sucesso.
- [x] **5.3 Testar execução no Chrome:**
  - Subir localmente para validação visual.
