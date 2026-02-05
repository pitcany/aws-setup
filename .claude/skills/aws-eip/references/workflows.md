# EIP Workflows Reference

## Contents
- Full EIP Lifecycle
- Static IP for a Dev Instance
- Cleanup Orphaned EIPs
- Moving an EIP Between Instances
- Adding a New EIP Subcommand
- Testing EIP Changes

## Full EIP Lifecycle

Copy this checklist and track progress:
- [ ] Step 1: Allocate EIP with a descriptive name
- [ ] Step 2: Associate with target instance
- [ ] Step 3: Verify SSH connectivity on new static IP
- [ ] Step 4: Update `~/.ssh/config` if using `--gen-config`
- [ ] Step 5: When done, disassociate then release

```bash
# 1. Allocate
ec2 eip alloc prod-api

# 2. Associate (note the allocation ID from output)
ec2 eip assoc eipalloc-abc123 my-instance

# 3. Verify
ec2 ssh my-instance

# 4. Later — disassociate
ec2 eip disassoc eipassoc-def456

# 5. Release
ec2 eip release eipalloc-abc123
```

## Static IP for a Dev Instance

When you stop/start instances, the public IP changes. An EIP gives you a stable address.

```bash
# Allocate and associate
ec2 eip alloc dev-static
ec2 eip assoc eipalloc-xxx dev-box

# Now SSH always works at the same IP, even after stop/start:
ec2 stop dev-box
ec2 start dev-box
ec2 ssh dev-box    # Same IP as before
```

**WARNING:** An EIP associated with a **stopped** instance costs $0.005/hr (~$3.60/month). Either:
- Keep the instance running (EIP is free when attached to running instance)
- Release the EIP when you stop the instance for extended periods

## Cleanup Orphaned EIPs

Orphaned EIPs waste money. Use cleanup to find them:

```bash
# Scan only (no changes)
ec2 cleanup

# Scan and interactively release orphans
ec2 cleanup --release-eips

# Non-interactive release (with --yes)
ec2 cleanup --release-eips --yes

# Preview what would happen
ec2 --dry-run cleanup --release-eips
```

Cleanup output for EIPs:

```
[1/4] Elastic IPs not associated with any instance
  ! eipalloc-abc123  54.1.2.3   my-old-ip  [aws-setup]
  ! eipalloc-def456  54.4.5.6   -          [untagged]
[warn] 2 unassociated EIP(s) found (~$3.60/month each)
```

1. Run `ec2 cleanup`
2. Review listed orphans
3. If safe to release, run `ec2 cleanup --release-eips`
4. Confirm each release individually (or `--yes` to skip prompts)

## Moving an EIP Between Instances

EIPs can be reassigned. Useful when replacing an instance:

```bash
# 1. Check current associations
ec2 eip list

# 2. Disassociate from old instance
ec2 eip disassoc eipassoc-abc123

# 3. Associate with new instance
ec2 eip assoc eipalloc-xxx new-instance

# 4. Verify
ec2 eip list
ec2 ssh new-instance
```

**WARNING:** Between disassociate and re-associate, the EIP is unattached and incurs charges. Do this in quick succession.

## Adding a New EIP Subcommand

Follow the project's command pattern. See the **bash** skill for function naming conventions.

Copy this checklist and track progress:
- [ ] Step 1: Create `_eip_<name>` function in `lib/cmd_network.sh`
- [ ] Step 2: Add case entry in `cmd_eip` dispatcher
- [ ] Step 3: Add to `_eip_help` output
- [ ] Step 4: Add tests in `tests/test_cli.sh`
- [ ] Step 5: Run `./tests/run_tests.sh` and verify all pass

Example — adding an `_eip_describe` subcommand:

```bash
# 1. Add function in lib/cmd_network.sh (before _eip_help)
_eip_describe() {
  local alloc_id="${1:-}"
  if [[ -z "$alloc_id" ]]; then
    die "Usage: ec2 eip describe <allocation-id>"
  fi

  local result
  result="$(aws_cmd ec2 describe-addresses \
    --allocation-ids "$alloc_id" \
    --output json 2>&1)" || die "EIP not found: $alloc_id"

  printf '%s\n' "$result" | jq '.'
}
```

```bash
# 2. Add routing in cmd_eip dispatcher
case "$action" in
  ls|list)     _eip_list "$@" ;;
  describe)    _eip_describe "$@" ;;  # NEW
  alloc)       _eip_allocate "$@" ;;
  # ...
esac
```

```bash
# 3. Update _eip_help
_eip_help() {
  cat <<'HELP'
Actions:
  list                              List all EIPs
  describe <alloc-id>               Detailed info for one EIP
  alloc [name]                      Allocate a new EIP
  # ...
HELP
}
```

## Testing EIP Changes

**WARNING:** No EIP-specific tests exist yet. When modifying EIP functions, add mock-mode tests.

The test pattern from this codebase (`tests/test_cli.sh`):

```bash
# Pattern: set EC2_MOCK=true, call the function, assert output
test_eip_list_no_results() {
  EC2_MOCK=true
  local output
  output="$(_eip_list 2>&1)" || true
  if [[ "$output" == *"No Elastic IPs found"* ]]; then
    pass "eip list handles empty result"
  else
    fail "eip list empty result handling"
  fi
}
```

Validate loop:
1. Make changes to `lib/cmd_network.sh`
2. Run: `./tests/run_tests.sh`
3. If shellcheck or tests fail, fix and repeat step 2
4. Only commit when all tests pass

See the **shellcheck** skill for lint rules that apply to EIP functions.