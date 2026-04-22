# Aegis Privileged Smoke Blocker Record

本记录用于说明当前 phase-7 仍未完成。它不是受控 macOS 14.5 privileged smoke 的完成记录，不能替代正式 smoke 留痕。

## Metadata

- Release tag: unreleased
- Commit SHA: c1613bc5a63e11181bdcbb651a4e3b3fb4f324d5
- Execution date: 2026-04-21
- Last revalidated at: 2026-04-22
- Executor: GitHub Copilot
- Host machine: local workspace host
- macOS version: 14.7.4
- Runner label: local-preflight
- DMG SHA256: 0f830ada96ce79fd856af0aa147a5ea066fb6520969adce6f8efefc98d622867

## Preconditions

- Release workflow run: not executed in this session
- Privileged smoke workflow run: not executed in this session
- `./scripts/validate-release.sh` result: passed after local notarization and stapling

## Automated Evidence

- Last validation command: `AEGIS_NOTARY_KEYCHAIN_PROFILE=notary-profile ./scripts/notarize.sh && ./scripts/validate-release.sh`
- Last validation date: 2026-04-22
- App validation result: passed
- App Gatekeeper result: accepted
- App Gatekeeper detail: `source=Notarized Developer ID`, `override=security disabled`
- App origin: Developer ID Application: Hangzhou Cyberserval Co., Ltd. (CCLJ2GNM3D)
- DMG validation result: passed
- DMG Gatekeeper detail: `accepted`, `source=Insufficient Context`, `override=security disabled`
- DMG stapler detail: `The validate action worked!`

## Current Phase Status

- Phase-7 completion: blocked
- Blocking verdict date: 2026-04-22
- Blocking reason: 当前本地预检已完成 notarization、stapling 和 release validation，但仍然缺少受控 macOS 14 及以上环境中的真实 privileged smoke 记录。

## Blocking Conditions

1. 当前主机虽然是 macOS 14.7.4，已满足 macOS 14 及以上版本门槛，但本次复核不是在 `aegis-privileged` runner 的真实 privileged smoke 流程中完成。
2. 尚无在 `aegis-privileged` runner 或等效受控主机上完成的真实 privileged smoke 记录。
3. 尚未形成带人工步骤证据与最终结论的正式 smoke 记录文件，因此 phase-7 不能判定完成。

## Next Required Actions

1. 将当前已 notarize 且已 stapled 的 DMG 通过 `.github/workflows/release.yml` 或等效受信流程提供给受控 smoke 环境。
2. 在标签包含 `self-hosted`、`macOS`、`aegis-privileged` 的受控 runner 上执行 `.github/workflows/privileged-smoke.yml`，并完成人工步骤。
3. 使用 `docs/release/privileged-smoke-record-template.md` 生成正式记录文件，并为每个手工步骤补齐证据。

## Final Decision

- Release readiness: `No-Go`
- Summary: phase-7 文档与本地发布预检已齐，截至 2026-04-22 复核时，本地 DMG 已完成 notarization、stapling 并通过 `./scripts/validate-release.sh`，但受控 macOS 14 及以上环境中的真实 privileged smoke 仍未执行。
- Follow-up actions:
  - 在受控 runner 上完成真实 smoke，并把结论同步到 `docs/release/readiness-checklist.md`。
  - 形成正式 smoke 留痕后，再判断是否可以完成 phase-7 并写回计划状态。