# Aegis macOS 15+ 新建产品规划

## 结论

Aegis 不是迁移项目，而是一个面向 `macOS 15.0+` 的全新原生产品。现有仓库中的实验性代码只能作为参考，不构成兼容目标，也不作为架构包袱继承。

本规划将以下要求视为硬约束，而不是“后续优化项”：

- 全新新建，不做兼容式迁移
- UI 完全遵循 Apple macOS 默认系统设计规范和视觉风格
- 不引入任何第三方依赖
- 产品运行时完全本地化，无云端交互
- 重视本地隐私，用户数据完全持有在终端设备
- 从第一天起纳入 TDD、充分测试、签名、公证、发布和 GitHub CI 自动化
- 支持中文、英文、日文等国际化
- 严格遵循 Apple 官方 `EndpointSecurity` 文档
- 日志遵循 Apple unified logging 最佳实践

## 产品目标

Aegis v1 要解决的问题非常单一：

- 当任意进程访问用户定义的受保护目录时
- `AegisExtension` 能稳定拦截 Endpoint Security AUTH 事件
- `AegisAgent` 能在用户登录会话内弹出原生确认窗口
- 用户在 5 秒内选择允许或拒绝
- 若未响应，则由本地默认策略执行 `Allow` 或 `Deny`

## 非目标

v1 明确不做以下能力：

- 云端服务
- 账号体系
- 遥测、埋点、崩溃上传
- 长期白名单
- WebView / H5 审批界面
- 第三方 UI 组件库
- 第三方构建系统
- `macOS 15` 以下版本兼容

## 硬性工程约束

### 平台与工具链

- 最低系统版本：`macOS 15.0`
- 开发工具：`Xcode 16+`
- 语言：`Swift 6`
- UI：`SwiftUI`
- 并发：`Swift Concurrency`
- 状态管理：`Observation`
- 工程组织：原生 `.xcodeproj`
- 构建工具：`xcodebuild`

### 零第三方依赖

禁止引入以下内容：

- CocoaPods
- Carthage
- 第三方 Swift Package
- XcodeGen
- 第三方脚本运行时依赖
- 第三方测试框架

允许使用的仅限 Apple 官方框架和系统工具：

- `SwiftUI`
- `AppKit`
- `Foundation`
- `SystemExtensions`
- `EndpointSecurity`
- `ServiceManagement`
- `OSLog`
- `XCTest`
- `XCUITest`
- `xcodebuild`
- `codesign`
- `security`
- `notarytool`
- `stapler`
- `spctl`
- `hdiutil`

## Apple 平台约束

本方案遵守以下平台事实：

- `System Extension` 需要由宿主 App 触发安装和用户批准
- `Login Item` 应使用 `SMAppService`
- `Full Disk Access` 不能由 App 直接静默授予，只能通过引导用户完成系统设置
- 公证分发应使用 `notarytool`
- 视觉风格应遵循 Apple Human Interface Guidelines 的原生模式，而不是自定义品牌化壳层
- 国际化应使用 Xcode `String Catalog`
- 日志应使用 `Logger` / unified logging，并对敏感插值应用隐私标记

因此，Aegis 的新手引导必须承认并利用这些平台约束，而不是试图绕过它们。

## 官方文档遵循原则

`AegisExtension` 的实现边界必须以 Apple 官方 `EndpointSecurity` 文档为准：

- 只使用公开文档中的 API
- 不依赖私有 API
- 不依赖未文档化字段行为
- 不用 bundle path 猜测进程归属

v1 的 ES 订阅实践固定收敛为：

- 仅订阅 `ES_EVENT_TYPE_AUTH_OPEN`

除非后续设计文档明确扩展，否则不得擅自新增其他 AUTH 事件。

## 产品形态

### AegisApp

宿主应用，负责：

- 首次启动的新手引导
- 安装和卸载 `AegisExtension`
- 注册和检查 `AegisAgent` Login Item
- 编辑本地策略
- 展示运行状态
- 展示权限完成度

### AegisAgent

用户登录会话中的 Login Item，负责：

