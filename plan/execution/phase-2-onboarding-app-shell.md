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

- 首次启动进入 onboarding（具体表现为自动打开独立的 Onboarding 窗口，而不是 Settings 窗口）
- 关键状态可展示
- 三语界面骨架可运行
- `plutil -p build/Debug/AegisApp.app/Contents/Info.plist` 显示 `LSUIElement => 1`，运行时无 Dock 图标
- 菜单栏 `MenuBarExtra` 出现 SF Symbol 图标并能展开四项固定菜单（Open Onboarding / Install（或 Reinstall）System Extension / Open Settings / Quit Aegis）
- Onboarding 窗口与 Settings 窗口在 SwiftUI 代码中被声明为两个互相独立的 scene：Onboarding 使用 `Window(id:)` 或 `WindowGroup`，设置使用 `Settings { ... }`，`SettingsLink` 是唯一唤起设置窗口的方式
- 非首次启动时点击菜单项“Open Onboarding”仍能唤起 Onboarding 窗口（UI 测试或手工验证皆可）
- 「Install System Extension」菜单项与 onboarding 的 Install Protection 步骤点击后能触发 `OSSystemExtensionManager.submitRequest`，且 UI 能反映 requesting / awaitingUserApproval / willCompleteAfterReboot / activated / failed 五种状态
- `Localizable.xcstrings` 中存在 `aegis.menu.open_onboarding`、`aegis.menu.install_extension`、`aegis.menu.install_extension.pending`、`aegis.menu.install_extension.reboot`、`aegis.menu.reinstall_extension` 等键且覆盖 en / zh-Hans / ja

## 执行裁决规则

- 任意非原生 macOS 风格实现都不应进入本阶段结果
- 本地化如果只做单语，不算完成
