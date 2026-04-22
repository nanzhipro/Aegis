# Phase 3: Agent 与 IPC

## 阶段定位

这个阶段补齐用户会话内的确认能力，把 `AegisAgent`、IPC 合约和 App/Agent/Extension 状态通信先打通，为后续决策引擎接入真实事件流做准备。

## 必带上下文

- `plan/common.md`
- Phase 2 已完成

## 阶段目标

- 完成 Login Item
- 完成 prompt 服务
- 完成 App / Agent / Extension 状态通信
- 完成 rememberChoice 交互回传
- 在 `AegisExtension` 内建立基于 `NSXPCListener` 的 Mach service 监听，同时承载 App ↔ Extension 与 Agent ↔ Extension 两条双向 XPC 通道

## 实施范围

- 落地 `AegisAgent` 通过 `SMAppService.agent(plistName:)` 加载 AegisApp 内嵌 LaunchAgent plist 完成登录项注册与可达性检查
- 定义 AegisAgent 的嵌入式部署目录契约：`AegisApp.app/Contents/Library/LoginItems/AegisAgent.app` 与 `AegisApp.app/Contents/Library/LaunchAgents/<agent>.plist`；plist 的 `BundleProgram`（或 `Program`）必须相对指向同一 bundle 内的 Agent 可执行体
- 落地 `AccessPromptRequest` / `AccessPromptDecision` 的传输与错误映射
- 建立 App、Agent、Extension 之间的状态查询与策略重载能力
- 实现 prompt 请求排队、展示与 rememberChoice 回传
- 在 `AegisExtension` 中建立 `NSXPCListener(machServiceName: "<TeamID>.com.nanzhipro.AegisExtension.xpc")`，接受 AegisApp 与 AegisAgent 两类 `NSXPCConnection`；每条连接同时设置 `remoteObjectInterface` 与 `exportedInterface`，支持 Extension 反向回调
- 每条 XPC 连接调用 `setCodeSigningRequirement`（同 Team、同 bundle 前缀），并在 `invalidationHandler` / `interruptionHandler` 中实现自动重连
- 按 `plan/common.md` 的 IPC 章节实现 `AegisExtensionControlProtocol` / `AegisAppObserverProtocol` / `AegisAgentPromptProtocol` 的具体端点

## 本阶段产出

- 可启动、通过 `SMAppService.agent(plistName:)` 加载嵌入式 LaunchAgent plist 自动注册的 AegisAgent，Agent bundle 嵌入在 `AegisApp.app/Contents/Library/LoginItems/AegisAgent.app`
- Extension 上可用的 Mach service `NSXPCListener`，同时服务 App 与 Agent 两条双向连接
- 实现 prompt 推送、decision 回传、`statusDidChange` 反向通知的 XPC 传输层
- 基于 `NSXPCListener.anonymous` 的 loopback 契约测试，覆盖双向握手、prompt 推送、decision 回传、`statusDidChange`、连接中断自动重连、代码签名校验失败拒绝连接

## 明确不做

- 不在此阶段完成 AUTH_OPEN 决策引擎
- 不实现完整设置页与 remembered decision 管理界面
- 不引入除 Mach service 之外的跨进程传输方式（例如共享容器文件 prompt 队列）

## 完成判定

- Agent 可由宿主 App 通过 `SMAppService.agent(plistName:)` 注册并检查状态；`SMAppService.status` 可上报到 `IPCStatusSnapshot`
- AegisApp 构建产物中存在 `Contents/Library/LoginItems/AegisAgent.app` 与 `Contents/Library/LaunchAgents/<agent>.plist`，且 plist 指向 bundle 内 Agent 可执行体
- IPC 合约测试能够覆盖请求、响应、超时与错误映射
- rememberChoice 信息能从 prompt 交互正确回传
- App ↔ Extension 与 Agent ↔ Extension 两条 XPC 连接均能建立、自动重连，并拒绝非同 Team 对端
- 所有 prompt、状态、决策流均通过 `NSXPCConnection` 传输，不依赖共享容器文件队列

## 依赖关系

- 依赖 Phase 2
