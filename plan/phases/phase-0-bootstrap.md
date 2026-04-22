# Phase 0: 新建工程与约束固化

## 阶段定位

这是 Aegis 的工程起步阶段，目标不是实现业务能力，而是把“全新原生构建、零第三方依赖、macOS 14.5+、Swift 5.10、TDD 优先”的底层边界一次性固化到工程结构里。

## 必带上下文

- `plan/common.md`

## 阶段目标

- 新建原生 `.xcodeproj`
- 建立 `AegisApp`、`AegisAgent`、`AegisExtension`、`AegisShared` 四模块骨架
- 固化零第三方依赖边界
- 建立基础测试 target，为后续 TDD 留出最小可运行底座

## 实施范围

- 初始化原生工程与 target 结构
- 建立共享目录、资源目录、测试目录和基础 entitlements 占位
- 明确禁止第三方依赖的工程边界
- 保证后续所有实现都能落回原生 `.xcodeproj` 与 `xcodebuild`

## 本阶段产出

- 可被 Xcode 和 `xcodebuild` 正常识别的工程骨架
- 四模块与测试模块的基础目录/target 布局
- 为后续 Phase 预留的资源、服务、IPC、测试目录结构
- 初始工程约束说明，避免后续偏离通用约定

## 明确不做

- 不实现具体业务模型和策略存储
- 不实现 onboarding、Agent、Extension 逻辑
- 不实现签名、公证、CI 工作流

## 完成判定

- 工程结构与通用规划中的目标工程结构一致
- 不存在任何第三方依赖入口
- 基础测试 target 已建立，可供后续 Phase 扩展
- 后续 Phase 不需要再回头重做工程分层或依赖边界

## 依赖关系

- 无前置 Phase
