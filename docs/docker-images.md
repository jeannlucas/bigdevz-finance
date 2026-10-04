# Imagens Docker locais

A API usa `bigdevz/finance-api:dev`, definida em `docker-compose.yml`.
O Dockerfile inclui `com.bigdevz.project=finance` e `com.bigdevz.service=api`.
As labels passam a constar nas imagens produzidas pelo próximo build.

O PostgreSQL mantém o nome oficial `postgres:18-alpine`.
A padronização não altera portas, volumes, banco ou configuração da aplicação.

Para conferir os nomes sem abrir arquivo de ambiente real:

```sh
docker compose --env-file /dev/null config --images
```

Adicionar um nome à imagem já construída não reinicia containers nem incorpora
labels novas. As labels dependem de um novo build; nenhum build ou reinício
faz parte desta padronização.
