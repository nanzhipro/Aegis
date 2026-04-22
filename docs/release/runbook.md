# Aegis Release Runbook

本 runbook 对应 phase-7 的“团队可以按文档完成一次完整 release”要求。自动化发布入口、人工特权 smoke、最终发布前检查必须按本文顺序执行。

如果你只想看当前还剩哪些本地人工步骤未做，直接看 [phase-7-local-execution.md](phase-7-local-execution.md)。

## 适用范围

- 目标平台：本地可完整测试的 macOS 14 及以上环境
- 自动化构建环境：GitHub Actions `macos-14`
- 特权 smoke 环境：本地可完整测试环境，可以是开发环境，但必须能完整执行 phase-7 的人工验证并留痕

## 入口总览

- 自动化测试入口：`./scripts/test.sh`
- 发布环境预检查：`./scripts/bootstrap.sh`
- 归档：`./scripts/archive.sh`
- 签名：`./scripts/sign.sh`
- 打包 DMG：`./scripts/package-dmg.sh`
- 公证：`./scripts/notarize.sh`
- 发布校验：`./scripts/validate-release.sh`
- GitHub 托管发布流水线：`.github/workflows/release.yml`
- 本地 smoke 记录草稿：`./scripts/prepare-privileged-smoke-record.sh`

## 前置条件

执行 release 前必须确认：

- `main` 分支已包含目标提交。
- `./scripts/test.sh` 在当前提交上通过。
- GitHub Actions 发布所需 secrets 已在 GitHub 仓库中配置：
  - `DEVELOPER_ID_P12_BASE64`
  - `DEVELOPER_ID_P12_PASSWORD`
  - `KEYCHAIN_PASSWORD`
  - `APPLE_TEAM_ID`
  - `APPLE_NOTARY_KEY_ID`
  - `APPLE_NOTARY_ISSUER_ID`
  - `APPLE_NOTARY_PRIVATE_KEY`
- 本地 macOS 14 及以上完整测试环境可用，并具备执行 System Extension、Full Disk Access 和 Agent 提示链路的条件。
- 将要发布的 tag 已确定，例如 `v1.0.0`。

本地或受信开发机预跑时，公证凭据支持两种来源：

- 本地 Keychain profile：先执行 `xcrun notarytool store-credentials "notary-profile" ...`，再导出 `APPLE_NOTARY_KEYCHAIN_PROFILE=notary-profile` 或 `AEGIS_NOTARY_KEYCHAIN_PROFILE=notary-profile`。
- App Store Connect API key：继续使用 `APPLE_TEAM_ID`、`APPLE_NOTARY_KEY_ID`、`APPLE_NOTARY_ISSUER_ID`、`APPLE_NOTARY_PRIVATE_KEY`。

## 标准发布顺序

### 1. 本地或受信开发机预跑

按顺序执行：

```sh
./scripts/bootstrap.sh
./scripts/test.sh
./scripts/archive.sh
./scripts/sign.sh
./scripts/package-dmg.sh
./scripts/validate-release.sh
```

如果当前环境具备 notary 凭据，再执行：

```sh
./scripts/notarize.sh
./scripts/validate-release.sh
```

优先级规则如下：

- 如果设置了 `APPLE_NOTARY_KEYCHAIN_PROFILE` 或 `AEGIS_NOTARY_KEYCHAIN_PROFILE`，`./scripts/notarize.sh` 会直接使用本地 Keychain 中已保存的 notarytool profile。
- 如果没有设置 profile，脚本会回退到现有的 App Store Connect API key 流程。

预跑目的不是代替 GitHub Release，而是尽早发现签名、公证、DMG 与验证脚本回归。

### 2. 触发 GitHub Release

二选一：

- 推送 tag：`git tag vX.Y.Z && git push origin vX.Y.Z`
- 手动触发 `.github/workflows/release.yml`，并填写 `release_tag`

发布 workflow 的固定职责：

1. 选择 Xcode 15.4。
2. 运行 `./scripts/bootstrap.sh`。
3. 运行 `./scripts/test.sh`。
4. 归档、签名、打包 DMG、公证、发布校验。
5. 上传 `Aegis.xcarchive`、`AegisApp.app`、`AegisApp.dmg` 与公证日志。
6. 将 `AegisApp.dmg` 上传到对应 GitHub Release。

### 3. 在本地完整测试环境执行特权 smoke

release 完成后，在本地 macOS 14 及以上完整测试环境执行 phase-7 特权 smoke。

推荐顺序如下：

1. 从 GitHub Release 下载 `AegisApp.dmg`，或直接使用本地已 notarize 且已 stapled 的最终 DMG。
2. 解包并运行 `./scripts/validate-release.sh` 验证签名、stapler 与 Gatekeeper。
3. 运行 `./scripts/prepare-privileged-smoke-record.sh` 生成带 release 元数据的本地记录草稿。
4. 按 `docs/release/privileged-smoke-checklist.md` 执行所有人工步骤，并把证据补到记录草稿中。

人工执行人必须同时打开：

- 本地生成的 `build/release/*-privileged-smoke.md` 记录草稿
- `docs/release/privileged-smoke-checklist.md`
- `docs/release/readiness-checklist.md`

若本地记录草稿不可用，再回退到 `docs/release/privileged-smoke-record-template.md` 手工建档。

### 4. 留痕并给出结论

完成特权 smoke 后，必须把记录模板保存为具体记录文件，例如：

- `docs/release/records/2026-04-21-v1.0.0-privileged-smoke.md`

推荐流程是先在本地生成并填写 `privileged-smoke-record.md` 草稿，确认结论后再将最终内容落入仓库中的 `docs/release/records/`。

若在进入人工 smoke 前就发现前置条件不满足，也必须写入 blocker 记录，例如：

- `docs/release/records/2026-04-21-v1.0.0-privileged-smoke-blocked.md`

记录中至少包含：

- 执行人
- 时间
- 本地主机版本
- release tag
- 每个 smoke 步骤的通过/失败结果
- 失败项与处置
- 最终结论：`Go`、`Go with caveats` 或 `No-Go`

### 5. 发布判定

只有同时满足以下条件，才能认定本次发布准备完成：

- 自动化测试通过
- release workflow 通过
- 特权 smoke 有真实记录
- 最终发布前检查清单全部勾完
- 结论为 `Go`

## 故障处理

### release workflow 失败

- 优先查看失败步骤对应的脚本输出。
- 若失败发生在签名、公证或 DMG 验证，先在受信开发机复现对应脚本。
- 未修复前不得重试 privileged smoke。

### privileged smoke 失败

- 记录失败步骤与截图。
- 标记本次结果为 `No-Go`。
- 修复后必须基于新的 release 产物重新执行 smoke，而不是对旧结论追加口头说明。

### 当前环境不满足本地完整测试条件

- 低于 macOS 14 的主机不能作为最终 smoke 结果。
- 即使主机版本满足 macOS 14 及以上，也必须能够完整执行 System Extension、Full Disk Access、Agent 提示与回退链路验证，并形成真实 smoke 留痕。
- 发现环境不满足时，必须立即写 blocker 记录，并把结论标记为 `No-Go`。
- 没有真实 smoke 留痕时，phase-7 不能标记完成。
