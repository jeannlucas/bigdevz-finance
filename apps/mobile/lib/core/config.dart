/// URL da API definida no build: --dart-define=API_BASE_URL=...
///
/// Simulador iOS: http://127.0.0.1:8000/api (padrão).
/// Emulador Android: http://10.0.2.2:8000/api.
/// Aparelho físico: `http://IP-do-Mac-na-rede:8000/api`, com a API publicada
/// em 0.0.0.0 (BIGDEVZ_API_BIND). Fora do desenvolvimento, apenas HTTPS.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000/api',
);

/// Versão e número de build sincronizados com pubspec.yaml (version: 1.0.0+1).
/// Suporta injeção de flags no build (--dart-define=APP_VERSION=... --dart-define=APP_BUILD=...).
const String appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.0',
);

const String appBuildNumber = String.fromEnvironment(
  'APP_BUILD',
  defaultValue: '1',
);

const String appVersionLabel = '$appVersion (Build $appBuildNumber)';
