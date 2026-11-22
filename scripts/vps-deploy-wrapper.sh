#!/usr/bin/env bash
set -euo pipefail

readonly DEPLOY_SCRIPT="/srv/finance/scripts/vps-deploy.sh"
cmd="${SSH_ORIGINAL_COMMAND:-}"
semver='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

tag=""
digest=""
web_hash=""

# Suporta chamada direta via SSH (SSH_ORIGINAL_COMMAND) ou argumentos posicionais ($@):
# - v1.0.1 bigdevz/finance-api@sha256:...
# - v1.0.1 bigdevz/finance-api@sha256:... <web_hash>
# - --tag v1.0.1 --digest bigdevz/finance-api@sha256:... --web-hash <web_hash>
# - -- v1.0.1 bigdevz/finance-api@sha256:... <web_hash>
if [ -n "$cmd" ]; then
  read -r -a args <<< "$cmd"
else
  args=("$@")
fi

# Descartar separador '--' se presente no início
if [ ${#args[@]} -gt 0 ] && [ "${args[0]}" = "--" ]; then
  args=("${args[@]:1}")
fi

if [ ${#args[@]} -eq 1 ]; then
  tag="${args[0]}"
elif [ ${#args[@]} -eq 2 ] && [[ "${args[0]}" =~ $semver ]]; then
  tag="${args[0]}"
  digest="${args[1]}"
elif [ ${#args[@]} -eq 3 ] && [[ "${args[0]}" =~ $semver ]]; then
  tag="${args[0]}"
  digest="${args[1]}"
  web_hash="${args[2]}"
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
      --web-hash|--expected-web-hash)
        web_hash="${args[1]:-}"
        args=("${args[@]:2}")
        ;;
      *)
        if [ -z "$tag" ] && [[ "${args[0]}" =~ ^v ]]; then
          tag="${args[0]}"
          args=("${args[@]:1}")
        elif [ -z "$digest" ] && [[ "${args[0]}" =~ @sha256: || "${args[0]}" =~ ^sha256: ]]; then
          digest="${args[0]}"
          args=("${args[@]:1}")
        elif [ -z "$web_hash" ] && [[ "${args[0]}" =~ ^[a-fA-F0-9]{64}$ ]]; then
          web_hash="${args[0]}"
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
if [ -z "$web_hash" ]; then
  echo "Entrada rejeitada. O hash SHA-256 esperado do frontend web é obrigatório (--web-hash <64 hex chars>)." >&2
  exit 1
fi
if ! [[ "$web_hash" =~ ^[a-fA-F0-9]{64}$ ]]; then
  echo "Entrada rejeitada. O hash web deve ser um SHA-256 hexadecimal de 64 caracteres." >&2
  exit 1
fi
if [ ! -x "$DEPLOY_SCRIPT" ]; then
  echo "Script de deploy indisponível: $DEPLOY_SCRIPT" >&2
  exit 1
fi

deploy_cmd=("$DEPLOY_SCRIPT" --tag "$tag")
if [ -n "$digest" ]; then
  deploy_cmd+=(--digest "$digest")
fi
deploy_cmd+=(--web-hash "$web_hash")
exec "${deploy_cmd[@]}"