- 接收访问确认请求
- 展示原生确认弹窗
- 把用户决策回传给 Extension
- 在用户选择“记住此选择”后，将本地规则写回共享策略存储

### AegisExtension

Endpoint Security System Extension，负责：

- 仅订阅 `AUTH_OPEN`
- 匹配受保护目录
- 执行内建 trusted process policy
- 优先匹配本地 remembered decision cache
- 请求 Agent 做人工确认
- 在 deadline 内完成最终 allow/deny

### AegisShared

共享模块，负责：

- 共享模型
- 路径标准化
- 策略持久化
- IPC 协议
- 通用状态枚举

## 运行时隐私模型

Aegis 在运行时必须是完全本地化产品。

### 本地优先原则

- 所有策略配置保存在本地 `App Group` 共享容器
- 所有访问决策在本地设备完成
- 所有提示窗口和状态判断在本地完成
- 不依赖云端接口、远程配置、联网鉴权或遥测

### 明确禁止

- 不发送行为日志到服务端
- 不上传文件路径、进程信息或工作区信息
- 不做在线统计
- 不做 SaaS 管控
- 不做自动崩溃上报

### 网络边界

产品运行时应当不存在业务网络依赖。

唯一允许的外部网络交互发生在开发和发布阶段：

- GitHub CI 拉取代码、上传 artifact
- Apple notarization 服务完成公证

这两类网络行为不属于终端用户运行时行为。

## 国际化与本地化

### 支持语言

v1 至少提供以下本地化：

- `en`
- `zh-Hans`
- `ja`

架构上允许未来继续扩展更多语言，但首发必须保证这三种语言可完整运行。

### 本地化实现

- 使用 Xcode `String Catalog (.xcstrings)`
- 所有用户可见字符串必须走本地化 API
- SwiftUI 文案默认可本地化
- 非 View 层字符串使用 `String(localized:)`
- 所有关键文案附带 translator comment

### 文案质量要求

- 表达精简
- 含义准确
- 术语统一
- 中文、英文、日文都要自然，不做机器直译感表达

### 国际化测试要求

- UI 测试至少覆盖 `en`、`zh-Hans`、`ja`
- 使用 pseudolanguage 做截断和布局健壮性检查
- 所有 onboarding、设置页、确认弹窗必须通过多语言检查

## 原生视觉与交互规范

### 设计原则

Aegis 所有视觉和交互都必须贴合 macOS 默认系统体验：

- 使用系统字体
- 使用系统颜色和语义色
- 使用 `SF Symbols`
- 使用标准窗口、toolbar、sheet、form、list 和 settings 布局
- 使用系统间距、分组和分隔方式
- 使用原生控件文案和交互节奏

### 明确禁止

- 不做自定义皮肤
- 不做自定义窗口边框
- 不做夸张动效
- 不做品牌主导型 landing page 风格界面
- 不做拟物、插画、渐变氛围背景
- 不做与系统相冲突的自定义交互模式

### 结果要求

用户应感觉它像一个标准的 macOS 安全工具，而不是“套了 Apple API 的自定义产品壳”。

## 新手引导

`AegisApp` 首次启动后必须进入新手引导，而不是直接进入设置页。

### Onboarding 目标

- 用最少步骤帮助用户完成可运行准备
- 清楚解释本地隐私原则
- 安装 `System Extension`
- 引导用户完成 `Full Disk Access`
- 检查 Login Item 与保护状态

### 推荐步骤

1. `Welcome`
   - 产品用途
   - 仅在本地工作
   - 不上传数据
2. `Install Protection`
   - 触发 `System Extension` 安装
   - 展示当前安装状态
   - 明确提示用户去系统设置批准
3. `Grant Full Disk Access`
   - 解释为什么需要
   - 引导用户打开对应设置页
   - 用原生文案说明完成步骤
4. `Enable Background Prompting`
   - 注册并确认 `AegisAgent` Login Item
   - 展示 Agent 是否可达
5. `Readiness Check`
   - 汇总展示：
     - System Extension
     - Full Disk Access 指导完成情况
     - Agent 状态
     - 当前默认保护策略
