#!/bin/zsh
# Runs SwiftLint over the Swift sources/tests using .swiftlint.yml.
#
# SwiftLint is optional locally: if it isn't installed we print a hint and exit 0
# so a fresh clone can still run the harness. CI installs SwiftLint (see
# .github/workflows/ci.yml) and enforces it for real. To force a hard failure
# when the binary is missing (e.g. in CI), set OPEN_ISLAND_REQUIRE_SWIFTLINT=1.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if ! command -v swiftlint >/dev/null 2>&1; then
    if [[ "${OPEN_ISLAND_REQUIRE_SWIFTLINT:-0}" == "1" ]]; then
        echo "FAIL: swiftlint not installed but OPEN_ISLAND_REQUIRE_SWIFTLINT=1" >&2
        exit 1
    fi
    echo "swiftlint not installed — skipping Swift lint (install: brew install swiftlint)"
    exit 0
fi

# --strict promotes warnings to errors so the configured rules act as a gate.
swiftlint lint --strict --quiet
