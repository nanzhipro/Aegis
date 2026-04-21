# Phase 5 执行包

本文件不能单独使用。执行 Phase 5 时，必须同时携带完整的 `plan/common.md` 和 `plan/phases/phase-5-settings-local-config.md`。

## 必带上下文

- `plan/common.md`
- `plan/phases/phase-5-settings-local-config.md`

## 执行目标

- 把已有保护能力暴露为可操作的原生设置页
- 打通本地策略编辑、热重载和 remembered decision 清理
- 提供最小诊断视图

## 本次允许改动

- 设置页布局与交互
- 本地策略编辑与保存
- 热重载触发逻辑
- remembered decision 清理入口
- 最小诊断/状态视图

## 本次不要做

- 不扩展成云端配置平台
- 不加入非原生 UI 风格

## 交付检查

- 用户能完成目录管理和默认行为配置
- 策略变更能在多组件之间一致生效
- remembered decision 至少支持全量清理

## 执行裁决规则

- 如果 UI 偏离 macOS 原生体验，视为不符合通用约束
- 如果策略修改不能形成一致的热重载，也视为未完成
