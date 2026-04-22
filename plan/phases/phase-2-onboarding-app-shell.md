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
- AegisApp 以 `LSUIElement=YES` 作为菜单栏常驻应用，无 Dock 图标
- `MenuBarExtra` 入口使用 SF Symbol（`shield.lefthalf.filled`，`symbolRenderingMode(.hierarchical)`），禁止自定义位图
- Onboarding / 状态概览窗口与设置窗口必须分别声明为独立的 SwiftUI scene：Onboarding 窗口用 `Window(id:)` / `WindowGroup`，设置窗口仅由 `Settings { ... }` + `SettingsLink` 唤起；两窗不共享导航栈和生命周期
- 首次启动默认打开 Onboarding 窗口而非设置窗口；非首次启动时，Onboarding 窗口可被菜单项随时主动唤起
- 菜单下拉固定四项并全部本地化：Open Onboarding（打开新手引导 / 主窗口）/ Install（或 Reinstall）System Extension / Open Settings（`SettingsLink`，唯一打开设置窗口的入口）/ Quit Aegis
- Onboarding 的 Install Protection 步骤与菜单的安装入口均须真实调用 `OSSystemExtensionManager.shared.submitRequest(.activationRequest)`，并把 `requesting` / `awaitingUserApproval` / `willCompleteAfterReboot` / `activated` / `failed` 五种状态反映到 UI
- 新增 `systemExtensionInstallActionKey`、`openOnboardingActionKey` 等菜单相关本地化键，覆盖 en / zh-Hans / ja 三语

## 明确不做

- 不实现 Agent 的实际确认弹窗
- 不实现 Extension 的最终 allow/deny 决策链
- 不在此阶段实现发布链路

## 完成判定

- 首次启动默认进入 onboarding（打开独立的 Onboarding 窗口而非 Settings 窗口）
- readiness 聚合逻辑可在主界面展示
- `en`、`zh-Hans`、`ja` 下关键界面可正常渲染
- App 壳层已为后续 Agent / Extension 集成预留稳定入口
- Onboarding 窗口和 Settings 窗口在 SwiftUI scene 层面互相独立，且没有共用 view hierarchy
- 菜单上的 Open Onboarding 项在非首次启动状态下仍能唤起独立的 Onboarding 窗口

## 依赖关系

- 依赖 Phase 1
