# Aegis 术语表

本文档汇总 Aegis 规划文档中的关键术语、阶段目标和相关关系，便于快速理解产品主链路、工程链路和发布链路。

如果你想看 phase 为什么必须按当前顺序推进，请同时阅读 [architecture-causality.md](architecture-causality.md)。

## 什么是 Privileged Smoke

在 Aegis 语境里，privileged smoke 指发布前在本地可完整测试的 macOS 14 及以上环境中进行的最小真实冒烟验证，用来确认自动化无法完整覆盖的系统特权链路是否可用。

它同时具备两个特征：

- privileged：涉及 Apple 平台真实权限和系统授权链路，例如 System Extension 安装与用户批准、Full Disk Access 引导、登录会话中的 Agent 原生提示。
- smoke：不是做全面穷举测试，而是优先验证最关键的主链路已经跑通，确保 release 产物具备对外发布的基本可信度。

在 Aegis 中，privileged smoke 主要检查：

- DMG 下载、挂载、安装是否正常。
- App 首次启动是否进入正确 onboarding。
- System Extension 安装与批准链路是否可走通。
- Full Disk Access 是否仅做引导而不尝试静默授权。
- Agent 是否能在登录会话中弹出原生确认。
- Allow、Deny、remember choice、timeout fallback 等关键分支是否成立。

如果这些验证没有在本地完整测试环境中形成真实留痕，即使脚本、公证和签名都通过，也不能认定 phase-7 完成，也不能认定 release ready。

## 全局核心概念

### 产品目标

- 受保护目录：用户配置为需要保护的目录。当进程访问这些目录时，Aegis 需要介入判断。
- 访问确认：当请求既不属于受信进程，也没有命中 remembered decision 时，Aegis 会请求用户做 Allow 或 Deny。
- 本地默认策略：当用户没有及时响应，或 Agent 不可达时，系统按本地配置的默认策略回退执行。

### 模块职责

- AegisApp：宿主应用，负责 onboarding、System Extension 安装与状态检查、Login Item 管理、策略编辑和状态展示。
- AegisAgent：登录会话中的 Login Item，负责接收访问确认请求、展示原生确认窗口并把用户决定回传给 Extension。
- AegisExtension：基于 Endpoint Security 的 System Extension，负责拦截 AUTH_OPEN 请求并给出最终 allow 或 deny。
- AegisShared：共享模块，负责模型、路径标准化、策略持久化、IPC 协议和通用状态枚举。

### Apple 平台约束

- System Extension：运行在系统扩展模型下的扩展，不能像普通 App 插件那样自由加载，必须由宿主 App 触发安装并经用户批准。
- Endpoint Security：Apple 提供的安全事件框架。Aegis v1 只订阅授权型的 AUTH_OPEN 事件。
- AUTH_OPEN：进程试图打开文件或目录时触发的授权事件。Aegis 用它来判断是否放行访问。
- Full Disk Access：完整磁盘访问权限。Aegis 只能引导用户去系统设置中配置，不能静默授权。
- Login Item：用户登录后自动运行的后台项。AegisAgent 依靠它进入正确的用户会话。
- SMAppService：Apple 提供的 Login Item 注册与管理机制。
- unified logging：Apple 官方日志体系，要求对敏感信息做隐私标记并使用 Logger 记录。

### 规划执行概念

- phase：规划中的单个阶段，每个阶段都有自己的目标、边界、交付物和完成标准。
- plan/common.md：全部 phase 的长期稳定约束来源。
- plan/phases：每个阶段的目标、范围、产出和依赖文档。
- plan/execution：每个阶段的执行包，定义当前一次执行允许改什么、不要改什么、怎样算完成。
- manifest：位于 plan/manifest.yaml 的结构化清单，用来定义 phase 顺序、依赖关系和 required_context。
- state：位于 plan/state.yaml 的进度状态文件，记录哪些 phase 已完成。
- handoff：位于 plan/handoff.md 的连续执行交接文件，用于长流程压缩恢复。
- planctl：位于 scripts/planctl 的解析器与状态写回入口，用来解析当前合法 phase 并写回完成状态。
- strict 模式：执行 planctl 时启用的严格检查模式，会校验依赖是否完成、上下文文件是否完整。

