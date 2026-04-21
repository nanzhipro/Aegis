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

## 实施范围

- 落地 `AegisAgent` 的登录项注册与可达性检查
- 落地 `AccessPromptRequest` / `AccessPromptDecision` 的传输与错误映射
- 建立 App、Agent、Extension 之间的状态查询与策略重载能力
- 实现 prompt 请求排队、展示与 rememberChoice 回传

## 本阶段产出

- 可启动的 Login Item Agent
- 可被后续 Extension 调用的 prompt 服务
- 可测试的 IPC 合约与状态接口
- Agent 与主 App 之间的最小联通链路

## 明确不做

- 不在此阶段完成 AUTH_OPEN 决策引擎
- 不实现完整设置页与 remembered decision 管理界面

## 完成判定

- Agent 可由宿主 App 注册并检查状态
- IPC 合约测试能够覆盖请求、响应、超时与错误映射
- rememberChoice 信息能从 prompt 交互正确回传

## 依赖关系

- 依赖 Phase 2
