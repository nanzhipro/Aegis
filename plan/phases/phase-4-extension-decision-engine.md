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
- 接入真实 EndpointSecurity 客户端（`es_new_client` / `es_subscribe([ES_EVENT_TYPE_AUTH_OPEN], 1)` / `es_respond_auth_result`）

## 实施范围

- 仅处理 `ES_EVENT_TYPE_AUTH_OPEN`
- 接入路径匹配、trusted process policy 和 remembered decision cache
- 对需要人工确认的请求调用 Agent
- 在 deadline 内执行 allow/deny，并处理超时、Agent 不可达和无效响应回退
- 抽象 `EndpointSecurityClient` 协议（Sendable），生产实现绑定真实 `es_*` 调用，单元测试使用 fake 客户端注入 `AUTH_OPEN` 事件
- 对 `ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED` / `_NOT_PRIVILEGED` / `_NOT_PERMITTED` / `_INVALID_ARGUMENT` 做显式错误映射并上报到 `IPCStatusSnapshot.extensionService`

## 本阶段产出

- `AegisExtension` 的决策引擎主链路
- trusted process policy 的明确实现
- remembered decision 命中与回退策略
- 围绕请求生命周期的日志和测试覆盖
- 真实 ES 客户端封装与 fake 实现两套，单元测试覆盖 allow / deny / timeout 三条路径

## 明确不做

- 不扩展到 `WRITE`、`CREATE`、`RENAME`、`UNLINK` 等其他 AUTH 事件
- 不在此阶段实现完整配置 UI

## 完成判定

- `AUTH_OPEN` 决策路径可稳定跑通
- Apple-signed 默认放行和 remembered decision 命中行为可验证
- 超时、Agent 不可达、无效响应都能回退到本地默认策略
- Extension 启动时成功调用 `es_new_client` 与 `es_subscribe`，并在订阅成功前不声明 `extensionService.state = .ready`
- 所有 `es_respond_auth_result` 调用固定使用 `cache: false`，并保证在 ES kernel deadline 前完成响应

## 依赖关系

- 依赖 Phase 3
