---
name: aws-eip
description: |
  Manages Elastic IP allocation, association, and lifecycle operations in the EC2 Ops Kit.
  Use when: working on EIP commands (alloc/assoc/disassoc/release), cleanup of orphaned EIPs,
  or modifying the `cmd_eip` function family in `lib/cmd_network.sh`.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# AWS EIP Skill

Elastic IP management in EC2 Ops Kit lives in `lib/cmd_network.sh:189-356`. The `cmd_eip` dispatcher routes to five private functions (`_eip_list`, `_eip_allocate`, `_eip_associate`, `_eip_disassociate`, `_eip_release`). Orphaned EIP detection is in `lib/cmd_cleanup.sh:35-72`.

EIPs are the only resource type in cleanup that scans **without** a Project tag filter — orphaned EIPs may have been manually created outside the tool.

## Quick Start

### List all EIPs

```bash
ec2 eip list
```

### Full lifecycle

```bash
ec2 eip alloc my-static-ip              # allocate + tag
ec2 eip assoc eipalloc-abc123 dev-box   # associate with instance
ec2 eip disassoc eipassoc-abc123        # disassociate
ec2 eip release eipalloc-abc123         # release (delete)
```

## Key Concepts

| Concept | ID Format | Usage |
|---------|-----------|-------|
| Allocation ID | `eipalloc-*` | Identifies the EIP resource. Used for `assoc`, `release` |
| Association ID | `eipassoc-*` | Identifies the EIP↔instance binding. Used for `disassoc` |
| Domain | `vpc` | Always `vpc` — EC2-Classic is deprecated |

## Architecture

```
cmd_eip()  →  dispatcher (lib/cmd_network.sh:189)
  ├── _eip_list         →  describe-addresses, tabular output
  ├── _eip_allocate     →  allocate-address + create-tags (Project, Owner, ManagedBy, Name)
  ├── _eip_associate    →  resolve_one_instance() + associate-address
  ├── _eip_disassociate →  confirm() + disassociate-address
  └── _eip_release      →  confirm() + release-address

cmd_cleanup()  →  orphan EIP scanner (lib/cmd_cleanup.sh:35)
  └── Scans ALL EIPs where AssociationId==null (no Project filter)
```

## Common Patterns

### Instance resolution in `assoc`

`_eip_associate` uses `resolve_one_instance()` so users pass a name, not an instance ID:

```bash
# User passes name:
ec2 eip assoc eipalloc-abc123 dev-box

# Internally resolves to i-xxx via resolve_one_instance()
```

### Safety: dry-run + confirm gates

All mutating EIP operations go through `dry_run_guard` before execution. `disassoc` and `release` also require `confirm()`:

```bash
# Dry-run preview:
ec2 --dry-run eip release eipalloc-abc123
# [dry-run] Would execute: aws ec2 release-address --allocation-id eipalloc-abc123
```

### Auto-tagging on allocate

`_eip_allocate` tags with Project, Owner, ManagedBy, and optional Name:

```bash
ec2 eip alloc my-ip
# Tags: Name=my-ip, Project=aws-setup, Owner=yannik, ManagedBy=ec2-ops-kit
```

## WARNING: No EIP tests exist

The test suite (`tests/`) has zero coverage for EIP operations. Any changes to `_eip_*` functions should include tests in `tests/test_cli.sh`.

## See Also

- [patterns](references/patterns.md)
- [workflows](references/workflows.md)

## Related Skills

- See the **aws-cli** skill for `aws_cmd` wrapper and profile/region handling
- See the **aws-ec2** skill for instance resolution (`resolve_one_instance`)
- See the **bash** skill for error handling patterns (`die`, `confirm`, `dry_run_guard`)
- See the **jq** skill for parsing `allocate-address` JSON responses