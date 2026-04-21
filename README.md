# Aegis

Aegis 是一个面向 `macOS 15.0+` 的全新原生安全产品规划仓库，目标是在完全本地化、零第三方依赖的前提下，基于 Apple 官方 `EndpointSecurity` 能力实现受保护目录访问确认。

## 核心原则

- 全新构建，不继承旧原型兼容包袱
- 完全遵循 macOS 原生设计和系统能力边界
- 运行时完全本地化，不依赖云端服务
- 从第一天起纳入 TDD、测试、签名、公证、发布和 GitHub CI
- 首发支持英文、简体中文、日文

## 文档入口

- 总规划索引：`Plan.md`
- 通用约束：`plan/common.md`
- 执行说明：`plan/workflow.md`
- 结构化清单：`plan/manifest.yaml`
- 连续执行交接：`plan/handoff.md`
- 流程控制：`scripts/planctl` + `plan/state.yaml`
- 分阶段规划：`plan/phases/`
- 分阶段执行包：`plan/execution/`

README 只保留高层概览，具体约束、阶段计划和执行说明都沉淀在上述规划文档中。
