# Spot Patterns Reference

## Contents
- Spot Launch Integration
- Price Query Pattern
- Spot-Friendly Preset Guard
- Cancel vs Terminate Distinction
- Interruption Metadata Polling
- Anti-Patterns

## Spot Launch Integration

Spot mode is toggled by `--spot` in `cmd_up` (`lib/cmd_instances.sh:278-284`). The spot arguments are conditionally appended to the `run_args` array:

```bash
# lib/cmd_instances.sh:277-284
local spot_args=()
if [[ "$use_spot" == "true" ]]; then
  if [[ "$PRESET_SPOT_FRIENDLY" != "true" ]]; then
    warn "Preset '$PRESET_NAME' is not marked as spot-friendly"
    confirm "Continue with spot anyway?" || return 1
  fi
  spot_args=(--instance-market-options \
    '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time"}}')
fi
```

The `spot_args` array is spliced into `run_args` later at line 362-364. This pattern keeps the base command clean and adds spot only when needed.

## Price Query Pattern

`_spot_prices` iterates instance types and queries current prices per AZ:

```bash
# lib/cmd_spot.sh:85-109
for itype in "${types[@]}"; do
  local prices
  prices="$(aws_cmd ec2 describe-spot-price-history \
    --instance-types "$itype" \
    --product-descriptions "Linux/UNIX" \
    --start-time "$(date -u '+%Y-%m-%dT%H:%M:%S')" \
    --query 'SpotPriceHistory[].[AvailabilityZone, SpotPrice]' \
    --output text)"
  # Sort by price, show top 3 cheapest AZs
  printf '%s\n' "$prices" | sort -t$'\t' -k2 -n | head -3
done
```

Key detail: `--start-time` is set to "now" so the API returns only the most recent price per AZ, not historical data. See the **aws-cli** skill for `--query` JMESPath syntax.

## Spot-Friendly Preset Guard

Presets declare `spot_friendly: true` or `false`. The guard warns but doesn't block — users can override:

```yaml
# presets/gpu-t4.yaml
spot_friendly: true    # GPU presets are spot-friendly
```

```yaml
# DO — Mark presets correctly
spot_friendly: true    # For interruptible workloads (training, batch)

# DON'T — Mark everything as spot-friendly
spot_friendly: true    # On a preset used for long-running services
```

## Cancel vs Terminate Distinction

`_spot_cancel` cancels the spot **request** but explicitly warns the instance stays alive:

```bash
# lib/cmd_spot.sh:154-156
log "Spot request cancelled: $request_id"
warn "Note: The running instance (if any) is NOT automatically terminated."
info "To also terminate the instance, use: ec2 terminate <instance-name-or-id>"
```

This is a critical UX decision. AWS `cancel-spot-instance-requests` only cancels the request — the instance keeps running and billing. Always follow cancel with terminate if the instance is no longer needed.

## Interruption Metadata Polling

The interruption guide (`_spot_interruption_info`) documents the instance metadata endpoint:

```bash
# Poll for interruption notice on the spot instance itself
curl -s http://169.254.169.254/latest/meta-data/spot/instance-action
# Returns 404 = no interruption, 200 = interruption imminent (2 min warning)
```

Best practice: checkpoint to S3 immediately when 200 is received. See the **aws-s3** skill for `aws s3 sync` patterns.

## Anti-Patterns

### WARNING: Forgetting TTL on Spot Instances

**The Problem:**

```bash
# BAD — No TTL, cleanup can't detect if this instance outlives its purpose
ec2 up --preset gpu-t4 --name train --spot
```

**Why This Breaks:**
1. Spot instances that survive interruption can run indefinitely
2. `ec2 cleanup` has no TTL tag to compare against
3. Forgotten GPU instances at $0.53/hr cost $12.72/day

**The Fix:**

```bash
# GOOD — TTL ensures cleanup flags it after 8 hours
ec2 up --preset gpu-t4 --name train --spot --ttl-hours 8
```

### WARNING: Cancelling Without Terminating

**The Problem:**

```bash
# BAD — Cancels request but instance keeps running and billing
ec2 spot cancel sir-abc12345
# ... forgets to terminate the actual instance
```

**Why This Breaks:**
1. The running instance continues billing at spot rate
2. No spot request visible in `ec2 spot list` — looks clean but isn't
3. Instance only appears in `ec2 list` or `ec2 cleanup`

**The Fix:**

```bash
# GOOD — Cancel request AND terminate the instance
ec2 spot cancel sir-abc12345
ec2 terminate my-gpu-instance
```

### WARNING: Hardcoding AZ in Spot Launches

**When You Might Be Tempted:** Spot capacity varies by AZ. If one AZ fails with `InsufficientInstanceCapacity`, you might hardcode a "known good" AZ.

The current codebase does NOT specify AZ in spot launches — it lets AWS pick the cheapest available AZ. This is correct. Hardcoding an AZ reduces availability and may hit capacity errors. Use `ec2 spot prices` to check which AZs have capacity before manually overriding.