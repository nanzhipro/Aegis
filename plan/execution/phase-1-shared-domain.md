# Phase 1 执行包

本文件不能单独使用。执行 Phase 1 时，必须同时携带完整的 `plan/common.md` 和 `plan/phases/phase-1-shared-domain.md`。

## 必带上下文

- `plan/common.md`
- `plan/phases/phase-1-shared-domain.md`

## 执行目标

- 先完成 `AegisShared`
- 用测试固化模型、路径规则和策略存储
- 固化 remembered decision 的数据结构与命中规则

## 本次允许改动

- 共享模型
- 路径工具
- 策略持久化
- 本地化资源骨架
- `AegisShared` 相关测试

## 本次不要做

- 不提前做 onboarding UI
- 不提前做 Agent 提示窗
- 不提前订阅真实 ES 事件

## 交付检查

- 共享模型和路径规则已经测试化
- remembered decision 结构可以被后续模块复用
- `AegisShared` 成为唯一真相来源

## 执行裁决规则

- 若缺少测试，不算完成
- 若共享规则仍散落在多个模块，也不算完成