6. `Finish`
   - 进入主界面

### 设计要求

- 每一步只做一件事
- 不承诺一键授予 `Full Disk Access`
- 不使用私有 API 绕开系统授权流程
- 即使 deep link 不可用，引导也必须可完成

## 产品架构

### 目标工程结构

建议新建如下原生工程结构：

```text
Aegis/
├── Aegis.xcodeproj
├── AegisApp/
│   ├── App/
│   ├── Onboarding/
│   ├── Settings/
│   ├── Status/
│   ├── Services/
│   ├── Resources/
│   └── AegisApp.entitlements
├── AegisAgent/
│   ├── App/
│   ├── Prompt/
│   ├── Services/
│   ├── Resources/
│   └── AegisAgent.entitlements
├── AegisExtension/
│   ├── Bootstrap/
│   ├── EndpointSecurity/
│   ├── Policy/
│   ├── IPC/
│   ├── Resources/
│   └── AegisExtension.entitlements
├── AegisShared/
│   ├── Models/
│   ├── Persistence/
│   ├── IPC/
│   └── Utilities/
├── Tests/
│   ├── AegisSharedTests/
│   ├── AegisAppTests/
│   ├── AegisExtensionTests/
│   ├── AegisAppUITests/
│   └── ReleaseValidationTests/
├── scripts/
│   ├── bootstrap.sh
│   ├── test.sh
│   ├── archive.sh
│   ├── sign.sh
│   ├── notarize.sh
│   ├── package-dmg.sh
│   └── validate-release.sh
└── .github/
    └── workflows/
        ├── ci.yml
        ├── release.yml
        └── privileged-smoke.yml
```

### 模块职责

- `AegisApp`
  - 新手引导
  - 状态页
  - 目录管理
  - 默认策略设置
  - remembered decisions 管理
  - 扩展与 Login Item 管理
- `AegisAgent`
  - 原生确认窗口
  - 请求排队与显示
  - 用户决策返回
- `AegisExtension`
  - ES 事件订阅
  - 路径提取
  - trusted process policy
  - deadline 驱动决策
- `AegisShared`
  - 模型与协议唯一真相来源

## 本地策略模型

```swift
struct ProtectedWorkspace: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var path: String
    var isEnabled: Bool
}

enum AccessDecision: String, Codable, Sendable {
    case allow
    case deny
}

enum DecisionSource: String, Codable, Sendable {
    case user
    case timeoutFallback
    case agentUnavailable
    case invalidResponse
}

struct PolicySettings: Codable, Sendable {
    var defaultTimeoutDecision: AccessDecision
    var workspaces: [ProtectedWorkspace]
}

struct ProcessIdentityFingerprint: Codable, Hashable, Sendable {
    let signingIdentifier: String?
    let teamIdentifier: String?
    let executablePath: String
    let isAppleSigned: Bool
}

struct RememberedDecisionRule: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let workspaceID: UUID
    let process: ProcessIdentityFingerprint
    var decision: AccessDecision
    var createdAt: Date
    var updatedAt: Date
}

struct LocalPolicyStore: Codable, Sendable {
    var settings: PolicySettings
    var rememberedRules: [RememberedDecisionRule]
}

struct AccessPromptRequest: Codable, Sendable {
    let requestID: UUID
    let eventType: String
    let targetPath: String
    let workspaceID: UUID
    let workspaceName: String
    let processPath: String
    let pid: Int32
    let signingIdentifier: String?
    let teamIdentifier: String?
    let isAppleSigned: Bool
    let deadline: Date
}

struct AccessPromptDecision: Codable, Sendable {
    let requestID: UUID
    let decision: AccessDecision
    let source: DecisionSource
    let rememberChoice: Bool
    let respondedAt: Date
}
```

### 约束

- `promptTimeoutSeconds` 固定为 `5`
- v1 不开放 prompt timeout 编辑
- v1 不允许用户编辑 trusted process 列表
- 策略文件只允许由 `AegisApp` 写入
- `AegisAgent` 与 `AegisExtension` 只能只读加载本地策略
- remembered decision rule 为本地持久化数据
- remembered decision 的命中粒度固定为：
  - 同一受保护目录
  - 同一进程身份
  - 同一 `AUTH_OPEN` 访问类型
