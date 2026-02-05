#!/usr/bin/env bash
# test_cli.sh — Unit tests for CLI parsing and utilities
# Usage: test_cli.sh <test-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export EC2_ROOT="$PROJECT_ROOT"
export EC2_MOCK="true"
source "${PROJECT_ROOT}/lib/core.sh"

test_name="${1:-}"

case "$test_name" in
  help)
    output="$("$PROJECT_ROOT/bin/ec2" help 2>&1)" || true
    echo "$output" | grep -qi "EC2 Ops Kit" || { echo "FAIL: help missing title"; exit 1; }
    echo "$output" | grep -q "list" || { echo "FAIL: help missing list cmd"; exit 1; }
    echo "$output" | grep -q "ssh" || { echo "FAIL: help missing ssh cmd"; exit 1; }
    echo "$output" | grep -q "cleanup" || { echo "FAIL: help missing cleanup cmd"; exit 1; }
    ;;

  version)
    output="$("$PROJECT_ROOT/bin/ec2" --version 2>&1)"
    echo "$output" | grep -q "ec2 ops kit v" || { echo "FAIL: version output"; exit 1; }
    ;;

  unknown)
    # Unknown command should exit non-zero
    if "$PROJECT_ROOT/bin/ec2" --mock xyznotacommand &>/dev/null; then
      echo "FAIL: unknown command should exit non-zero"
      exit 1
    fi
    ;;

  profile)
    # Test that --profile flag is parsed
    EC2_PROFILE="test-profile"
    load_config
    [[ "$CFG_AWS_PROFILE" == "test-profile" ]] || { echo "FAIL: profile=$CFG_AWS_PROFILE"; exit 1; }
    ;;

  region)
    EC2_REGION="ap-southeast-1"
    load_config
    [[ "$CFG_AWS_REGION" == "ap-southeast-1" ]] || { echo "FAIL: region=$CFG_AWS_REGION"; exit 1; }
    ;;

  dryrun)
    EC2_DRY_RUN="true"
    # dry_run_guard should return 1 (preventing action)
    if dry_run_guard "test action" 2>/dev/null; then
      echo "FAIL: dry_run_guard should return 1"
      exit 1
    fi
    ;;

  tags)
    CFG_TAG_PROJECT="test-project"
    CFG_TAG_OWNER="testuser"
    CFG_TAG_COST_CENTER=""
    CFG_DEFAULT_TTL_HOURS="0"

    tags="$(build_tags "my-instance" "")"
    echo "$tags" | grep -q "Name,Value=my-instance" || { echo "FAIL: Name tag"; exit 1; }
    echo "$tags" | grep -q "Project,Value=test-project" || { echo "FAIL: Project tag"; exit 1; }
    echo "$tags" | grep -q "Owner,Value=testuser" || { echo "FAIL: Owner tag"; exit 1; }
    echo "$tags" | grep -q "ManagedBy,Value=ec2-ops-kit" || { echo "FAIL: ManagedBy tag"; exit 1; }
    ;;

  format_state)
    # Test that format_state produces output for each state
    for state in running stopped terminated pending stopping; do
      result="$(format_state "$state")"
      [[ -n "$result" ]] || { echo "FAIL: empty output for $state"; exit 1; }
    done
    ;;

  cost)
    # Test cost estimation
    cost="$(estimate_cost "t3.medium" 10)"
    [[ "$cost" == "0.42" ]] || { echo "FAIL: t3.medium 10h = $cost (expected 0.42)"; exit 1; }

    cost="$(estimate_cost "g4dn.xlarge" 1)"
    [[ "$cost" == "0.53" ]] || { echo "FAIL: g4dn.xlarge 1h = $cost (expected 0.53)"; exit 1; }

    # Unknown type should return empty
    cost="$(estimate_cost "x99.unknown" 1)"
    [[ -z "$cost" ]] || { echo "FAIL: unknown type should return empty, got $cost"; exit 1; }
    ;;

  *)
    echo "Unknown test: $test_name"
    exit 1
    ;;
esac
