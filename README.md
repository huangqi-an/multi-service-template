# Multi-Service Template

**单机多服务基础设施模板**：nginx 统一入口 + 可插拔业务服务 + PostgreSQL / Redis 数据层，
全部用 Docker Compose 编排。目标环境是一台 2 核 2G 的轻量服务器，所以
**资源上限、网络分域、服务可插拔**这三件事是模板的核心，不是可选项。

拿它开新项目：在 GitHub 上点 **Use this template**，或 clone 后删掉 `.git` 重新 `git init`。

## 快速开始

前提：Docker 与 **Compose v2.20+**（用到了 `include`）。

```bash
# 1. 创建两个外部网络
#     compose 里声明为 external，意味着它只管使用、不负责创建
./scripts/init-networks.sh

# 2. 数据层的密码（.env 不入库，只提交 .env.example）
cp services/postgres/.env.example services/postgres/.env   # 改掉 change-me

# 3. 示例服务的环境变量
cp services/hello-api/.env.example services/hello-api/.env

# 4. 起来
docker compose up -d
docker compose ps
curl http://localhost/hello/
```

## 目录

```
compose.yml            总入口：只写 include，不含服务定义
nginx/                 入口层：:80 路由表
services/
  _template/           服务模板（不是可运行服务，总入口不 include）
  hello-api/           最小示例，可直接删
  postgres/            PostgreSQL 17
  redis/               Redis 7
data/                  持久化数据（已 gitignore；属主是容器内 uid，清理需 sudo）
scripts/
  init-networks.sh     创建 external 网络（首次部署必跑）
  new-service.sh       从模板生成新服务
docs/                  架构设计文档
```

## 自带的服务

| 服务 | 对外入口 | 内存上限 | 说明 |
|---|---|---|---|
| nginx | `:80` | 128m | 唯一对外入口 |
| hello-api | `/hello/` | 256m | 最小示例，Go，可删 |
| postgres | 仅 `db-net` | 512m | 5432，不映射宿主机 |
| redis | 仅 `db-net` | 128m | 6379，不映射宿主机 |

## 新增一个服务

```bash
./scripts/new-service.sh my-service
```

脚本会复制模板、替换占位符、剥掉只对模板有意义的说明，然后打印还要做的三步：

1. 根 `compose.yml` 的 `include` 里加一行
2. `nginx/conf.d/default.conf` 里加一段 `location`
3. `cp .env.example .env` 后 `docker compose up -d --build`

**有写操作（POST/PUT/DELETE）的路由不要用 301 补斜杠**——301 会让客户端把方法
改成 GET 并丢掉请求体，写操作会悄悄变成读操作。纯 GET 的路由用 301 没问题。

### 要连数据库的话

```yaml
    networks:
      - web-net
      - db-net          # ← 加上这个
```

环境变量里主机名写 **容器名 `postgres`**，不是 `localhost`。另外 `depends_on`
只保证启动顺序、不保证数据库能接受连接，应用要自己轮询等待。
完整实现（连接池、等待重试、迁移）见 git 历史：

```bash
git show 6f076bd -- services/notes-api
```

## 四条约定

1. **一个服务一个目录**，总入口只做 include 聚合，接入与移除不牵连其他服务。
2. **服务名 = 容器名 = 内部域名**，反代直接写容器名，不依赖 IP。
3. **统一在根目录启停**。各服务固定了 `container_name`，在子目录另起项目会撞名。
4. **数据组件不映射端口**，只在 `db-net` 内可达；入口层只接 `web-net`。
