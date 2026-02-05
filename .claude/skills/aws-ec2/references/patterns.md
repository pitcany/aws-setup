# EC2 Ops Kit — Code Patterns

## Contents
- Instance Resolution
- Tag Building
- Safety Guards
- Global State Flow
- YAML Parsing Constraints
- AWS Command Wrapper
- Cost Estimation
- Anti-Patterns

## Instance Resolution

All commands resolve names/IDs through `resolve_one_instance`. It returns tab-separated fields.

```bash
local line
line="$(resolve_one_instance "$identifier")"
local id name state itype pip prip
IFS=$'\t' read -r id name state itype pip prip <<< "$line"
```

Pass `"--all"` as second argument to include terminated instances (needed for `cmd_up` idempotency checks and `cmd_start`).

### WARNING: Forgetting --all for start/up

```bash
# BAD — won't find stopped instances that have been terminated
line="$(resolve_one_instance "$identifier")"
```

```bash
# GOOD — includes terminated for idempotency check in cmd_up
line="$(resolve_one_instance "$identifier" "--all")"
```

## Tag Building

Use `build_tag_spec` for `--tag-specifications` in `run-instances`. Tags both instance and volume:

```bash
local tag_spec
tag_spec="$(build_tag_spec "$inst_name" "$ttl" "instance")"
local vol_tag_spec
vol_tag_spec="$(build_tag_spec "$inst_name" "$ttl" "volume")"
run_args+=(--tag-specifications "$tag_spec" "$vol_tag_spec")
```

Every resource gets: `Name`, `Project`, `Owner`, `ManagedBy=ec2-ops-kit`. TTL adds `TTLHours` and `ExpiresAt`.

## Safety Guards

Three layers protect destructive operations:

```bash
# 1. dry_run_guard — blocks execution in --dry-run mode
if ! dry_run_guard "aws ec2 stop-instances --instance-ids $id"; then
  return 0  # return 0, not 1 — dry-run is not an error
fi

# 2. confirm — [y/N] prompt, skipped when EC2_YES=true
confirm "Stop instance ${name:-$id}?" || return 1

# 3. Typed confirmation — terminate requires typing name/ID
if [[ "$EC2_YES" != "true" ]]; then
  printf '%b' "${YELLOW}Type the instance name or ID to confirm: ${NC}"
  local reply
  read -r reply
  [[ "$reply" != "$name" && "$reply" != "$id" ]] && { err "Confirmation failed."; return 1; }
fi
```

### WARNING: Returning 1 from dry_run_guard

```bash
# BAD — exits the entire script due to set -e
dry_run_guard "..." || return 1
```

```bash
# GOOD — return 0 because dry-run preview is success, not failure
if ! dry_run_guard "..."; then return 0; fi
```

## Global State Flow

| Prefix | Set by | Example |
|--------|--------|---------|
| `EC2_*` | CLI flag parsing in `bin/ec2` | `EC2_DRY_RUN`, `EC2_MOCK`, `EC2_YES` |
| `CFG_*` | `load_config()` in `core.sh` | `CFG_AWS_REGION`, `CFG_SSH_KEY_PATH` |
| `PRESET_*` | `load_preset()` in `core.sh` | `PRESET_INSTANCE_TYPE`, `PRESET_VOLUME_SIZE` |

CLI flags override config: `EC2_PROFILE` → `CFG_AWS_PROFILE`, `EC2_REGION` → `CFG_AWS_REGION`.

### WARNING: Using raw echo for output

```bash
# BAD — breaks color gating and consistent formatting
echo "Instance started"
```

```bash
# GOOD — use logging functions from core.sh
log "Instance started"   # [ok] prefix, green
info "Waiting for IP..."  # [info] prefix, blue
warn "Key permissions"    # [warn] prefix, yellow, stderr
die "Not found"           # [error] prefix, red, stderr, exit 1
```

## YAML Parsing Constraints

The custom parser in `lib/core.sh:57` handles ONLY:
- Flat keys: `key: value`
- One-level nesting: `section:\n  key: value` → `section_key=value`
- Quoted values (single or double, stripped)
- Comments (line-level, not inline within quotes)

NEVER use nested sections deeper than one level, arrays, or multi-line values. See the **yaml** skill.

## AWS Command Wrapper

Always use `aws_cmd` instead of raw `aws`:

```bash
# GOOD — automatically applies --profile and --region from config
aws_cmd ec2 describe-instances --filters "..."

# BAD — ignores user's profile/region settings
aws ec2 describe-instances --filters "..."
```

## Cost Estimation

`estimate_cost` checks config `costs:` section first, falls back to hardcoded rates:

```bash
local rate
rate="$(estimate_cost "$itype" "$hours")"
if [[ -n "$rate" ]]; then
  printf '  Cost (est): ~$%s\n' "$rate"
fi
```

Always guard for empty return — unknown instance types return empty string.

## Anti-Patterns

### WARNING: Unquoted Variables

```bash
# BAD — word splitting breaks on spaces in names/paths
local key_path=$CFG_SSH_KEY_PATH
```

```bash
# GOOD — always double-quote
local key_path="$CFG_SSH_KEY_PATH"
```

### WARNING: Missing local Declaration

```bash
# BAD — leaks into global scope, causes subtle bugs
function do_thing() {
  result="$(some_command)"
}
```

```bash
# GOOD — always use local inside functions
function do_thing() {
  local result
  result="$(some_command)"
}
```

### WARNING: Skipping State Check Before Operation

```bash
# BAD — will error or produce confusing output
aws_cmd ec2 stop-instances --instance-ids "$id"
```

```bash
# GOOD — check state first, handle idempotent cases
if [[ "$state" == "stopped" ]]; then
  info "$name ($id) is already stopped."
  return 0
fi
if [[ "$state" != "running" ]]; then
  die "Cannot stop instance in state: $state"
fi
```