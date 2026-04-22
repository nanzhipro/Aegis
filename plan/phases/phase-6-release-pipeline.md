# Phase 6: 签名、公证、CI 与发布链路

## 阶段定位

这个阶段不再扩展产品能力，而是把已有成果接到可复用、可审计、可自动化的构建、签名、公证和发布流程上。

## 必带上下文

- `plan/common.md`
- Phase 5 已完成

## 阶段目标

- 实现脚本
- 实现 GitHub Actions
- 完成发布验证
- 固化已签名、已公证、已 stapled 的 `AegisApp.app` + `AegisApp.zip` 为对外分发唯一产物（单一 app bundle，嵌入 AegisAgent.app 与 AegisExtension.systemextension）；不使用 `.pkg`

## 实施范围

- 落地 `scripts/bootstrap.sh`、`scripts/test.sh`、`scripts/archive.sh`、`scripts/sign.sh`、`scripts/notarize.sh`、`scripts/package-app.sh`、`scripts/validate-release.sh`
- 落地 `ci.yml`、`release.yml`
- 固化签名（仅 `Developer ID Application` 一套身份）、公证（`notarytool submit AegisApp.zip --wait`）、stapler 将票据附加到 `.app`、发布 zip 打包和发布验证入口
- 移除或显式停用早期的 pkg / dmg 脚本（`scripts/package-pkg.sh`、`scripts/distribution.xml`、`scripts/package-dmg.sh` 及 `ReleaseValidationTests` 中 pkg/dmg 相关断言）

## 本阶段产出

- 本地与 CI 复用的发布脚本集合
- GitHub Actions 工作流
- 产物校验和发布前置检查
- 可审计的 secrets 使用约束（不包含 installer 凭据）
- 可分发的 `AegisApp.zip`（内含已签名、已公证、已 stapled 的 `AegisApp.app`；`AegisApp.app` 内部包含 `Contents/Library/SystemExtensions/AegisExtension.systemextension`、`Contents/Library/LoginItems/AegisAgent.app` 与 `Contents/Library/LaunchAgents/<agent>.plist`）

## 明确不做

- 不在此阶段执行真实特权 smoke 测试
- 不在 workflow 里复制脚本逻辑
- 不引入 `.pkg` / `.dmg` 路径，`pkgbuild` / `productbuild` / `productsign` / `pkgutil` / `hdiutil` 不出现在发布链路
- 不再使用 Developer ID Installer 身份
- 不把特权 smoke 伪装成托管 CI 可自动化能力

## 完成判定

- 自动化测试、归档、签名、公证、zip 打包链路清晰可复用
- workflow 只编排，不埋复杂实现逻辑
- 发布校验入口明确且可重复执行
- 仓库存在 `scripts/package-app.sh`；`scripts/sign.sh`、`scripts/notarize.sh`、`scripts/validate-release.sh` 均面向 `.app` 与 `.zip`
- `scripts/validate-release.sh` 至少执行 `codesign -vvv --deep --strict`、`codesign -dvvv --entitlements :-`（顶层与两类嵌套组件）、`spctl --assess --type execute`、`xcrun stapler validate`；禁止出现 `spctl --assess --type install`、`pkgutil --check-signature`
- `release.yml` 产出可下载的 `AegisApp.zip`；用户解压后拖入 `/Applications` 即可使用，`AegisApp.app` 内嵌入 AegisAgent.app、AegisExtension.systemextension 与 LaunchAgent plist
- 如仓库仍保留 `scripts/package-pkg.sh`、`scripts/distribution.xml`、`scripts/package-dmg.sh`，必须在本阶段移除或显式标注为已停用；CI / release 流水线不得再调用
- `ReleaseValidationTests` 以 `AegisApp.app` 与 `AegisApp.zip` 为验证对象，不再依赖 `.pkg` / `.dmg`

## 依赖关系

- 依赖 Phase 5
