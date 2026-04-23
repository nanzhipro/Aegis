# Endpoint Security System Extension 必备条件与 Aegis 现状评审

> 范围：仅覆盖 ES System Extension（`.systemextension` 产物类型），不涉及 `.appex`、DriverKit 或 Network Extension 的独有条款。所有要求引自 Apple 官方文档。

## 一、官方确定性方案

### A. 开发者前提

| 项 | 要求 | 官方来源 |
|---|---|---|
| A1 | 加入 **Apple Developer Program** 付费计划 | `developer.apple.com/programs` |
| A2 | 向 Apple 提交 **Endpoint Security entitlement 申请**（邮件审批，周期不定） | `com.apple.developer.endpoint-security.client` 文档 |
| A3 | 获批后，在 developer portal 创建包含该 entitlement 的 **App ID + Provisioning Profile**（Developer ID 分发型） | System Extensions and DriverKit 指南 |
| A4 | 下载 profile 嵌入 host App 与 System Extension，分别在 `Contents/embedded.provisionprofile` | SE/Code Signing Guide |
| A5 | 产物必须由 **Developer ID Application** 证书签名，由 **Developer ID Installer 不需要**（不走 pkg），并走 `notarytool` 公证 + `stapler` staple | Notarization for macOS |

### B. 工程配置（Xcode / pbxproj）

| 项 | 要求 |
|---|---|
| B1 | System Extension target `productType = com.apple.product-type.system-extension`；产物后缀 `.systemextension` |
| B2 | Host App 的 **Embed build phase** 把 `.systemextension` 拷贝到 `AegisApp.app/Contents/Library/SystemExtensions/` |
| B3 | Host App target：entitlements 含 `com.apple.developer.system-extension.install = true` |
| B4 | Extension target：entitlements 含 `com.apple.developer.endpoint-security.client = true`（单独 entitlement，**不能** 启用 `com.apple.security.app-sandbox`，**不能** 启用 `com.apple.security.get-task-allow`（Release）） |
| B5 | Extension target：`INFOPLIST_KEY_NSSystemExtensionUsageDescription` 必填（Apple 要求所有非 DriverKit system extension 都提供用户可见说明） |
| B6 | Extension：链接 `usr/lib/libEndpointSecurity.tbd`（`-framework` 不适用，因为它是纯 C dylib） |
| B7 | 所有三件（App、Agent、Extension）共用同一 `DEVELOPMENT_TEAM`；Mach service 名称以 Team ID 为前缀 |
| B8 | Extension bundle ID 必须与 host App **同前缀或同团队**；Apple 推荐以 host app bundle ID 为前缀（如 `com.acme.host.esext`） |
| B9 | `MACOSX_DEPLOYMENT_TARGET ≥ 10.15`；Aegis 固定 14.5 OK |
| B10 | Hardened Runtime 开启（`ENABLE_HARDENED_RUNTIME = YES`），公证硬性要求 |

### C. 源码

| 项 | 要求 |
|---|---|
| C1 | Extension `@main` 保持 RunLoop 常驻：`RunLoop.main.run()` 或 `dispatchMain()` |
| C2 | `es_new_client(&client, handler)` → 检查 `es_new_client_result_t`；必须映射 `ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED`、`_NOT_PRIVILEGED`（非 root）、`_NOT_PERMITTED`（TCC/FDA 未授权） |
| C3 | `es_subscribe(client, events, count)` 仅订阅需要的事件 |
| C4 | AUTH 事件必须在 kernel deadline 前用 `es_respond_auth_result` 或 `es_respond_flags_result` 响应；超时将被强制 DENY 并终止客户端 |
| C5 | Host App 激活：`OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier:queue:)` + `OSSystemExtensionManager.shared.submitRequest(_)`；delegate 必须强引用 |
| C6 | Delegate 必需实现 4 个方法：`actionForReplacingExtension:withExtension:`、`requestNeedsUserApproval:`、`didFinishWithResult:`、`didFailWithError:` |
| C7 | XPC：Extension 侧 `NSXPCListener(machServiceName:)` + `shouldAcceptNewConnection` 内 `setCodeSigningRequirement(_)`；App/Agent 侧 `NSXPCConnection(machServiceName:, options: .privileged)` + 同步 `setCodeSigningRequirement` |
| C8 | Mach service 名称必须出现在 `launchd.plist` 或 Extension 的 `Info.plist → MachServices`，否则 `bootstrap_check_in` 失败；但 System Extension 下 Apple 会基于 team ID 前缀自动发布，名称形如 `<TEAMID>.<bundleid>` |

