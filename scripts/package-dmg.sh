#!/bin/sh
set -eu

printf '%s\n' '[aegis-release] error: scripts/package-dmg.sh is disabled. Phase-6 release artifacts are AegisApp.app and AegisApp.zip only.' >&2
exit 1
