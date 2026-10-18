# ─────────────────────────────────────────────────────────────────────
# hello-api 镜像（Go 版）
# 多阶段构建：编译阶段用 golang 镜像，运行阶段只带编译产物，
# 最终镜像不包含 Go 工具链（省掉约 300MB）。
# ─────────────────────────────────────────────────────────────────────

FROM golang:1.23-alpine AS builder
# ↑ 只在构建阶段存在，不会进入最终镜像。

WORKDIR /src

# 没有第三方依赖，go.mod 只声明模块与语言版本。
# 先拷源码再编译；依赖清单单独 COPY 的习惯在这里保留，
# 以后加了第三方库时不用改结构。
COPY go.mod ./
COPY main.go ./

RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/hello-api .
# ↑ CGO_ENABLED=0   ：编出纯静态二进制，不依赖目标机的 libc
#   -trimpath       ：去掉产物里的本机路径，构建可复现
#   -ldflags "-s -w"：去掉符号表与调试信息，二进制更小

FROM alpine:3.20
# ↑ 运行阶段没有用 scratch：scratch 里没有 shell、没有 wget，
#   compose 的 healthcheck 就完全跑不起来。alpine 只多 5MB，
#   换来「能探活、能 exec 进去排查」，在这个环境里值得。

RUN adduser -D -u 10001 appuser
# ↑ 非 root 用户运行；ADDUSER 的 -D 表示不设密码的普通用户

COPY --from=builder /out/hello-api /usr/local/bin/hello-api

USER appuser
EXPOSE 8000
# ↑ 仅文档性质，真正对外与否由 compose 的 ports 与网络决定

CMD ["hello-api"]
# ↑ exec 形式：进程直接作为 PID 1，能正确接收 docker stop 的 SIGTERM