### D. 二进制 / 运行时

| 项 | 要求 |
|---|---|
| D1 | App 必须位于 `/Applications` 或 `/Applications/<Subdir>/`（开发调试可用 `systemextensionsctl developer on` 绕过） |
| D2 | 调试须 `systemextensionsctl developer on`，Release 必须 **关闭** |
| D3 | 调试可临时禁用 SIP，Release 必须启用 SIP |
| D4 | 首次激活，系统会提示用户跳转 **系统设置 → 通用 → 登录项与扩展 → 端点安全扩展** 批准；未批准前 `requestNeedsUserApproval` 回调触发 |
| D5 | 用户批准后可能需要提供 **完全磁盘访问权限 (FDA)**，否则 `es_new_client` 返回 `ERR_NOT_PERMITTED` |
| D6 | 启动后以 **root** 身份运行（macOS 会 launchd 拉起 extension 进程为 root），非 root 则 `ERR_NOT_PRIVILEGED` |
| D7 | 产物链路必须干净：先签 Extension，再签 App 外壳；`codesign --verify --deep --strict --verbose=2` 必须通过 |
| D8 | 公证 + staple 后通过 `spctl --assess --type execute` 检验 |
| D9 | `systemextensionsctl list` 应能看到 `[activated enabled]` |

### E. 用户交互

1. App 打开 → 调 `submitRequest(activationRequest)`。
2. 系统弹「扩展需要批准」系统通知。
3. 用户前往"设置 → 登录项与扩展 → 端点安全扩展"勾选。
4. 系统可能要求 FDA，引导用户到"隐私与安全性 → 完全磁盘访问"加入 `AegisApp`（及/或 Extension 的 helper）。
5. `didFinishWithResult(.completed)` 回调触发。
6. Extension 进程由 launchd 以 root 拉起，`es_new_client` 成功，`es_subscribe` 成功。
7. App / Agent 通过 Team-ID 前缀 Mach service 建立 XPC，`setCodeSigningRequirement` 双向互认。

---

## 二、Aegis 现状逐项对照

### 已满足（✅）

- B1 Extension target `com.apple.product-type.system-extension`，产物 `.systemextension`（`Aegis.xcodeproj/project.pbxproj` line 527）。
- B2 `Embed System Extension` build phase 输出到 `Contents/Library/SystemExtensions/`（line 683-697）。
- B3 `AegisApp.entitlements` 含 `com.apple.developer.system-extension.install` 与 App Group。
- B4 `AegisExtension.entitlements` 仅含 `com.apple.developer.endpoint-security.client`，没有 sandbox / get-task-allow。
- B5 Debug+Release 两处 `INFOPLIST_KEY_NSSystemExtensionUsageDescription` 已补齐（上一轮修复）。
- B6 Extension target Frameworks build phase 链接 `usr/lib/libEndpointSecurity.tbd`。
- B9 `MACOSX_DEPLOYMENT_TARGET = 14.5`。
- C1 `AegisExtensionMain.main()` 中 `RunLoop.main.run()`。
- C2 `LiveEndpointSecurityClient.start()` 调用 `es_new_client` 并将 4 个错误码映射到 `EndpointSecurityClientError`。
- C3 `es_subscribe` 严格只订阅 `ES_EVENT_TYPE_AUTH_OPEN`。
- C4 decision engine 在 deadline 内回 `es_respond_auth_result`（`promptTimeoutSeconds = 5` < kernel deadline）。
- C5 `SystemExtensionInstaller.activate` 使用 `OSSystemExtensionRequest.activationRequest`，通过 `pendingDelegate` 强引用。
- C6 `SystemExtensionRequestDelegate` 实现了 4 个回调。
- C7 `AegisExtensionXPCService` 在 `shouldAcceptNewConnection` 调 `setCodeSigningRequirement`；客户端侧 `AegisAppXPCController` / `AegisAgentXPCController` 同样设置。
- UI：overview 与 onboarding 有 `SystemExtensionInstallationCard`，会显示 `didFailWithError.localizedDescription`。

### 未满足 / 高风险（❌ / ⚠）

