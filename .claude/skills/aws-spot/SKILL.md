---
name: aws-spot
description: |
  Handles spot instance pricing, history, requests, and interruption handling in EC2 Ops Kit.
  Use when: working with spot instance commands in lib/cmd_spot.sh, launching spot instances via `ec2 up --spot`, comparing spot vs on-demand pricing, handling spot interruptions, or modifying spot-related cleanup logic.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# AWS Spot Skill

Spot instance management for EC2 Ops Kit. The spot subsystem lives in `lib/cmd_spot.sh` and integrates with `cmd_up` in `lib/cmd_instances.sh` for spot launches. All spot commands route through `cmd_spot()` → `_spot_*` private functions.

## Quick Start

### Check Spot Prices

```bash
# Default types: g4dn.xlarge, g5.xlarge, t3.medium, c5.2xlarge
ec2 spot prices

# Specific types
ec2 spot prices g4dn.xlarge g5.xlarge

# Price history (last 48 hours)
ec2 spot history g4dn.xlarge 48
```

### Launch a Spot Instance

```bash
# Spot GPU with 8-hour TTL
ec2 up --preset gpu-t4 --name training --spot --ttl-hours 8

# Spot CPU for batch work
ec2 up --preset cpu-large --name batch --spot
```

### Manage Spot Requests

```bash
ec2 spot list                    # List requests + running spot instances
ec2 spot cancel sir-abc12345     # Cancel request (does NOT terminate instance)
ec2 spot interruption            # Show interruption handling guide
```

## Key Concepts

| Concept | Usage | Location |
|---------|-------|----------|
| Spot launch | `--spot` flag on `cmd_up` | `lib/cmd_instances.sh:278-284` |
| Spot-friendly check | `PRESET_SPOT_FRIENDLY` from preset YAML | `lib/cmd_instances.sh:279` |
| Price comparison | `_spot_prices` with `estimate_cost` fallback | `lib/cmd_spot.sh:73-111` |
| Spot request cancel | Cancels request only, warns about instance | `lib/cmd_spot.sh:137-157` |
| Interruption guide | Metadata endpoint + checkpoint strategy | `lib/cmd_spot.sh:159-200` |
| Spot instance filter | `instance-lifecycle=spot` filter | `lib/cmd_spot.sh:54-56` |

## Common Patterns

### Spot Market Options JSON

The spot launch uses a hardcoded one-time spot request:

```bash
spot_args=(--instance-market-options \
  '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time"}}')
```

This is `one-time` only — no persistent or fleet requests. See the **aws-cli** skill for the full `run-instances` argument structure.

### Savings Calculation

`_spot_prices` computes savings percentage using `awk`:

```bash
savings="$(awk "BEGIN { pct = (1 - $price / $od_rate) * 100; printf \"%.0f%% off\", pct }")"
```

The on-demand rate comes from `estimate_cost` in `lib/core.sh:457`, which checks `config.yaml` costs section first, then falls back to hardcoded rates.

### TTL Tags for Spot Cost Control

Always use `--ttl-hours` with spot instances so `ec2 cleanup` can detect expired ones:

```bash
ec2 up --preset gpu-t4 --name train --spot --ttl-hours 8
# Creates tags: TTLHours=8, ExpiresAt=<ISO timestamp>
```

## See Also

- [patterns](references/patterns.md)
- [workflows](references/workflows.md)

## Related Skills

- See the **aws-cli** skill for `aws ec2 describe-spot-price-history` and `run-instances` argument patterns
- See the **aws-ec2** skill for instance lifecycle (start/stop/terminate) after spot launch
- See the **bash** skill for `set -euo pipefail`, quoting, and `local` variable conventions
- See the **jq** skill for parsing AWS CLI JSON output in spot queries
- See the **yaml** skill for preset `spot_friendly` field parsing