- 默认预置目录：
  - `~/OpenClaw`
  - `~/HermesAgentWorkspace`

## 路径与事件规则

### 路径标准化

所有路径在写入和匹配前统一执行：

- 展开 `~`
- 标准化路径
- 解析符号链接
- 去除尾部斜杠

### 目录命中规则

- 路径与受保护目录完全相等，或
- 路径位于该目录树下

### AUTH 事件范围

v1 只订阅并处理：

- `AUTH_OPEN`

不实现 `WRITE`、`CREATE`、`RENAME`、`UNLINK` 等其他 AUTH 事件。

## 内建 trusted process policy

v1 的 trusted process policy 为内建代码规则，不属于用户配置。

### 放行对象

- `AegisApp`
- `AegisAgent`
- `AegisExtension`
- 所有可判定为 Apple-signed 的 Apple 生态进程
- 极少量其他必要系统进程

### 匹配优先级

1. 代码签名标识
2. 明确 bundle identifier
3. 明确可执行路径

禁止使用“根据 app bundle path 猜 bundle ID”的启发式判断作为正式实现。

### 产品决策说明

“默认允许 Apple 生态所有进程访问受保护目录”是明确的产品策略，不是实现偶然结果。

这意味着访问决策优先级为：

1. Aegis 自身组件
2. Apple-signed 进程
3. remembered decision rule
4. 用户交互确认
5. timeout fallback

该策略降低了 Apple 生态噪音，但也缩小了保护覆盖面，应作为显式产品选择写入文档和测试。

## Remembered Decision Cache

### 目标

当用户在确认弹窗中勾选“记住此选择”后，下次相同访问不再弹窗，而是直接命中本地缓存规则。

### v1 规则粒度

v1 将“相同访问”定义为：

- 同一受保护目录
- 同一进程身份指纹
- 同一访问类型 `AUTH_OPEN`

其中“同一进程身份指纹”由以下字段组成：

- `signingIdentifier`
- `teamIdentifier`
- `executablePath`

### 行为规则

- 仅对非 Apple-signed 进程应用 remembered decision cache
- Apple-signed 进程已在 trusted process policy 中直接放行，不进入 remembered decision cache
- 用户点击 `允许` 或 `拒绝` 时，可同时选择“记住此选择”
- 命中 remembered rule 时，Extension 直接执行对应决策，不请求 Agent
- remembered rule 必须保存在本地 `App Group` 共享容器

### 最低可管理能力

引入 remembered rule 后，主界面必须提供至少一种撤销手段：

- `Clear All Remembered Decisions`

若实现成本可控，建议进一步支持：

- 按 workspace 清理
- 按 rule 单条删除

## IPC 与状态模型

### Extension <-> Agent

```swift
func evaluateAccessRequest(_ request: AccessPromptRequest) async throws -> AccessPromptDecision
```

约束：

- Extension 负责超时
- Agent 只返回用户操作
- Agent 不存储历史决策
- Agent 断连、崩溃、无效响应都回退到本地默认策略
- remember 规则由共享本地策略存储落盘

### App <-> Agent / Extension

```swift
func reloadPolicy() async throws
func queryStatus() async throws -> ComponentStatus
```

### 状态展示

主界面状态分成四类：

- `System Extension`
- `Login Item`
- `Policy`
- `Protection Readiness`

不承诺提供“绝对准确的 Full Disk Access 布尔检测值”，而是展示引导完成度和整体 readiness。

## UI 方案

### AegisApp 主界面

主界面建议使用标准 `Settings` 风格，划分为三个区块：

- `Protection Status`
  - System Extension 状态
  - Login Item 状态
  - Policy 状态
  - Readiness 状态
- `Protected Folders`
  - 目录列表
  - 添加目录
  - 删除目录
  - 启停保护
