# Guia de Desenvolvimento Multiplataforma (iOS & Android)

Este documento descreve os requisitos, fluxo de configuração, comandos operacionais e soluções de conectividade para desenvolver, testar e compilar o aplicativo móvel do **BigDev.Z Finance** tanto no **Android** quanto no **iOS**.

---

## 1. Ferramentas e Pré-requisitos

### Pré-requisitos Gerais do Flutter
- **Flutter SDK**: 3.47.6 (canal `stable`) com Dart 3.13.5 ou superior.
- **Git** e **cURL**.
- **Docker & Docker Compose**: para executar os serviços locais de backend (Laravel + PostgreSQL).

### Pré-requisitos para Desenvolvimento iOS
- macOS com arquitetura Apple Silicon ou Intel.
- **Xcode**: 16+ / 27+ com ferramentas de linha de comando (`xcode-select -p`).
- **Simulador iOS**: runtime instalado (ex.: iPhone 17 Pro ou compatível).
- **CocoaPods**: 1.16+ ou superior (`pod --version`).

### Pré-requisitos para Desenvolvimento Android
- **Android Studio** (Koala / Ladybug ou superior).
- **JDK**: Java 17+ (OpenJDK 17 / 21 ou o JBR embutido do Android Studio).
- **Android SDK Platform**: API Level 36 (`android-36`).
- **Android SDK Build-Tools**: 36.0.0.
- **Android SDK Platform-Tools**: `adb` 35+.
- **Android SDK Command-line Tools**: `latest` (`sdkmanager`).
- **Android Emulator**: 35+ com suporte a arquitetura host (`arm64-v8a` no Apple Silicon).

---

## 2. Diagnóstico e Verificação do Ambiente

Execute os diagnósticos automatizados do repositório:

```bash
# Diagnóstico rápido de ferramentas locais e serviços
sh scripts/check-environment.sh

# Diagnóstico detalhado do Flutter e cadeias de ferramentas nativas
flutter doctor -v
```

Caso existam licenças do Android SDK pendentes de aceite:

```bash
flutter doctor --android-licenses
```

---

## 3. Inicialização dos Serviços da API Backend

O aplicativo móvel necessita da API Laravel em execução com o banco de dados e os dados demonstrativos carregados:

```bash
# Subir PostgreSQL 18 e API Laravel (http://127.0.0.1:8000)
make up

# Aplicar migrations do banco de dados de desenvolvimento
make migrate

# Inserir o usuário e as movimentações demonstrativas locais
make seed
```

> **Credenciais de Teste**:
> - E-mail: `demo@example.com`
> - Senha: `demo-bigdevz-local`

---

## 4. Estratégia de Rede e Conectividade com a API

O aplicativo Flutter consome o endpoint base através do parâmetro de compilação `--dart-define=API_BASE_URL=...`. O endereço varia conforme o ambiente de execução:

| Ambiente de Execução | URL da API (`API_BASE_URL`) | Resolução de Rede e Roteamento |
| :--- | :--- | :--- |
| **Simulador iOS** | `http://127.0.0.1:8000/api` | Compartilha a interface de loopback (`localhost`) diretamente com o Mac host. |
| **Emulador Android** | `http://10.0.2.2:8000/api` | O gateway virtual do emulador Android roteia `10.0.2.2` para o `127.0.0.1` do host. |
| **Android Físico (via USB)** | `http://127.0.0.1:8000/api` | Requer redirecionamento reverso de portas via ADB: `adb reverse tcp:8000 tcp:8000`. |
| **Aparelho Físico (Wi-Fi local)** | `http://<IP_DO_MAC>:8000/api` | Requer iniciar a API escutando em todas as interfaces: `BIGDEVZ_API_BIND=0.0.0.0 make up`. |
| **Produção** | `https://api.seudominio.com/api` | Comunicação estrita via HTTPS com certificado TLS válido. |

