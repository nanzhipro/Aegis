# Phase 5: 设置页与本地配置

## 阶段定位

这个阶段把已经具备的保护链路暴露成用户可操作的原生设置界面，并补齐策略热重载、remembered decision 清理和最小诊断能力。

## 必带上下文

- `plan/common.md`
- Phase 4 已完成

## 阶段目标

- 完成目录管理
- 完成默认行为设置
- 完成策略热重载
- 完成 remembered decision 清理入口
- 完成日志与诊断视图最小能力

## 实施范围

- 落地 `Protected Folders`、`Remembered Decisions`、`Default Behavior` 等设置区块
- 支持添加、删除、启停受保护目录
- 支持切换超时默认行为并写回本地策略
- 提供最小的 remembered decision 清理入口
- 补齐最小诊断/状态展示，便于排查本地运行状态

## 本阶段产出

- 可用的原生设置页
- 本地策略写入与热重载链路
- remembered decision 清理入口
- 反映当前运行状态的最小诊断能力

## 明确不做

- 不在此阶段实现签名、公证和 CI 发布自动化
- 不扩展为云端或多端配置管理

## 完成判定

- 用户能通过设置页完成目录和默认策略管理
- 策略变更能被 App、Agent、Extension 一致感知
- remembered decision 至少支持全量清理

## 依赖关系

- 依赖 Phase 4
