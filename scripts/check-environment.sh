#!/bin/sh
# Diagnóstico somente leitura. Não imprime tokens ou arquivos de credenciais.
set -u

failures=0
check() {
    label=$1
    shift
    if "$@"; then
        printf 'OK: %s\n' "$label"
    else
        printf 'FALHA: %s\n' "$label"
        failures=$((failures + 1))
    fi
}

check 'Git' git --version
check 'GitHub CLI' gh --version
check 'PHP' php --version
check 'Composer' composer --version
# Aceita o SDK no PATH ou em ~/development/flutter (mesma regra do Makefile).
flutter_bin() { command -v flutter >/dev/null || test -x "$HOME/development/flutter/bin/flutter"; }
dart_bin() { command -v dart >/dev/null || test -x "$HOME/development/flutter/bin/dart"; }
check 'Flutter (PATH ou ~/development/flutter)' flutter_bin
check 'Dart (PATH ou ~/development/flutter)' dart_bin
check 'Android adb no PATH' command -v adb
check 'Android sdkmanager no PATH' command -v sdkmanager
check 'Docker CLI' docker --version
check 'Docker Compose' docker compose version
check 'Acesso ao daemon Docker' docker info --format '{{.ServerVersion}}'
check 'Rede Packagist' curl --silent --show-error --fail --head --connect-timeout 5 --max-time 10 --output /dev/null https://repo.packagist.org/packages.json
check 'Rede Flutter SDK' curl --silent --show-error --fail --head --connect-timeout 5 --max-time 10 --output /dev/null https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json
check 'Rede GitHub API' curl --silent --show-error --fail --head --connect-timeout 5 --max-time 10 --output /dev/null https://api.github.com

if [ "$(uname -s)" = Darwin ]; then
    check 'Xcode' xcodebuild -version
    check 'Diretório Xcode selecionado' xcode-select -p
fi

printf '\nFalhas de ambiente: %s\n' "$failures"
printf 'Autenticação GitHub e escrita Git devem ser verificadas separadamente.\n'
if [ "$failures" -gt 0 ]; then
    exit 1
fi