### Segurança de Rede (Cleartext HTTP em Desenvolvimento)
- **Android Debug**: O arquivo `apps/mobile/android/app/src/debug/AndroidManifest.xml` possui a diretiva `android:usesCleartextTraffic="true"` estritamente restrita ao build de desenvolvimento (debug), permitindo chamadas HTTP locais sem comprometer a segurança do build de release.
- **Android Release**: O manifesto principal (`src/main/AndroidManifest.xml`) recusa tráfego HTTP em texto claro por padrão, exigindo HTTPS para conformidade de segurança.

---

## 5. Inicialização de Emuladores e Dispositivos

### Listar Emuladores e Dispositivos Disponíveis
```bash
# Listar dispositivos conectados ou simuladores ativos
flutter devices

# Listar emuladores virtuais cadastrados
flutter emulators
```

### Iniciar o Emulador Android
```bash
# Iniciar o emulador pelo identificador (ex.: bigdevz_api36)
flutter emulators --launch bigdevz_api36

# Ou via emulator CLI diretamente
$ANDROID_HOME/emulator/emulator -avd bigdevz_api36 &
```

### Iniciar o Simulador iOS
```bash
# Iniciar simulador iOS no macOS
xcrun simctl boot "iPhone 17 Pro"
open -a Simulator 2>/dev/null || open -a DeviceHub 2>/dev/null || true
```

---

## 6. Execução do Aplicativo (Flutter Run)

### Executando no Emulador Android
Utilize a URL virtual `10.0.2.2:8000` (ou utilize o alvo simplificado do Makefile):

```bash
# Via Makefile (recomendado):
make run-android

# Ou diretamente pelo Flutter CLI:
cd apps/mobile
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

Se preferir utilizar `127.0.0.1` no Android, configure o túnel reverso do ADB:
```bash
adb reverse tcp:8000 tcp:8000
cd apps/mobile
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

### Executando no Simulador iOS
```bash
# Via Makefile (recomendado):
make run-ios DEVICE="iPhone 17 Pro"

# Ou diretamente pelo Flutter CLI:
cd apps/mobile
flutter run -d "iPhone 17 Pro" --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

---

## 7. Validação e Testes Automatizados

### Análise Estática e Testes Unitários/Widgets
```bash
# Instalar dependências Flutter
make mobile-deps

# Verificar integridade e formatação de código
make analyze-mobile

# Executar suíte de testes Flutter (86 testes unitários e de widgets)
make test-mobile
```

### Testes de Integração com a API Real no Dispositivo

Para executar os testes de ponta a ponta no emulador Android conectado à API real:

```bash
cd apps/mobile
flutter test integration_test/inspection_test.dart -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

---

## 8. Compilação Nativa do Android (Build APK)

Para verificar que a compilação do Android e o Android Gradle Plugin (AGP) estão operacionais sem executar o aplicativo:

```bash
# Compilar APK de depuração via Makefile:
make build-android-debug

# Ou via Flutter CLI:
cd apps/mobile
flutter build apk --debug
```

O arquivo gerado é localizado em:
`apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`

---

## 9. Resolução de Problemas Comuns de Conectividade

| Sintoma / Erro | Causa Provável | Solução Recomendada |
| :--- | :--- | :--- |
| **"API indisponível" no Android Emulator** | Aplicação apontando para `127.0.0.1` sem `adb reverse`. | Execute com `--dart-define=API_BASE_URL=http://10.0.2.2:8000/api` ou rode `adb reverse tcp:8000 tcp:8000`. |
| **Falha de conexão em dispositivo físico** | Host vinculado apenas a `127.0.0.1` ou firewall bloqueando porta 8000. | Suba a API com `BIGDEVZ_API_BIND=0.0.0.0 make up` e informe o IP da rede local do computador. |
| **"Cleartext HTTP traffic not permitted"** | Executando build de release ou ausência da permissão de rede em debug. | Verifique se está executando em modo `debug` ou use HTTPS se estiver testando build de staging/release. |
| **Erro "adb: command not found"** | Ferramentas de plataforma do Android não adicionadas ao PATH. | Exporte `export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"` no shell. |
| **Java/Gradle Incompatible Version** | Versão incompatível do Java utilizada pelo Gradle. | Configure o Java do Android Studio: `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`. |
