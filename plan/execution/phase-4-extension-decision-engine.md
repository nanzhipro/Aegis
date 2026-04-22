# Phase 4 执行包

本文件不能单独使用。执行 Phase 4 时，必须同时携带完整的 `plan/common.md` 和 `plan/phases/phase-4-extension-decision-engine.md`。

## 必带上下文

- `plan/common.md`
- `plan/phases/phase-4-extension-decision-engine.md`

## 执行目标

- 只实现 `AUTH_OPEN` 决策链
- 接入 trusted process policy、remembered decision cache 和 Agent prompt
- 在 deadline 内给出 allow/deny

## 本次允许改动

- `AegisExtension` 事件处理主链路
- 路径匹配与 trusted process policy
- remembered decision 命中逻辑
- 超时与异常回退逻辑

## 本次不要做

- 不扩展到其他 AUTH 事件
- 不在这里扩展完整设置管理 UI

## 交付检查

- `AUTH_OPEN` 主链路可稳定跑通
- Apple-signed 默认放行可验证
- 超时和 Agent 不可达都有明确 fallback
- `AegisExtension` 中存在 `import EndpointSecurity`，在 bootstrap 阶段调用 `es_new_client`/`es_subscribe`/`es_respond_auth_result`
- `EndpointSecurityClient` 协议（Sendable）及其真实实现、fake 实现均在仓库中存在，单元测试通过 fake 客户端覆盖 allow / deny / timeout / Apple-signed 直通 / remembered 命中五条路径
- `ES_NEW_CLIENT_RESULT_ERR_*` 四类错误映射表在代码与日志中均能落地，并通过 IPC 上报到 `IPCStatusSnapshot.extensionService`
- Extension 未成功订阅 `AUTH_OPEN` 时不得向 App / Agent 声明 ready

## 执行裁决规则

- 如果实现依赖私有 API，直接判定无效
- 如果引入超出 `AUTH_OPEN` 的范围漂移，直接回退到规划边界
