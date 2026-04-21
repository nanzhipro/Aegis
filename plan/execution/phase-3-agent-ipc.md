# Phase 3 执行包

本文件不能单独使用。执行 Phase 3 时，必须同时携带完整的 `plan/common.md` 和 `plan/phases/phase-3-agent-ipc.md`。

## 必带上下文

- `plan/common.md`
- `plan/phases/phase-3-agent-ipc.md`

## 执行目标

- 建立 `AegisAgent` Login Item
- 打通 prompt 服务与 IPC 合约
- 打通 App / Agent / Extension 的最小通信链路

## 本次允许改动

- Agent 登录项与可达性检查
- Prompt 请求与响应协议
- 状态查询与策略重载接口
- rememberChoice 回传链路

## 本次不要做

- 不在这里扩展为完整决策引擎
- 不把设置页和配置管理全部塞进当前阶段

## 交付检查

- Agent 可以注册、检测和交互
- IPC 契约可测试
- rememberChoice 可以回传到共享层

## 执行裁决规则

- 若通信契约不稳定，禁止进入 Phase 4
- 若状态接口和错误映射不明确，视为未完成
