# Aegis Plan Index

原来的单文件规划已经拆分为结构化存储，分成“通用部分”“Phase 规划”“Phase 执行包”三层，避免在一个文件里同时维护长期约束和逐步执行内容。

## 入口文件

- 通用约束总文档：`plan/common.md`
- 执行流程说明：`plan/workflow.md`
- 结构化清单：`plan/manifest.yaml`
- 连续执行交接：`plan/handoff.md`
- 分阶段规划：`plan/phases/`
- 分阶段执行包：`plan/execution/`

## 执行规则

每次执行任一 Phase，都必须同时携带三部分上下文：

1. 完整通用部分：`plan/common.md`
2. 当前 Phase 的专属文档：`plan/phases/<phase-file>.md`
3. 当前 Phase 的执行包：`plan/execution/<phase-file>.md`

为避免遗漏，仓库同时提供了 `plan/execution/` 下的执行包文档。执行包不是新的约束来源，而是对“本次执行必须带哪些上下文、只做什么、完成到什么程度”的显式封装。

## 流程化执行

这套规划现在不再只靠人工自觉遵守，而是通过 manifest + resolver + state + handoff 四件套进入执行流程：

1. 如果要连续执行全部规划，先运行 `ruby scripts/planctl next --format prompt --strict`
2. 只读取当前返回的 `required_context`，不要一次性加载全部 phase 文档
3. 若依赖未满足或上下文文件缺失，则停止实施并先处理 blocker
4. Phase 完成后运行 `ruby scripts/planctl complete <phase-id> --summary "<summary>" --next-focus "<next-focus>"`
5. 运行 `ruby scripts/planctl handoff --write` 更新 `plan/handoff.md`
6. 若 AI 发生压缩或会话中断，恢复时先读 `plan/manifest.yaml` 与 `plan/handoff.md`，再重新运行 `ruby scripts/planctl next --format prompt --strict`

如果要显式处理某个已知 Phase，仍可运行 `ruby scripts/planctl resolve <phase-id> --format prompt --strict`。

仓库级 AI 指令定义在 `.github/copilot-instructions.md`，它要求 Copilot 在处理 phase 相关任务时先走这条解析流程，并在长流程执行中使用 handoff 控制上下文体积。

## Phase 导航

- Phase 0：`plan/phases/phase-0-bootstrap.md`
- Phase 1：`plan/phases/phase-1-shared-domain.md`
- Phase 2：`plan/phases/phase-2-onboarding-app-shell.md`
- Phase 3：`plan/phases/phase-3-agent-ipc.md`
- Phase 4：`plan/phases/phase-4-extension-decision-engine.md`
- Phase 5：`plan/phases/phase-5-settings-local-config.md`
- Phase 6：`plan/phases/phase-6-release-pipeline.md`
- Phase 7：`plan/phases/phase-7-privileged-smoke-release-readiness.md`

## 推荐使用方式

如果只是了解产品边界，先读：

1. `plan/common.md`
2. `plan/workflow.md`
3. `plan/manifest.yaml`

如果要连续执行全部 Phase，按以下顺序开始：

1. `plan/manifest.yaml`
2. `plan/handoff.md`
3. `ruby scripts/planctl next --format prompt --strict`

如果要执行某个 Phase，按以下顺序读取：

1. `plan/common.md`
2. 对应的 `plan/phases/*.md`
3. 对应的 `plan/execution/*.md`

## 压缩控制

- 不要把 `plan/phases/` 和 `plan/execution/` 全量塞进同一个上下文
- 长流程时始终只带：`plan/common.md` + 当前 phase plan + 当前 phase execution + `plan/handoff.md`
- 每完成一个 phase 就写入 summary 并刷新 handoff，供压缩后恢复

## 维护原则

- 长期稳定约束只改 `plan/common.md`
- Phase 范围和阶段目标只改 `plan/phases/`
- 执行时的交付、边界和必带上下文只改 `plan/execution/`
- 连续执行与压缩恢复规则只改 `scripts/planctl`、`plan/handoff.md` 和 `.github/copilot-instructions.md`
- 新增或调整 Phase 时，同步更新 `plan/manifest.yaml`
