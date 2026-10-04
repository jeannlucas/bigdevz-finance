# 0002 — Dinheiro e geração de parcelas

Data: 04/10/2026. Estado: implementado no núcleo PHP e integrado à API,
ao PostgreSQL e ao app na mesma data (decisão 0003).

O contrato escolhido para dinheiro é string decimal canônica, com ponto e duas
casas, como `"2000.00"`. O núcleo converte para centavos inteiros, calcula sem
float e retorna strings. Limite por valor: `999999999999.99`; PHP de 64 bits.
O limite é menor que a capacidade proposta de NUMERIC(19,2), para manter
cálculos inteiros seguros e permitir representação futura no app. Validações
da API e banco adotam o mesmo limite: regra `MoneyAmount` na API e colunas
`BIGINT` em centavos com `CHECK` no PostgreSQL. O app Flutter normaliza a
entrada brasileira em centavos `int` (`lib/core/money.dart`), sem double.

O cronograma recebe total, quantidade e primeiro vencimento. Aceita 1–1200
parcelas, todas positivas; não permite mais parcelas que o total em centavos.
Os centavos restantes entram nas primeiras parcelas, em ordem numérica:
R$ 100,00 em três gera R$ 33,34, R$ 33,33 e R$ 33,33.

O dia do primeiro vencimento permanece como referência. Meses curtos usam seu
último dia válido: 31/01/2026, 28/02/2026, 31/03/2026. Anos bissextos são
considerados. Sem deslocamento por feriado/fim de semana. Datas são calendário
`AAAA-MM-DD`, de 0001 a 9999; cronogramas que excedam esse período são recusados.
UTC é usado apenas para a representação interna sem horário; não há conversão
de vencimento para instante.

O núcleo continua puro: quem grava acordo, parcelas e recebimentos são os casos
de uso em `apps/api/app/Actions/Receivables` (decisão 0003).
