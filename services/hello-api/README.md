# hello-api

端到端链路验证服务（**Go 版**）。存在的唯一目的：证明
`浏览器 → 安全组:80 → nginx → web-net → 业务容器` 这条路径是通的。

后续写 Go 服务时，本目录可以整个照着抄（多阶段 Dockerfile + compose + 健康检查 + 反代接入）。
Node/TypeScript 版的等价样板见 `services/hello-node/`。

## 服务记录项

- **用途**：链路连通性验证，不含业务逻辑
- **技术栈**：Go 1.23，只用标准库 `net/http`，无第三方依赖
- **访问方式**：`http://<host>/hello/`（经 nginx 入口层）
- **依赖**：无。不连数据库、不读写挂载目录
- **数据目录**：无（无持久化状态，容器可随意销毁重建）
- **内存上限**：256m，实测常驻约 **1.3 MiB**
- **镜像大小**：约 19.7 MB（多阶段构建，运行阶段基于 alpine）
- **内部端口**：8000（不映射到宿主机）

## 端点

| 容器内路径 | 经入口层访问 | 说明 |
|---|---|---|
| `/` | `/hello/` | 返回服务名、容器 hostname、UTC 时间 |
| `/healthz` | `/hello/healthz` | 供 compose 探活，返回 `{"status":"ok"}` |

`/` 注册的是 `GET /{$}`，`{$}` 表示路径必须到此结束——
不用它的话 `/nothere` 也会命中 `/` 处理器，永远返回 200，
「前缀有没有被正确剥掉」就验不出来了。

## 为什么运行镜像用 alpine 而不是 scratch

scratch 镜像最小，但里面没有 shell、没有 wget，
compose 的 `healthcheck` 就没有可执行的东西。
alpine 只多 5MB，换来能探活、能 `docker exec` 进去排查。

## 验证链路是否真的走通

不要只看响应码，**看后端访问日志里的请求路径**：

```bash
docker compose logs --tail 5 hello-api
# GET /         -> 200     ← 说明 /hello/ 的前缀已被 nginx 剥掉
# GET /nothere  -> 404     ← 说明请求确实进了后端，而不是被入口层拦住
```

## 构建与调试

```bash
# 从仓库根目录统一启停
docker compose up -d --build hello-api
docker compose logs -f hello-api
```

改了 `main.go` 必须带 `--build`，否则用的是旧镜像。
