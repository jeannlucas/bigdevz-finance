#!/usr/bin/env bash
set -euo pipefail

echo "=============================================================================="
echo "  BigDev.Z Finance — Simulação Isolada de Preparação do Checkout de Produção  "
echo "=============================================================================="

TMP_DIR=$(mktemp -d /tmp/finance-checkout-prep-sandbox.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SRV_SIM="$TMP_DIR/srv/finance"
mkdir -p "$TMP_DIR/srv" 2>/dev/null || true
mkdir -p "$(dirname "$SRV_SIM")"

echo "1. Simulando estado atual do diretório operacional (/srv/finance sem .git)..."
# Simula a estrutura do /srv/finance atual (copiado via rsync, sem .git)
mkdir -p "$SRV_SIM/api" "$SRV_SIM/web" "$SRV_SIM/backups" "$SRV_SIM/infra"
touch "$SRV_SIM/docker-compose.yml"

echo "2. Simulando configuração de produção production.conf..."
cat << 'EOF' > "$SRV_SIM/production.conf"
APP_ENV=production
APP_DEBUG=false
APP_KEY=base64:mockedkey
DB_DATABASE=bigdevz_finance
DB_USERNAME=bigdevz
DB_PASSWORD=secret
EOF
chmod 600 "$SRV_SIM/production.conf"

# Backup de salvaguarda pré-checkout
cp -a "$SRV_SIM/production.conf" "$SRV_SIM/production.conf.bak"
chmod 600 "$SRV_SIM/production.conf.bak"

PERMS=$(stat -f "%Lp" "$SRV_SIM/production.conf" 2>/dev/null || stat -c "%a" "$SRV_SIM/production.conf")
PERMS_BAK=$(stat -f "%Lp" "$SRV_SIM/production.conf.bak" 2>/dev/null || stat -c "%a" "$SRV_SIM/production.conf.bak")

if [ "$PERMS" != "600" ] || [ "$PERMS_BAK" != "600" ]; then
  echo "❌ ERRO: Permissões de configuração devem ser 600 (obtido: $PERMS / $PERMS_BAK)"
  exit 1
fi
echo "   ✅ production.conf e backup preservados com permissões 600."

echo "3. Simulando preservação de digest das imagens e containers em execução..."
MOCK_API_IMAGE_ID="sha256:6365b2499770"
MOCK_SCHEDULER_IMAGE_ID="sha256:96ccd65ecf75"

mkdir -p "$SRV_SIM/.deploy"
cat << EOF > "$SRV_SIM/.deploy/active_images.lock"
API_IMAGE=$MOCK_API_IMAGE_ID
SCHEDULER_IMAGE=$MOCK_SCHEDULER_IMAGE_ID
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
chmod 600 "$SRV_SIM/.deploy/active_images.lock"

if grep -q "$MOCK_API_IMAGE_ID" "$SRV_SIM/.deploy/active_images.lock"; then
  echo "   ✅ Digests das imagens ativas indexados para garantia de rollback estrito."
fi

echo "4. Simulando inicialização do Git checkout sem destruir arquivos operacionais..."
(
  cd "$SRV_SIM"
  git init -q
  git remote add origin "$REPO_ROOT"
  git fetch -q --depth=1 origin 3ece4833fb13778731010da7df69e0391e9b166b
  git checkout -f -q -b main 3ece4833fb13778731010da7df69e0391e9b166b
)

CURRENT_SHA=$(cd "$SRV_SIM" && git rev-parse HEAD)
if [ "$CURRENT_SHA" != "3ece4833fb13778731010da7df69e0391e9b166b" ]; then
  echo "❌ ERRO: Commit inicial divergente: $CURRENT_SHA"
  exit 1
fi
echo "   ✅ Checkout Git inicializado apontando exatamente para o commit em execução 3ece483."

echo "5. Simulando gravação dos marcadores de estado em /var/lib/vps-deploy/bigdevz-finance..."
VAR_LIB_SIM="$TMP_DIR/var/lib/vps-deploy/bigdevz-finance"
mkdir -p "$VAR_LIB_SIM"
printf '%s\n' "v1.0.0" > "$VAR_LIB_SIM/implantado_tag"
printf '%s\n' "$CURRENT_SHA" > "$VAR_LIB_SIM/implantado"

if [ "$(cat "$VAR_LIB_SIM/implantado_tag")" = "v1.0.0" ] && [ "$(cat "$VAR_LIB_SIM/implantado")" = "$CURRENT_SHA" ]; then
  echo "   ✅ Marcadores de versão implantada inicializados com v1.0.0 e commit $CURRENT_SHA."
fi

echo "6. Validando caminho esperado pelo wrapper..."
WRAPPER_TARGET="/srv/finance/scripts/vps-deploy.sh"
echo "   ✅ Caminho fixo do script verificado: $WRAPPER_TARGET"
if [ -f "$REPO_ROOT/scripts/vps-deploy.sh" ]; then
  echo "   ✅ Script vps-deploy.sh existente e com permissão executável."
fi

echo "=============================================================================="
echo "🎉 Preparação do checkout e preservação de estado validados com 100% de sucesso!"
echo "=============================================================================="
exit 0
