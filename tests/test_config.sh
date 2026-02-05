#!/usr/bin/env bash
# test_config.sh — Unit tests for YAML config parsing
# Usage: test_config.sh <test-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source core library (sets up parse_yaml and friends)
export EC2_ROOT="$PROJECT_ROOT"
export EC2_MOCK="true"
source "${PROJECT_ROOT}/lib/core.sh"

TMPDIR="${TMPDIR:-/tmp}"
tmp_file="${TMPDIR}/ec2_test_$$.yaml"
trap 'rm -f "$tmp_file"' EXIT

test_name="${1:-}"

case "$test_name" in
  basic)
    cat > "$tmp_file" <<'YAML'
name: test-value
instance_type: t3.medium
volume_size: 20
YAML
    result="$(parse_yaml "$tmp_file")"
    echo "$result" | grep -q "name=test-value" || { echo "FAIL: name"; exit 1; }
    echo "$result" | grep -q "instance_type=t3.medium" || { echo "FAIL: instance_type"; exit 1; }
    echo "$result" | grep -q "volume_size=20" || { echo "FAIL: volume_size"; exit 1; }
    ;;

  nested)
    cat > "$tmp_file" <<'YAML'
aws:
  profile: myprofile
  region: eu-west-1
ssh:
  key_path: ~/.ssh/test.pem
YAML
    result="$(parse_yaml "$tmp_file")"
    echo "$result" | grep -q "aws_profile=myprofile" || { echo "FAIL: aws_profile"; exit 1; }
    echo "$result" | grep -q "aws_region=eu-west-1" || { echo "FAIL: aws_region"; exit 1; }
    echo "$result" | grep -q "ssh_key_path=~/.ssh/test.pem" || { echo "FAIL: ssh_key_path"; exit 1; }
    ;;

  comments)
    cat > "$tmp_file" <<'YAML'
# This is a comment
name: value1
# Another comment
type: value2
YAML
    result="$(parse_yaml "$tmp_file")"
    # Should have exactly 2 lines
    count="$(echo "$result" | wc -l | tr -d ' ')"
    [[ "$count" == "2" ]] || { echo "FAIL: expected 2 lines, got $count"; exit 1; }
    echo "$result" | grep -q "name=value1" || { echo "FAIL: name"; exit 1; }
    echo "$result" | grep -q "type=value2" || { echo "FAIL: type"; exit 1; }
    ;;

  quotes)
    cat > "$tmp_file" <<'YAML'
desc: "hello world"
path: '/home/user/.ssh/key.pem'
bare: no-quotes
YAML
    result="$(parse_yaml "$tmp_file")"
    echo "$result" | grep -q "desc=hello world" || { echo "FAIL: double quotes"; exit 1; }
    echo "$result" | grep -q "path=/home/user/.ssh/key.pem" || { echo "FAIL: single quotes"; exit 1; }
    echo "$result" | grep -q "bare=no-quotes" || { echo "FAIL: bare value"; exit 1; }
    ;;

  defaults)
    # Test load_config with no config file (uses defaults)
    EC2_CONFIG_FILE="/nonexistent/config.yaml"
    load_config
    [[ "$CFG_AWS_REGION" == "us-west-2" ]] || { echo "FAIL: default region=$CFG_AWS_REGION"; exit 1; }
    [[ "$CFG_TAG_PROJECT" == "aws-setup" ]] || { echo "FAIL: default project=$CFG_TAG_PROJECT"; exit 1; }
    ;;

  *)
    echo "Unknown test: $test_name"
    exit 1
    ;;
esac
