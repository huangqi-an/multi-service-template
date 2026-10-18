#!/bin/bash
# 只在数据目录为空、首次初始化时执行一次（/docker-entrypoint-initdb.d 机制）。
# 目的：让 POSTGRES_USER 保持为超级用户 postgres，另外建一个只能碰业务库的 app 账号，
#      避免业务服务直接拿到超级用户权限。
set -euo pipefail

: "${APP_PASSWORD:?APP_PASSWORD 未设置，检查 .env}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
CREATE ROLE app LOGIN PASSWORD '${APP_PASSWORD}';
-- 允许连接业务库
GRANT CONNECT ON DATABASE "${POSTGRES_DB}" TO app;
-- PG 15 起 public schema 默认不再允许普通角色创建对象，
-- 这里显式授权，否则 app 连建表都做不到
GRANT USAGE, CREATE ON SCHEMA public TO app;
EOSQL

echo "已创建业务账号 app，并授予 ${POSTGRES_DB} 库的 public schema 权限"
