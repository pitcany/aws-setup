#!/usr/bin/env bash
# cmd_cleanup.sh — Orphan resource scanner
# Sourced by bin/ec2; do not run directly.

cmd_cleanup() {
  local max_stopped_days="${1:-7}"
  local do_release=false
  local do_delete_vols=false
  local do_terminate=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days)           max_stopped_days="$2"; shift 2 ;;
      --release-eips)   do_release=true; shift ;;
      --delete-volumes) do_delete_vols=true; shift ;;
      --terminate)      do_terminate=true; shift ;;
      -h|--help)        _cleanup_help; return 0 ;;
      *)                shift ;;
    esac
  done

  printf '\n'
  info "Scanning for orphaned resources (project=${CFG_TAG_PROJECT})..."
  printf '\n'

  local found_issues=false

  # ── 1. Unassociated Elastic IPs ─────────────────────────────────────
  printf '  %b[1/4] Elastic IPs not associated with any instance%b\n' "$BOLD" "$NC"
  local orphan_eips
  orphan_eips="$(aws_cmd ec2 describe-addresses \
    --filters "Name=tag:Project,Values=${CFG_TAG_PROJECT}" \
    --query 'Addresses[?AssociationId==null].[AllocationId, PublicIp, (Tags[?Key==`Name`].Value)[0]]' \
    --output text 2>/dev/null || echo "")"

  if [[ -n "$orphan_eips" ]]; then
    found_issues=true
    printf '%s\n' "$orphan_eips" | while IFS=$'\t' read -r alloc ip name; do
      printf '    %b!%b %-24s %-15s %s\n' "$YELLOW" "$NC" "$alloc" "$ip" "${name:--}"
    done
    local eip_count
    eip_count="$(printf '%s\n' "$orphan_eips" | wc -l | tr -d ' ')"
    warn "  $eip_count unassociated EIP(s) found (~\$3.60/month each)"

    if [[ "$do_release" == "true" ]]; then
      printf '%s\n' "$orphan_eips" | while IFS=$'\t' read -r alloc ip name; do
        if confirm "    Release $alloc ($ip)?"; then
          if dry_run_guard "aws ec2 release-address --allocation-id $alloc"; then
            aws_cmd ec2 release-address --allocation-id "$alloc" 2>/dev/null
            log "    Released $alloc"
          fi
        fi
      done
    else
      info "  Run with --release-eips to release them"
    fi
  else
    printf '    %bNone found%b\n' "$GREEN" "$NC"
  fi
  printf '\n'

  # ── 2. Unattached EBS volumes ───────────────────────────────────────
  printf '  %b[2/4] Unattached EBS volumes%b\n' "$BOLD" "$NC"
  local orphan_vols
  orphan_vols="$(aws_cmd ec2 describe-volumes \
    --filters "Name=status,Values=available" \
              "Name=tag:Project,Values=${CFG_TAG_PROJECT}" \
    --query 'Volumes[].[VolumeId, Size, VolumeType, CreateTime, (Tags[?Key==`Name`].Value)[0]]' \
    --output text 2>/dev/null || echo "")"

  if [[ -n "$orphan_vols" ]]; then
    found_issues=true
    printf '    %-21s %-8s %-6s %-24s %s\n' "VOLUME ID" "SIZE" "TYPE" "CREATED" "NAME"
    printf '%s\n' "$orphan_vols" | while IFS=$'\t' read -r vid size vtype created name; do
      printf '    %b!%b %-20s %-5s GB %-6s %-24s %s\n' "$YELLOW" "$NC" "$vid" "$size" "$vtype" "${created:0:19}" "${name:--}"
    done
    local vol_count
    vol_count="$(printf '%s\n' "$orphan_vols" | wc -l | tr -d ' ')"
    warn "  $vol_count unattached volume(s) found"

    if [[ "$do_delete_vols" == "true" ]]; then
      printf '%s\n' "$orphan_vols" | while IFS=$'\t' read -r vid size vtype created name; do
        if confirm "    Delete $vid (${size}GB)?"; then
          if dry_run_guard "aws ec2 delete-volume --volume-id $vid"; then
            aws_cmd ec2 delete-volume --volume-id "$vid" 2>/dev/null
            log "    Deleted $vid"
          fi
        fi
      done
    else
      info "  Run with --delete-volumes to delete them"
    fi
  else
    printf '    %bNone found%b\n' "$GREEN" "$NC"
  fi
  printf '\n'

  # ── 3. Stopped instances older than N days ──────────────────────────
  printf '  %b[3/4] Instances stopped > %d days%b\n' "$BOLD" "$max_stopped_days" "$NC"
  local now_epoch
  now_epoch="$(date -u +%s 2>/dev/null || date +%s)"
  local threshold=$((max_stopped_days * 86400))

  local stopped
  stopped="$(aws_cmd ec2 describe-instances \
    --filters "Name=instance-state-name,Values=stopped" \
              "Name=tag:Project,Values=${CFG_TAG_PROJECT}" \
    --query 'Reservations[].Instances[].[InstanceId, (Tags[?Key==`Name`].Value)[0], InstanceType, StateTransitionReason, LaunchTime]' \
    --output text 2>/dev/null || echo "")"

  local old_stopped=""
  if [[ -n "$stopped" ]]; then
    while IFS=$'\t' read -r id name itype reason launch; do
      # Try to extract stop time from StateTransitionReason (format varies)
      # Fall back to launch time as approximation
      local ref_time="${launch%%.*}"
      local ref_epoch
      ref_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%S' "$ref_time" +%s 2>/dev/null || \
                   date -u -d "$ref_time" +%s 2>/dev/null || echo "0")"

      if [[ $ref_epoch -gt 0 ]]; then
        local age=$((now_epoch - ref_epoch))
        if [[ $age -gt $threshold ]]; then
          local days=$((age / 86400))
          old_stopped="${old_stopped}${id}\t${name}\t${itype}\t${days}\n"
        fi
      fi
    done <<< "$stopped"
  fi

  if [[ -n "$old_stopped" ]]; then
    found_issues=true
    printf '    %-19s %-20s %-14s %s\n' "INSTANCE" "NAME" "TYPE" "DAYS SINCE LAUNCH"
    printf '%b' "$old_stopped" | while IFS=$'\t' read -r id name itype days; do
      printf '    %b!%b %-19s %-20s %-14s %s days\n' "$YELLOW" "$NC" "$id" "${name:--}" "$itype" "$days"
    done

    if [[ "$do_terminate" == "true" ]]; then
      printf '%b' "$old_stopped" | while IFS=$'\t' read -r id name itype days; do
        if confirm "    Terminate $id ($name)?"; then
          if dry_run_guard "aws ec2 terminate-instances --instance-ids $id"; then
            aws_cmd ec2 terminate-instances --instance-ids "$id" >/dev/null
            log "    Terminated $id"
          fi
        fi
      done
    else
      info "  Run with --terminate to terminate them"
    fi
  else
    printf '    %bNone found%b\n' "$GREEN" "$NC"
  fi
  printf '\n'

  # ── 4. TTL-expired instances ────────────────────────────────────────
  printf '  %b[4/4] Instances past TTL expiry%b\n' "$BOLD" "$NC"
  local ttl_expired=""

  local ttl_instances
  ttl_instances="$(aws_cmd ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running,stopped" \
              "Name=tag:Project,Values=${CFG_TAG_PROJECT}" \
              "Name=tag-key,Values=TTLHours" \
    --query 'Reservations[].Instances[].[InstanceId, (Tags[?Key==`Name`].Value)[0], State.Name, InstanceType, (Tags[?Key==`TTLHours`].Value)[0], (Tags[?Key==`ExpiresAt`].Value)[0], LaunchTime]' \
    --output text 2>/dev/null || echo "")"

  if [[ -n "$ttl_instances" ]]; then
    while IFS=$'\t' read -r id name state itype ttl expires launch; do
      [[ -z "$ttl" || "$ttl" == "None" || "$ttl" == "0" ]] && continue

      local expired=false
      if [[ -n "$expires" && "$expires" != "None" ]]; then
        local exp_epoch
        exp_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$expires" +%s 2>/dev/null || \
                     date -u -d "$expires" +%s 2>/dev/null || echo "0")"
        if [[ $exp_epoch -gt 0 && $now_epoch -gt $exp_epoch ]]; then
          expired=true
        fi
      else
        # Compute from launch time + TTL
        local launch_clean="${launch%%.*}"
        local launch_epoch
        launch_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%S' "$launch_clean" +%s 2>/dev/null || \
                        date -u -d "$launch_clean" +%s 2>/dev/null || echo "0")"
        if [[ $launch_epoch -gt 0 ]]; then
          local expiry=$((launch_epoch + ttl * 3600))
          if [[ $now_epoch -gt $expiry ]]; then
            expired=true
          fi
        fi
      fi

      if [[ "$expired" == "true" ]]; then
        ttl_expired="${ttl_expired}${id}\t${name}\t${state}\t${itype}\t${ttl}h\n"
      fi
    done <<< "$ttl_instances"
  fi

  if [[ -n "$ttl_expired" ]]; then
    found_issues=true
    printf '    %-19s %-20s %-10s %-14s %s\n' "INSTANCE" "NAME" "STATE" "TYPE" "TTL"
    printf '%b' "$ttl_expired" | while IFS=$'\t' read -r id name state itype ttl; do
      printf '    %b!%b %-19s %-20s %-10s %-14s %s (expired)\n' "$RED" "$NC" "$id" "${name:--}" "$state" "$itype" "$ttl"
    done

    if [[ "$do_terminate" == "true" ]]; then
      printf '%b' "$ttl_expired" | while IFS=$'\t' read -r id name state itype ttl; do
        if confirm "    Terminate $id ($name, TTL=$ttl)?"; then
          if dry_run_guard "aws ec2 terminate-instances --instance-ids $id"; then
            aws_cmd ec2 terminate-instances --instance-ids "$id" >/dev/null
            log "    Terminated $id"
          fi
        fi
      done
    else
      info "  Run with --terminate to terminate expired instances"
    fi
  else
    printf '    %bNone found%b\n' "$GREEN" "$NC"
  fi
  printf '\n'

  # Summary
  if [[ "$found_issues" == "false" ]]; then
    log "No orphaned resources found. All clean!"
  else
    warn "Orphaned resources detected. Review above and take action."
  fi
  printf '\n'
}

_cleanup_help() {
  cat <<'HELP'
Usage: ec2 cleanup [OPTIONS]

Scan for orphaned or wasteful resources.

Checks:
  1. Elastic IPs not associated with any instance
  2. Unattached EBS volumes
  3. Instances stopped longer than N days
  4. Instances past their TTL expiry tag

Options:
  --days N            Threshold for "old stopped" instances (default: 7)
  --release-eips      Interactively release orphaned EIPs
  --delete-volumes    Interactively delete unattached volumes
  --terminate         Interactively terminate old/expired instances
  --dry-run           Show what would be done
  -h, --help          Show this help

Examples:
  ec2 cleanup                     # Scan only
  ec2 cleanup --days 3            # Flag instances stopped > 3 days
  ec2 cleanup --release-eips      # Scan + offer to release EIPs
  ec2 cleanup --terminate --yes   # Terminate expired (skip prompts)
HELP
}
