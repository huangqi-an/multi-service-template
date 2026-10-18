#!/usr/bin/env bash
#
# 创建本项目依赖的两个 external 网络（web-net / db-net）。
#
# 为什么需要这一步：compose 里这两个网络声明为 external，意思是
# 「已存在、由外部管理」——compose 既不会创建也不会删除它们。
# 所以在任何一台新机器上首次部署前，必须先跑这个脚本，
# 否则 docker compose up 会报：
#   network web-net declared as external, but could not be found
#
# 脚本是幂等的：网络已存在就跳过，可以反复执行。

set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
    echo "找不到 docker 命令，请先安装 Docker" >&2
    exit 1
fi

# 子网写死而不让 Docker 自动分配，是为了让每套环境的内网地址保持一致
# （日志、排查时看到的 172.27.x / 172.28.x 含义固定）。
# 如果与宿主机所在网段冲突，改这两个变量即可。
WEB_NET_SUBNET="${WEB_NET_SUBNET:-172.27.0.0/16}"
DB_NET_SUBNET="${DB_NET_SUBNET:-172.28.0.0/16}"

create_if_missing() {
    local name="$1"
    local subnet="$2"

    if docker network inspect "$name" >/dev/null 2>&1; then
        echo "已存在，跳过：$name"
        return 0
    fi

    # lab.managed=true 是自定义标记，方便识别"这套环境自己管的网络"，
    # 与 compose 自动创建的网络（带 com.docker.compose.* 标签）区分开
    docker network create \
        --label lab.managed=true \
        --subnet "$subnet" \
        "$name" >/dev/null

    echo "已创建：$name（$subnet）"
}

create_if_missing web-net "$WEB_NET_SUBNET"
create_if_missing db-net  "$DB_NET_SUBNET"

echo
echo "当前网络："
docker network ls --filter label=lab.managed=true --format '  {{.Name}}\t{{.Driver}}\t{{.Scope}}'
