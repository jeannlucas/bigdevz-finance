# Procedimento Operacional: Backup e Restauração de Banco de Dados

> **Aplicação:** BigDev.Z Finance  
> **Banco de Dados:** PostgreSQL 18 (com restrições compostas de integridade `(id, space_id)`)  
> **Objetivo:** Garantir a preservação total de auditoria (`obligation_changes`), papéis e permissões (`space_users`), encerramentos contábeis (`spaces.closed_until`, `space_closing_logs`) e dados patrimoniais sob falhas ou migrações.

---

## 1. Princípios de Segurança e Integridade
1. **Zero Credenciais em Linha de Comando:** Senhas e tokens nunca devem ser passados como texto direto no terminal. Utilize o mecanismo padrão `pgpass` ou variáveis de ambiente seguras do container.
2. **Formato Custom (`-Fc`):** Os backups devem ser gerados exclusivamente com compressão e formato custom (`pg_dump -Fc`), permitindo restauração seletiva, paralelismo e checagem de integridade SHA-256.
3. **Consistência Transacional:** O PostgreSQL garante snapshots consistentes no momento de início do dump (`MVCC`). Nenhuma transação financeira é salva parcialmente.

---

## 2. Rotina de Backup

### 2.1. Execução via Container Docker
```bash
# 1. Definir data/hora canônica
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="./backups"
mkdir -p "$BACKUP_DIR"

# 2. Executar dump consistente
docker exec bigdevz-finance-postgres-1 pg_dump \
  -U bigdevz \
  -Fc \
  bigdevz_finance > "$BACKUP_DIR/bigdevz_finance_${TIMESTAMP}.dump"

# 3. Gerar checksum SHA-256 para auditoria
shasum -a 256 "$BACKUP_DIR/bigdevz_finance_${TIMESTAMP}.dump" > "$BACKUP_DIR/bigdevz_finance_${TIMESTAMP}.dump.sha256"
```

### 2.2. Execução Direta no Host (PostgreSQL 127.0.0.1:5440)
```bash
PGPASSWORD="$BIGDEVZ_DB_PASSWORD" pg_dump \
  -h 127.0.0.1 \
  -p 5440 \
  -U bigdevz \
  -Fc \
  bigdevz_finance > "$BACKUP_DIR/bigdevz_finance_${TIMESTAMP}.dump"
```

---

## 3. Rotina de Restauração (Restore)

### 3.1. Restauração de Teste em Banco Isolado (Sem sobrescrever produção/desenvolvimento)
```bash
# 1. Criar banco temporário para validação
docker exec bigdevz-finance-postgres-1 psql -U bigdevz -d postgres -c "CREATE DATABASE bigdevz_finance_restore_test;"

# 2. Restaurar dump no banco de validação
docker exec -i bigdevz-finance-postgres-1 pg_restore \
  -U bigdevz \
  -d bigdevz_finance_restore_test \
  --no-owner \
  --no-privileges < "$BACKUP_DIR/bigdevz_finance_${TIMESTAMP}.dump"

# 3. Validar tabelas e contagens
docker exec bigdevz-finance-postgres-1 psql -U bigdevz -d bigdevz_finance_restore_test -c "
SELECT count(*) FROM obligation_changes;
SELECT count(*) FROM space_users;
SELECT count(*) FROM space_closing_logs;
"

# 4. Limpar banco de teste após validação
docker exec bigdevz-finance-postgres-1 psql -U bigdevz -d postgres -c "DROP DATABASE bigdevz_finance_restore_test;"
```

### 3.2. Restauração Completa em Caso de Desastre (Disaster Recovery)
```bash
# 1. Interromper containers da API e Scheduler para evitar novas mutações
docker compose stop api scheduler

# 2. Renomear banco corrompido para fins forenses
docker exec bigdevz-finance-postgres-1 psql -U bigdevz -d postgres -c "ALTER DATABASE bigdevz_finance RENAME TO bigdevz_finance_corrupted_${TIMESTAMP};"

# 3. Recriar banco limpo
docker exec bigdevz-finance-postgres-1 psql -U bigdevz -d postgres -c "CREATE DATABASE bigdevz_finance OWNER bigdevz;"

# 4. Restaurar backup homologado
docker exec -i bigdevz-finance-postgres-1 pg_restore \
  -U bigdevz \
  -d bigdevz_finance \
  --no-owner \
  --no-privileges < "$BACKUP_FILE"

# 5. Reiniciar serviços
docker compose up -d api scheduler

# 6. Validar health check
curl -f http://127.0.0.1:8000/api/health
```

---

## 4. Política de Retenção e Auditoria
- **Backups Diários:** Retidos por 30 dias.
- **Backups Semanais (Fim de Semana):** Retidos por 12 semanas.
- **Backups Mensais (Fechamento Contábil):** Retidos permanentemente por exigência fiscal e de compliance patrimonial.
