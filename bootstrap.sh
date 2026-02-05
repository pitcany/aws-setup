#!/usr/bin/env bash
# bootstrap.sh — EC2 Ops Kit setup wizard
# Checks dependencies, guides AWS configuration, and validates setup.

set -euo pipefail

# Colors
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'
  DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ok()   { printf '  %b✓%b %s\n' "$GREEN" "$NC" "$*"; }
fail() { printf '  %b✗%b %s\n' "$RED" "$NC" "$*"; }
warn() { printf '  %b!%b %s\n' "$YELLOW" "$NC" "$*"; }

# Minimal YAML key lookup: _bs_yaml_get <file> <key>
# Searches for "key: value" anywhere (including indented), returns value.
_bs_yaml_get() {
  local file="$1" target="$2"
  local val=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*#  ]] && continue
    if [[ "$line" =~ [[:space:]]*${target}:(.+)$ ]]; then
      val="${BASH_REMATCH[1]}"
      val="${val#"${val%%[^[:space:]]*}"}"  # ltrim
      val="${val%%#*}"                       # strip inline comment
      val="${val%"${val##*[^[:space:]]}"}"  # rtrim
      # Strip matching outer quotes only
      if [[ "$val" =~ ^\"(.*)\"$ ]]; then val="${BASH_REMATCH[1]}"
      elif [[ "$val" =~ ^\'(.*)\'$ ]]; then val="${BASH_REMATCH[1]}"
      fi
      break
    fi
  done < "$file"
  printf '%s' "$val"
}
info() { printf '  %b→%b %s\n' "$BLUE" "$NC" "$*"; }

printf '\n%b━━━ EC2 Ops Kit Bootstrap ━━━%b\n\n' "$BOLD" "$NC"

errors=0

# ── 1. Check required dependencies ───────────────────────────────────
printf '%b[1/6] Checking dependencies%b\n' "$BOLD" "$NC"

# AWS CLI
if command -v aws &>/dev/null; then
  ver="$(aws --version 2>&1 | head -1)"
  ok "AWS CLI: $ver"
  # Check for v2
  if [[ "$ver" == aws-cli/2* ]]; then
    ok "AWS CLI v2 detected"
  else
    warn "AWS CLI v1 detected. v2 is recommended: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  fi
else
  fail "AWS CLI not found"
  info "Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  errors=$((errors + 1))
fi

# jq
if command -v jq &>/dev/null; then
  ok "jq: $(jq --version 2>&1)"
else
  fail "jq not found"
  info "Install: brew install jq  (macOS) or apt install jq  (Linux)"
  errors=$((errors + 1))
fi

# Python 3 (optional)
if command -v python3 &>/dev/null; then
  ok "Python 3: $(python3 --version 2>&1) (optional — enables rich output)"
  if python3 -c "import boto3" 2>/dev/null; then
    ok "boto3 available"
  else
    warn "boto3 not installed (optional): pip3 install boto3"
  fi
else
  warn "Python 3 not found (optional — kit works without it)"
fi

# shellcheck (optional)
if command -v shellcheck &>/dev/null; then
  ok "shellcheck: $(shellcheck --version 2>&1 | grep '^version:' | head -1)"
else
  warn "shellcheck not found (optional — used for lint checks)"
  info "Install: brew install shellcheck  (macOS) or apt install shellcheck  (Linux)"
fi

printf '\n'

# ── 2. Check AWS credentials ─────────────────────────────────────────
printf '%b[2/6] Checking AWS credentials%b\n' "$BOLD" "$NC"

if command -v aws &>/dev/null; then
  if aws sts get-caller-identity &>/dev/null; then
    identity="$(aws sts get-caller-identity --output json 2>/dev/null)"
    account="$(printf '%s' "$identity" | jq -r '.Account // "unknown"')"
    arn="$(printf '%s' "$identity" | jq -r '.Arn // "unknown"')"
    ok "Authenticated: $arn (account: $account)"
  else
    fail "AWS credentials not configured or expired"
    info "Run: aws configure"
    info "Or set AWS_PROFILE: export AWS_PROFILE=myprofile"
    errors=$((errors + 1))
  fi

  # List available profiles
  profiles="$(aws configure list-profiles 2>/dev/null || echo "default")"
  profile_count="$(printf '%s\n' "$profiles" | wc -l | tr -d ' ')"
  ok "Available profiles ($profile_count): $(printf '%s\n' "$profiles" | tr '\n' ' ')"
  info "Use with: ec2 --profile <name> <command>"
else
  warn "Skipping credential check (AWS CLI not installed)"
fi

printf '\n'

# ── 3. Check/create config ───────────────────────────────────────────
printf '%b[3/6] Configuration%b\n' "$BOLD" "$NC"

config_file="${SCRIPT_DIR}/config.yaml"
example_file="${SCRIPT_DIR}/config.example.yaml"

if [[ -f "$config_file" ]]; then
  ok "config.yaml exists"
else
  if [[ -f "$example_file" ]]; then
    warn "config.yaml not found"
    printf '\n'
    read -rp "  Create config.yaml from example? [Y/n] " reply
    case "$reply" in
      [nN]*) info "Skipped. Create manually: cp config.example.yaml config.yaml" ;;
      *)
        cp "$example_file" "$config_file"
        ok "Created config.yaml from example"
        info "Edit ${config_file} with your settings"
        ;;
    esac
  else
    fail "Neither config.yaml nor config.example.yaml found"
    errors=$((errors + 1))
  fi
fi

# Check for legacy .env config
if [[ -f "${SCRIPT_DIR}/config/.env" ]]; then
  warn "Legacy config/.env found. The new CLI uses config.yaml."
  info "Migrate your settings to config.yaml (see config.example.yaml)"
fi

printf '\n'

# ── 4. SSH key setup ─────────────────────────────────────────────────
printf '%b[4/6] SSH Key Setup%b\n' "$BOLD" "$NC"

if [[ -f "$config_file" ]]; then
  key_path="$(_bs_yaml_get "$config_file" "key_path")"
  key_path="${key_path/#\~/$HOME}"
  key_name="$(_bs_yaml_get "$config_file" "key_name")"
fi

: "${key_path:=$HOME/.ssh/my-ec2-key.pem}"
: "${key_name:=my-ec2-key}"

if [[ -f "$key_path" ]]; then
  ok "SSH key found: $key_path"
  perms="$(stat -f '%OLp' "$key_path" 2>/dev/null || stat -c '%a' "$key_path" 2>/dev/null || echo "unknown")"
  if [[ "$perms" == "400" || "$perms" == "600" ]]; then
    ok "Key permissions: $perms"
  else
    warn "Key permissions: $perms (should be 400 or 600)"
    info "Fix: chmod 400 $key_path"
  fi
else
  warn "SSH key not found: $key_path"
  printf '\n'
  printf '  To create a new key pair:\n'
  printf '    aws ec2 create-key-pair --key-name %s --query KeyMaterial --output text > %s\n' "$key_name" "$key_path"
  printf '    chmod 400 %s\n' "$key_path"
  printf '\n'
  printf '  Or import an existing key:\n'
  printf '    aws ec2 import-key-pair --key-name %s --public-key-material fileb://~/.ssh/id_rsa.pub\n' "$key_name"
fi

printf '\n'

# ── 5. Security group check ──────────────────────────────────────────
printf '%b[5/6] Security Group%b\n' "$BOLD" "$NC"

if [[ -f "$config_file" ]]; then
  sg_id="$(grep 'group_id:' "$config_file" 2>/dev/null | head -1 | sed 's/.*group_id:[[:space:]]*//' | sed 's/#.*//' | tr -d '"' | tr -d "'" | xargs)"
fi

: "${sg_id:=}"

if [[ -n "$sg_id" && "$sg_id" != "sg-REPLACE_ME" ]]; then
  if command -v aws &>/dev/null && aws sts get-caller-identity &>/dev/null; then
    if aws ec2 describe-security-groups --group-ids "$sg_id" &>/dev/null; then
      ok "Security group exists: $sg_id"
      # Check for SSH rule
      ssh_rules="$(aws ec2 describe-security-groups --group-ids "$sg_id" \
        --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]' --output text 2>/dev/null || echo "")"
      if [[ -n "$ssh_rules" ]]; then
        ok "SSH (port 22) rule found"
      else
        warn "No SSH (port 22) rule found in $sg_id"
        info "Run: ./scripts/setup-security-group.sh"
      fi
    else
      fail "Security group $sg_id not found"
      errors=$((errors + 1))
    fi
  else
    warn "Cannot validate security group (no AWS credentials)"
  fi
else
  warn "Security group not configured in config.yaml"
  info "Set security.group_id or run: ./scripts/setup-security-group.sh"
fi

printf '\n'

# ── 6. Required IAM permissions ──────────────────────────────────────
printf '%b[6/6] Required IAM Permissions%b\n' "$BOLD" "$NC"
cat <<'PERMS'
  The following IAM permissions are needed (least-privilege):

  ec2:DescribeInstances          (list, info, ssh, cleanup)
  ec2:RunInstances               (up)
  ec2:StartInstances             (start)
  ec2:StopInstances              (stop)
  ec2:TerminateInstances         (terminate)
  ec2:CreateTags                 (up, eip alloc)
  ec2:DescribeImages             (up — AMI auto-detection)
  ec2:DescribeAddresses          (eip list, cleanup)
  ec2:AllocateAddress            (eip alloc)
  ec2:AssociateAddress           (eip assoc)
  ec2:DisassociateAddress        (eip disassoc)
  ec2:ReleaseAddress             (eip release)
  ec2:DescribeVolumes            (cleanup)
  ec2:CreateVolume               (up --volume)
  ec2:AttachVolume               (up --volume)
  ec2:DeleteVolume               (cleanup --delete-volumes)
  ec2:DescribeSpotInstanceRequests  (spot list)
  ec2:DescribeSpotPriceHistory   (spot prices)
  ec2:CancelSpotInstanceRequests (spot cancel)
  ec2:DescribeSecurityGroups     (bootstrap validation)
  sts:GetCallerIdentity          (auth check)

  Recommended: Create an IAM policy with these permissions
  and attach it to your IAM user or role.

PERMS

printf '\n'

# ── Summary ───────────────────────────────────────────────────────────
printf '%b━━━ Summary ━━━%b\n\n' "$BOLD" "$NC"

if [[ $errors -gt 0 ]]; then
  printf '  %b%d issue(s) found. Fix the above errors before using the kit.%b\n\n' "$RED" "$errors" "$NC"
  exit 1
else
  printf '  %bAll checks passed! You are ready to go.%b\n\n' "$GREEN" "$NC"
  printf '  Quick start:\n'
  printf '    %b./bin/ec2 help%b              Show all commands\n' "$CYAN" "$NC"
  printf '    %b./bin/ec2 list%b              List your instances\n' "$CYAN" "$NC"
  printf '    %b./bin/ec2 presets%b           Show available presets\n' "$CYAN" "$NC"
  printf '    %b./bin/ec2 up --preset cpu-small --name dev%b\n' "$CYAN" "$NC"
  printf '\n'
fi