| # | 项 | 现状 | 影响 | 处理建议 |
|---|---|---|---|---|
| G1 | **A2 / A3：Apple 端 Endpoint Security entitlement 审批 + Provisioning Profile** | 未知（仓库中无 `*.mobileprovision` / `embedded.provisionprofile`；pbxproj 无 `DEVELOPMENT_TEAM` / `PROVISIONING_PROFILE_SPECIFIER`） | **致命**：即使 entitlement 文件声明了 key，没有 Apple 颁发的 profile，code signing 会成功但运行时 `es_new_client` 会返回 `ERR_NOT_ENTITLED`，并且 `submitRequest` 在 stricter macOS（非 dev mode）会直接拒绝 | 由开发者完成。邮件向 Apple Developer Support 申请 ES entitlement；获批后在 Xcode 的 AegisApp 与 AegisExtension target 都设置 `DEVELOPMENT_TEAM` 和 manual profile |
| G2 | **B7：`DEVELOPMENT_TEAM` 未在 pbxproj 固化** | 无任何 target 有 `DEVELOPMENT_TEAM` 字段 | Xcode 本地开发会用当前登录 Apple ID，CI 会失败；team-prefixed Mach service 名可能错乱 | 建议通过 `Config/Signing.xcconfig` 或 pbxproj 显式写入，或至少在 CI 配 `DEVELOPMENT_TEAM` 环境变量 |
| G3 | **B10：`ENABLE_HARDENED_RUNTIME`** | pbxproj 未显式设置 | 公证硬性要求 | 需要显式 `ENABLE_HARDENED_RUNTIME = YES` 至少在 Release 配置 |
| G4 | **B8：Extension bundle ID 未以 host app 为前缀** | `com.nanzhipro.AegisApp` + `com.nanzhipro.AegisExtension`（兄弟） | 非强制但不符合 Apple 推荐；某些老版本 macOS 曾对此更严格；当前不影响激活 | 保留或改为 `com.nanzhipro.AegisApp.Extension`（需同步 `defaultExtensionIdentifier`、Mach service 名、测试） |
| G5 | **D1 / D2：运行位置 + developer mode** | 用户从 `DerivedData` 或其他位置启动；`systemextensionsctl developer on` 未必开启 | `submitRequest` 会以 `OSSystemExtensionErrorCodeExtensionMissingIdentifier` / `CodeSignatureInvalid` / 仅 sysextd 日志"attempting to realize"静默失败 | Onboarding 引导 + 启动时自检；或在 README 明确开发者步骤 |
| G6 | **D4 / D5：首次激活后系统设置与 FDA 引导** | 代码只 open 主窗口 + 激活 | 用户看不到"去哪里批准"的指示；失败原因用户不易理解 | 在 `requestNeedsUserApproval` 回调触发时，用 `NSWorkspace.shared.open` 自动打开 `x-apple.systempreferences:com.apple.LoginItems-Settings.extension` URL；失败含关键字 `not permitted` 时引导到 FDA pane |
| G7 | **C8：Mach service 名的 team 前缀** | `AegisXPCContract.machServiceName()` 在环境变量 `AEGIS_TEAM_ID` 未设时会用 `AppIdentifierPrefix`，若为 ad-hoc 签名将返回无前缀名 | 签名/运行时 team 前缀不匹配会让 `NSXPCConnection` 立即失败 | 生产构建必须确保 `DEVELOPMENT_TEAM` 与 entitlement 的 App Group 前缀一致；或在 Info.plist 固化 `AppIdentifierPrefix` |
| G8 | **C 错误上报 UX** | 失败直接显示 NSError.localizedDescription | 用户看到"Extension not found in App bundle"等原始字符串 | 已有 reason UI；建议补一层错误码→本地化文案映射（`OSSystemExtensionErrorCode`） |

---

## 三、立即可做的最小调整（已落）

