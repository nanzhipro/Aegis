# Phase 6 执行包

本文件不能单独使用。执行 Phase 6 时，必须同时携带完整的 `plan/common.md` 和 `plan/phases/phase-6-release-pipeline.md`。

## 必带上下文

- `plan/common.md`
- `plan/phases/phase-6-release-pipeline.md`

## 执行目标

- 落地本地与 CI 复用的发布脚本
- 建立 GitHub Actions 工作流
- 固化签名、公证、打包和发布校验流程

## 本次允许改动

- `scripts/*.sh`
- `.github/workflows/*.yml`
- 发布相关文档与校验脚本

## 本次不要做

- 不在 workflow 中复制复杂 shell 逻辑
- 不跳过签名、公证或校验步骤
- 不把特权 smoke 伪装成托管 CI 可自动化能力

## 交付检查

- 自动化测试、归档、签名、公证、打包链路清晰可复用
- workflow 只编排，不埋复杂实现逻辑
- 发布校验入口明确且可重复执行

## 执行裁决规则

- 如果脚本与 workflow 逻辑分叉，优先修正为脚本单一真相来源
- 如果使用 `macos-latest` 而非固定版本，不符合规划
