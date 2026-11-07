#!/usr/bin/env bash
# BigDev.Z — O Primeiro Não da Máquina (Quality Gate & Backpressure Pré-Push)
# Contrato de Execução:
#   scripts/check.sh [--fast | --full]
#   Padrão (sem argumentos): --full
# Códigos de Saída:
#   0: Todas as verificações obrigatórias passaram com ZERO erros
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

# Detecção de runtime PHP: nativo no host (com extensão pdo_pgsql) ou via container Docker
USE_DOCKER_PHP=0
if ! command -v php >/dev/null 2>&1; then
  USE_DOCKER_PHP=1
  echo "ℹ️  PHP não detectado no PATH do Mac. Utilizando container homologado bigdevz/finance-api:dev."
fi

# --- ETAPA FAST: Tipagem, Estilo e Testes Unitários ---

echo "[1/4] Análise Estática e Tipagem..."
echo "  -> Domínio financeiro PHP..."
if [ "$USE_DOCKER_PHP" -eq 0 ]; then
  php "$ROOT_DIR/apps/api/tests/domain.php" >/dev/null
else
  docker run --rm -v "$ROOT_DIR/apps/api:/app" -w /app bigdevz/finance-api:dev php tests/domain.php >/dev/null
fi

echo "  -> Análise estática Dart (flutter analyze)..."
(cd "$ROOT_DIR/apps/mobile" && flutter analyze)

echo "[2/4] Linters e Formatação..."
echo "  -> Laravel Pint (apps/api)..."
if [ "$USE_DOCKER_PHP" -eq 0 ]; then
  (cd "$ROOT_DIR/apps/api" && vendor/bin/pint --test)
else
  docker run --rm -v "$ROOT_DIR/apps/api:/app" -w /app bigdevz/finance-api:dev vendor/bin/pint --test
fi

echo "  -> Formatação Dart (apps/mobile)..."
(cd "$ROOT_DIR/apps/mobile" && dart format --output=none --set-exit-if-changed lib test integration_test)

echo "[3/4] Testes de Domínio e Unidade..."
echo "  -> Testes de domínio financeiro puro..."
if [ "$USE_DOCKER_PHP" -eq 0 ]; then
  php "$ROOT_DIR/apps/api/tests/domain.php"
else
  docker run --rm -v "$ROOT_DIR/apps/api:/app" -w /app bigdevz/finance-api:dev php tests/domain.php
fi

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

if [ "$USE_DOCKER_PHP" -eq 0 ] && php -m 2>/dev/null | grep -qi pgsql; then
  echo "  -> Sondagem ativa de conexão PostgreSQL de teste (porta 5440)..."
  DB_STATUS=0
  (cd "$ROOT_DIR/apps/api" && php -r '
    $xml = simplexml_load_file("phpunit.xml");
    if (!$xml) { exit(2); }
    $env = [];
    foreach ($xml->php->env as $e) {
      $env[(string)$e["name"]] = (string)$e["value"];
    }
    $host = $env["DB_HOST"] ?? "";
    $port = $env["DB_PORT"] ?? "";
    $db = $env["DB_DATABASE"] ?? "";
    try {
      $dsn = "pgsql:host={$host};port={$port};dbname={$db}";
      $pdo = new PDO($dsn, $env["DB_USERNAME"] ?? "", $env["DB_PASSWORD"] ?? "", [
        PDO::ATTR_TIMEOUT => 3,
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
      ]);
      $stmt = $pdo->query("SELECT current_database()");
      $row = $stmt->fetch(PDO::FETCH_ASSOC);
      if (($row["current_database"] ?? "") !== "bigdevz_finance_test") {
        exit(2);
      }
      exit(0);
    } catch (Throwable) {
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

  echo "  -> Executando suíte completa de testes da API (inclui concorrência e idempotência)..."
  (cd "$ROOT_DIR/apps/api" && php artisan test)
elif docker ps --format '{{.Names}}' | grep -q 'bigdevz-finance-api'; then
  API_CONTAINER=$(docker ps --format '{{.Names}}' | grep 'bigdevz-finance-api' | head -n 1)
  echo "  -> Executando suíte completa de testes da API via container ativo ($API_CONTAINER)..."
  docker exec -e DB_DATABASE=bigdevz_finance_test "$API_CONTAINER" php artisan test
else
  echo "  -> Garantindo container postgres ativo na rede Compose..."
  if ! docker compose ps postgres --filter "status=running" -q | grep -q .; then
    echo "  -> Iniciando container postgres via Docker Compose..."
    BIGDEVZ_DB_PASSWORD="${BIGDEVZ_DB_PASSWORD:-bigdevz_local_dev}" docker compose up -d postgres
  fi

  echo "  -> Executando suíte completa de testes da API via container (concorrência e idempotência)..."
  BIGDEVZ_DB_PASSWORD="${BIGDEVZ_DB_PASSWORD:-bigdevz_local_dev}" docker compose run --rm \
    -e DB_HOST=postgres \
    -e DB_PORT=5432 \
    -e DB_DATABASE=bigdevz_finance_test \
    api php artisan test
fi

echo "================================================="
echo "✅ TUDO VERDE (--full): Homologação automatizada completa!"
echo "   Backpressure satisfeito com ZERO erros."
echo "   A máquina autorizou submeter para homologação humana"
echo "   do desenvolvedor Jeann Lucas!"
echo "================================================="
exit 0
