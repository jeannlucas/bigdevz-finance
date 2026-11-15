#!/usr/bin/env bash
set -euo pipefail

readonly DEPLOY_SCRIPT="/srv/finance/scripts/vps-deploy.sh"
cmd="${SSH_ORIGINAL_COMMAND:-}"
semver='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

tag=""
digest=""

# Suporta chamada direta via SSH:
# - v1.0.1 bigdevz/finance-api@sha256:...
# - --tag v1.0.1 --digest bigdevz/finance-api@sha256:...
# - v1.0.1 (repassado para que o vps-deploy.sh aplique o fail-closed exigindo digest)
read -r -a args <<< "$cmd"

if [ ${#args[@]} -eq 1 ]; then
  tag="${args[0]}"
elif [ ${#args[@]} -eq 2 ] && [[ "${args[0]}" =~ $semver ]]; then
  tag="${args[0]}"
  digest="${args[1]}"
else
  while [ ${#args[@]} -gt 0 ]; do
    case "${args[0]}" in
      --tag)
        tag="${args[1]:-}"
        args=("${args[@]:2}")
        ;;
      --digest|--image-digest)
        digest="${args[1]:-}"
        args=("${args[@]:2}")
        ;;
      *)
        if [ -z "$tag" ] && [[ "${args[0]}" =~ ^v ]]; then
          tag="${args[0]}"
          args=("${args[@]:1}")
        else
          echo "Argumento não reconhecido no wrapper de deploy: ${args[0]}" >&2
          exit 1
        fi
        ;;
    esac
  done
fi

if ! [[ "$tag" =~ $semver ]]; then
  echo "Entrada rejeitada. A tag deve seguir o formato vMAJOR.MINOR.PATCH." >&2
  exit 1
fi
if [ ! -x "$DEPLOY_SCRIPT" ]; then
  echo "Script de deploy indisponível: $DEPLOY_SCRIPT" >&2
  exit 1
fi

if [ -n "$digest" ]; then
  exec "$DEPLOY_SCRIPT" --tag "$tag" --digest "$digest"
else
  exec "$DEPLOY_SCRIPT" --tag "$tag"
fi
