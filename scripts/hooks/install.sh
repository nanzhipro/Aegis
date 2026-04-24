#!/bin/sh
#
# Aegis · 一键安装仓库自带的 git hooks
# -----------------------------------
# 把 git 的 hooksPath 指向 scripts/hooks，让本仓库的 pre-commit 等钩子在
# 每个 clone 副本里自动生效。幂等，随时可以重复运行。

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

cd "$ROOT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '[install-hooks] 当前目录不是 git 工作区，跳过。\n' >&2
    exit 0
fi

chmod +x scripts/hooks/pre-commit

current=$(git config --local --get core.hooksPath || true)
if [ "$current" = "scripts/hooks" ]; then
    printf '[install-hooks] core.hooksPath 已指向 scripts/hooks，无需重复设置。\n'
else
    git config --local core.hooksPath scripts/hooks
    printf '[install-hooks] 已把 core.hooksPath 设为 scripts/hooks\n'
fi

# 提交身份同步固定，避免 hooks 安装好后仍然因默认身份被拒绝。
expected_name="南朋友"
expected_email="deer_hope@live.cn"
if [ "$(git config --local --get user.name || true)" != "$expected_name" ]; then
    git config --local user.name "$expected_name"
    printf '[install-hooks] 已设置 user.name  = %s\n' "$expected_name"
fi
if [ "$(git config --local --get user.email || true)" != "$expected_email" ]; then
    git config --local user.email "$expected_email"
    printf '[install-hooks] 已设置 user.email = %s\n' "$expected_email"
fi

printf '[install-hooks] 完成。\n'
