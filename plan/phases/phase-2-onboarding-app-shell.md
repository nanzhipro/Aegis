# Phase 2: Onboarding 与原生 App 外壳

## 阶段定位

这个阶段只解决宿主 App 的原生外壳和首次启动路径，让用户进入产品时先看到正确的 onboarding、readiness 信息和多语言骨架，而不是先追求完整保护链路。

## 必带上下文

- `plan/common.md`
- Phase 1 已完成

## 阶段目标

- 完成首次启动引导
- 完成 readiness 状态聚合
- 完成默认目录注入
- 完成三语本地化骨架

## 实施范围

- 落地 onboarding step flow 与状态机
- 实现宿主 App 的原生设置式外壳
- 接入默认策略和默认目录展示
- 打通 `en`、`zh-Hans`、`ja` 的基础文案结构

## 本阶段产出

- 首次启动进入 onboarding 的宿主 App 壳层
- `System Extension`、`Login Item`、`Policy`、`Protection Readiness` 的状态展示骨架
- 默认受保护目录注入与展示逻辑
- 三语本地化资源骨架与关键文案

## 明确不做

- 不实现 Agent 的实际确认弹窗
- 不实现 Extension 的最终 allow/deny 决策链
- 不在此阶段实现发布链路

## 完成判定

- 首次启动默认进入 onboarding
- readiness 聚合逻辑可在主界面展示
- `en`、`zh-Hans`、`ja` 下关键界面可正常渲染
- App 壳层已为后续 Agent / Extension 集成预留稳定入口

## 依赖关系

- 依赖 Phase 1
