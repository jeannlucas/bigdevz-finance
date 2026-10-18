#!/usr/bin/env bash
# BigDev.Z — O Primeiro Não da Máquina (Quality Gate)
# Contrato de Execução:
#   scripts/check.sh [--fast | --full]
#   Padrão (sem argumentos): --full
# Códigos de Saída:
#   0: Todas as verificações obrigatórias passaram
#   1: Falha em teste, linter, formatação ou análise estática
#   2: Pré-requisito obrigatório indisponível (ex: banco de testes offline no modo --full)
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Garante Flutter e Dart no PATH caso estejam instalados no diretório padrão local
if [ -d "$HOME/development/flutter/bin" ]; then
  export PATH="$HOME/development/flutter/bin:$PATH"
fi

MODE="full"
if [ "$#" -gt 1 ]; then
  echo "Uso: $0 [--fast | --full]"
  exit 1
elif [ "$#" -eq 1 ]; then
  case "$1" in
    --fast)
      MODE="fast"
      ;;
    --full)
      MODE="full"
      ;;
    *)
      echo "Argumento inválido: $1"
      echo "Uso: $0 [--fast | --full]"
      exit 1
      ;;
  esac
fi

echo "================================================="
echo "  BigDev.Z Quality Gate — scripts/check.sh"
echo "  Repositório: BigDev.Z Finance"
echo "  Modo Selecionado: --${MODE}"
echo "================================================="

# --- ETAPA FAST: Tipagem, Estilo e Testes Unitários ---

echo "[1/4] Análise Estática e Tipagem..."
echo "  -> Domínio financeiro PHP..."
php "$ROOT_DIR/apps/api/tests/domain.php" >/dev/null

echo "  -> Análise estática Dart (flutter analyze)..."
(cd "$ROOT_DIR/apps/mobile" && flutter analyze)

echo "[2/4] Linters e Formatação..."
echo "  -> Laravel Pint (apps/api)..."
(cd "$ROOT_DIR/apps/api" && vendor/bin/pint --test)

echo "  -> Formatação Dart (apps/mobile)..."
(cd "$ROOT_DIR/apps/mobile" && dart format --output=none --set-exit-if-changed lib test integration_test)

echo "[3/4] Testes de Domínio e Unidade..."
echo "  -> Testes de domínio financeiro puro..."
php "$ROOT_DIR/apps/api/tests/domain.php"

echo "  -> Suíte Flutter (apps/mobile)..."
(cd "$ROOT_DIR/apps/mobile" && flutter test)

if [ "$MODE" = "fast" ]; then
  echo "================================================="
  echo "⚡ FAST GATE OK: Testes e análise estática aprovados!"
  echo "   Aviso: Homologação completa requer --full."
  echo "================================================="
  exit 0
fi

# --- ETAPA FULL: Integração com PostgreSQL de Testes e Concorrência ---

echo "[4/4] Verificação de Banco de Testes e Testes da API..."
echo "  -> Sondagem ativa de conexão PostgreSQL de teste (porta 5440)..."

DB_STATUS=0
(cd "$ROOT_DIR/apps/api" && php -r '
  $xml = simplexml_load_file("phpunit.xml");
  if (!$xml) {
    fwrite(STDERR, "Erro: Falha ao carregar phpunit.xml\n");
    exit(2);
  }
  $env = [];
  foreach ($xml->php->env as $e) {
    $env[(string)$e["name"]] = (string)$e["value"];
  }
  $host = $env["DB_HOST"] ?? "";
  $port = $env["DB_PORT"] ?? "";
  $db = $env["DB_DATABASE"] ?? "";
  if ($host !== "127.0.0.1" || $port !== "5440" || $db !== "bigdevz_finance_test") {
    fwrite(STDERR, "Erro: Configuração de teste inválida. Exigido 127.0.0.1:5440/bigdevz_finance_test\n");
    exit(2);
  }
  try {
    $dsn = "pgsql:host={$host};port={$port};dbname={$db}";
    $pdo = new PDO($dsn, $env["DB_USERNAME"] ?? "", $env["DB_PASSWORD"] ?? "", [
      PDO::ATTR_TIMEOUT => 3,
      PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
    $stmt = $pdo->query("SELECT current_database()");
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (($row["current_database"] ?? "") !== "bigdevz_finance_test") {
      fwrite(STDERR, "Erro: Conectado a banco inesperado.\n");
      exit(2);
    }
    echo "  -> PostgreSQL de teste ativo e homologado (127.0.0.1:5440/bigdevz_finance_test).\n";
    exit(0);
  } catch (Throwable) {
    fwrite(STDERR, "  -> [BLOQUEADO] Falha de conexao com PostgreSQL de teste na porta 5440.\n");
    exit(2);
  }
') || DB_STATUS=$?

if [ "$DB_STATUS" -ne 0 ]; then
  echo ""
  echo "================================================="
  echo "❌ QUALITY GATE BLOQUEADO: Banco de teste indisponível!"
  echo "   O modo --full exige PostgreSQL ativo em 127.0.0.1:5440 (bigdevz_finance_test)."
  echo "   Execute os containers de teste ou use --fast para validação local sem banco."
  echo "================================================="
  exit 2
fi

echo "  -> Validando conexão efetiva do runtime da API (127.0.0.1:5440/bigdevz_finance_test)..."
(cd "$ROOT_DIR/apps/api" && php -r '
  $xml = simplexml_load_file("phpunit.xml");
  if (!$xml) { exit(2); }
  foreach ($xml->php->env as $e) {
    putenv("{$e["name"]}={$e["value"]}");
    $_ENV[(string)$e["name"]] = (string)$e["value"];
  }
  require "vendor/autoload.php";
  $app = require_once "bootstrap/app.php";
  $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
  $conn = Illuminate\Support\Facades\DB::connection();
  $cfg = $conn->getConfig();
  $host = $cfg["host"] ?? "";
  $port = (string)($cfg["port"] ?? "");
  $db = $cfg["database"] ?? "";
  if ($host !== "127.0.0.1" || $port !== "5440" || $db !== "bigdevz_finance_test") {
    fwrite(STDERR, "Erro: Conexao efetiva do runtime ({$host}:{$port}/{$db}) diverge de 127.0.0.1:5440/bigdevz_finance_test\n");
    exit(2);
  }
  try {
    $current = (string) $conn->getPdo()->query("SELECT current_database()")->fetchColumn();
    if ($current !== "bigdevz_finance_test") {
      fwrite(STDERR, "Erro: Conexao efetiva do PDO conectada a banco inesperado ({$current})\n");
      exit(2);
    }
  } catch (Throwable) {
    fwrite(STDERR, "Erro: Falha ao consultar banco efetivo pelo runtime do Laravel\n");
    exit(2);
  }
')

echo "  -> Executando suíte completa de testes da API (inclui concorrência e idempotência)..."
(cd "$ROOT_DIR/apps/api" && php artisan test)

echo "================================================="
echo "✅ TUDO VERDE (--full): Homologação automatizada completa!"
echo "   A máquina autorizou submeter para homologação humana"
echo "   do desenvolvedor Jeann Lucas!"
echo "================================================="
exit 0