## 按 Phase 汇总术语与概念

## Phase 0：新建工程与约束固化

### Phase 0 阶段作用

先把工程骨架和规则固定下来，避免后续功能实现反复返工。

### Phase 0 关键术语

- 原生 .xcodeproj：直接使用 Xcode 原生工程，而不是通过第三方生成器管理工程结构。
- 零第三方依赖：不使用 CocoaPods、Carthage、第三方 Swift Package 或其他非 Apple 官方依赖。
- target 骨架：AegisApp、AegisAgent、AegisExtension、AegisShared 与测试 target 的基础结构。
- entitlements：Apple 平台权限声明文件，用于签名后声明 App、Agent 或 Extension 的能力。
- TDD 底座：先建立测试 target 和可运行测试环境，后续功能以测试驱动方式演进。

## Phase 1：Shared Domain 与 TDD 底座

### Phase 1 阶段作用

先把共享模型和规则固化，避免不同模块对同一业务概念有不同解释。

### Phase 1 关键术语

- Shared Domain：跨 App、Agent、Extension 共享的业务模型和规则真相来源。
- ProtectedWorkspace：表示一个受保护目录或受保护工作区的共享模型。
- PolicySettings：本地策略配置模型，通常包含默认行为、受保护目录等信息。
- ProcessIdentityFingerprint：进程身份指纹，用来识别访问请求的发起方，并支撑规则匹配。
- 路径标准化：把不同路径表示规范化，避免规则匹配因路径表示差异失效。
- remembered decision：用户曾经确认并记住的访问决定，可在后续同类请求中直接命中。
- remembered decision cache：remembered decision 的本地缓存与持久化结构。
- 本地化骨架：为 en、zh-Hans、ja 等语言预置的资源结构。

## Phase 2：Onboarding 与原生 App 外壳

### Phase 2 阶段作用

提供用户首次进入产品时的正确前台入口和基本状态感知。

### Phase 2 关键术语

- onboarding：首次启动引导，目标是帮助用户完成可运行准备，而不是做营销介绍。
- step flow：由多个明确步骤组成的引导流程。
- 状态机：控制 onboarding 当前步骤、可跳转条件和完成条件的逻辑结构。
- readiness：对多个关键状态进行聚合后的就绪度概念。
- Protection Readiness：系统是否已经具备进行目录保护所需的关键运行条件。
- 默认目录注入：为用户预先放入默认受保护目录，避免初始状态为空。
- 原生设置式外壳：贴合 macOS 原生设置页结构的宿主 App UI 壳层。

## Phase 3：Agent 与 IPC

### Phase 3 阶段作用

让用户会话中的确认链路先打通，为后续决策引擎接入真实事件流做准备。

### Phase 3 关键术语

- Agent：这里特指 AegisAgent，运行在用户登录会话里的辅助进程。
- IPC：进程间通信。Aegis 需要用它连接 App、Agent、Extension 三者之间的消息和状态传递。
- prompt 服务：接收访问确认请求并弹出原生提示的服务能力。
- AccessPromptRequest：一次访问确认请求的数据结构。
- AccessPromptDecision：一次访问确认后的决策结果数据结构。
- rememberChoice：用户在确认窗口里选择“记住此决定”的附带意图。
- 状态查询与策略重载：让各模块互相知道当前状态，并在策略变化后及时更新本地视图。

## Phase 4：Extension 决策引擎

### Phase 4 阶段作用

实现真正的访问拦截和最终 allow 或 deny 决策主链路。

### Phase 4 关键术语

- 决策引擎：收到 AUTH_OPEN 后，综合路径匹配、trusted process policy、remembered decision 和 Agent 响应得出最终结果的核心逻辑。
- trusted process policy：内建的受信进程规则，用于让某些可信来源直接放行。
- Apple-signed 默认放行：对 Apple 签名进程的默认放行策略，用来减少对系统正常行为的干扰。
- prompt + timeout fallback：当需要人工确认时向 Agent 发起 prompt，但若超时则按默认策略回退。
- deadline：ES 授权事件要求在限定时间内给出结果，不能无限等待。
- Agent 不可达回退：如果 Agent 没启动、连接失败或响应异常，Extension 仍必须给出本地决策。
- 请求生命周期日志：记录一次访问请求从进入系统到最终决策的完整过程。

