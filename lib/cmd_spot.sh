#!/usr/bin/env bash
# cmd_spot.sh — Spot instance management
# Sourced by bin/ec2; do not run directly.

cmd_spot() {
  local action="${1:-}"
  shift 2>/dev/null || true

  case "$action" in
    ls|list)      _spot_list "$@" ;;
    prices|price) _spot_prices "$@" ;;
    history)      _spot_history "$@" ;;
    cancel)       _spot_cancel "$@" ;;
    interruption|int) _spot_interruption_info ;;
    -h|--help|"")     _spot_help ;;
    *)            die "Unknown spot action: $action. Run: ec2 spot --help" ;;
  esac
}

_spot_list() {
  info "Spot instance requests:"

  local result
  result="$(aws_cmd ec2 describe-spot-instance-requests \
    --query 'SpotInstanceRequests[].[SpotInstanceRequestId, State, Status.Code, InstanceId, (Tags[?Key==`Name`].Value)[0], LaunchSpecification.InstanceType, CreateTime]' \
    --output text 2>/dev/null || echo "")"

  if [[ -z "$result" ]]; then
    info "No spot instance requests found."
    return 0
  fi

  printf '\n'
  printf '  %-24s %-10s %-20s %-19s %-16s %-14s %s\n' \
    "REQUEST ID" "STATE" "STATUS" "INSTANCE" "NAME" "TYPE" "CREATED"
  printf '  %s\n' "$(printf '%0.s─' {1..130})"

  printf '%s\n' "$result" | while IFS=$'\t' read -r rid state status inst name itype created; do
    local state_color="$NC"
    case "$state" in
      active)    state_color="$GREEN" ;;
      open)      state_color="$YELLOW" ;;
      cancelled) state_color="$RED" ;;
      failed)    state_color="$RED" ;;
    esac
    printf '  %-24s %b%-10s%b %-20s %-19s %-16s %-14s %s\n' \
      "$rid" "$state_color" "$state" "$NC" "${status:--}" "${inst:--}" "${name:--}" "${itype:--}" "${created:--}"
  done
  printf '\n'

  # Also show running spot instances
  info "Running spot instances:"
  local spot_instances
  spot_instances="$(aws_cmd ec2 describe-instances \
    --filters "Name=instance-lifecycle,Values=spot" \
              "Name=instance-state-name,Values=running,pending" \
              "Name=tag:Project,Values=${CFG_TAG_PROJECT}" \
    --query 'Reservations[].Instances[].[InstanceId, (Tags[?Key==`Name`].Value)[0], InstanceType, PublicIpAddress, State.Name]' \
    --output text 2>/dev/null || echo "")"

  if [[ -z "$spot_instances" ]]; then
    info "  No running spot instances."
  else
    printf '\n  %-19s %-20s %-14s %-15s %s\n' "INSTANCE" "NAME" "TYPE" "IP" "STATE"
    printf '  %s\n' "$(printf '%0.s─' {1..80})"
    printf '%s\n' "$spot_instances" | while IFS=$'\t' read -r id name itype ip state; do
      printf '  %-19s %-20s %-14s %-15s %b\n' "$id" "${name:--}" "$itype" "${ip:--}" "$(format_state "$state")"
    done
  fi
  printf '\n'
}