1. **`project.pbxproj` 缩进**：`INFOPLIST_KEY_NSSystemExtensionUsageDescription` 两行缩进已从 `\t\t\t\t\t` 归一化为 `\t\t\t\t`。
2. **`ReleaseValidationTests`**：已有 `testAegisExtensionDeclaresSystemExtensionUsageDescription` 回归断言。
3. **签名与模板收敛（2026-04-23）**：完成以下最小调整，并把所有示例值改为占位符模板，避免保留外部工程信息：
   - 六个 product target 配置（`A70000…0003`–`A70000…0008`）统一加上 `ENABLE_HARDENED_RUNTIME = YES`。
   - `AegisExtension.entitlements` 追加 `com.apple.security.application-groups = [group.com.nanzhipro.Aegis]`，与 `AegisApp` / `AegisAgent` 对齐。
   - `AegisAgent.entitlements` 从空 `<dict/>` 补齐 `application-groups`，解决原先 Agent 拿不到共享容器的隐患。
   - 新增 [Signing.xcconfig.template](../Signing.xcconfig.template)：仅保留 `CODE_SIGN_STYLE`、`DEVELOPMENT_TEAM`、`CODE_SIGN_IDENTITY`、`PROVISIONING_PROFILE_SPECIFIER` 和 entitlement 相关键位的占位符示例。模板没有被自动注入 pbxproj 和 entitlements —— 一旦注入，本地会触发 `No profiles for 'com.nanzhipro.*' were found` 错误，必须先等 Apple 批准 ES entitlement 并在 Developer Portal 创建 `AegisAppProvisioningProfile`、`AegisAgentProvisioningProfile`、`AegisExtensionProvisioningProfile` 后，再按模板把键值拷贝回 Xcode target 设置（见第四节 P0 步骤 3）。

> 结论：当前文档只保留 Aegis 自身需要的签名与分发要点，不再保留任何外部工程、团队、证书主体或 bundle 标识示例。

## 四、待用户/开发者侧操作（阻塞真实安装）

**优先级 P0**（不做，永远装不上）：

1. 确认团队已获 Apple 颁发的 `com.apple.developer.endpoint-security.client` entitlement。未获批请邮件申请。
2. 在 Apple Developer Portal 为 `com.nanzhipro.AegisApp` 与 `com.nanzhipro.AegisExtension` 创建 Developer ID Application profile，包含 ES entitlement。
3. 在 Xcode 中给 AegisApp / AegisAgent / AegisExtension 三个 target 都配：
   - `DEVELOPMENT_TEAM = <你的 10 位 Team ID>`
   - `CODE_SIGN_STYLE = Manual`
   - `PROVISIONING_PROFILE_SPECIFIER = <profile 名>`
4. 开发调试前跑一次：
   - `sudo systemextensionsctl developer on`
   - （可选）Recovery 模式临时关 SIP
5. 把 `AegisApp.app` 拖到 `/Applications`，在那里运行，不要在 `DerivedData` 里直接双击。

**优先级 P1**（强健性）：

6. ~~pbxproj 为所有 target Release 配置加 `ENABLE_HARDENED_RUNTIME = YES`~~ **已完成（2026-04-23）**：6 个 product target 的 Debug/Release 均已写入 `ENABLE_HARDENED_RUNTIME = YES`。
7. `requestNeedsUserApproval` 里调 `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)` 自动拉起系统设置面板。
8. 针对 `OSSystemExtensionErrorCode` 做本地化错误映射（代替原始 `localizedDescription`）。

**优先级 P2**（规范）：

9. 将 `com.nanzhipro.AegisExtension` 更名为 `com.nanzhipro.AegisApp.Extension`，与 Apple 推荐的前缀约定对齐。
10. 把本文件要点沉淀进 `plan/phases/phase-7-*.md` 的 smoke checklist。

---

## 五、Go/No-Go 自检脚本（建议加入 `scripts/`）

```bash
# 1. 验证 Info.plist 关键字
plutil -extract NSSystemExtensionUsageDescription raw \
  "AegisApp.app/Contents/Library/SystemExtensions/AegisExtension.systemextension/Contents/Info.plist"

# 2. 验证 entitlement
codesign -d --entitlements :- \
  "AegisApp.app/Contents/Library/SystemExtensions/AegisExtension.systemextension" \
  | grep endpoint-security.client

# 3. 验证签名链
codesign --verify --deep --strict --verbose=2 AegisApp.app

# 4. 验证嵌入 profile
ls AegisApp.app/Contents/embedded.provisionprofile
ls AegisApp.app/Contents/Library/SystemExtensions/AegisExtension.systemextension/Contents/embedded.provisionprofile

# 5. 验证安装后状态（需要交互）
systemextensionsctl list | grep AegisExtension

# 6. 验证 ES 订阅成功
log stream --style compact --predicate 'subsystem == "com.nanzhipro.AegisExtension"' &
```

