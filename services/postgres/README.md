# postgres

关系型数据服务。**只接 `db-net`，不映射宿主机端口**——
外部不可达，业务服务通过容器名 `postgres` 在 `db-net` 内访问。

选型说明：本模板用 PostgreSQL 而非 MySQL —— 目标机内存有限，PG 的镜像体积与常驻内存都明显更低，且跨库查询受限、按库隔离更硬。

## 服务记录项

- **用途**：业务数据持久化
- **访问方式**：仅容器网络内，`host=postgres`、`port=5432`、库 `app`、账号 `app`
- **依赖**：无
- **数据目录**：`data/postgres/`（仓库根下，已 gitignore）
- **内存上限**：512m（`shared_buffers` 128MB 为主要占用）
- **内部端口**：5432（不映射到宿主机）

## 账号模型

两个角色，职责分开：

| 角色 | 用途 | 权限 |
|---|---|---|
| `postgres` | 管理 | 超级用户，仅用于维护 |
| `app` | 业务 | 只能连 `app` 库、在 `public` schema 里建表 |

`app` 由 `initdb/01-app-role.sh` 在首次初始化时创建。**业务服务一律用 `app`，不要用 `postgres`。**

顺带一提：PG 15 起 `public` schema 默认不再允许普通角色创建对象，
所以脚本里显式做了 `GRANT USAGE, CREATE ON SCHEMA public TO app`——
不加这行，`app` 连建表都会报 permission denied。

## 连接

从同处 `db-net` 的容器里：

```bash
psql -h postgres -U app -d app
```

宿主机连不上（无端口映射），需要临时用客户端时进容器：

```bash
docker compose exec postgres psql -U postgres -d app
```

## 内存参数

`mem_limit: 512m` 只是兜底，真正决定占用的是 `command` 里的 `-c` 参数：

| 参数 | 值 | 说明 |
|---|---|---|
| `shared_buffers` | 128MB | 共享缓冲池，PG 最大的一块 |
| `effective_cache_size` | 256MB | 只影响优化器估算，**不实际分配内存** |
| `work_mem` | 4MB | 每个排序/哈希操作，连接多时会累乘，所以给小值 |
| `maintenance_work_mem` | 64MB | VACUUM、建索引用 |
| `max_connections` | 50 | PG 是一连接一进程，每条连接都有独立内存开销 |

为什么用 `-c` 参数而不是挂 `postgresql.conf`：一旦用 `config_file` 指向别处，
PG 会连带把 `pg_hba.conf` 的默认位置也改到那个目录，找不到就起不来。

## 初始化与重置

首次启动（`data/postgres/` 为空）时，镜像会用 `POSTGRES_*` 建库建超级用户，
然后依次执行 `initdb/` 下的脚本创建 `app` 角色。

**`.env` 里的变量只在这一次生效**，之后改不动已有密码——轮换要走 `ALTER ROLE`，步骤见 `docs/架构设计.md` §9.6。

彻底重置：

```bash
docker compose down
sudo rm -rf data/postgres     # 会删掉全部数据，确认后再执行
cp .env.example .env          # 重新设置密码
docker compose up -d postgres
```

## 与 MySQL 的一处概念差异

MySQL 的「库」和 PG 的「库」不完全对等。PG 在库内部还有 **schema** 一层：
`app` 库下默认是 `public` schema，表都建在这里。
跨库查询在 PG 里做不到（要 `dblink`/`fdw`），而 MySQL 同实例内可以跨库查。
这也意味着 PG 的隔离更硬——按库拆服务时，天然查不到别人的表。
