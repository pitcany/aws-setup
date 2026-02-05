# Bash Patterns Reference

## Contents
- Error Handling
- Array Construction
- String Manipulation
- Process Substitution and Subshells
- Portable Date Handling
- Color Output with TTY Detection
- Argument Validation

## Error Handling

### set -euo pipefail

Every script starts with this. `set -e` exits on error, `-u` catches unset variables, `-o pipefail` catches failures in pipes.

```bash
set -euo pipefail
```

### WARNING: Removing pipefail

**The Problem:**

```bash
# BAD — silently swallows pipe failures
set -eo
result="$(aws ec2 describe-instances | jq '.[]')"  # jq error hidden
```

**Why This Breaks:** Without `pipefail`, only the last command's exit code matters. If `aws` succeeds but `jq` fails, the pipeline reports success. You get empty or corrupt data with no error.

**The Fix:**

```bash
set -euo pipefail
result="$(aws ec2 describe-instances | jq '.[]')" || die "Failed to query instances"
```

### die vs warn vs err

```bash
# Fatal — stops execution
die "Security group not configured. Set security.group_id in config.yaml"

# Non-fatal warning — continues execution
warn "SSH key permissions $perms (expected 400 or 600)"

# Error message without exit — use when caller handles the failure
err "Unknown command: $COMMAND"
```

### Guard Clauses for State Checks

Check preconditions early and exit. Prevents deep nesting.

```bash
# GOOD — guard clause pattern from cmd_instances.sh
cmd_start() {
  local identifier="${1:-}"
  if [[ -z "$identifier" ]]; then
    die "Usage: ec2 start <name|instance-id>"
  fi

  local line
  line="$(resolve_one_instance "$identifier" "--all")"
  local id name state
  IFS=$'\t' read -r id name state _ _ _ <<< "$line"

  if [[ "$state" == "running" ]]; then
    info "$name ($id) is already running."
    return 0
  fi
  if [[ "$state" != "stopped" ]]; then
    die "Cannot start instance in state: $state"
  fi
  # ... proceed with start
}
```

```bash
# BAD — deep nesting
cmd_start() {
  if [[ -n "$identifier" ]]; then
    local line="$(resolve_one_instance "$identifier")"
    if [[ -n "$line" ]]; then
      if [[ "$state" == "stopped" ]]; then
        # actual work buried 3 levels deep
      fi
    fi
  fi
}
```

## Array Construction

Build command arrays incrementally. Never use eval or unquoted expansion.

```bash
# GOOD — from cmd_instances.sh cmd_up
local run_args=(
  ec2 run-instances
  --instance-type "$itype"
  --image-id "$ami_id"
  --key-name "$CFG_SSH_KEY_NAME"
  --security-group-ids "$CFG_SECURITY_GROUP_ID"
  --block-device-mappings "$bdm"
)
if [[ -n "$CFG_SUBNET_ID" ]]; then
  run_args+=(--subnet-id "$CFG_SUBNET_ID")
fi
if [[ ${#spot_args[@]} -gt 0 ]]; then
  run_args+=("${spot_args[@]}")
fi
aws_cmd "${run_args[@]}" --output json
```

### WARNING: String-Building Commands

```bash
# BAD — fragile, breaks on spaces
cmd="aws ec2 run-instances --instance-type $itype"
if [[ -n "$subnet" ]]; then
  cmd="$cmd --subnet-id $subnet"
fi
eval $cmd  # NEVER eval user-influenced strings
```

**Why This Breaks:** Spaces in values break word splitting. `eval` introduces command injection. Arrays preserve argument boundaries correctly.

## String Manipulation

Use parameter expansion instead of external tools (`sed`, `awk`, `cut`) for simple operations.

```bash
# Trim whitespace (from parse_yaml in core.sh)
val="${val#"${val%%[^[:space:]]*}"}"   # ltrim
val="${val%"${val##*[^[:space:]]}"}"   # rtrim

# Strip matching outer quotes
if [[ "$val" =~ ^\"(.*)\"$ ]]; then val="${BASH_REMATCH[1]}"; fi

# Default values
local config_file="${EC2_CONFIG_FILE:-${EC2_ROOT}/config.yaml}"

# Tilde expansion (from resolve_ssh_key)
key_path="${key_path/#\~/$HOME}"

# Substring/replacement
local sanitized="${instance_type//./_}"  # t3.medium → t3_medium
```

## Process Substitution and Subshells

### WARNING: Variable Loss in Pipes

```bash
# BAD — count is always 0 after the loop
count=0
echo "$data" | while read -r line; do
  count=$((count + 1))  # modifies subshell copy
done
echo "$count"  # still 0

# GOOD — use here-string or process substitution
count=0
while read -r line; do
  count=$((count + 1))
done <<< "$data"
```

This project uses `done <<< "$data"` and `done 3< <(printf '%s\n' "$data")` patterns in `cmd_cleanup.sh` to avoid subshell variable loss.

## Portable Date Handling

macOS (BSD) and Linux (GNU) have incompatible `date` flags. This project cascades through options with fallback. See the **aws-cli** skill for timestamp handling.

```bash
# From core.sh — works on macOS, Linux, and Python fallback
parse_iso_date() {
  local ts="$1"
  ts="${ts%%.*}"; ts="${ts%Z}"
  date -u -d "${ts}" +%s 2>/dev/null && return 0          # GNU
  date -u -j -f '%Y-%m-%dT%H:%M:%S' "${ts}" +%s 2>/dev/null && return 0  # BSD
  python3 -c "..." 2>/dev/null && return 0                 # fallback
  return 1
}
```

## Color Output with TTY Detection

Gate colors on `[[ -t 1 ]]` so piped output stays clean.

```bash
# From core.sh
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
else
  RED=''; GREEN=''; NC=''
fi
```

## Argument Validation

Validate before acting. Check types, existence, and ranges.

```bash
# From cmd_up — validate integers before use
if [[ -n "$ttl" && ! "$ttl" =~ ^[0-9]+$ ]]; then
  die "Invalid TTL hours: $ttl (must be a non-negative integer)"
fi
if [[ -n "$extra_volume" ]]; then
  if [[ ! "$extra_volume" =~ ^[0-9]+$ ]] || [[ "$extra_volume" -lt 1 ]]; then
    die "Invalid extra volume size: $extra_volume (must be a positive integer)"
  fi
fi

# Validate enum-like values
case "$CFG_DEFAULT_VOLUME_TYPE" in
  gp2|gp3|io1|io2|st1|sc1|standard) ;;
  *) die "Invalid volume type: $CFG_DEFAULT_VOLUME_TYPE" ;;
esac
```