#!/usr/bin/env bash
# run_tests.sh — EC2 Ops Kit test runner
# Runs lint checks and mock-mode unit tests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; NC='\033[0m'

pass=0
fail=0
skip=0

run_test() {
  local name="$1"
  shift
  printf '  %-50s ' "$name"
  if output=$("$@" 2>&1); then
    printf '%b\n' "${GREEN}PASS${NC}"
    pass=$((pass + 1))
  else
    printf '%b\n' "${RED}FAIL${NC}"
    printf '%s\n' "$output" | head -5 | sed 's/^/    /'
    fail=$((fail + 1))
  fi
}

run_skip() {
  local name="$1" reason="$2"
  printf '  %-50s %b\n' "$name" "${YELLOW}SKIP${NC} ($reason)"
  skip=$((skip + 1))
}

printf '\n%b━━━ EC2 Ops Kit Tests ━━━%b\n\n' "$BOLD" "$NC"

# ── Lint checks ──────────────────────────────────────────────────────
printf '%b[Lint]%b\n' "$BOLD" "$NC"

if command -v shellcheck &>/dev/null; then
  for f in "$PROJECT_ROOT"/bin/ec2 "$PROJECT_ROOT"/lib/*.sh; do
    name="shellcheck $(basename "$f")"
    run_test "$name" shellcheck -x -S warning "$f"
  done
else
  run_skip "shellcheck" "not installed"
fi

printf '\n'

# ── Config parsing tests ─────────────────────────────────────────────
printf '%b[Config Parsing]%b\n' "$BOLD" "$NC"

run_test "parse_yaml basic" bash "$SCRIPT_DIR/test_config.sh" basic
run_test "parse_yaml nested" bash "$SCRIPT_DIR/test_config.sh" nested
run_test "parse_yaml comments" bash "$SCRIPT_DIR/test_config.sh" comments
run_test "parse_yaml quotes" bash "$SCRIPT_DIR/test_config.sh" quotes
run_test "load_config defaults" bash "$SCRIPT_DIR/test_config.sh" defaults

printf '\n'

# ── Preset tests ─────────────────────────────────────────────────────
printf '%b[Presets]%b\n' "$BOLD" "$NC"

run_test "preset cpu-small loads" bash "$SCRIPT_DIR/test_presets.sh" cpu-small
run_test "preset cpu-large loads" bash "$SCRIPT_DIR/test_presets.sh" cpu-large
run_test "preset gpu-t4 loads" bash "$SCRIPT_DIR/test_presets.sh" gpu-t4
run_test "preset gpu-a10 loads" bash "$SCRIPT_DIR/test_presets.sh" gpu-a10
run_test "list_presets output" bash "$SCRIPT_DIR/test_presets.sh" list
run_test "preset missing fails" bash "$SCRIPT_DIR/test_presets.sh" missing

printf '\n'

# ── CLI parsing tests ────────────────────────────────────────────────
printf '%b[CLI]%b\n' "$BOLD" "$NC"

run_test "help command" bash "$SCRIPT_DIR/test_cli.sh" help
run_test "version command" bash "$SCRIPT_DIR/test_cli.sh" version
run_test "unknown command exits 1" bash "$SCRIPT_DIR/test_cli.sh" unknown
run_test "global --profile parsing" bash "$SCRIPT_DIR/test_cli.sh" profile
run_test "global --region parsing" bash "$SCRIPT_DIR/test_cli.sh" region
run_test "global --dry-run parsing" bash "$SCRIPT_DIR/test_cli.sh" dryrun
run_test "tag builder" bash "$SCRIPT_DIR/test_cli.sh" tags
run_test "format_state coloring" bash "$SCRIPT_DIR/test_cli.sh" format_state
run_test "cost estimation" bash "$SCRIPT_DIR/test_cli.sh" cost

printf '\n'

# ── Summary ──────────────────────────────────────────────────────────
total=$((pass + fail + skip))
printf '%b━━━ Results ━━━%b\n' "$BOLD" "$NC"
printf '  Total: %d  ' "$total"
printf '%bPassed: %d%b  ' "$GREEN" "$pass" "$NC"
printf '%bFailed: %d%b  ' "$RED" "$fail" "$NC"
printf '%bSkipped: %d%b\n\n' "$YELLOW" "$skip" "$NC"

if [[ $fail -gt 0 ]]; then
  exit 1
fi
