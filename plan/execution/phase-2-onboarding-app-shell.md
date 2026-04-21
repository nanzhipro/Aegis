# Phase 2 执行包

本文件不能单独使用。执行 Phase 2 时，必须同时携带完整的 `plan/common.md` 和 `plan/phases/phase-2-onboarding-app-shell.md`。

## 必带上下文

- `plan/common.md`
- `plan/phases/phase-2-onboarding-app-shell.md`

## 执行目标

- 落地原生宿主 App 外壳
- 保证首次启动进入 onboarding
- 补齐 readiness 展示和三语本地化骨架

## 本次允许改动

- onboarding 状态机与界面
- 宿主 App 壳层
- 默认目录注入
- 多语言文案骨架

## 本次不要做

- 不提前实现真实 Agent prompt 流程
- 不提前实现 Extension 决策引擎

## 交付检查

- 首次启动进入 onboarding
- 关键状态可展示
- 三语界面骨架可运行

## 执行裁决规则

- 任意非原生 macOS 风格实现都不应进入本阶段结果
- 本地化如果只做单语，不算完成
