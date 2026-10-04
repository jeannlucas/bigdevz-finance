#!/bin/sh
# Roteiro HTTP do cenário principal contra a API local, com o usuário fictício
# do seed. Cria uma conta e um acordo novos a cada execução; não apaga nada.
set -eu

API=${API_URL:-http://127.0.0.1:8000/api}
stamp=$(date +%Y%m%d%H%M%S)

call() { # método caminho [json] [chave-idempotente]
    curl -sS -X "$1" "$API$2" -H 'Accept: application/json' -H 'Content-Type: application/json' \
        ${TOKEN:+-H "Authorization: Bearer $TOKEN"} ${4:+-H "Idempotency-Key: $4"} \
        ${3:+-d "$3"} -w '\n%{http_code}'
}
expect() { # descrição valor-obtido valor-esperado
    if [ "$2" = "$3" ]; then printf 'OK: %s (%s)\n' "$1" "$2"; else printf 'FALHA: %s: obtido %s, esperado %s\n' "$1" "$2" "$3"; exit 1; fi
}
body() { printf '%s\n' "$1" | sed '$d'; }
status() { printf '%s\n' "$1" | tail -n1; }

r=$(call POST /auth/login '{"email":"demo@example.com","password":"demo-bigdevz-local","device_name":"smoke"}')
expect 'login' "$(status "$r")" 200
TOKEN=$(body "$r" | jq -r .token)

PF=$(body "$(call GET /spaces)" | jq -r '.data[] | select(.kind=="PF") | .id')
PJ=$(body "$(call GET /spaces)" | jq -r '.data[] | select(.kind=="PJ") | .id')

r=$(call POST "/spaces/$PF/accounts" "{\"name\":\"Conta roteiro $stamp\",\"opening_balance\":\"1000.00\",\"opening_balance_date\":\"2026-01-01\"}")
expect 'conta PF criada' "$(status "$r")" 201
ACC=$(body "$r" | jq -r .data.id)
ACC_PJ=$(body "$(call GET "/spaces/$PJ/accounts")" | jq -r '.data[0].id')

r=$(call POST "/spaces/$PF/agreements" '{"description":"Venda de veículo (fictícia)","total":"24000.00","installment_count":12,"first_due_date":"2026-02-10"}')
expect 'acordo criado' "$(status "$r")" 201
expect 'parcelas de 2000.00' "$(body "$r" | jq -r '[.data.installments[].amount] | unique | join(",")')" 2000.00
expect 'quantidade de parcelas' "$(body "$r" | jq -r '.data.installments | length')" 12
P1=$(body "$r" | jq -r '.data.installments[0].id')
P2=$(body "$r" | jq -r '.data.installments[1].id')
expect 'saldo após cadastrar acordo' "$(body "$(call GET "/spaces/$PF/accounts/$ACC")" | jq -r .data.balance)" 1000.00

r=$(call POST "/spaces/$PF/installments/$P1/receipts" "{\"account_id\":$ACC,\"amount\":\"2000.00\",\"received_on\":\"2026-02-10\"}" "smoke-$stamp-1")
expect 'recebimento integral' "$(status "$r")" 201
expect 'saldo após 1ª parcela' "$(body "$r" | jq -r .data.account.balance)" 3000.00
expect 'acordo a receber' "$(body "$r" | jq -r .data.agreement.remaining)" 22000.00

r=$(call POST "/spaces/$PF/installments/$P2/receipts" "{\"account_id\":$ACC,\"amount\":\"500.00\",\"received_on\":\"2026-03-10\"}" "smoke-$stamp-2")
expect 'recebimento parcial' "$(status "$r")" 201
expect 'saldo após parcial' "$(body "$r" | jq -r .data.account.balance)" 3500.00
expect 'restante da 2ª parcela' "$(body "$r" | jq -r .data.installment.remaining)" 1500.00
expect 'restante do acordo' "$(body "$r" | jq -r .data.agreement.remaining)" 21500.00

r=$(call POST "/spaces/$PF/installments/$P2/receipts" "{\"account_id\":$ACC,\"amount\":\"500.00\",\"received_on\":\"2026-03-10\"}" "smoke-$stamp-2")
expect 'reenvio idempotente' "$(status "$r")" 200
expect 'saldo sem duplicar' "$(body "$r" | jq -r .data.account.balance)" 3500.00

r=$(call POST "/spaces/$PF/installments/$P2/receipts" "{\"account_id\":$ACC,\"amount\":\"600.00\",\"received_on\":\"2026-03-10\"}" "smoke-$stamp-2")
expect 'mesma chave, outro valor' "$(status "$r")" 409

r=$(call POST "/spaces/$PF/installments/$P2/receipts" "{\"account_id\":$ACC_PJ,\"amount\":\"100.00\",\"received_on\":\"2026-03-10\"}" "smoke-$stamp-pj")
expect 'conta PJ em acordo PF' "$(status "$r")" 422
expect 'saldo final' "$(body "$(call GET "/spaces/$PF/accounts/$ACC")" | jq -r .data.balance)" 3500.00

expect 'logout' "$(status "$(call POST /auth/logout)")" 204
printf 'Roteiro concluído.\n'
