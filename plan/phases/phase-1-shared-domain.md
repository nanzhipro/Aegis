# Phase 1: Shared Domain 与 TDD 底座

## 阶段定位

这个阶段先实现 `AegisShared`，把模型、路径规则、策略存储和 remembered decision 的基础能力沉淀成唯一真相来源，再用测试固定行为边界。

## 必带上下文

- `plan/common.md`
- Phase 0 已完成

## 阶段目标

- 先实现 `AegisShared`
- 建立模型、路径工具、策略存储
- 建立 remembered decision rule 存储
- 建立本地化资源结构
- 建立跨进程 IPC 协议与 DTO 契约
- 所有能力先用单元测试驱动

## 实施范围

- 落地 `ProtectedWorkspace`、`PolicySettings`、`ProcessIdentityFingerprint` 等共享模型
- 落地路径标准化、目录命中和本地策略编解码
- 固化 remembered decision cache 的命中粒度与持久化结构
- 为 `en`、`zh-Hans`、`ja` 建立本地化资源骨架
- 在 `AegisShared/IPC/` 声明三条 `@objc` XPC 协议（`AegisExtensionControlProtocol` / `AegisAppObserverProtocol` / `AegisAgentPromptProtocol`），作为后续阶段唯一的跨进程合约来源
- 所有跨进程 DTO（`AccessPromptRequest` / `AccessPromptDecision` / `IPCStatusSnapshot` / `LocalPolicyStore` 等）实现 `NSSecureCoding`，并提供 `NSXPCInterface.setClasses` 注册的统一入口

## 本阶段产出

- `AegisShared` 模型与持久化能力
- 路径规则和策略规则的测试用例
- 默认策略与默认目录的生成逻辑
- 可复用的共享协议与基础测试夹具
- `AegisShared/IPC/` 中稳定的三条 XPC 协议与 DTO `NSSecureCoding` 往返测试

## 明确不做

- 不实现 onboarding UI
- 不实现 Agent 提示窗
- 不实现 Endpoint Security 事件订阅
- 不在本阶段建立真实 Mach service 监听器（留给 Phase 3）

## 完成判定

- `AegisShared` 相关单元测试全部通过
- 共享模型可以支撑后续 App、Agent、Extension 同步使用
- remembered decision 与路径匹配规则已经通过测试固化
- 三条 XPC 协议与所有跨进程 DTO 的 `NSSecureCoding` 往返、`NSXPCInterface.setClasses` 注册完备性均在 `AegisSharedTests` 中有对应测试

## 依赖关系

- 依赖 Phase 0