---

## 六、结论

**代码层面**：已高度符合 Apple 官方规范，除了 G6/G7/G8 三个"增强型"缺口之外，源码与工程配置没有阻塞性缺陷。

**分发链路层面**：当前阻塞点 **完全** 落在 Apple 侧 entitlement 审批 + Developer ID 签名身份 + provisioning profile 上（G1 / G2 / G3）。没有这些，无论怎么改代码都装不上、订阅不到 ES 事件。

**最终目标拆解**：

| 目标 | 当前状态 | 还差什么 |
|---|---|---|
| SystemExtension 能被 App 提交安装请求 | ✅ | 已实现 |
| 用户弹出系统批准提示 | ⚠ | 需要有效 ES entitlement 的签名，否则请求被 sysextd 静默吞掉 |
| 用户批准后 Extension 完整运行 | ⚠ | 需要 FDA + root + ES entitlement |
| Extension 与 App 建立 XPC | ✅（代码就位） | 需要双端同团队签名，Mach service 名 team-prefix 一致 |

---

## 七、Developer Mode 下的本地调试最小配置（`systemextensionsctl developer on`）

> 目标：在无 Apple ES entitlement 审批、无 Developer ID profile、无 notarization 的前提下，本地完成 Aegis 的 SE 加载、激活与 ES 事件订阅。

### 7.1 Developer Mode 放宽项（不再需要）

| 放宽项 | Release 要求 | Dev Mode 下 |
|---|---|---|
| `embedded.provisionprofile` | 必须由 Apple 颁发 | 可缺省 |
| `com.apple.developer.endpoint-security.client` 的 Apple 审批 | 必须 | 本地签名可直接声明 |
| codesign 证书 | Developer ID Application | 允许 **ad-hoc (`-`)** 或任意 Apple Development 证书 |
| Notarize + staple | 必须 | 完全跳过 |
| 安装位置 | 必须 `/Applications` 下 | DerivedData / 桌面 / 任意路径都允许 |

对应到 Aegis 当前仓库状态：pbxproj 中 **没有** `DEVELOPMENT_TEAM` / `CODE_SIGN_STYLE` / `PROVISIONING_PROFILE_SPECIFIER`（保持 ad-hoc），`Signing.xcconfig.template` 留作日后正式分发激活。此状态**正好**是 Dev Mode 需要的最小状态，**不要**把模板写回 pbxproj，否则 Xcode 会报 `No profiles for 'com.nanzhipro.*' were found`。

### 7.2 Dev Mode 下仍强制的条件（不放宽）

#### 系统 / 交互

1. `sudo systemextensionsctl developer on` 后以 `systemextensionsctl list` 首行出现 `*** Developer Mode is ON ***` 为准（首次开启通常需要重登或重启 `sysextd`）。
2. **FDA（完全磁盘访问）**：首次激活成功后，macOS 会要求在「系统设置 → 隐私与安全性 → 完全磁盘访问」为 AegisExtension 勾选；未授予前 `es_new_client` 返回 `ERR_NOT_PERMITTED`。Dev Mode **不替你打勾**。
3. Extension 进程由 `sysextd` 以 **root** 拉起（自动），host App 本身普通用户启动即可。
4. SIP **无需** 关闭。ES 路径全部在 userland，不需要。

#### Bundle / 工程（Dev Mode 一条都不放宽）

| # | 强制项 | Aegis 现状 |
|---|---|---|
| 1 | Extension productType = `com.apple.product-type.system-extension`，产物 `.systemextension` | ✅ |
| 2 | Host App `Embed System Extension` build phase → `Contents/Library/SystemExtensions/` | ✅ |
| 3 | AegisApp.entitlements 含 `com.apple.developer.system-extension.install = true` | ✅ |
| 4 | AegisExtension.entitlements 含 `com.apple.developer.endpoint-security.client = true`，且 **不得** 有 `app-sandbox` / `get-task-allow`(Release) | ✅ |
| 5 | Extension Info.plist 含 `NSSystemExtensionUsageDescription`（launchServices 硬校验，Dev Mode 也查） | ✅（pbxproj `INFOPLIST_KEY_NSSystemExtensionUsageDescription`） |
| 6 | Extension 链接 `usr/lib/libEndpointSecurity.tbd` | ✅ |
| 7 | Extension bundle ID 与 host App 同团队（ad-hoc 下同为 ad-hoc 也算） | ✅ |
| 8 | `MACOSX_DEPLOYMENT_TARGET ≥ 10.15` | ✅（14.5） |
| 9 | `ENABLE_HARDENED_RUNTIME = YES`（Dev Mode 不强制，但现仓库已启，**保留不回滚**，便于无缝切正式分发） | ✅ |

