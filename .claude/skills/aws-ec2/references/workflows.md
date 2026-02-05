# EC2 Ops Kit — Workflows

## Contents
- Adding a New Command
- Adding a New Preset
- Running Tests
- Instance Launch Flow
- SSH Connection Flow
- Cleanup Flow
- Development Checklist

## Adding a New Command

Copy this checklist and track progress:
- [ ] Step 1: Create `cmd_<name>()` in the appropriate `lib/cmd_*.sh` file
- [ ] Step 2: Add `_<name>_help()` function with usage, options, examples
- [ ] Step 3: Add routing entry in `bin/ec2` case statement (line 137+), including aliases
- [ ] Step 4: Add to `show_help()` in `bin/ec2` (line 30+)
- [ ] Step 5: Add tests in `tests/test_cli.sh`
- [ ] Step 6: Run `./tests/run_tests.sh` and verify all pass

### Command function structure

```bash
cmd_mycommand() {
  local identifier="" some_flag=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --flag)     some_flag=true; shift ;;
      -h|--help)  _mycommand_help; return 0 ;;
      *)          identifier="$1"; shift ;;
    esac
  done

  if [[ -z "$identifier" ]]; then
    die "Usage: ec2 mycommand <name|instance-id>"
  fi

  local line
  line="$(resolve_one_instance "$identifier")"
  local id name state itype pip prip
  IFS=$'\t' read -r id name state itype pip prip <<< "$line"

  # State guard
  if [[ "$state" != "running" ]]; then
    die "Instance must be running"
  fi

  # Dry-run guard for destructive operations
  if ! dry_run_guard "aws ec2 do-something --instance-ids $id"; then
    return 0
  fi

  # Execute
  aws_cmd ec2 do-something --instance-ids "$id" >/dev/null
  log "Done: $id"
}
```

### Routing entry in bin/ec2

```bash
# In bin/ec2, inside the case statement:
  mycommand|myalias)  cmd_mycommand "$@" ;;
```

## Adding a New Preset

Copy this checklist:
- [ ] Step 1: Create `presets/<name>.yaml` with all required fields
- [ ] Step 2: Run `./tests/run_tests.sh` to validate preset loading
- [ ] Step 3: Test with `ec2 presets` to verify it appears in the list

### Required preset fields

```yaml
name: my-preset
description: "What this preset is for"
instance_type: m5.xlarge
ami_pattern: "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
ami_owner: "099720109477"
ami_id: ""
volume_size: 50
root_device: /dev/sda1
ssh_user: ubuntu
spot_friendly: true
cost_per_hour: 0.192
```

Leave `ami_id` empty to auto-detect via `ami_pattern`. Set `ami_id` explicitly to skip the `describe-images` call (faster, deterministic).

### WARNING: Missing required fields

The YAML parser won't error on missing keys — it returns empty strings. Missing `instance_type` causes `aws ec2 run-instances` to fail with a confusing error. Always include all fields.

## Running Tests

```bash
./tests/run_tests.sh
```

1. Make changes
2. Validate: `./tests/run_tests.sh`
3. If validation fails, fix issues and repeat step 2
4. Only proceed when all tests pass

Tests run in mock mode (`EC2_MOCK=true`) — no AWS API calls. Four suites:

| Suite | What it checks |
|-------|---------------|
| Lint | `shellcheck -S warning` on `bin/ec2` and all `lib/*.sh` |
| Config | YAML parser unit tests (basic, nested, comments, quotes) |
| Presets | All `presets/*.yaml` load without errors |
| CLI | Command routing, flag parsing, tag builder, cost estimation |

### Shellcheck compliance

All scripts must pass `shellcheck -S warning`. Use source directives:

```bash
# shellcheck source=../lib/core.sh
source "${EC2_ROOT}/lib/core.sh"
```

See the **shellcheck** skill for common warnings and fixes.

## Instance Launch Flow (cmd_up)

The `cmd_up` function in `lib/cmd_instances.sh:184` follows this sequence:

1. Parse flags (`--preset`, `--name`, `--spot`, `--ttl-hours`, `--volume`)
2. `load_preset "$preset"` → populates `PRESET_*` globals
3. `resolve_ami` → auto-detect or use explicit AMI ID
4. **Idempotency check**: `resolve_instance "$inst_name" "--all"` — if running, return; if stopped, offer start; if transitioning, abort; if terminated, proceed
5. Validate config: security group, SSH key name, TTL, volume size
6. `dry_run_guard` → preview if `--dry-run`
7. Build `--block-device-mappings` JSON, `--tag-specifications`
8. `aws_cmd ec2 run-instances` → extract instance ID
9. `wait_for_ip` → poll for public IP
10. Print summary with quick commands

### WARNING: Skipping idempotency check

```bash
# BAD — will create duplicate instances with the same name
aws_cmd ec2 run-instances ...
```

The idempotency check at step 4 is critical. It handles all five instance states (running, stopped, pending/stopping/shutting-down, terminated) with appropriate actions for each.

## SSH Connection Flow (cmd_ssh)

`cmd_ssh` in `lib/cmd_network.sh:6`:

1. Parse identifier and extra SSH args (port forwards, etc.)
2. `resolve_one_instance` → get state and IPs
3. If stopped → offer to start (`confirm` + `cmd_start`)
4. Determine IP: prefer public, fall back to private
5. `resolve_ssh_key` → validate key path and permissions
6. Auto-detect SSH user from AMI name (`ubuntu` vs `ec2-user`)
7. Build SSH command with bastion/ProxyJump if configured
8. `--print` → output command string; otherwise execute

### Passing extra SSH args

```bash
# Port forward Jupyter
ec2 ssh dev-box -L 8888:localhost:8888

# Verbose SSH
ec2 ssh dev-box -- -v
```

Extra args are collected into `ssh_extra_args` array and appended to the SSH command.

## Cleanup Flow (cmd_cleanup)

`cmd_cleanup` in `lib/cmd_cleanup.sh` scans four categories:

1. **Orphan EIPs** — unassociated Elastic IPs (~$3.60/month each)
2. **Unattached volumes** — EBS volumes with `status=available`
3. **Stale stopped instances** — stopped longer than `--days N` (default 7)
4. **TTL-expired instances** — running/stopped instances past `ExpiresAt` tag

Each scan reports findings. Pass `--release-eips`, `--delete-volumes`, or `--terminate` to interactively act on findings. Combine with `--yes` to skip prompts.

```bash
# Scan only (safe, read-only)
ec2 cleanup

# Scan + offer to clean up everything
ec2 cleanup --release-eips --delete-volumes --terminate

# Automated cleanup (skip prompts) — use with caution
ec2 cleanup --terminate --yes
```

## Development Checklist

Copy this checklist for any feature work:
- [ ] Read relevant source files before modifying
- [ ] Follow naming: `cmd_*` for public, `_prefix_*` for private, `snake_case` for utils
- [ ] Use `local` for all function variables
- [ ] Quote all `"$variables"`
- [ ] Use `log`/`warn`/`err`/`die` — never raw `echo`
- [ ] Add `dry_run_guard` before destructive AWS calls
- [ ] Add `confirm` for user-facing destructive operations
- [ ] Check instance state before operations
- [ ] Add help function with usage, options, examples
- [ ] Add routing in `bin/ec2` case statement
- [ ] Add tests in `tests/test_cli.sh`
- [ ] Run `./tests/run_tests.sh` — all must pass
- [ ] Run `shellcheck -S warning` on changed files