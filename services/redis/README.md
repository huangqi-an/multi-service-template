# redis

缓存 / 中间件。**只接 `db-net`，不映射宿主机端口**——
与 MySQL 一样，外部不可达由「安全组 + 无端口映射」双重保证。

## 服务记录项

- **用途**：缓存、临时数据、将来可能用作任务队列
- **访问方式**：仅容器网络内，`host=redis`、`port=6379`
- **依赖**：无
- **数据目录**：`data/redis/`（RDB 快照落在这里）
- **内存上限**：128m（容器硬上限，实测常驻约 13.6 MiB），其中 `maxmemory 96mb` 由配置管理
- **内部端口**：6379（不映射到宿主机）

## 两个参数为什么是这两个数

| 参数 | 值 | 理由 |
|---|---|---|
| `mem_limit`（compose） | 128m | 架构文档 §7 的预算，超了会被 OOM kill |
| `maxmemory`（redis.conf） | 96mb | 留约 32M 给客户端缓冲与内存碎片 |
| `maxmemory-policy` | allkeys-lru | 纯缓存场景；当持久存储用时须改 `noeviction` |

**两者的区别值得记住**：`mem_limit` 是保险丝，撞上就是进程被杀；
`maxmemory` 是日常管理，到达后按策略淘汰而不是崩溃。
只设前者，Redis 会在接近上限时被 OOM；只设后者，配置写错时没有兜底。

## 没有设置密码，为什么

Redis 默认无鉴权。这里不加 `requirepass`，依据是架构文档的隔离模型：
只接 `db-net`、无端口映射，能连上它的只有同处 `db-net` 的业务容器；
而 `web-net` 上的 nginx 连 `redis` 这个名字都解析不出来（已实测）。

如果将来扩大可达范围（例如给宿主机开调试端口），**必须先加密码**：

```yaml
    command:
      - sh
      - -c
      - exec redis-server /usr/local/etc/redis/redis.conf --requirepass "$$REDIS_PASSWORD"
    env_file: .env          # 放 REDIS_PASSWORD
```

对应健康检查也要改成 `REDISCLI_AUTH="$$REDIS_PASSWORD" redis-cli ping`。

## 持久化

只开 RDB（`save 900 1` / `save 300 10`），不开 AOF。
快照文件在 `data/redis/dump.rdb`。

代价：**最近一次快照之后的写入，在容器被杀时会丢**。作为缓存这无所谓；
如果把 Redis 用于不可丢的数据，应开启 AOF 或改用其他存储。

## 常用操作

```bash
docker compose exec redis redis-cli ping
docker compose exec redis redis-cli info memory | grep -E 'used_memory_human|maxmemory_human'
docker compose exec redis redis-cli config get maxmemory-policy
```
