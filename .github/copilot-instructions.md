# Aegis Phase 执行规约

当用户请求涉及 phase、计划执行、实施步骤、持续推进、恢复执行，或要求你遵循本仓库的规划体系开展工作时，本规约生效。生效后，必须把 `plan/manifest.yaml` 视为执行契约，而不是参考性文档。

## 一、规约定位

- 本文件用于约束 AI 在 Aegis 仓库中的 phase 执行行为。
- `plan/workflow.md` 负责解释流程；本文件负责规定行为。
- `scripts/planctl`、`plan/state.yaml`、`plan/handoff.md` 共同构成当前工程的实际执行机制；本文件必须与它们保持一致。

## 二、解释优先级

当不同文档提供的信息存在交叉时，按以下顺序解释和执行：

1. 当前应执行哪个 phase，以 `plan/manifest.yaml`、`plan/state.yaml` 和 `scripts/planctl` 的结果为准。
2. 全局长期约束，以 `plan/common.md` 为准。
3. 当前 phase 的实施边界、交付合同和完成检查，以对应的 `plan/execution/*.md` 为准。
4. 当前 phase 的阶段定位、目标与范围，以对应的 `plan/phases/*.md` 为准。
5. 压缩恢复和续跑锚点，以 `plan/handoff.md` 为准。
6. `plan/workflow.md` 仅用于说明，不得覆盖上述规则。

## 三、开始实施前的强制步骤

1. 先读取 `plan/manifest.yaml`，确认 phase 顺序、依赖关系、required_context、连续执行规则和压缩恢复规则。
2. 识别当前任务属于哪一种模式：
   - 连续推进全部计划或继续推进剩余 phase。
   - 明确指定某个已知 phase。
   - 讨论规划体系本身，而不是实施某个业务 phase。
3. 如果是连续推进全部计划、持续推进剩余 phase，或用户表达出“一口气做完/继续往下做”的意图，必须先读取 `plan/handoff.md`，再运行 `ruby scripts/planctl next --format prompt --strict`。
4. 如果用户明确指定某个已知 phase，必须运行 `ruby scripts/planctl resolve <phase-id> --format prompt --strict`。
5. 如果用户讨论的是规划体系本身，而不是某个业务 phase 的实施，也必须先从 `plan/manifest.yaml` 出发，再确保表述与 `plan/workflow.md` 和 `scripts/planctl` 的实际行为一致。

## 四、当前 Phase 的确定规则

1. 当前应执行哪个 phase，不得靠主观判断决定。
2. 连续执行时，`planctl next` 返回的结果，是唯一合法的当前 phase。
3. 指定 phase 时，`planctl resolve` 返回的结果，是唯一合法的当前 phase。
4. 不得跳过 `depends_on` 检查，也不得手工判定“前置 phase 基本完成”。
5. 只要 strict 模式失败，就视为当前 phase 尚不具备实施条件。

## 五、上下文装载规约

1. 必须严格按 resolver 返回的 `required_context` 顺序读取上下文，不得调换顺序，也不得跳读。
2. `plan/common.md` 是所有 phase 的强制上下文，不得省略。
3. 当当前 phase 存在 execution 文档时，不得只读 `plan/phases/*.md` 就开始实施。
4. resolver 已经给出当前 `required_context` 时，不要擅自扩读其他 phase 的 plan 或 execution 文档，以免把未来阶段内容混入当前实施边界。
5. 长流程执行时，不得一次性把全部 `plan/phases/` 和 `plan/execution/` 文档装入同一个上下文窗口。
6. 长流程中允许保留的核心上下文，默认仅限于：
   - `plan/common.md`
   - 当前 phase 的 `plan/phases/*.md`
   - 当前 phase 的 `plan/execution/*.md`
   - `plan/handoff.md`

## 六、实施边界规约

1. 当前 phase 对应的 `plan/execution/*.md` 是本次实施的范围边界、交付合同和完成检查表。
2. 如果 execution 文档与泛化理解冲突，以 execution 文档为准。
3. 业务 phase 的实施过程中，默认不要修改下列流程基础设施文件：
   - `plan/manifest.yaml`
   - `plan/workflow.md`
   - `.github/copilot-instructions.md`
   - `scripts/planctl`
   - `plan/state.yaml`
   - `plan/handoff.md`
4. 只有当任务本身就是修改规划体系或流程基础设施时，才允许修改上述文件。

## 七、中止条件

出现以下任一情况时，必须停止实施并先报告 blocker，不得继续编辑文件：

1. resolver 报告依赖未满足。
2. resolver 报告上下文文件缺失。
3. strict 模式失败。
4. 当前工作树中存在与当前 phase 契约直接冲突、且无法在不破坏用户已有修改的前提下兼容的变更。
5. 用户请求与当前 manifest 定义的 phase 顺序、边界或完成规则直接冲突，而规划体系本身尚未被更新。

## 八、完成与推进规约

1. 只有在当前 phase 真实完成后，才能运行 `ruby scripts/planctl complete <phase-id> --summary "<summary>" --next-focus "<next-focus>"` 写回执行状态。
2. “真实完成”至少意味着：
   - 当前 phase 的 execution 文档中的交付检查已经满足。
   - 当前 phase 的阶段目标已经达到。
   - 当前 phase 没有违反禁止项和裁决规则。
3. 未写入 `plan/state.yaml` 的 phase，不视为完成。
4. 连续执行多个 phase 时，每完成一个 phase，都要运行 `ruby scripts/planctl handoff --write` 刷新 `plan/handoff.md`，然后再进入下一 phase。
5. 不得在未运行 `complete` 的情况下，直接开始后续 phase。

## 九、压缩恢复规约

1. 如果发生上下文压缩或进入新会话，恢复顺序固定为：
   - 先读 `plan/manifest.yaml`
   - 再读 `plan/handoff.md`
   - 然后运行 `ruby scripts/planctl next --format prompt --strict`
2. 恢复后只进入当前应执行的 phase，不得自行回到更早或跳到更晚的 phase。
3. 恢复后只读取 `next` 返回的当前 `required_context`，不要重新全量装载全部 phase 文档。

## 十、禁止行为

- 不得在 resolver 或 next 完成之前，开始任何与 phase 实施相关的代码或文档编辑。
- 不得绕过 `planctl` 手工选择当前 phase。
- 不得跳过 `depends_on` 检查。
- 不得把未来 phase 的目标、交付或代码实现提前混入当前 phase。
- 不得一次性加载全部 phase 文档，导致当前上下文被未来阶段信息污染。
- 不得手工编辑 `plan/state.yaml` 和 `plan/handoff.md` 来伪造进度或恢复状态，除非任务本身就是维护流程基础设施。
- 不得在未满足当前 phase 完成条件时宣告完成。

## 十一、流程基础设施维护例外

当任务本身就是修改规划体系、执行流程或其基础设施时，可以修改：

- `plan/manifest.yaml`
- `plan/workflow.md`
- `.github/copilot-instructions.md`
- `scripts/planctl`
- `plan/state.yaml`
- `plan/handoff.md`

但此时必须同时满足以下要求：

1. 修改后的规则、文档和脚本行为保持一致。
2. 如涉及 `scripts/planctl`，必须验证命令行为与文档描述一致。
3. 如涉及文档入口或恢复规则，必须同步更新相关入口文档。
4. 不得只改说明文字而不改实际流程，也不得只改脚本而不改说明文字。
