# Spot Workflows Reference

## Contents
- GPU Training Workflow
- Spot Price Comparison Workflow
- Spot Cleanup Workflow
- Adding Spot Features
- Debugging Spot Issues

## GPU Training Workflow

The primary spot use case in this codebase: launch GPU, train, save results, terminate.

Copy this checklist and track progress:
- [ ] Step 1: Check spot prices — `ec2 spot prices g4dn.xlarge g5.xlarge`
- [ ] Step 2: Launch spot GPU — `ec2 up --preset gpu-t4 --name train --spot --ttl-hours 8`
- [ ] Step 3: SSH in — `ec2 ssh train`
- [ ] Step 4: Run training with S3 checkpoints
- [ ] Step 5: Upload results — `aws s3 cp model.pt s3://bucket/`
- [ ] Step 6: Terminate — `ec2 terminate train`
- [ ] Step 7: Verify cleanup — `ec2 spot list` (no orphan requests)

The `--ttl-hours 8` flag ensures `ec2 cleanup --terminate` catches it if you forget step 6.

## Spot Price Comparison Workflow

Before launching, compare spot vs on-demand to decide if spot is worth it:

```bash
# 1. Check current spot prices
ec2 spot prices g4dn.xlarge

# Output shows:
#   INSTANCE TYPE    AZ           SPOT PRICE      ON-DEMAND (est)
#   g4dn.xlarge      us-west-2b   $0.1812         $0.526 (66% off)
#   g4dn.xlarge      us-west-2a   $0.1890         $0.526 (64% off)

# 2. Check price stability over 48 hours
ec2 spot history g4dn.xlarge 48

# 3. If savings > 50% and prices are stable, use spot
ec2 up --preset gpu-t4 --name train --spot --ttl-hours 8
```

The savings calculation in `_spot_prices` (`lib/cmd_spot.sh:103-106`) uses `estimate_cost` from `lib/core.sh:457` for the on-demand baseline. These are approximate — see the **aws-cli** skill for querying real-time on-demand prices.

## Spot Cleanup Workflow

Spot instances create multiple resources that can become orphaned:

```bash
# 1. Check for orphan spot requests
ec2 spot list
# Shows both spot requests AND running spot instances

# 2. Cancel any stale requests
ec2 spot cancel sir-abc12345

# 3. Run full cleanup to catch orphaned resources
ec2 cleanup --days 1 --terminate
# Scans: orphan EIPs, unattached volumes, stopped instances, TTL-expired
```

`ec2 cleanup` scan 4/4 specifically checks TTL-expired instances (`lib/cmd_cleanup.sh:182-244`). Spot instances launched with `--ttl-hours` get `TTLHours` and `ExpiresAt` tags that cleanup uses for detection.

1. Run `ec2 cleanup`
2. Review flagged resources
3. If stale spot resources found, run `ec2 cleanup --terminate`
4. Verify with `ec2 spot list` — should show no orphans
5. Only stop when both commands report clean

## Adding Spot Features

To extend spot functionality in `lib/cmd_spot.sh`:

1. Add a new `_spot_<action>` function
2. Add routing in `cmd_spot()` case statement (`lib/cmd_spot.sh:9-17`)
3. Add to `_spot_help()` (`lib/cmd_spot.sh:202-224`)
4. Add routing alias in `bin/ec2` if needed (spot subcommands route through `cmd_spot`)
5. Add tests in `tests/test_cli.sh`

Example — adding a `_spot_savings` function:

```bash
_spot_savings() {
  local itype="${1:-g4dn.xlarge}"
  local od_rate
  od_rate="$(estimate_cost "$itype" 1)"
  if [[ -z "$od_rate" ]]; then
    die "No on-demand rate for $itype"
  fi
  # ... query spot price and compute savings
}
```

Follow the naming convention: private functions use `_spot_` prefix, always declare `local` variables, use `die`/`warn`/`info` from `core.sh` for output. See the **bash** skill for the full code style guide.

## Debugging Spot Issues

### Spot request stuck in "open" state

```bash
# Check request status
ec2 spot list
# If STATUS shows "capacity-not-available":
ec2 spot prices g4dn.xlarge
# Pick an AZ with recent price data (indicates capacity)
```

### Instance launched but no public IP

Spot instances in a VPC without auto-assign public IP won't get one. Check:

```bash
# Verify subnet has auto-assign public IP enabled
aws ec2 describe-subnets --subnet-ids subnet-xxx \
  --query 'Subnets[0].MapPublicIpOnLaunch'
```

If `false`, either enable it on the subnet or associate an EIP after launch. See the **aws-eip** skill.

### Cost estimate shows wrong savings percentage

The `_spot_prices` function computes savings from `estimate_cost` which uses config or hardcoded rates (`lib/core.sh:457-495`). If rates are outdated:

```bash
# Update config.yaml costs section
costs:
  g4dn_xlarge: 0.526    # Check current on-demand price
  g5_xlarge: 1.006
```

Note: config keys use underscores (`g4dn_xlarge`), not dots. The YAML parser in `core.sh` converts `costs.g4dn_xlarge` → `costs_g4dn_xlarge`. See the **yaml** skill for parser details.