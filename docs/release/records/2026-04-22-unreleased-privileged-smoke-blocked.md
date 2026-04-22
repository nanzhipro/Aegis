# Aegis Privileged Smoke Blocker Record

本记录用于说明当前 phase-7 仍未完成。它记录的是当前仓库在自动化与文档层面的预检结果，以及阻止正式 privileged smoke 完成的缺口；它不能替代 macOS 14 及以上完整测试环境中的正式 smoke 留痕。

## Metadata

- Release tag: unreleased
- Commit SHA: 8da0c4e82c8acbcf461e0e9e4dc71d96ddd8cb8b
- Execution date: 2026-04-22
- Last revalidated at: 2026-04-22
- Executor: GitHub Copilot
- Host machine: local workspace host
- macOS version: 14.7.4
- Execution environment: local-preflight

## Preconditions

- Release workflow run: not executed in this session
- Privileged smoke entrypoint: local manual smoke pending
- Local packaged artifacts: `build/release` currently does not contain `AegisApp.app` or `AegisApp.zip`
- Real notarization validation: not executed in this session because packaged release artifacts and release credentials are not available in the workspace

## Automated Evidence

- Focused contract validation command: `xcodebuild -project Aegis.xcodeproj -scheme ReleaseValidationTests -destination 'platform=macOS' test`
- Latest validation result: passed
- Last validation date: 2026-04-22
- Coverage summary: release scripts, release workflow, legacy disk-image packaging disablement, and `AegisApp.app` + `AegisApp.zip` artifact expectations
- Smoke draft: unavailable in current workspace
- Phase-6 release pipeline state: scripts, workflow, tests, and release docs are aligned to the `AegisApp.app` + `AegisApp.zip` distribution model

## Current Phase Status

- Phase-7 completion: blocked
- Blocking verdict date: 2026-04-22
- Blocking reason: 当前 `HEAD` 的 phase-6 自动化契约已经闭合，但仍然缺少本地 macOS 14 及以上完整测试环境中的真实 privileged smoke 记录。

## Blocking Conditions

1. 当前工作区没有可供手工安装验证的 `AegisApp.zip` 或 `AegisApp.app`，因此无法从本次会话直接执行“解压 -> 拖入 `/Applications` -> 首次启动”的真实分发路径。
2. 仓库中不存在针对当前 `HEAD` 的正式 privileged smoke 证据，仍缺少以下四项真实截图、日志或命令输出：
   - `AegisApp.zip` 解压拖入 `/Applications` 后只产生单个 `/Applications/AegisApp.app`
   - Extension 日志显示 `es_new_client` 成功并完成 `AUTH_OPEN` 订阅
   - `AegisApp ↔ AegisExtension`、`AegisAgent ↔ AegisExtension` 两条 XPC 通道均完成握手并回传 `statusDidChange`
   - 登出再登入后 AegisAgent 通过 `SMAppService.agent(plistName:)` 自动随系统启动
3. 本次会话没有执行真实签名、公证或 release workflow，因此也无法在这里验证最终分发 zip 的 Gatekeeper、quarantine 和 stapled 行为。

## Next Required Actions

1. 在 macOS 14 及以上完整测试环境中生成或获取当前 `HEAD` 对应的已签名、已公证、已 stapled 的 `AegisApp.zip`。
2. 按 `docs/release/privileged-smoke-checklist.md` 完成完整人工验证，并为四项必备证据逐项留痕。
3. 形成正式 smoke 记录文件并同步更新 `docs/release/readiness-checklist.md`，然后再判断是否可以完成 phase-7。

## Final Decision

- Release readiness: `No-Go`
- Summary: phase-6 的发布脚本、workflow、测试与文档已经切换到 `AegisApp.app` + `AegisApp.zip`，但 phase-7 仍被真实特权 smoke 缺口阻塞。当前仓库缺少可执行的最终分发产物，也缺少对当前 `HEAD` 的四项人工验证证据，因此不能判定发布准备完成。
- Follow-up actions:
  - 在本地完整测试环境中完成真实 smoke，并把结论与证据写入正式记录。
  - 形成正式 smoke 留痕后，再决定是否写回 phase-7 完成状态。