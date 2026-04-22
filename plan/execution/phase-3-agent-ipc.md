# Phase 3 执行包

本文件不能单独使用。执行 Phase 3 时，必须同时携带完整的 `plan/common.md` 和 `plan/phases/phase-3-agent-ipc.md`。

## 必带上下文

- `plan/common.md`
- `plan/phases/phase-3-agent-ipc.md`

## 执行目标

- 建立 `AegisAgent` LaunchAgent（通过 `SMAppService.agent(plistName:)` 加载嵌入在 AegisApp 内的 LaunchAgent plist）
- 打通 prompt 服务与 IPC 合约
- 在 Extension 上建立 `NSXPCListener` Mach service，承载 App ↔ Extension 与 Agent ↔ Extension 两条双向 XPC 通道
- 打通 App / Agent / Extension 基于 XPC 的完整通信链路

## 本次允许改动

- AegisAgent 登录项注册（`SMAppService.agent(plistName:)`）与可达性检查
- AegisApp target 构建时拷贝 `AegisAgent.app` 与 LaunchAgent plist 到指定嵌入目录（`Contents/Library/LoginItems/` 与 `Contents/Library/LaunchAgents/`）
- Extension 侧 `NSXPCListener(machServiceName:)` 监听与连接校验（`setCodeSigningRequirement`）
- AegisApp 与 AegisAgent 侧 `NSXPCConnection` 客户端及 `exportedInterface` 绑定
- Prompt 请求与响应协议在 XPC 上的端到端实现
- 状态查询与策略重载接口（`statusDidChange`、`reloadPolicy`）
- rememberChoice 回传链路

## 本次不要做

- 不在这里扩展为完整决策引擎
- 不把设置页和配置管理全部塞进当前阶段
- 不引入除 Mach service 以外的跨进程传输方式（禁止以共享容器文件做 prompt 队列）

## 交付检查

- Agent 通过 `SMAppService.agent(plistName:)` 加载 AegisApp 内嵌 LaunchAgent plist 完成注册，`SMAppService.status` 能通过 XPC 回传到 `IPCStatusSnapshot.loginItem`
- `AegisAgent.app` 作为 bundle 嵌入在 `AegisApp.app/Contents/Library/LoginItems/AegisAgent.app`，LaunchAgent plist 嵌入在 `AegisApp.app/Contents/Library/LaunchAgents/<agent>.plist` 且 `BundleProgram`/`Program` 相对指向同一 bundle 内的 Agent；不允许将 Agent 作为独立顶级 app 安装或派生 `~/Library/LaunchAgents/` 文件
- `AegisExtension` 监听 `<TeamID>.com.nanzhipro.AegisExtension.xpc`，同时接受 App 与 Agent 两类连接
- 每条 XPC 连接都设置 `setCodeSigningRequirement`，拒绝非同 Team、非同 bundle 前缀的对端；`invalidationHandler` / `interruptionHandler` 触发后可自动重连
- Extension → 客户端的反向通知（`presentPrompt` / `cancelPrompt` / `statusDidChange` / `extensionDidEmitDiagnostic`）通过 `exportedInterface` 成功下发
- rememberChoice 可以回传到共享层并由 `AccessPromptDecision.rememberChoice` 驱动落盘
- 存在基于 `NSXPCListener.anonymous` 的 loopback 契约测试，覆盖：双向握手、Extension 推送 prompt → Agent 回调 `submitDecision`、Extension 推送 `statusDidChange`、连接中断后自动重连、代码签名校验失败导致拒绝连接
- 所有 prompt、状态、决策流均通过 `NSXPCConnection` 传输，不再依赖共享容器文件队列

## 执行裁决规则

- 若通信契约不稳定，禁止进入 Phase 4
- 若状态接口和错误映射不明确，视为未完成
- 若任一条 XPC 连接未设置 `setCodeSigningRequirement`，视为未完成
- 若出现共享容器文件 prompt 队列替代 XPC 的实现，视为未完成