- `Remembered Decisions`
  - 规则数量
  - 清空入口
- `Default Behavior`
  - `Allow after 5s timeout`
  - `Deny after 5s timeout`

### AegisAgent Prompt

确认弹窗使用 SwiftUI 原生窗口。

固定信息结构：

- 标题：`文件访问确认`
- 副标题：某进程正在访问受保护目录
- 详情区：
  - Process
  - Path
  - Target
  - Event
  - Workspace
- 底部按钮：
  - `拒绝`
  - `允许`
- 记忆选项：
  - `记住此应用对该受保护目录的选择`

如展示倒计时，只显示只读倒计时文案。

## 日志策略

### 总体原则

日志必须遵循 Apple unified logging 最佳实践：

- 使用 `Logger`
- 明确 `subsystem` 和 `category`
- 使用合适的 `log level`
- 对敏感数据使用 privacy 标记
- 默认不把用户路径、进程信息以公开明文写入持久日志

### 推荐 subsystem / category

- `com.company.aegis.app`
  - `onboarding`
  - `policy`
  - `status`
- `com.company.aegis.agent`
  - `prompt`
  - `ipc`
- `com.company.aegis.extension`
  - `endpoint-security`
  - `decision`
  - `cache`

### 日志级别约束

- `debug`
  - 本地调试细节
- `info` / `notice`
  - 生命周期、状态变化、配置更新
- `warning`
  - 可恢复异常
- `error`
  - 请求失败、状态异常
- `fault`
  - 明显程序错误或关键流程失效

### 敏感信息策略

以下信息默认按 `private` 或 `sensitive` 处理：

- 文件路径
- 进程路径
- 工作区路径
- 策略文件内容

若需要跨日志关联同一值，使用 hash mask，而不是公开原文。

### 诊断关联

- 每个访问确认链路必须带 `requestID`
- App、Agent、Extension 的相关日志应能通过 `requestID` 关联
- 正常路径日志保持克制，避免日志噪音和磁盘污染

## TDD 与测试策略

测试不是补充项，而是实施前提。

### TDD 强制规则

任何生产代码改动都必须遵循：

1. 先写失败测试
2. 运行并确认失败
3. 编写最小实现
4. 运行目标测试并确认通过
5. 运行完整测试矩阵并确认通过
6. 仅在全部通过后允许合并或发布

### 自动化测试层次

#### 1. AegisShared 单元测试

- 模型编解码
- 路径标准化
- 目录命中判断
- 策略持久化
- 默认策略生成

#### 2. AegisExtension 单元测试

- `AUTH_OPEN` 事件路径提取
- trusted process policy
- Apple-signed 默认放行
- remembered decision 命中与失效
- timeout fallback
- Agent 不可达 fallback

#### 3. IPC 合约测试

- `AccessPromptRequest` 与 `AccessPromptDecision` 编解码
- deadline 传播
- 错误映射
- 状态查询接口契约
- rememberChoice 标记传播

#### 4. AegisApp 测试

- onboarding state machine
- readiness 聚合逻辑
- 策略编辑和保存
- Login Item 状态管理
- remembered decision 清空逻辑
- 本地化资源加载

#### 5. UI 自动化测试

- 首次启动进入 onboarding
- Onboarding 每一步可前进/后退
- 默认目录展示正确
- 设置页增删目录可用
- 默认超时策略切换可用
- 确认弹窗 remember 选项可用
- `en` / `zh-Hans` / `ja` 基本界面可用

#### 6. 发布验证测试

- app bundle 结构检查
- nested code signing 检查
- entitlement 检查
- hardened runtime 检查
- notarization stapling 检查
- Gatekeeper 验证

#### 7. 日志策略测试

- Logger category 路由正确
- requestID 贯通正确
- 敏感字段默认不以 public 方式输出

### 特权能力测试现实

需要直接说明：

- GitHub 托管 runner 上无法完整自动化真实的 `System Extension` 用户批准和 `Full Disk Access` 人工授权流程
- 这些流程必须设计为：
  - 自动化可验证部分
  - 受控 macOS 15 机器上的特权 smoke 测试