#### 代码 / 运行时

1. Extension main `RunLoop.main.run()` 常驻 —— ✅ `AegisExtensionMain.main()`。
2. `es_new_client` → `es_subscribe(ES_EVENT_TYPE_AUTH_OPEN)` → 在 kernel deadline 前 `es_respond_auth_result` —— ✅ `promptTimeoutSeconds = 5`。
3. XPC 双端 `setCodeSigningRequirement` —— ⚠ **Dev Mode 特别提示**：ad-hoc 签名下，`AppIdentifierPrefix` 为空，`AegisXPCContract.machServiceName()` 依赖的 team 前缀会退化。若观察到 `XPCConnection invalidated`：
   - 临时方案：在本机 shell 导出 `AEGIS_TEAM_ID=<任意稳定字符串>` 后再 `open AegisApp.app`，三端使用同一值即可；
   - 或暂时放宽 `setCodeSigningRequirement` 至 `identifier "com.nanzhipro.AegisExtension"`（不带 `anchor apple generic and certificate leaf[...]`）。
   - 切正式分发时由 Signing.xcconfig.template 回填 DEVELOPMENT_TEAM，此项自动回归严格模式。

### 7.3 Aegis 本地 Dev Mode 启跑 checklist

```bash
# 0. 开发者模式（只需一次，重启后仍生效）
sudo systemextensionsctl developer on
systemextensionsctl list | head -n 3          # 看到 *** Developer Mode is ON ***

# 1. ad-hoc 构建（pbxproj 保持当前无签名配置）
xcodebuild -project Aegis.xcodeproj -scheme AegisApp -destination 'platform=macOS' build

# 2. 直接从 DerivedData 启动（Dev Mode 下允许非 /Applications 路径）
open DerivedData/Aegis/Build/Products/Debug/AegisApp.app

# 3. Onboarding 里点激活 → 系统弹「需要批准」→ 去「系统设置 → 隐私与安全性」批准
# 4. 再去「完全磁盘访问」为 AegisExtension 勾选
# 5. 观察订阅
log stream --style compact --predicate 'subsystem == "com.nanzhipro.AegisExtension"'

# 6. 排错：查看 sysextd 日志
log stream --predicate 'subsystem == "com.apple.sysextd"' --info
systemextensionsctl list | grep AegisExtension    # 期望 [activated enabled]
```

### 7.4 Dev Mode 下的常见坑与对照

| 症状 | 根因 | 处理 |
|---|---|---|
| `submitRequest` 回调 `didFailWithError: code=4` (`OSSystemExtensionErrorCodeExtensionMissingIdentifier`) | Dev Mode 未真正开启 / 未重启 | 重新 `systemextensionsctl developer on` 后重登录 |
| sysextd 日志仅 `attempting to realize...` 后静默 | 从 DerivedData 启动但签名 requirement 不匹配 | 确认 ad-hoc 签名成功；或改到 `/Applications` 再试 |
| `didFinishWithResult(.completed)` 但 Extension 不启动 | NSSystemExtensionUsageDescription 缺失（Aegis 已补） | 验证 `plutil -p .../Info.plist \| grep -i usage` |
| Extension 启动了但 `es_new_client` 返回 `NOT_PERMITTED` | FDA 未授予 | 到「隐私与安全性 → 完全磁盘访问」打勾 |
| `NOT_PRIVILEGED` | Extension 未以 root 运行 | 不应发生；若发生说明 sysextd 异常，重启机器 |
| XPC 连接 `invalidated` | ad-hoc 下 team 前缀为空导致 Mach service 名退化 | 见 7.2 代码/运行时第 3 条 |

> 一句话结论：**Aegis 当前的 pbxproj + entitlements 配置已经是 Dev Mode 下可立即跑通的最小集**，开发者端只需跑 `systemextensionsctl developer on` + 授 FDA，即可在无 Apple 审批的前提下本地观察 ES 事件订阅与 AUTH 响应链路。
