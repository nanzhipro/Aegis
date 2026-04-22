# Phase 7: 特权 Smoke 与发布准备

## 阶段定位

这是正式发布前的收口阶段，目标是在本地可完整测试的 macOS 14 及以上环境完成自动化无法覆盖的特权验证，并把文档和发布流程固定下来。

## 必带上下文

- `plan/common.md`
- Phase 6 已完成

## 阶段目标

- 在 macOS 14 及以上本地完整测试环境完成特权验证
- 补齐文档
- 固化发布流程

## 实施范围

- 执行 `System Extension` 安装、用户批准、`Full Disk Access` 指导等特权 smoke 测试
- 记录 release runbook、人工验证步骤和最终发布前检查项
- 回补因平台限制无法在托管 CI 自动化的验证说明
- 验证 `AegisApp.zip` 分发流程在干净系统上可落地：解压后拖入 `/Applications/` 只产生单个 `AegisApp.app`，且嵌入的 `Contents/Library/SystemExtensions/AegisExtension.systemextension`、`Contents/Library/LoginItems/AegisAgent.app`、`Contents/Library/LaunchAgents/<agent>.plist` 均按预期落地；首次双击可启动，无 Gatekeeper / quarantine 拦截
- 验证 AegisAgent 通过 `SMAppService.agent(plistName:)` 加载嵌入 plist 注册为 LaunchAgent，并在下一次登录时自启
- 验证 AegisApp ↔ AegisExtension、AegisAgent ↔ AegisExtension 两条 XPC 双向通道能建立连接、代码签名校验通过

## 本阶段产出

- 特权 smoke 测试记录
- 最终发布前检查清单
- 补齐后的发布与运维文档
- 可复用的正式发布流程说明

## 明确不做

- 不在此阶段新增产品范围
- 不为规避平台授权限制而引入私有 API 或非常规手段

## 完成判定

- 本地 macOS 14 及以上完整测试环境中的特权 smoke 已完成并留痕
- 发布文档与人工验证流程完整
- 团队可以按固定流程复现正式发布
- smoke 记录包含：`AegisApp.zip` 解压拖入 `/Applications` 后的单 bundle 安装验证（`/Applications/AegisApp.app` 可启动，嵌入的 Agent / Extension / LaunchAgent plist 路径全部存在，无 Gatekeeper 拦截）、ES 客户端 `es_new_client` 实际成功、XPC 双向握手、Agent LaunchAgent 自启四项实测截图或日志

## 依赖关系

- 依赖 Phase 6
