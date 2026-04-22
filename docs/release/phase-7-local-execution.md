# Phase 7 本地执行单

本文档只保留 phase-7 在当前新口径下仍需完成的本地人工步骤，不重复解释 phase-6 已完成的自动化构建、签名、公证与发布链路。

如果你需要完整背景，请同时阅读：

- [runbook.md](runbook.md)
- [privileged-smoke-checklist.md](privileged-smoke-checklist.md)
- [readiness-checklist.md](readiness-checklist.md)

## 当前未完成项

在当前仓库状态下，phase-7 还缺以下内容：

1. 在本地 macOS 14 及以上完整测试环境执行真实 privileged smoke。
2. 形成正式 smoke 记录文件，而不是只停留在本地预检。
3. 把 smoke 结果同步到最终发布前检查清单。
4. 若所有检查为 `Go`，再回写 `plan/state.yaml` 和 `plan/handoff.md`。

## 执行前确认

先确认以下前提成立：

1. 当前本地机器是 macOS 14 及以上。
2. 当前机器可以完整执行 System Extension、Full Disk Access、Agent 提示与超时回退链路验证。
3. 已有最终 `AegisApp.zip`，可来自 GitHub Release，或来自本地已 notarize 且已 stapled 的最终产物。
4. `./scripts/test.sh`、`./scripts/validate-release.sh` 对应产物已经通过。

## 最短执行路径

按下面顺序执行即可：

1. 准备最终产物。

```sh
# 二选一：
# 方案 A：从 GitHub Release 下载最终 AegisApp.zip
# 方案 B：直接使用本地 build/release/AegisApp.zip
```

1. 校验最终产物。

```sh
./scripts/validate-release.sh
```

1. 生成本地 smoke 记录草稿。

```sh
AEGIS_PRIVILEGED_SMOKE_TAG=vX.Y.Z \
AEGIS_PRIVILEGED_SMOKE_ENVIRONMENT='local-full-test-environment' \
./scripts/prepare-privileged-smoke-record.sh
```

1. 打开以下三份文档并开始人工验证：

- `build/release/*-privileged-smoke.md`
- `docs/release/privileged-smoke-checklist.md`
- `docs/release/readiness-checklist.md`

1. 在本地机器上逐项完成以下人工检查：

- 解压 `AegisApp.zip` 并将 `AegisApp.app` 拖入 `/Applications`。
- 首次启动确认 onboarding 出现。
- 触发 System Extension 安装并在系统设置中完成批准。
- 按引导完成 Full Disk Access。
- 确认 Login Item 注册成功，Agent 能在登录会话中启动。
- 触发一次 Allow 路径和一次 Deny 路径。
- 验证 remember choice 命中。
- 验证默认超时回退。
- 验证 Dashboard 状态展示。
- 验证设置页中的目录与默认策略展示。
- 清理 remembered decisions 后，再次确认请求回到提示链路。

1. 将结果写回正式记录文件，例如：

```text
docs/release/records/2026-04-22-vX.Y.Z-privileged-smoke.md
```

1. 更新 `docs/release/readiness-checklist.md`，把本次 smoke 的结论同步进去。

1. 给出最终发布结论：

- 全部通过：`Go`
- 允许带已知 caveat 发布：`Go with caveats`
- 任一关键链路失败：`No-Go`

## 何时可以宣告 phase-7 完成

只有同时满足以下条件，phase-7 才能从“未完成”变成“可回写完成”：

1. 本地完整测试环境中的 privileged smoke 已真实执行。
2. 正式 smoke 记录文件已生成并补齐证据。
3. `docs/release/readiness-checklist.md` 已同步本次结果。
4. 最终结论为 `Go`。

## 完成后的收口命令

如果以上条件全部满足，再执行：

```sh
ruby scripts/planctl complete phase-7 \
  --summary "完成本地完整测试环境中的 privileged smoke、发布留痕与 readiness 收口。" \
  --next-focus "全部 phase 已完成"

ruby scripts/planctl handoff --write
```

## 失败时怎么处理

如果人工验证中任一关键链路失败，不要回写 phase 完成状态，而是：

1. 记录 `No-Go`。
2. 将失败步骤、截图、日志写入 blocker 或正式 smoke 记录。
3. 修复问题后，基于新的最终产物重新执行完整 smoke。
