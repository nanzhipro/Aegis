# Phase 7 执行包

本文件不能单独使用。执行 Phase 7 时，必须同时携带完整的 `plan/common.md` 和 `plan/phases/phase-7-privileged-smoke-release-readiness.md`。

## 必带上下文

- `plan/common.md`
- `plan/phases/phase-7-privileged-smoke-release-readiness.md`

## 执行目标

- 在本地可完整测试的 macOS 14 及以上环境完成特权 smoke
- 补齐发布前文档与 runbook
- 固化正式发布流程

## 本次允许改动

- 特权验证记录
- 发布 runbook
- 发布前检查清单
- 人工验证说明

## 本次不要做

- 不新增产品能力范围
- 不为绕过平台授权限制而引入私有 API 或异常流程

## 交付检查

- 特权 smoke 有结果、有记录、有结论
- 正式发布前检查路径清晰可复用
- 团队可以按文档完成一次完整 release

## 执行裁决规则

- 若缺少本地完整测试环境中的真实验证记录，不能判定发布准备完成
- 若文档不足以让其他人复现发布，也不能判定完成
