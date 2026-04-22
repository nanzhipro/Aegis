# Aegis Privileged Smoke Record Template

优先使用 `./scripts/prepare-privileged-smoke-record.sh` 在本地生成的 `build/release/*-privileged-smoke.md` 作为记录草稿；仅在该草稿不可用时，才复制本模板为具体记录文件，例如 `docs/release/records/2026-04-21-v1.0.0-privileged-smoke.md`。

## Metadata

- Release tag:
- Commit SHA:
- Execution date:
- Executor:
- Host machine:
- macOS version:
- Execution environment:
- ZIP SHA256:

## Preconditions

- Release workflow run:
- Privileged smoke entrypoint:
- `./scripts/validate-release.sh` result:

## Manual Smoke Results

- ZIP download and extraction:
  - Result:
  - Evidence:
  - Notes:
- App install to `/Applications`:
  - Result:
  - Evidence:
  - Notes:
- Onboarding appears on first launch:
  - Result:
  - Evidence:
  - Notes:
- System Extension install request:
  - Result:
  - Evidence:
  - Notes:
- System Extension approval in System Settings:
  - Result:
  - Evidence:
  - Notes:
- Full Disk Access guidance:
  - Result:
  - Evidence:
  - Notes:
- Login Item registration:
  - Result:
  - Evidence:
  - Notes:
- Agent prompt presentation:
  - Result:
  - Evidence:
  - Notes:
- Allow decision path:
  - Result:
  - Evidence:
  - Notes:
- Deny decision path:
  - Result:
  - Evidence:
  - Notes:
- Remember choice hit:
  - Result:
  - Evidence:
  - Notes:
- Default timeout fallback:
  - Result:
  - Evidence:
  - Notes:
- Dashboard readiness visibility:
  - Result:
  - Evidence:
  - Notes:
- Settings page policy editing:
  - Result:
  - Evidence:
  - Notes:
- Remembered decisions clearing:
  - Result:
  - Evidence:
  - Notes:

## Issues Found

- None / list each issue with reproduction and impact.

## Final Decision

- Release readiness: `Go` / `Go with caveats` / `No-Go`
- Summary:
- Follow-up actions:
