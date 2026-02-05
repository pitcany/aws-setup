#!/usr/bin/env bash
# core.sh — Shared utilities for EC2 Ops Kit
# Sourced by bin/ec2; do not run directly.

# ── Colors ────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'
  DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

# ── Logging ───────────────────────────────────────────────────────────
log()   { printf '%b\n' "${GREEN}[ok]${NC} $*"; }
warn()  { printf '%b\n' "${YELLOW}[warn]${NC} $*" >&2; }
err()   { printf '%b\n' "${RED}[error]${NC} $*" >&2; }
die()   { err "$@"; exit 1; }
info()  { printf '%b\n' "${BLUE}[info]${NC} $*"; }
debug() {
  if [[ "${EC2_DEBUG:-0}" == "1" ]]; then
    printf '%b\n' "${DIM}[debug] $*${NC}" >&2
  fi
}

# ── Global state ──────────────────────────────────────────────────────
EC2_ROOT="${EC2_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
EC2_DRY_RUN="${EC2_DRY_RUN:-false}"
EC2_YES="${EC2_YES:-false}"
EC2_PROFILE="${EC2_PROFILE:-}"
EC2_REGION="${EC2_REGION:-}"
EC2_CONFIG_FILE="${EC2_CONFIG_FILE:-}"
EC2_MOCK="${EC2_MOCK:-false}"

# Resolved config values (populated by load_config)
CFG_AWS_PROFILE="default"
CFG_AWS_REGION="us-west-2"
CFG_SSH_KEY_PATH=""
CFG_SSH_KEY_NAME=""
CFG_SSH_DEFAULT_USER="ubuntu"
CFG_SSH_BASTION_HOST=""
CFG_SSH_BASTION_USER=""
CFG_SSH_BASTION_KEY_PATH=""
CFG_SECURITY_GROUP_ID=""
CFG_SUBNET_ID=""
CFG_TAG_PROJECT="aws-setup"
CFG_TAG_OWNER=""
CFG_TAG_COST_CENTER=""
CFG_DEFAULT_TTL_HOURS="0"
CFG_DEFAULT_VOLUME_TYPE="gp3"
CFG_DEFAULT_CPU_AMI=""
CFG_DEFAULT_GPU_AMI=""

