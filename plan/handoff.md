# Aegis Execution Handoff

本文件用于长流程执行时的压缩恢复。不要一次性重新加载全部 phase 文档；恢复时按本文档与 manifest 继续。

## 当前状态

- State file: `plan/state.yaml`
- Handoff file: `plan/handoff.md`
- Updated at: `2026-04-22T14:33:21Z`
- Completed phases: `phase-0, phase-1, phase-2, phase-3, phase-4, phase-5, phase-6`

## 最近完成

- `phase-4` Extension 决策引擎: 完成 AUTH_OPEN 实时决策链路，接入真实 EndpointSecurity client 与 ExtensionActivationCoordinator，补齐 ready 前订阅控制、ES_NEW_CLIENT_RESULT_ERR_* 显式错误映射、extensionService 状态/诊断上报，并让 AegisExtensionTests 通过 fake client 覆盖 allow、deny、timeout、Apple-signed 与 remembered 路径；同时验证 AegisExtension 目标构建通过。
- next focus: 进入 phase-5，按设置页与本地配置契约审查 Settings scene、本地策略编辑入口与共享配置持久化链路。
- `phase-5` 设置页与本地配置: 确认设置页、本地策略写回、热重载与 remembered decision 全量清理链路满足契约，补齐 Settings 诊断项对 endpoint detail 与最近一条 extension diagnostic 的暴露，并新增 AegisAppTests 覆盖目录移除联动清理 remembered 规则、reload 生效与诊断传播展示。
- next focus: 进入 phase-6，按签名、公证、CI 与发布链路契约审查现有脚本、README 与 release 文档，收敛缺口到最小发布路径。
- `phase-6` 签名、公证、CI 与发布链路: 将发布链路从 DMG 收敛到单一 AegisApp.app + AegisApp.zip 路径，新增 scripts/package-app.sh，改造 notarize/validate/sign/common 脚本、release workflow 与 ReleaseValidationTests，并同步更新 release runbook、readiness checklist 与 privileged smoke 资料到 zip 口径；验证 ReleaseValidationTests 通过。
- next focus: 进入 phase-7，核对本地完整测试环境、最终 zip 产物与人工 privileged smoke 留痕前提；若条件不足，明确 blocker。

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
