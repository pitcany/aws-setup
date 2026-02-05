# EIP Patterns Reference

## Contents
- Dispatcher Pattern
- Tagging on Allocate
- Instance Resolution in Associate
- Orphan Detection in Cleanup
- Safety Gates
- Anti-Patterns

## Dispatcher Pattern

`cmd_eip` uses the standard subcommand dispatch from `lib/cmd_network.sh:189`:

```bash
cmd_eip() {
  local action="${1:-}"
  shift 2>/dev/null || true

  case "$action" in
    ls|list)     _eip_list "$@" ;;
    alloc)       _eip_allocate "$@" ;;
    assoc)       _eip_associate "$@" ;;
    disassoc)    _eip_disassociate "$@" ;;
    release)     _eip_release "$@" ;;
    -h|--help|"") _eip_help ;;
    *)           die "Unknown eip action: $action. Run: ec2 eip --help" ;;
  esac
}
```

When adding a new EIP subcommand, add the alias in the `case` and create `_eip_<name>`.

## Tagging on Allocate

`_eip_allocate` tags EIPs immediately after creation (`lib/cmd_network.sh:252-257`):

```bash
# DO — Tag with standard project tags
local tag_args=("Key=Project,Value=${CFG_TAG_PROJECT}"
                "Key=Owner,Value=${CFG_TAG_OWNER}"
                "Key=ManagedBy,Value=ec2-ops-kit")
if [[ -n "$name" ]]; then
  tag_args+=("Key=Name,Value=${name}")
fi
aws_cmd ec2 create-tags --resources "$alloc_id" --tags "${tag_args[@]}"
```

```bash
# DON'T — Skip tagging
aws_cmd ec2 allocate-address --domain vpc
# Untagged EIPs are flagged as "[untagged]" by cleanup and are harder to track
```

**Why:** Untagged EIPs show up as orphans in `ec2 cleanup` with `[untagged]` status, making it impossible to determine ownership. Always tag on creation.

## Instance Resolution in Associate

`_eip_associate` accepts instance names, not just IDs (`lib/cmd_network.sh:274`):

```bash
# The function resolves names to IDs:
local line
line="$(resolve_one_instance "$identifier")"
local inst_id name
IFS=$'\t' read -r inst_id name _ _ _ _ <<< "$line"
```

```bash
# DO — Pass a name
ec2 eip assoc eipalloc-abc123 dev-box

# DON'T — Require raw instance IDs from users
ec2 eip assoc eipalloc-abc123 i-0a1b2c3d4e5f
# This works but defeats the purpose of name-based resolution
```

## Orphan Detection in Cleanup

Cleanup scans for unassociated EIPs without a Project tag filter (`lib/cmd_cleanup.sh:39`):

```bash
# Scans ALL EIPs, not just project-tagged ones
orphan_eips="$(aws_cmd ec2 describe-addresses \
  --query 'Addresses[?AssociationId==null].[AllocationId, PublicIp, \
           (Tags[?Key==\`Name\`].Value)[0], (Tags[?Key==\`Project\`].Value)[0]]' \
  --output text)"
```

**Why no Project filter:** EIPs created manually (outside the tool) or with missing tags would be invisible to cleanup. Scanning all orphans catches cost leaks regardless of origin.

The output distinguishes tagged vs untagged:
```bash
# Tagged:   eipalloc-abc123  54.1.2.3  my-ip  [aws-setup]
# Untagged: eipalloc-def456  54.4.5.6  -      [untagged]
```

## Safety Gates

Every mutating EIP operation uses the two-layer safety pattern:

```bash
# Layer 1: dry_run_guard (blocks in --dry-run mode)
if ! dry_run_guard "aws ec2 release-address --allocation-id $alloc_id"; then
  return 0
fi

# Layer 2: confirm (blocks without explicit y/N — skipped with --yes)
confirm "Release this Elastic IP permanently?" || return 1

# Layer 3: actual execution
aws_cmd ec2 release-address --allocation-id "$alloc_id"
```

**Ordering matters:** `dry_run_guard` comes first (cheap, no side effects), then `confirm` (user interaction), then execution.

### WARNING: Inconsistent Safety in Allocate

`_eip_allocate` uses `dry_run_guard` but NOT `confirm`. This is intentional — allocation is non-destructive (creates a new resource). But be aware: allocating an EIP without associating it costs ~$3.60/month.

## Anti-Patterns

### WARNING: Releasing Without Disassociating First

**The Problem:**

```bash
# BAD — Release while still associated
ec2 eip release eipalloc-abc123
# AWS will reject this with: "The address with allocation id eipalloc-abc123
# is associated with instance i-xxx. Please disassociate first."
```

**Why This Breaks:**
1. AWS blocks release of associated EIPs at the API level
2. The CLI currently doesn't pre-check association status before release
3. Users see a raw AWS error instead of a helpful message

**The Fix:**

```bash
# GOOD — Disassociate then release
ec2 eip disassoc eipassoc-abc123
ec2 eip release eipalloc-abc123
```

### WARNING: Confusing Allocation ID vs Association ID

**The Problem:**

```bash
# BAD — Using wrong ID type
ec2 eip disassoc eipalloc-abc123    # Wrong! Needs eipassoc-*
ec2 eip release eipassoc-abc123     # Wrong! Needs eipalloc-*
```

**Why This Breaks:**
1. `disassoc` requires `eipassoc-*` (the binding ID)
2. `release` requires `eipalloc-*` (the resource ID)
3. AWS returns cryptic "InvalidParameterValue" errors

**The Fix:**

Run `ec2 eip list` first — it shows both IDs side by side:

```
ALLOCATION ID           PUBLIC IP       NAME    INSTANCE    ASSOCIATION
eipalloc-abc123         54.1.2.3        my-ip   i-xxx       eipassoc-def456
```