# ── Simple YAML parser ───────────────────────────────────────────────
# Handles one level of nesting: section:\n  key: value
# Returns lines like: section_key=value
parse_yaml() {
  local file="$1"
  local section=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip trailing carriage return (Windows line endings)
    line="${line%$'\r'}"
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # Remove inline comments (but not inside quotes)
    if [[ ! "$line" =~ \" && ! "$line" =~ \' ]]; then
      line="${line%%#*}"
    fi
    # Trim trailing whitespace
    line="${line%"${line##*[^[:space:]]}"}"

    # Section header: "key:" with nothing after (or only whitespace)
    if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):$ ]] || \
       [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
      section="${BASH_REMATCH[1]}"
      continue
    fi

    # Indented key: value (part of a section)
    if [[ "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*):(.+)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      val="${val#"${val%%[^[:space:]]*}"}" # ltrim
      val="${val%"${val##*[^[:space:]]}"}" # rtrim
      # Strip surrounding quotes
      val="${val#\"}"; val="${val%\"}"
      val="${val#\'}"; val="${val%\'}"
      if [[ -n "$section" ]]; then
        printf '%s\n' "${section}_${key}=${val}"
      fi
      continue
    fi

    # Top-level key: value
    if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):(.+)$ ]]; then
      section=""
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      val="${val#"${val%%[^[:space:]]*}"}"
      val="${val%"${val##*[^[:space:]]}"}"
      val="${val#\"}"; val="${val%\"}"
      val="${val#\'}"; val="${val%\'}"
      printf '%s\n' "${key}=${val}"
      continue
    fi
  done < "$file"
}

# ── Config loading ────────────────────────────────────────────────────
load_config() {
  local config_file="${EC2_CONFIG_FILE:-}"
  if [[ -z "$config_file" ]]; then
    config_file="${EC2_ROOT}/config.yaml"
  fi

  if [[ ! -f "$config_file" ]]; then
    debug "No config.yaml found at $config_file — using defaults"
    _apply_defaults
    return 0
  fi

  debug "Loading config from $config_file"
  local parsed
  parsed="$(parse_yaml "$config_file")"

  _cfg_get() {
    local key="$1" default="${2:-}"
    local val
    val="$(printf '%s\n' "$parsed" | while IFS='=' read -r k v; do
      [[ "$k" == "$key" ]] && printf '%s' "$v" && break
    done)"
    printf '%s' "${val:-$default}"
  }

  CFG_AWS_PROFILE="$(_cfg_get aws_profile "default")"
  CFG_AWS_REGION="$(_cfg_get aws_region "us-west-2")"
  CFG_SSH_KEY_PATH="$(_cfg_get ssh_key_path "")"
  CFG_SSH_KEY_NAME="$(_cfg_get ssh_key_name "")"
  CFG_SSH_DEFAULT_USER="$(_cfg_get ssh_default_user "ubuntu")"
  CFG_SSH_BASTION_HOST="$(_cfg_get ssh_bastion_host "")"
  CFG_SSH_BASTION_USER="$(_cfg_get ssh_bastion_user "")"
  CFG_SSH_BASTION_KEY_PATH="$(_cfg_get ssh_bastion_key_path "")"
  CFG_SECURITY_GROUP_ID="$(_cfg_get security_group_id "")"
  CFG_SUBNET_ID="$(_cfg_get security_subnet_id "")"
  CFG_TAG_PROJECT="$(_cfg_get tags_Project "aws-setup")"
  CFG_TAG_OWNER="$(_cfg_get tags_Owner "me")"
  CFG_TAG_COST_CENTER="$(_cfg_get tags_CostCenter "")"
  CFG_DEFAULT_TTL_HOURS="$(_cfg_get defaults_ttl_hours "0")"
  CFG_DEFAULT_VOLUME_TYPE="$(_cfg_get defaults_volume_type "gp3")"
  CFG_DEFAULT_CPU_AMI="$(_cfg_get defaults_cpu_ami_id "")"
  CFG_DEFAULT_GPU_AMI="$(_cfg_get defaults_gpu_ami_id "")"

  unset -f _cfg_get
  _apply_defaults
}

_apply_defaults() {
  # CLI flags override config
  if [[ -n "$EC2_PROFILE" ]]; then CFG_AWS_PROFILE="$EC2_PROFILE"; fi
  if [[ -n "$EC2_REGION" ]]; then CFG_AWS_REGION="$EC2_REGION"; fi
  # Discover owner from whoami / AWS caller if not set
  if [[ -z "$CFG_TAG_OWNER" || "$CFG_TAG_OWNER" == "me" ]]; then
    CFG_TAG_OWNER="$(whoami 2>/dev/null || echo "me")"
  fi
}

# ── Preset loading ────────────────────────────────────────────────────
load_preset() {
  local preset_name="$1"
  local preset_file="${EC2_ROOT}/presets/${preset_name}.yaml"
  if [[ ! -f "$preset_file" ]]; then
    die "Preset not found: $preset_name (looked in ${EC2_ROOT}/presets/)"
  fi

  local parsed
  parsed="$(parse_yaml "$preset_file")"

  _preset_get() {
    local key="$1" default="${2:-}"
    local val
    val="$(printf '%s\n' "$parsed" | while IFS='=' read -r k v; do
      [[ "$k" == "$key" ]] && printf '%s' "$v" && break
    done)"
    printf '%s' "${val:-$default}"
  }

  PRESET_NAME="$(_preset_get name "$preset_name")"
  PRESET_DESC="$(_preset_get description "")"
  PRESET_INSTANCE_TYPE="$(_preset_get instance_type "t3.medium")"
  PRESET_AMI_PATTERN="$(_preset_get ami_pattern "")"
  PRESET_AMI_OWNER="$(_preset_get ami_owner "099720109477")"
  PRESET_AMI_ID="$(_preset_get ami_id "")"
  PRESET_VOLUME_SIZE="$(_preset_get volume_size "20")"
  PRESET_ROOT_DEVICE="$(_preset_get root_device "/dev/sda1")"
  PRESET_SSH_USER="$(_preset_get ssh_user "ubuntu")"
  PRESET_SPOT_FRIENDLY="$(_preset_get spot_friendly "false")"
  PRESET_COST_PER_HOUR="$(_preset_get cost_per_hour "")"
  PRESET_POST_LAUNCH_HINT="$(_preset_get post_launch_hint "")"

  unset -f _preset_get
}

list_presets() {
  local dir="${EC2_ROOT}/presets"
  if [[ ! -d "$dir" ]]; then
    die "Presets directory not found: $dir"
  fi
  for f in "$dir"/*.yaml; do
    [[ -f "$f" ]] || continue
    local name desc itype parsed_data
    name="$(basename "$f" .yaml)"
    parsed_data="$(parse_yaml "$f")"
    desc="$(printf '%s\n' "$parsed_data" | while IFS='=' read -r k v; do
      if [[ "$k" == "description" ]]; then printf '%s' "$v"; break; fi
    done)"
    itype="$(printf '%s\n' "$parsed_data" | while IFS='=' read -r k v; do
      if [[ "$k" == "instance_type" ]]; then printf '%s' "$v"; break; fi
    done)"
    printf "  ${CYAN}%-14s${NC} %-14s %s\n" "$name" "$itype" "$desc"
  done
}

# ── AWS CLI helpers ───────────────────────────────────────────────────
aws_cmd() {
  # Build the base aws command with profile/region
  local cmd=(aws)
  if [[ -n "$CFG_AWS_PROFILE" && "$CFG_AWS_PROFILE" != "default" ]]; then
    cmd+=(--profile "$CFG_AWS_PROFILE")
  fi
  if [[ -n "$CFG_AWS_REGION" ]]; then
    cmd+=(--region "$CFG_AWS_REGION")
  fi
  "${cmd[@]}" "$@"
}

# Print the active profile + region header on every invocation
print_context() {
  local profile="${CFG_AWS_PROFILE:-default}"
  local region="${CFG_AWS_REGION:-us-west-2}"
  printf '%b\n' "${DIM}aws profile=${BOLD}${profile}${NC}${DIM}  region=${BOLD}${region}${NC}"
}

check_aws_cli() {
  if ! command -v aws &>/dev/null; then
    die "AWS CLI not found. Install: https://aws.amazon.com/cli/"
  fi
  if ! command -v jq &>/dev/null; then
    die "jq not found. Install: https://stedolan.github.io/jq/download/"
  fi
}

check_auth() {
  if [[ "$EC2_MOCK" == "true" ]]; then
    debug "Mock mode — skipping auth check"
    return 0
  fi
  if ! aws_cmd sts get-caller-identity &>/dev/null; then
    die "AWS credentials not configured or expired. Run: aws configure"
  fi
}

# ── Safety helpers ────────────────────────────────────────────────────
confirm() {
  local msg="${1:-Are you sure?}"
  if [[ "$EC2_YES" == "true" ]]; then
    return 0
  fi
  printf '%b ' "${YELLOW}${msg} [y/N]${NC}"
  local reply
  read -r reply
  case "$reply" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

dry_run_guard() {
  if [[ "$EC2_DRY_RUN" == "true" ]]; then
    info "${DIM}[dry-run]${NC} Would execute: $*"
    return 1
  fi
  return 0
}

# ── Instance resolution ──────────────────────────────────────────────
# Resolve a name-or-id to instance ID(s). Returns tab-separated:
#   instance_id  name  state  instance_type  public_ip  private_ip
resolve_instance() {
  local identifier="$1"
  local filter

  if [[ "$identifier" == i-* ]]; then
    # Looks like an instance ID
    filter="Name=instance-id,Values=${identifier}"
  else
    # Treat as a Name tag
    filter="Name=tag:Name,Values=${identifier}"
  fi

  aws_cmd ec2 describe-instances \
    --filters "$filter" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].[InstanceId, (Tags[?Key==`Name`].Value)[0], State.Name, InstanceType, PublicIpAddress, PrivateIpAddress]' \
    --output text 2>/dev/null || true
}

# Resolve to exactly one instance or die
resolve_one_instance() {
  local identifier="$1"
  local results
  results="$(resolve_instance "$identifier")"

  if [[ -z "$results" ]]; then
    die "No instance found matching '$identifier'"
  fi

  local count
  count="$(printf '%s\n' "$results" | wc -l | tr -d ' ')"
  if [[ "$count" -gt 1 ]]; then
    warn "Multiple instances match '$identifier':"
    printf '%s\n' "$results" | while IFS=$'\t' read -r id name state itype pip prip; do
      printf "  %-20s %-19s %-10s %-14s %s\n" "${name:-<unnamed>}" "$id" "$state" "$itype" "${pip:-$prip}"
    done
    die "Please specify the instance ID directly."
  fi

  printf '%s' "$results"
}

# ── SSH key validation ────────────────────────────────────────────────
resolve_ssh_key() {
  local key_path="${1:-$CFG_SSH_KEY_PATH}"
  # Expand ~
  key_path="${key_path/#\~/$HOME}"

  if [[ -z "$key_path" ]]; then
    die "SSH key path not configured. Set ssh.key_path in config.yaml"
  fi
  if [[ ! -f "$key_path" ]]; then
    die "SSH key not found: $key_path"
  fi

  # Check permissions (warn, don't die)
  local perms
  perms="$(stat -f '%OLp' "$key_path" 2>/dev/null || stat -c '%a' "$key_path" 2>/dev/null || echo "unknown")"
  if [[ "$perms" != "600" && "$perms" != "400" && "$perms" != "unknown" ]]; then
    warn "SSH key $key_path has permissions $perms (expected 400 or 600)"
  fi

  printf '%s' "$key_path"
}

# ── AMI resolution ───────────────────────────────────────────────────
resolve_ami() {
  local ami_id="$1"
  local pattern="$2"
  local owner="$3"

  # If explicit ID provided and not placeholder, use it
  if [[ -n "$ami_id" && "$ami_id" != "" && "$ami_id" != "ami-xxxxxxxx" ]]; then
    printf '%s' "$ami_id"
    return 0
  fi

  if [[ -z "$pattern" ]]; then
    die "No AMI ID or pattern specified"
  fi

  info "Auto-detecting AMI: ${pattern}..."

  local owner_args=(--owners "$owner")

  local ami
  ami="$(aws_cmd ec2 describe-images \
    "${owner_args[@]}" \
    --filters "Name=name,Values=${pattern}" "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text 2>/dev/null || echo "None")"

  if [[ "$ami" == "None" || -z "$ami" ]]; then
    die "Could not find AMI matching pattern: $pattern"
  fi

  info "Found AMI: $ami"
  printf '%s' "$ami"
}

# ── Tag builder ──────────────────────────────────────────────────────
build_tags() {
  local name="$1"
  local ttl="${2:-$CFG_DEFAULT_TTL_HOURS}"

  local tags="Key=Name,Value=${name}"
  tags="${tags} Key=Project,Value=${CFG_TAG_PROJECT}"
  tags="${tags} Key=Owner,Value=${CFG_TAG_OWNER}"
  tags="${tags} Key=ManagedBy,Value=ec2-ops-kit"

  if [[ -n "$ttl" && "$ttl" != "0" ]]; then
    tags="${tags} Key=TTLHours,Value=${ttl}"
    # Compute expiry timestamp
    local now
    now="$(date -u +%s 2>/dev/null || date +%s)"
    local expiry=$((now + ttl * 3600))
    local expiry_iso
    expiry_iso="$(date -u -r "$expiry" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
                  date -u -d "@$expiry" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "")"
    if [[ -n "$expiry_iso" ]]; then
      tags="${tags} Key=ExpiresAt,Value=${expiry_iso}"
    fi
  fi

  if [[ -n "$CFG_TAG_COST_CENTER" ]]; then
    tags="${tags} Key=CostCenter,Value=${CFG_TAG_COST_CENTER}"
  fi

  printf '%s' "$tags"
}

# Build --tag-specifications JSON for run-instances
build_tag_spec() {
  local name="$1"
  local ttl="${2:-$CFG_DEFAULT_TTL_HOURS}"
  local resource_type="${3:-instance}"

  local tag_pairs
  tag_pairs="{Key=Name,Value=${name}}"
  tag_pairs="${tag_pairs},{Key=Project,Value=${CFG_TAG_PROJECT}}"
  tag_pairs="${tag_pairs},{Key=Owner,Value=${CFG_TAG_OWNER}}"
  tag_pairs="${tag_pairs},{Key=ManagedBy,Value=ec2-ops-kit}"

  if [[ -n "$ttl" && "$ttl" != "0" ]]; then
    tag_pairs="${tag_pairs},{Key=TTLHours,Value=${ttl}}"
  fi
  if [[ -n "$CFG_TAG_COST_CENTER" ]]; then
    tag_pairs="${tag_pairs},{Key=CostCenter,Value=${CFG_TAG_COST_CENTER}}"
  fi

  printf 'ResourceType=%s,Tags=[%s]' "$resource_type" "$tag_pairs"
}

# ── Cost helpers ──────────────────────────────────────────────────────
estimate_cost() {
  local instance_type="$1"
  local hours="${2:-1}"
  local rate=""

  # Try to find rate from config costs section
  local config_file="${EC2_CONFIG_FILE:-${EC2_ROOT}/config.yaml}"
  if [[ -f "$config_file" ]]; then
    local sanitized="${instance_type//./_}"
    rate="$(parse_yaml "$config_file" | while IFS='=' read -r k v; do
      [[ "$k" == "costs_${sanitized}" ]] && printf '%s' "$v" && break
    done)"
  fi

  if [[ -z "$rate" ]]; then
    # Hardcoded fallback for common types
    case "$instance_type" in
      t3.micro)    rate="0.0104" ;;
      t3.small)    rate="0.0208" ;;
      t3.medium)   rate="0.0416" ;;
      t3.large)    rate="0.0832" ;;
      c5.xlarge)   rate="0.17" ;;
      c5.2xlarge)  rate="0.34" ;;
      g4dn.xlarge) rate="0.526" ;;
      g5.xlarge)   rate="1.006" ;;
      g5.2xlarge)  rate="1.212" ;;
      p3.2xlarge)  rate="3.06" ;;
      *)           rate="" ;;
    esac
  fi

  if [[ -n "$rate" ]]; then
    # Use awk for floating-point math (POSIX)
    local total
    total="$(awk "BEGIN { printf \"%.2f\", $rate * $hours }")"
    printf '%s' "$total"
  fi
}

# ── Formatting helpers ────────────────────────────────────────────────
format_state() {
  local state="$1"
  case "$state" in
    running)     printf '%b' "${GREEN}running${NC}" ;;
    stopped)     printf '%b' "${RED}stopped${NC}" ;;
    terminated)  printf '%b' "${DIM}terminated${NC}" ;;
    pending)     printf '%b' "${YELLOW}pending${NC}" ;;
    stopping)    printf '%b' "${YELLOW}stopping${NC}" ;;
    *)           printf '%s' "$state" ;;
  esac
}

# Wait for an instance to reach a target state
wait_for_state() {
  local instance_id="$1"
  local target="$2"  # running, stopped, terminated
  local max_wait="${3:-120}"

  info "Waiting for $instance_id to reach '$target' state..."
  local elapsed=0
  while [[ $elapsed -lt $max_wait ]]; do
    local current
    current="$(aws_cmd ec2 describe-instances \
      --instance-ids "$instance_id" \
      --query 'Reservations[0].Instances[0].State.Name' \
      --output text 2>/dev/null || echo "unknown")"

    if [[ "$current" == "$target" ]]; then
      log "Instance $instance_id is now $target"
      return 0
    fi
    printf '.' >&2
    sleep 5
    elapsed=$((elapsed + 5))
  done
  printf '\n' >&2
  warn "Timed out waiting for $instance_id to reach $target (current: $current)"
  return 1
}

# Wait for public IP
wait_for_ip() {
  local instance_id="$1"
  local max_attempts="${2:-24}"

  local attempt=0
  while [[ $attempt -lt $max_attempts ]]; do
    local ip
    ip="$(aws_cmd ec2 describe-instances \
      --instance-ids "$instance_id" \
      --query 'Reservations[0].Instances[0].PublicIpAddress' \
      --output text 2>/dev/null || echo "None")"

    if [[ -n "$ip" && "$ip" != "None" ]]; then
      printf '%s' "$ip"
      return 0
    fi
    printf '.' >&2
    sleep 5
    attempt=$((attempt + 1))
  done
  printf '\n' >&2
  return 1
}
