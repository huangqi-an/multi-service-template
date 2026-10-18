#!/usr/bin/env bash
#
# 从 services/_template 生成一个新的服务骨架。
#
#   ./scripts/new-service.sh my-service
#
# 只做"生成"，不替你改 nginx 路由和根 compose —— 那两处需要人判断
# （路径怎么分、要不要接 db-net），脚本直接把待办清单打出来。

set -euo pipefail

usage() {
    cat <<'EOF'
用法: scripts/new-service.sh <service-name>

服务名规则: 小写字母开头，只含小写字母、数字、连字符。
生成后会在 services/<service-name>/ 下得到 compose.yml、Dockerfile 占位、
.env.example 与 README，占位符 my-app 已全部替换。
EOF
}

if [ $# -ne 1 ]; then
    usage
    exit 1
fi

name="$1"

if ! [[ "$name" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "服务名不合法: '$name'（只允许小写字母、数字、连字符，且以字母开头）" >&2
    exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/services/_template"
dst="$root/services/$name"

if [ ! -d "$src" ]; then
    echo "找不到模板目录: $src" >&2
    exit 1
fi

if [ -e "$dst" ]; then
    echo "目标已存在，拒绝覆盖: $dst" >&2
    exit 1
fi

cp -r "$src" "$dst"

# 占位符替换：模板里统一用 my-app 表示"服务名 = 容器名 = 内部域名"
find "$dst" -type f \( -name '*.yml' -o -name '*.md' \) -exec sed -i "s/my-app/$name/g" {} +

# 去掉只对模板本身有意义的说明块（标记块里讲的是"怎么用模板"，
# 生成出来的真实服务不需要这些内容）
sed -i '/\[\[template-only:start\]\]/,/\[\[template-only:end\]\]/d' "$dst/compose.yml"

echo "已生成: services/$name"
echo
echo "接下来还要做三件事（脚本不代劳，因为需要你判断）:"
echo
echo "  1. 在根 compose.yml 的 include 里追加:"
echo "       - ./services/$name/compose.yml"
echo
echo "  2. 在 nginx/conf.d/default.conf 里加一段 location，上游写 $name"
echo "     注意写操作（POST/PUT/DELETE）不要用 301 补斜杠"
echo
echo "  3. 落地环境变量并启动:"
echo "       cp services/$name/.env.example services/$name/.env"
echo "       docker compose up -d --build $name"
echo
echo "另外记得: 在 docs/架构设计.md 的端口表登记（如需要），"
echo "          并核对 §7 的内存预算还剩多少。"