因此，“测试全部通过”的定义应包含两部分：

- 所有自动化测试全部通过
- 所有特权 smoke 检查全部通过

### 建议的测试门禁

- PR：必须通过全部自动化测试
- Tag Release：必须通过全部自动化测试和发布验证
- 正式发布前：必须在受控 macOS 15 机器完成特权 smoke 测试

### 固定测试入口

所有测试统一通过一个主入口脚本调度：

- `scripts/test.sh`

该脚本内部固定调用：

```bash
xcodebuild -project Aegis.xcodeproj -scheme AegisSharedTests -destination 'platform=macOS' test
xcodebuild -project Aegis.xcodeproj -scheme AegisExtensionTests -destination 'platform=macOS' test
xcodebuild -project Aegis.xcodeproj -scheme AegisAppTests -destination 'platform=macOS' test
xcodebuild -project Aegis.xcodeproj -scheme AegisAppUITests -destination 'platform=macOS' test
xcodebuild -project Aegis.xcodeproj -scheme ReleaseValidationTests -destination 'platform=macOS' test
```

任何代码变更都必须运行完整入口，而不是只跑局部测试后宣称完成。

## 构建、签名、公证与发布

### 产物策略

推荐最终对外分发产物为：

- 已签名、已公证、已 stapled 的 `.dmg`

中间产物包括：

- `.xcarchive`
- 导出的 `.app`
- CI 调试 artifact

### 签名要求

- 使用 `Developer ID Application`
- 所有嵌套代码必须完整签名
- 启用 hardened runtime
- entitlements 精简且可审计

### 公证要求

发布流程固定为：

1. `xcodebuild archive`
2. 导出 `.app`
3. 检查 bundle 完整性
4. 对嵌套代码和主 app 完成签名校验
5. 生成 `.dmg`
6. 使用 `notarytool` 提交公证
7. `stapler` 附加票据
8. `spctl` 和 `codesign` 完成最终验证

### 发布校验命令

`scripts/validate-release.sh` 至少应覆盖：

```bash
codesign -dvvv --entitlements :- "Aegis.app"
spctl -a -vv "Aegis.app"
xcrun stapler validate "Aegis.dmg"
```

### 发布脚本

必须提供可在本地和 CI 复用的脚本：

- `scripts/bootstrap.sh`
  - 环境预检查
- `scripts/test.sh`
  - 运行完整自动化测试矩阵
- `scripts/archive.sh`
  - 归档应用
- `scripts/sign.sh`
  - 签名和签名校验
- `scripts/notarize.sh`
  - 调用 `notarytool`
- `scripts/package-dmg.sh`
  - 生成发行 DMG
- `scripts/validate-release.sh`
  - 运行发布级校验

## GitHub CI 方案

### 推荐方案

推荐采用双层 GitHub CI：

- GitHub 托管 `macos-15` runner
  - 构建
  - 单元测试
  - UI 测试
  - 归档
  - 签名
  - 公证
  - 产物校验
- 受控 self-hosted macOS 15 runner
  - 特权 smoke 测试
  - 安装和引导链路验证

这样可以同时满足自动化和平台现实约束。

### 工作流划分

#### `ci.yml`

触发：

- `pull_request`
- `push` 到主分支

职责：

- 构建
- 运行全部自动化测试
- 上传测试报告和中间 artifact
- 禁止使用 `macos-latest`，固定 pin 到 `macos-15`

#### `release.yml`

触发：

- `tag`
- `workflow_dispatch`

职责：

- 归档
- 导出 app
- 签名
- 生成 DMG
- 公证
- staple
- 发布校验
- 上传 GitHub Release
- 所有构建、签名和发布逻辑必须调用仓库内 `scripts/*.sh`，避免把逻辑散落在 workflow YAML 中

#### `privileged-smoke.yml`

触发：

- `workflow_dispatch`
- Release 后手动触发

职责：

- 在受控 macOS 15 机器安装产物
- 验证 onboarding
- 验证 System Extension 安装流
- 验证 Agent 可达
- 记录特权 smoke 结果

