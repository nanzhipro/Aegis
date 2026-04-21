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

## 执行裁决规则

- 如果实现依赖私有 API，直接判定无效
- 如果引入超出 `AUTH_OPEN` 的范围漂移，直接回退到规划边界
