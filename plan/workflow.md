# Aegis 执行流程说明

本文件说明 Aegis 是如何确保全部任务按既定顺序、完整执行的，以及在 AI 上下文压缩后如何继续执行。

## 目标

这套流程要解决四个问题：

- 如何开始执行全部 plan
- 如何保证 phase 顺序不能被跳过
- 如何保证每个 phase 真正完成后才进入下一个 phase
- 如何在 AI 压缩或新会话后继续执行，而不是从头手工判断

## 核心角色

### `plan/manifest.yaml`

这是唯一的流程定义来源，负责声明：

- phase 顺序
- depends_on 依赖关系
- 每个 phase 的 `plan_file`
- 每个 phase 的 `execution_file`
- 每次执行必须读取的 `required_context`
- 连续执行和压缩恢复规则

顺序和边界都以它为准，不以聊天历史或人工记忆为准。

### `plan/common.md`

这是全局硬约束。任何 phase 执行都必须带上它，用来保证长期约束不会在局部执行时丢失。

### `plan/phases/*.md`

这是阶段蓝图，定义每个 phase 的：

- 阶段定位
- 阶段目标
- 实施范围
- 本阶段产出
- 明确不做
- 完成判定

它负责说明“这个阶段是什么”和“做到什么程度”。

### `plan/execution/*.md`

这是执行合同，定义一次实际执行时的：

- 必带上下文
- 本次允许改动
- 本次不要做
- 交付检查
- 执行裁决规则

它负责限制这次执行能改什么、不能改什么，以及如何判断当前 phase 是否真的完成。

### `scripts/planctl`

这是唯一的流程入口，负责把 manifest 中的定义转成可执行流程。主要命令有：

- `resolve`: 解析指定 phase 的上下文和依赖
- `next`: 找到当前应该执行的下一个 phase
- `status`: 展示已完成、可执行、被阻塞的 phase
- `complete`: 在 phase 真完成后把状态写回 `plan/state.yaml`
- `handoff`: 生成或刷新 `plan/handoff.md`

### `plan/state.yaml`

这是执行账本，记录：

- 哪些 phase 已完成
- 完成顺序
- 每次完成的摘要、下一步焦点和时间戳

后续 phase 是否可执行，最终以它为准。

### `plan/handoff.md`

这是压缩恢复锚点，记录：

- 当前状态
- 最近完成摘要
- 下一 phase
- 下一步要读的上下文
- 压缩后的恢复顺序

它的作用是避免 AI 在压缩后重新加载全部 phase 文档。

### `.github/copilot-instructions.md`

这是仓库级 AI 工作流约束，保证 AI 在 phase 相关任务里：

- 必须先读 manifest
- 必须走 `planctl`
- 不能跳过依赖检查
- 不能一次性加载全部 phase 文档
- 压缩或新会话后要从 handoff 恢复

## 如何确保顺序执行

顺序不是靠人工记忆，而是靠以下机制共同保证：

1. `plan/manifest.yaml` 明确写出 phase 的顺序和 `depends_on`
2. `planctl next` 只返回按 manifest 顺序找到的第一个未完成 phase
3. `planctl resolve --strict` 和 `planctl next --strict` 会校验依赖是否满足
4. 未完成前置 phase 时，后续 phase 会被标记为 blocked，不允许继续执行

因此，这套流程天然防止跳 phase 和乱序执行。

## 如何确保完整执行

完整执行不是“做了一部分就继续”，而是必须满足以下条件：

1. 当前 phase 执行前，必须读取完整 `required_context`
2. 必须同时携带：
   - `plan/common.md`
   - 当前 phase 文档
   - 当前 execution 文档
3. 实施时必须服从 execution 文档中的允许改动、禁止项和交付检查
4. phase 只有在真正完成后，才能运行 `planctl complete`
5. 未写入 `plan/state.yaml` 的 phase，不视为完成

因此，进入下一 phase 的前提不是“感觉差不多了”，而是“状态文件已经明确记录完成”。

