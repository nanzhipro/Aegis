# Phase 4: Extension 决策引擎

## 阶段定位

这个阶段落地真正的保护链路，让 `AegisExtension` 能基于 `AUTH_OPEN`、trusted process policy、remembered decision cache 和 Agent 交互完成最终 allow/deny 决策。

## 必带上下文

- `plan/common.md`
- Phase 3 已完成

## 阶段目标

- 实现 `AUTH_OPEN` 单事件处理
- 实现 trusted process policy
- 实现 Apple-signed 默认放行
- 实现 remembered decision cache
- 实现 prompt + timeout fallback

## 实施范围

- 仅处理 `ES_EVENT_TYPE_AUTH_OPEN`
- 接入路径匹配、trusted process policy 和 remembered decision cache
- 对需要人工确认的请求调用 Agent
- 在 deadline 内执行 allow/deny，并处理超时、Agent 不可达和无效响应回退

## 本阶段产出

- `AegisExtension` 的决策引擎主链路
- trusted process policy 的明确实现
- remembered decision 命中与回退策略
- 围绕请求生命周期的日志和测试覆盖

## 明确不做

- 不扩展到 `WRITE`、`CREATE`、`RENAME`、`UNLINK` 等其他 AUTH 事件
- 不在此阶段实现完整配置 UI

## 完成判定

- `AUTH_OPEN` 决策路径可稳定跑通
- Apple-signed 默认放行和 remembered decision 命中行为可验证
- 超时、Agent 不可达、无效响应都能回退到本地默认策略

## 依赖关系

- 依赖 Phase 3
