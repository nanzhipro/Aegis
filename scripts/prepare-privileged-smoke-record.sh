#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

# shellcheck disable=SC1091
. "$SCRIPT_DIR/release-common.sh"

release_tag=${AEGIS_PRIVILEGED_SMOKE_TAG:-${AEGIS_RELEASE_TAG:-}}
[ -n "$release_tag" ] || fail "Missing release tag. Set AEGIS_PRIVILEGED_SMOKE_TAG or AEGIS_RELEASE_TAG."

prepare_release_directories

sanitized_tag=$(printf '%s' "$release_tag" | tr '/ ' '--')
execution_timestamp=${AEGIS_PRIVILEGED_SMOKE_EXECUTION_TIMESTAMP:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}
execution_date=${AEGIS_PRIVILEGED_SMOKE_EXECUTION_DATE:-${execution_timestamp%%T*}}
output_path=${AEGIS_PRIVILEGED_SMOKE_OUTPUT_PATH:-"$BUILD_DIR/${execution_date}-${sanitized_tag}-privileged-smoke.md"}
commit_sha=${AEGIS_PRIVILEGED_SMOKE_COMMIT_SHA:-$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')}
executor=${AEGIS_PRIVILEGED_SMOKE_EXECUTOR:-${GITHUB_ACTOR:-unknown}}
host_machine=${AEGIS_PRIVILEGED_SMOKE_HOST_MACHINE:-$(scutil --get ComputerName 2>/dev/null || hostname)}
macos_version=${AEGIS_PRIVILEGED_SMOKE_MACOS_VERSION:-$(sw_vers -productVersion 2>/dev/null || printf 'unknown')}
execution_environment=${AEGIS_PRIVILEGED_SMOKE_ENVIRONMENT:-${AEGIS_PRIVILEGED_SMOKE_RUNNER_LABEL:-local-full-test-environment}}
validate_result=${AEGIS_PRIVILEGED_SMOKE_VALIDATE_RESULT:-passed}
release_workflow_run=${AEGIS_RELEASE_WORKFLOW_RUN:-GitHub release workflow for ${release_tag}}
final_record_path="docs/release/records/${execution_date}-${sanitized_tag}-privileged-smoke.md"

privileged_smoke_entrypoint=${AEGIS_PRIVILEGED_SMOKE_ENTRYPOINT:-local manual smoke}

if [ -n "${AEGIS_PRIVILEGED_SMOKE_ZIP_SHA256:-}" ]; then
  zip_sha256=$AEGIS_PRIVILEGED_SMOKE_ZIP_SHA256
elif [ -f "$ZIP_PATH" ]; then
  zip_sha256=$(shasum -a 256 "$ZIP_PATH" | awk '{ print $1 }')
else
  zip_sha256=pending
fi

mkdir -p "$(dirname -- "$output_path")"

cat >"$output_path" <<EOF
# Aegis Privileged Smoke Record

本文件由 scripts/prepare-privileged-smoke-record.sh 生成，用于在本地完整测试环境中直接补齐手工结果。完成后请把最终版本保存到 ${final_record_path}。

## Metadata

- Release tag: ${release_tag}
- Commit SHA: ${commit_sha}
- Execution date: ${execution_timestamp}
- Executor: ${executor}
- Host machine: ${host_machine}
- macOS version: ${macos_version}
- Execution environment: ${execution_environment}
- ZIP SHA256: ${zip_sha256}

## Preconditions

- Release workflow run: ${release_workflow_run}
- Privileged smoke entrypoint: ${privileged_smoke_entrypoint}
- ./scripts/validate-release.sh result: ${validate_result}

## Manual Smoke Results

- ZIP download and extraction:
  - Result:
  - Evidence:
  - Notes:
- App install to /Applications:
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

- Release readiness: Go / Go with caveats / No-Go
- Summary:
- Follow-up actions:
EOF

log "Wrote privileged smoke record draft to $output_path"