### GitHub Secrets

CI 至少需要以下 secrets：

- `DEVELOPER_ID_P12_BASE64`
- `DEVELOPER_ID_P12_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_PRIVATE_KEY`

推荐使用 App Store Connect Team API Key 驱动 `notarytool`，避免个人 Apple ID 型凭据。

## 分阶段实施

### Phase 0: 新建工程与约束固化

- 新建原生 `.xcodeproj`
- 建立四模块结构
- 明确零第三方依赖边界
- 建立基础测试 target

### Phase 1: Shared Domain + TDD 底座

- 先实现 `AegisShared`
- 建立模型、路径工具、策略存储
- 建立 remembered decision rule 存储
- 建立本地化资源结构
- 所有能力先用单元测试驱动

### Phase 2: Onboarding 与原生 App 外壳

- 完成首次启动引导
- 完成 readiness 状态聚合
- 完成默认目录注入
- 完成三语本地化骨架

### Phase 3: Agent 与 IPC

- 完成 Login Item
- 完成 prompt 服务
- 完成 App / Agent / Extension 状态通信
- 完成 rememberChoice 交互回传

### Phase 4: Extension 决策引擎

- 实现 `AUTH_OPEN` 单事件处理
- 实现 trusted process policy
- 实现 Apple-signed 默认放行
- 实现 remembered decision cache
- 实现 prompt + timeout fallback

### Phase 5: 设置页与本地配置

- 完成目录管理
- 完成默认行为设置
- 完成策略热重载
- 完成 remembered decision 清理入口
- 完成日志与诊断视图最小能力

### Phase 6: 签名、公证、CI 与发布链路

- 实现脚本
- 实现 GitHub Actions
- 完成发布验证

### Phase 7: 特权 smoke 与发布准备

- 在 macOS 15 受控环境完成特权验证
- 补齐文档
- 固化发布流程

## 完成定义

当且仅当以下条件全部满足时，Aegis v1 才算完成：

- 新工程独立建立完成，不依赖旧原型
- 不含任何第三方依赖
- 新手引导可完整引导用户完成安装和使用准备
- 所有界面符合 macOS 默认系统设计风格
- 至少完整支持英文、简体中文、日文
- 运行时完全本地化，无云端交互
- Endpoint Security 保护链路以 `AUTH_OPEN` 为唯一订阅事件并完整可用
- Apple-signed 进程默认放行行为可验证
- remembered decision cache 可用且可清理
- 日志符合统一日志最佳实践且敏感信息默认受保护
- 所有自动化测试全部通过
- 所有特权 smoke 检查全部通过
- GitHub CI 可完成构建、测试、打包、签名、公证和发布
- 最终产物为可分发的已公证 DMG

## 参考依据

- Apple Human Interface Guidelines
  - https://developer.apple.com/design/human-interface-guidelines/
- Embedding a helper app in a sandboxed app
  - https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app
- ServiceManagement / SMAppService
  - https://developer.apple.com/documentation/servicemanagement/smappservice
- System Extensions
  - https://developer.apple.com/documentation/systemextensions
- Endpoint Security
  - https://developer.apple.com/documentation/endpointsecurity
- `ES_EVENT_TYPE_AUTH_OPEN`
  - https://developer.apple.com/documentation/endpointsecurity/es_event_type_t/es_event_type_auth_open
- Logger
  - https://developer.apple.com/documentation/os/logger
- Logging
  - https://developer.apple.com/documentation/os/logging
- `OSLogPrivacy.sensitive`
  - https://developer.apple.com/documentation/os/oslogprivacy/sensitive
- Notarizing macOS software before distribution
  - https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution
- Customizing the notarization workflow
  - https://developer.apple.com/documentation/security/customizing_the_notarization_workflow
- Localizing and varying text with a string catalog
  - https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog
- Preparing your interface for localization
  - https://developer.apple.com/documentation/xcode/preparing-your-interface-for-localization
- GitHub Actions macOS runners
  - https://docs.github.com/actions/using-github-hosted-runners/about-github-hosted-runners