## 如何开始执行全部计划

如果目标是连续执行全部 plan，标准起点如下：

1. 读取 `plan/manifest.yaml`
2. 读取 `plan/handoff.md`
3. 运行 `ruby scripts/planctl next --format prompt --strict`
4. 按输出结果读取当前 phase 的 `required_context`
5. 开始实施当前 phase

开始时不要一次性加载全部 `plan/phases/` 和 `plan/execution/`，只加载当前 phase 所需上下文。

## 连续执行的标准循环

在长流程里，每个 phase 都遵循同一个循环：

1. 运行 `next`
2. 读取当前 phase 的 `required_context`
3. 按当前 execution 文档实施
4. phase 真完成后运行 `complete`
5. 刷新 `handoff`
6. 再次运行 `next`

对应命令如下：

```bash
ruby scripts/planctl next --format prompt --strict
ruby scripts/planctl complete <phase-id> --summary "<summary>" --next-focus "<next-focus>"
ruby scripts/planctl handoff --write
```

这样每完成一个 phase，状态、摘要和恢复锚点都会同步更新。

## 如何结束单个 Phase

单个 phase 的结束条件是：

- 当前 phase 的 execution 文档中交付检查已经满足
- 当前 phase 的阶段目标已经达到
- 当前 phase 没有违反禁止项和裁决规则

然后运行：

```bash
ruby scripts/planctl complete <phase-id> --summary "<summary>" --next-focus "<next-focus>"
```

此时会发生三件事：

- `plan/state.yaml` 记录该 phase 已完成
- completion log 记录摘要和下一步焦点
- 下一次 `next` 会进入后续 phase

## 如何结束全部计划

当全部 phase 都完成后，再运行：

```bash
ruby scripts/planctl next --format prompt --strict
```

如果没有剩余 phase，脚本会返回全部完成的结果。此时：

- `plan/state.yaml` 中应包含全部 phase
- `plan/handoff.md` 中不再有下一 phase
- `planctl status` 会显示没有 remaining queue

这才算整个计划真正结束。

## 如何在压缩或新会话后继续执行

AI 会遇到上下文窗口限制，所以恢复流程不能依赖聊天记忆，必须依赖仓库内持久文件。

标准恢复顺序如下：

1. 读取 `plan/manifest.yaml`
2. 读取 `plan/handoff.md`
3. 运行 `ruby scripts/planctl next --format prompt --strict`
4. 按输出结果读取当前 phase 的 `required_context`
5. 继续执行

恢复时不要重新全量加载全部 phase 文档；只读取：

- `plan/manifest.yaml`
- `plan/handoff.md`
- 当前 `next` 返回的 `required_context`

## 压缩控制原则

为了避免上下文窗口被历史内容占满，执行时必须遵守以下原则：

- 永远不要一次性加载全部 phase 文档
- 长流程时只保留：`plan/common.md` + 当前 phase plan + 当前 phase execution + `plan/handoff.md`
- 每完成一个 phase 后，立即刷新 `plan/handoff.md`
- 压缩后优先从 handoff 恢复，而不是重放整段历史聊天

## 推荐命令清单

查看当前整体状态：

```bash
ruby scripts/planctl status --format json
```

解析指定 phase：

```bash
ruby scripts/planctl resolve <phase-id> --format prompt --strict
```

连续执行下一个 phase：

```bash
ruby scripts/planctl next --format prompt --strict
```

标记当前 phase 完成：

```bash
ruby scripts/planctl complete <phase-id> --summary "<summary>" --next-focus "<next-focus>"
```

刷新交接文件：

```bash
ruby scripts/planctl handoff --write
```

## 一句话总结

这套流程通过 manifest 定义顺序，通过 planctl 推进状态，通过 state 记录完成事实，通过 handoff 处理压缩恢复，从而保证全部任务能按既定顺序、完整执行，并且可以在长流程中稳定续跑。
