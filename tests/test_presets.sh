#!/usr/bin/env bash
# test_presets.sh — Unit tests for preset loading
# Usage: test_presets.sh <test-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export EC2_ROOT="$PROJECT_ROOT"
export EC2_MOCK="true"
source "${PROJECT_ROOT}/lib/core.sh"

test_name="${1:-}"

case "$test_name" in
  cpu-small)
    load_preset "cpu-small"
    [[ "$PRESET_INSTANCE_TYPE" == "t3.medium" ]] || { echo "FAIL: type=$PRESET_INSTANCE_TYPE"; exit 1; }
    [[ "$PRESET_VOLUME_SIZE" == "20" ]] || { echo "FAIL: vol=$PRESET_VOLUME_SIZE"; exit 1; }
    [[ "$PRESET_SSH_USER" == "ubuntu" ]] || { echo "FAIL: user=$PRESET_SSH_USER"; exit 1; }
    [[ "$PRESET_SPOT_FRIENDLY" == "true" ]] || { echo "FAIL: spot=$PRESET_SPOT_FRIENDLY"; exit 1; }
    ;;

  cpu-large)
    load_preset "cpu-large"
    [[ "$PRESET_INSTANCE_TYPE" == "c5.2xlarge" ]] || { echo "FAIL: type=$PRESET_INSTANCE_TYPE"; exit 1; }
    [[ "$PRESET_VOLUME_SIZE" == "100" ]] || { echo "FAIL: vol=$PRESET_VOLUME_SIZE"; exit 1; }
    ;;

  gpu-t4)
    load_preset "gpu-t4"
    [[ "$PRESET_INSTANCE_TYPE" == "g4dn.xlarge" ]] || { echo "FAIL: type=$PRESET_INSTANCE_TYPE"; exit 1; }
    [[ "$PRESET_VOLUME_SIZE" == "100" ]] || { echo "FAIL: vol=$PRESET_VOLUME_SIZE"; exit 1; }
    [[ -n "$PRESET_AMI_PATTERN" ]] || { echo "FAIL: ami_pattern empty"; exit 1; }
    ;;

  gpu-a10)
    load_preset "gpu-a10"
    [[ "$PRESET_INSTANCE_TYPE" == "g5.xlarge" ]] || { echo "FAIL: type=$PRESET_INSTANCE_TYPE"; exit 1; }
    [[ "$PRESET_VOLUME_SIZE" == "200" ]] || { echo "FAIL: vol=$PRESET_VOLUME_SIZE"; exit 1; }
    ;;

  list)
    output="$(list_presets 2>&1)"
    echo "$output" | grep -q "cpu-small" || { echo "FAIL: cpu-small not in list"; exit 1; }
    echo "$output" | grep -q "gpu-t4" || { echo "FAIL: gpu-t4 not in list"; exit 1; }
    ;;

  missing)
    # Should fail for nonexistent preset
    # Run in subshell because die() calls exit 1
    if (load_preset "nonexistent-preset-xyz" 2>/dev/null); then
      echo "FAIL: should have failed for missing preset"
      exit 1
    fi
    # Expected: exit 1 from die() in subshell
    ;;

  *)
    echo "Unknown test: $test_name"
    exit 1
    ;;
esac
