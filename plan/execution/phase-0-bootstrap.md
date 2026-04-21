# Phase 0 执行包

本文件不能单独使用。执行 Phase 0 时，必须同时携带完整的 `plan/common.md` 和 `plan/phases/phase-0-bootstrap.md`。

## 必带上下文

- `plan/common.md`
- `plan/phases/phase-0-bootstrap.md`

## 执行目标

- 新建原生 `.xcodeproj`
- 建立四模块与基础测试 target
- 固化零第三方依赖边界

## 本次允许改动

- 工程骨架
- target 结构
- 基础目录与资源占位
- 基础测试 target

## 本次不要做

- 不提前实现业务逻辑
- 不提前实现 IPC 与 Endpoint Security 决策
- 不把发布链路提前塞进当前阶段

## 交付检查

- 工程可以作为后续 Phase 的稳定底座
- 无第三方依赖入口
- 后续 Phase 不需要返工工程分层

## 执行裁决规则

- 任何与 `plan/common.md` 冲突的实现都视为无效
- 任何超出当前阶段边界的能力都应延后到后续 Phase