_spot_prices() {
  local types=("${@:-g4dn.xlarge g5.xlarge t3.medium c5.2xlarge}")

  if [[ $# -eq 0 ]]; then
    types=(g4dn.xlarge g5.xlarge t3.medium c5.2xlarge)
  fi

  info "Current spot prices in ${CFG_AWS_REGION}:"
  printf '\n'
  printf '  %-16s %-12s %-15s %s\n' "INSTANCE TYPE" "AZ" "SPOT PRICE" "ON-DEMAND (est)"
  printf '  %s\n' "$(printf '%0.s─' {1..65})"

  for itype in "${types[@]}"; do
    local prices
    prices="$(aws_cmd ec2 describe-spot-price-history \
      --instance-types "$itype" \
      --product-descriptions "Linux/UNIX" \
      --start-time "$(date -u '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)" \
      --query 'SpotPriceHistory[].[AvailabilityZone, SpotPrice]' \
      --output text 2>/dev/null || echo "")"

    if [[ -z "$prices" ]]; then
      printf '  %-16s %s\n' "$itype" "no data"
      continue
    fi

    local od_rate
    od_rate="$(estimate_cost "$itype" 1)"

    printf '%s\n' "$prices" | sort -t$'\t' -k2 -n | head -3 | while IFS=$'\t' read -r az price; do
      local savings=""
      if [[ -n "$od_rate" && -n "$price" ]]; then
        savings="$(awk "BEGIN { pct = (1 - $price / $od_rate) * 100; printf \"(%.0f%% off)\", pct }" 2>/dev/null || echo "")"
      fi
      printf '  %-16s %-12s $%-14s %s\n' "$itype" "$az" "$price" "${od_rate:+\$$od_rate} $savings"
    done
  done
  printf '\n'
}

_spot_history() {
  local itype="${1:-g4dn.xlarge}"
  local hours="${2:-24}"

  local start_time
  if date -v -${hours}H &>/dev/null 2>&1; then
    start_time="$(date -u -v "-${hours}H" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)"
  else
    start_time="$(date -u -d "${hours} hours ago" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%S')"
  fi

  info "Spot price history for $itype (last ${hours}h):"

  aws_cmd ec2 describe-spot-price-history \
    --instance-types "$itype" \
    --product-descriptions "Linux/UNIX" \
    --start-time "$start_time" \
    --query 'SpotPriceHistory[].[Timestamp, AvailabilityZone, SpotPrice]' \
    --output table 2>/dev/null || warn "Could not retrieve spot price history"
}

_spot_cancel() {
  local request_id="${1:-}"
  if [[ -z "$request_id" ]]; then
    die "Usage: ec2 spot cancel <spot-request-id>"
  fi

  info "Cancelling spot request: $request_id"

  if ! dry_run_guard "aws ec2 cancel-spot-instance-requests --spot-instance-request-ids $request_id"; then
    return 0
  fi

  confirm "Cancel this spot request?" || return 1

  aws_cmd ec2 cancel-spot-instance-requests \
    --spot-instance-request-ids "$request_id" >/dev/null

  log "Spot request cancelled: $request_id"
  warn "Note: The running instance (if any) is NOT automatically terminated."
  info "To also terminate the instance, use: ec2 terminate <instance-name-or-id>"
}

_spot_interruption_info() {
  cat <<'INFO'

Spot Interruption Handling Guide
================================

AWS can reclaim spot instances with 2 minutes notice. Here's how to handle it:

1. DETECTION
   - AWS sends an interruption notice via instance metadata:
     curl -s http://169.254.169.254/latest/meta-data/spot/instance-action
   - Returns JSON with "action" and "time" when interruption is imminent
   - Returns 404 when no interruption is pending

2. MONITORING SCRIPT (run on your spot instance):
   #!/bin/bash
   while true; do
     resp=$(curl -s -o /dev/null -w "%{http_code}" \
       http://169.254.169.254/latest/meta-data/spot/instance-action)
     if [ "$resp" = "200" ]; then
       echo "SPOT INTERRUPTION NOTICE RECEIVED"
       # Save work, push to S3, checkpoint training, etc.
       aws s3 sync /data s3://my-bucket/backup/
       break
     fi
     sleep 5
   done

3. BEST PRACTICES
   - Checkpoint ML training regularly (every N epochs)
   - Use S3 or EFS for important data (not just local EBS)
   - Use multiple instance types in your spot requests
   - Consider spot fleet for higher availability
   - Tag spot instances with TTL for cost awareness

4. RECOMMENDED INSTANCE STRATEGY
   - g4dn.xlarge:  Good availability, ~55-70% savings
   - g5.xlarge:    Moderate availability, ~40-60% savings
   - Use ec2 spot prices to check current rates

INFO
}

_spot_help() {
  cat <<'HELP'
Usage: ec2 spot <action> [ARGS]

Manage spot instances.

Actions:
  list                          List spot requests and running spot instances
  prices [type1 type2 ...]      Show current spot prices
  history <type> [hours]        Show spot price history
  cancel <request-id>           Cancel a spot request
  interruption                  Show spot interruption handling guide

Examples:
  ec2 spot list
  ec2 spot prices g4dn.xlarge g5.xlarge
  ec2 spot history g4dn.xlarge 48
  ec2 spot cancel sir-abc12345

Creating spot instances:
  ec2 up --preset gpu-t4 --name my-gpu --spot
HELP
}