## Phase 5：设置页与本地配置

### Phase 5 阶段作用

把已有的保护能力转换成用户可编辑、可观察、可清理的原生设置界面。

### Phase 5 关键术语

- Protected Folders：设置页中用来管理受保护目录的区块。
- Remembered Decisions：设置页中用来展示或清理已记忆规则的区块。
- Default Behavior：设置页中定义超时或异常情况下默认 Allow 或 Deny 的区块。
- 策略热重载：用户改动本地策略后，App、Agent、Extension 无需重启即可感知新配置。
- remembered decision 清理：删除已缓存的记忆规则，至少支持全量清理。
- 诊断视图：用于展示运行状态、帮助排查本地问题的最小诊断能力。

## Phase 6：签名、公证、CI 与发布链路

### Phase 6 阶段作用

把产品能力接到稳定、可审计、可复用的构建与发布流程中。

### Phase 6 关键术语

- bootstrap：发布环境预检查脚本，确保工具链和环境前提满足。
- archive：将工程归档为可供导出和签名的构建产物。
- signing：使用 Developer ID 对导出产物进行签名。
- notarization：将产物提交给 Apple 公证服务，让 Gatekeeper 认可其分发安全性。
- package-dmg：将最终分发产物打包为 DMG。
- validate-release：对签名、公证、stapler 和 Gatekeeper 状态做发布前验证。
- CI：持续集成流程，用于自动执行测试和构建检查。
- GitHub Actions：Aegis 当前用来承载 CI 与 release 自动化流程的平台，不承担 phase-7 的本地特权 smoke。
- secrets：发布流程中使用的敏感凭据，例如 Developer ID 证书、公证密钥和 keychain 密码。

## Phase 7：特权 Smoke 与发布准备

### Phase 7 阶段作用

在真实平台权限模型下完成最后一轮发布前收口，确保 release 文档、流程和人工验证都可复现。

### Phase 7 关键术语

- privileged smoke：本地 macOS 14 及以上完整测试环境中的最小真实特权验证。
- 本地完整测试环境：一台 macOS 14 及以上、能够完整执行 System Extension、Full Disk Access、Agent 提示与回退链路验证的本地机器，可以是开发环境，但必须能留痕和复核。
- release runbook：正式发布的操作手册，定义从预跑到最终留痕的固定流程。
- readiness checklist：最终发布前的检查清单，用于明确当前是否达到 release ready。
- smoke record：一次 privileged smoke 的正式记录文件，包含执行环境、步骤结果、证据和结论。
- blocker record：当本地完整测试环境不满足或 smoke 无法执行时，用来记录阻塞事实和 No-Go 结论的文件。
- Go / Go with caveats / No-Go：发布结论。分别表示可以发布、带风险发布、不可发布。

## 术语之间的关系

- AegisShared 提供统一模型与规则，支撑 AegisApp、AegisAgent 和 AegisExtension 使用同一套业务定义。
- AegisApp 是前台入口，负责引导、配置和状态展示。
- AegisAgent 是用户交互入口，负责在登录会话中展示原生确认。
- AegisExtension 是最终执法入口，负责对 AUTH_OPEN 做授权判断。
- Phase 6 产出可分发 release 工件，Phase 7 用这些工件在真实权限环境里做最后验证。
- privileged smoke 不是 Phase 6 的替代，而是对自动化发布链路的补充验证。

## 快速阅读建议

- 想先理解产品要解决什么问题，先看“什么是 Privileged Smoke”和“全局核心概念”。
- 想理解为什么 phase 顺序不能打乱，先看 [architecture-causality.md](architecture-causality.md)。
- 想知道某个术语在哪个阶段首次变得重要，直接查看对应的 Phase 术语小节。
