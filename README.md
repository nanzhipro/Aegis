# Aegis macOS 15+ 产品规划

## 结论

Aegis 不是迁移项目，而是一个面向 `macOS 15.0+` 的全新原生产品。现有仓库中的实验性代码只能作为参考，不构成兼容目标，也不作为架构包袱继承。

本规划将以下要求视为硬约束，而不是“后续优化项”：

- 全新构建，不做兼容式迁移
- UI 完全遵循 Apple macOS 默认系统设计规范和视觉风格
- 不引入任何第三方依赖
- 产品运行时完全本地化，无云端交互
- 重视本地隐私，用户数据完全保存在本地设备
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
- 视觉风格应遵循 [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) 的原生模式，而不是自定义品牌化界面
- 国际化应使用 Xcode `String Catalog`
- 日志应使用 `Logger` / unified logging，并对敏感数据应用隐私标记

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
