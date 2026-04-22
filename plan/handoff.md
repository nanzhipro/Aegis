# Aegis Execution Handoff

本文件用于长流程执行时的压缩恢复。不要一次性重新加载全部 phase 文档；恢复时按本文档与 manifest 继续。

## 当前状态

- State file: `plan/state.yaml`
- Handoff file: `plan/handoff.md`
- Updated at: `2026-04-21T14:00:15Z`
- Completed phases: `phase-0, phase-1, phase-2, phase-3, phase-4, phase-5, phase-6`

## 最近完成

- `phase-4` Extension 决策引擎: 完成 AUTH_OPEN 决策引擎、trusted process policy、Apple-signed 与 remembered 决策命中、Agent fallback 与 phase-4 测试，并验证 scripts/test.sh 通过。
- next focus: phase-5 设置页与本地配置：接入本地策略持久化、设置页编辑与 App/Extension 状态联动。
- `phase-5` 设置页与本地配置: 完成原生设置页、本地策略编辑持久化、remembered decision 清理、诊断视图与 phase-5 测试，并验证 scripts/test.sh 通过。
- next focus: 进入 phase-6，落地发布流水线脚本与归档/签名/打包骨架。
- `phase-6` 签名、公证、CI 与发布链路: 完成发布脚本、GitHub Actions workflows、ReleaseValidationTests 与本地 archive/sign/package/validate 烟测，并验证 scripts/test.sh 通过。
- next focus: 进入 phase-7，在本地完整测试环境串联特权 smoke 与发布 readiness。

## 下一 Phase

- `phase-7` 特权 Smoke 与发布准备
- plan: `plan/phases/phase-7-privileged-smoke-release-readiness.md`
- execution: `plan/execution/phase-7-privileged-smoke-release-readiness.md`

下一步读取顺序：

1. `plan/common.md`
2. `plan/phases/phase-7-privileged-smoke-release-readiness.md`
3. `plan/execution/phase-7-privileged-smoke-release-readiness.md`

## 压缩恢复顺序

1. `plan/manifest.yaml`
2. `plan/handoff.md`
3. `next.phase.required_context`

## 压缩控制规则

- 永远不要一次性加载所有 phase 文档。
- 只在当前 phase 读取 plan/common.md、当前 phase plan 和当前 phase execution。
- 每完成一个 phase 后更新 handoff，再进入下一 phase。

## 连续执行命令

- next: `ruby scripts/planctl next --format prompt --strict`
- complete: `ruby scripts/planctl complete <phase-id> --summary "<summary>" --next-focus "<next-focus>"`
- handoff: `ruby scripts/planctl handoff --write`
