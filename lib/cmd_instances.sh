#!/usr/bin/env bash
# cmd_instances.sh — list, info, up, start, stop, terminate
# Sourced by bin/ec2; do not run directly.

# ── ec2 list ──────────────────────────────────────────────────────────
cmd_list() {
  local filter_state="" filter_tag="" show_all=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state)    filter_state="$2"; shift 2 ;;
      --tag)      filter_tag="$2"; shift 2 ;;
      --all)      show_all=true; shift ;;
      -h|--help)  _list_help; return 0 ;;
      *)          warn "Unknown option: $1"; shift ;;
    esac
  done

  local filters=()
  if [[ "$show_all" != "true" ]]; then
    # By default, exclude terminated
    if [[ -n "$filter_state" ]]; then
      filters+=("Name=instance-state-name,Values=${filter_state}")
    else
      filters+=("Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down")
    fi
  fi
  if [[ -n "$filter_tag" ]]; then
    filters+=("Name=tag:Name,Values=*${filter_tag}*")
  fi
  # Always filter by Project tag if possible
  filters+=("Name=tag:Project,Values=${CFG_TAG_PROJECT}")

  local filter_args=()
  if [[ ${#filters[@]} -gt 0 ]]; then
    filter_args+=(--filters "${filters[@]}")
  fi

  local result
  result="$(aws_cmd ec2 describe-instances \
    "${filter_args[@]}" \
    --query 'Reservations[].Instances[] | sort_by(@, &LaunchTime)' \
    --output json 2>/dev/null || echo "[]")"

  local count
  count="$(printf '%s' "$result" | jq 'length')"

  if [[ "$count" == "0" ]]; then
    info "No instances found (project=${CFG_TAG_PROJECT})"
    return 0
  fi

  printf '\n'
  printf '  %-20s %-19s %-10s %-14s %-15s %-15s %-12s %s\n' \
    "NAME" "INSTANCE ID" "STATE" "TYPE" "PUBLIC IP" "PRIVATE IP" "AZ" "LAUNCH TIME"
  printf '  %s\n' "$(printf '%0.s─' {1..130})"

  printf '%s' "$result" | jq -r '.[] |
    [
      (.Tags // [] | map(select(.Key == "Name")) | .[0].Value // "<unnamed>"),
      .InstanceId,
      .State.Name,
      .InstanceType,
      (.PublicIpAddress // "-"),
      (.PrivateIpAddress // "-"),
      .Placement.AvailabilityZone,
      (.LaunchTime // "-")
    ] | @tsv' | while IFS=$'\t' read -r name id state itype pip prip az launch; do
    local state_fmt
    state_fmt="$(format_state "$state")"
    # Trim launch time to readable format
    local launch_short="${launch%%.*}Z"
    launch_short="${launch_short/T/ }"
    printf '  %-20s %-19s %-22b %-14s %-15s %-15s %-12s %s\n' \
      "$name" "$id" "$state_fmt" "$itype" "$pip" "$prip" "$az" "$launch_short"
  done

  printf '\n  %s instances\n\n' "$count"
}

_list_help() {
  cat <<'HELP'
Usage: ec2 list [OPTIONS]

List EC2 instances tagged with this project.

Options:
  --state STATE   Filter by state (running, stopped, etc.)
  --tag NAME      Filter by Name tag (substring match)
  --all           Include terminated instances
  -h, --help      Show this help
HELP
}

# ── ec2 info ──────────────────────────────────────────────────────────
cmd_info() {
  local identifier="" show_all=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) show_all="--all"; shift ;;
      -h|--help) printf 'Usage: ec2 info [--all] <name|instance-id>\n  --all  Include terminated instances\n'; return 0 ;;
      *) identifier="$1"; shift ;;
    esac
  done
  if [[ -z "$identifier" ]]; then
    die "Usage: ec2 info [--all] <name|instance-id>"
  fi

  local line
  line="$(resolve_one_instance "$identifier" "$show_all")"
  local id name state itype pip prip
  IFS=$'\t' read -r id name state itype pip prip <<< "$line"

  # Get full details
  local detail
  detail="$(aws_cmd ec2 describe-instances \
    --instance-ids "$id" \
    --output json 2>/dev/null)"

  local inst
  inst="$(printf '%s' "$detail" | jq '.Reservations[0].Instances[0]')"

  printf '\n'
  printf '  %b%s%b (%s)\n' "$BOLD" "${name:-<unnamed>}" "$NC" "$id"
  printf '  %s\n' "$(printf '%0.s─' {1..50})"
  printf '  %-18s %b\n' "State:" "$(format_state "$state")"
  printf '  %-18s %s\n' "Type:" "$itype"
  printf '  %-18s %s\n' "Public IP:" "${pip:-None}"
  printf '  %-18s %s\n' "Private IP:" "${prip:-None}"

  local az launch ami sg subnet vpc key spot_type lifecycle
  az="$(printf '%s' "$inst" | jq -r '.Placement.AvailabilityZone // "-"')"
  launch="$(printf '%s' "$inst" | jq -r '.LaunchTime // "-"')"
  ami="$(printf '%s' "$inst" | jq -r '.ImageId // "-"')"
  sg="$(printf '%s' "$inst" | jq -r '[.SecurityGroups[].GroupId] | join(", ") // "-"')"
  subnet="$(printf '%s' "$inst" | jq -r '.SubnetId // "-"')"
  vpc="$(printf '%s' "$inst" | jq -r '.VpcId // "-"')"
  key="$(printf '%s' "$inst" | jq -r '.KeyName // "-"')"
  lifecycle="$(printf '%s' "$inst" | jq -r '.InstanceLifecycle // "on-demand"')"

  printf '  %-18s %s\n' "AZ:" "$az"
  printf '  %-18s %s\n' "AMI:" "$ami"
  printf '  %-18s %s\n' "Key:" "$key"
  printf '  %-18s %s\n' "Security Groups:" "$sg"
  printf '  %-18s %s\n' "Subnet:" "$subnet"
  printf '  %-18s %s\n' "VPC:" "$vpc"
  printf '  %-18s %s\n' "Lifecycle:" "$lifecycle"
  printf '  %-18s %s\n' "Launch Time:" "$launch"

  # Cost hint
  if [[ "$state" == "running" ]]; then
    local now
    now="$(date -u +%s 2>/dev/null || date +%s)"
    local launch_epoch
    launch_epoch="$(parse_iso_date "$launch" 2>/dev/null || echo "")"
    if [[ -n "$launch_epoch" ]]; then
      local hours=$(( (now - launch_epoch) / 3600 ))
      [[ $hours -lt 1 ]] && hours=1
      local cost
      cost="$(estimate_cost "$itype" "$hours")"
      if [[ -n "$cost" ]]; then
        printf '  %-18s ~$%s (%s hrs running)\n' "Cost (est):" "$cost" "$hours"
      fi
    fi
  fi

  # Tags
  local tags
  tags="$(printf '%s' "$inst" | jq -r '(.Tags // [])[] | "    \(.Key) = \(.Value)"')"
  if [[ -n "$tags" ]]; then
    printf '\n  %bTags:%b\n%s\n' "$BOLD" "$NC" "$tags"
  fi

  # EBS Volumes
  local vols
  vols="$(printf '%s' "$inst" | jq -r '(.BlockDeviceMappings // [])[] | "    \(.DeviceName)  \(.Ebs.VolumeId // "-")  \(.Ebs.Status // "-")"')"
  if [[ -n "$vols" ]]; then
    printf '\n  %bVolumes:%b\n%s\n' "$BOLD" "$NC" "$vols"
  fi

  printf '\n'
}

# ── ec2 up ────────────────────────────────────────────────────────────
cmd_up() {
  local preset="" inst_name="" use_spot=false ttl="" extra_volume="" user_data=""
  local override_type="" override_ami="" override_vol_size=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --preset)       preset="$2"; shift 2 ;;
      --name)         inst_name="$2"; shift 2 ;;
      --spot)         use_spot=true; shift ;;
      --ttl-hours)    ttl="$2"; shift 2 ;;
      --type)         override_type="$2"; shift 2 ;;
      --ami)          override_ami="$2"; shift 2 ;;
      --volume-size)  override_vol_size="$2"; shift 2 ;;
      --volume)       extra_volume="$2"; shift 2 ;;
      --user-data)    user_data="$2"; shift 2 ;;
      -h|--help)      _up_help; return 0 ;;
      *)              warn "Unknown option: $1"; shift ;;
    esac
  done

  if [[ -z "$preset" ]]; then
    die "Usage: ec2 up --preset <name> --name <instance-name> [--spot] [--ttl-hours N]

Available presets:
$(list_presets)"
  fi

  load_preset "$preset"

  if [[ -z "$inst_name" ]]; then
    inst_name="${PRESET_NAME}-$(date +%H%M)"
  fi

  local itype="${override_type:-$PRESET_INSTANCE_TYPE}"
  local vol_size="${override_vol_size:-$PRESET_VOLUME_SIZE}"
  local ami_id="${override_ami:-$PRESET_AMI_ID}"

  # Resolve AMI
  ami_id="$(resolve_ami "$ami_id" "$PRESET_AMI_PATTERN" "$PRESET_AMI_OWNER")"

  # Check for idempotency: does an instance with this name already exist?
  local existing
  existing="$(resolve_instance "$inst_name")"
  if [[ -n "$existing" ]]; then
    local ex_id ex_name ex_state
    IFS=$'\t' read -r ex_id ex_name ex_state _ _ _ <<< "$(printf '%s\n' "$existing" | head -1)"
    case "$ex_state" in
      running)
        warn "Instance '$inst_name' already exists: $ex_id ($ex_state)"
        info "Instance is already running."
        return 0
        ;;
      stopped)
        warn "Instance '$inst_name' already exists: $ex_id ($ex_state)"
        if confirm "Start the existing instance instead?"; then
          cmd_start "$ex_id"
          return $?
        fi
        return 1
        ;;
      pending|stopping)
        warn "Instance '$inst_name' already exists: $ex_id ($ex_state)"
        info "Instance is currently $ex_state. Try again later."
        return 0
        ;;
    esac
  fi

  # Spot handling
  local spot_args=()
  if [[ "$use_spot" == "true" ]]; then
    if [[ "$PRESET_SPOT_FRIENDLY" != "true" ]]; then
      warn "Preset '$PRESET_NAME' is not marked as spot-friendly"
      confirm "Continue with spot anyway?" || return 1
    fi
    spot_args=(--instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time"}}')
  fi

  # Security group
  if [[ -z "$CFG_SECURITY_GROUP_ID" ]]; then
    die "Security group not configured. Set security.group_id in config.yaml"
  fi

  # SSH key
  if [[ -z "$CFG_SSH_KEY_NAME" ]]; then
    die "SSH key name not configured. Set ssh.key_name in config.yaml"
  fi

  if [[ -n "$user_data" && ! -f "$user_data" ]]; then
    die "User-data file not found: $user_data"
  fi

  # Build tag spec
  local tag_spec
  tag_spec="$(build_tag_spec "$inst_name" "$ttl" "instance")"
  local vol_tag_spec
  vol_tag_spec="$(build_tag_spec "$inst_name" "$ttl" "volume")"

  printf '\n'
  info "Creating instance:"
  printf '  %-18s %s\n' "Name:" "$inst_name"
  printf '  %-18s %s\n' "Preset:" "$PRESET_NAME"
  printf '  %-18s %s\n' "Type:" "$itype"
  printf '  %-18s %s\n' "AMI:" "$ami_id"
  printf '  %-18s %s GB\n' "Volume:" "$vol_size"
  printf '  %-18s %s\n' "Market:" "$(if [[ "$use_spot" == "true" ]]; then echo "spot"; else echo "on-demand"; fi)"
  if [[ -n "$ttl" && "$ttl" != "0" ]]; then
    printf '  %-18s %s hours\n' "TTL:" "$ttl"
  fi
  printf '\n'

  if ! dry_run_guard "aws ec2 run-instances --instance-type $itype ..."; then
    return 0
  fi

  # Build run-instances command
  local run_args=(
    ec2 run-instances
    --instance-type "$itype"
    --image-id "$ami_id"
    --key-name "$CFG_SSH_KEY_NAME"
    --security-group-ids "$CFG_SECURITY_GROUP_ID"
    --block-device-mappings "[{\"DeviceName\":\"${PRESET_ROOT_DEVICE}\",\"Ebs\":{\"VolumeSize\":${vol_size},\"VolumeType\":\"${CFG_DEFAULT_VOLUME_TYPE}\"}}]"
    --tag-specifications "$tag_spec" "$vol_tag_spec"
  )

  if [[ -n "$CFG_SUBNET_ID" ]]; then
    run_args+=(--subnet-id "$CFG_SUBNET_ID")
  fi

  if [[ ${#spot_args[@]} -gt 0 ]]; then
    run_args+=("${spot_args[@]}")
  fi

  if [[ -n "$user_data" ]]; then
    run_args+=(--user-data "file://$user_data")
  fi

  local output
  output="$(aws_cmd "${run_args[@]}" --output json 2>&1)" || die "Failed to launch instance:\n$output"

  local instance_id
  instance_id="$(printf '%s' "$output" | jq -r '.Instances[0].InstanceId')"

  if [[ -z "$instance_id" || "$instance_id" == "null" ]]; then
    die "Failed to extract instance ID from response"
  fi

  log "Instance launched: $instance_id"

  # Wait for public IP
  printf '  Waiting for IP' >&2
  local ip
  ip="$(wait_for_ip "$instance_id" 30)" || true
  printf '\n' >&2

  local cost_hint=""
  local rate
  rate="$(estimate_cost "$itype" 1)"
  if [[ -n "$rate" ]]; then
    cost_hint=" (~\$${rate}/hr)"
  fi

  printf '\n'
  log "Instance ready!"
  printf '  %-18s %s\n' "Instance ID:" "$instance_id"
  printf '  %-18s %s\n' "Name:" "$inst_name"
  printf '  %-18s %s\n' "Public IP:" "${ip:-pending...}"
  printf '  %-18s %s%s\n' "Type:" "$itype" "$cost_hint"

  if [[ -n "$PRESET_POST_LAUNCH_HINT" ]]; then
    printf '\n  %b%s%b\n' "$YELLOW" "$PRESET_POST_LAUNCH_HINT" "$NC"
  fi

  printf '\n  Quick commands:\n'
  printf '    ec2 ssh %s\n' "$inst_name"
  printf '    ec2 stop %s\n' "$inst_name"
  printf '    ec2 terminate %s\n' "$inst_name"
  printf '\n'

  # Create extra volume if requested
  if [[ -n "$extra_volume" ]]; then
    _create_and_attach_volume "$instance_id" "$extra_volume" "$inst_name" "$ttl"
  fi
}

_create_and_attach_volume() {
  local instance_id="$1" size="$2" name="$3" ttl="$4"

  info "Creating ${size} GB additional volume..."
  local az
  az="$(aws_cmd ec2 describe-instances \
    --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' \
    --output text)"

  local vol_tags
  vol_tags="$(build_tag_spec "${name}-data" "$ttl" "volume")"

  local vol_id
  vol_id="$(aws_cmd ec2 create-volume \
    --size "$size" \
    --volume-type "${CFG_DEFAULT_VOLUME_TYPE}" \
    --availability-zone "$az" \
    --tag-specifications "$vol_tags" \
    --query 'VolumeId' \
    --output text)"

  log "Volume created: $vol_id"

  # Wait for volume to be available
  aws_cmd ec2 wait volume-available --volume-ids "$vol_id" 2>/dev/null || true

  # Attach
  aws_cmd ec2 attach-volume \
    --volume-id "$vol_id" \
    --instance-id "$instance_id" \
    --device /dev/xvdf >/dev/null

  log "Volume $vol_id attached to $instance_id as /dev/xvdf"
  info "Mount with: sudo mkfs -t ext4 /dev/xvdf && sudo mount /dev/xvdf /data"
}

_up_help() {
  cat <<'HELP'
Usage: ec2 up --preset <name> --name <instance-name> [OPTIONS]

Create a new EC2 instance from a preset.

Options:
  --preset NAME      Preset to use (required)
  --name NAME        Instance Name tag (default: preset-HHMM)
  --spot             Request a spot instance
  --ttl-hours N      Tag with TTL; cleanup will flag expired instances
  --type TYPE        Override instance type from preset
  --ami AMI_ID       Override AMI from preset
  --volume-size GB   Override root volume size
  --volume GB        Create + attach an additional data volume
  --user-data FILE   Path to user-data script
  --dry-run          Show what would be created
  -h, --help         Show this help
HELP
}

# ── ec2 start ─────────────────────────────────────────────────────────
cmd_start() {
  local identifier="${1:-}"
  if [[ -z "$identifier" ]]; then
    die "Usage: ec2 start <name|instance-id>"
  fi

  local line
  line="$(resolve_one_instance "$identifier")"
  local id name state
  IFS=$'\t' read -r id name state _ _ _ <<< "$line"

  if [[ "$state" == "running" ]]; then
    info "$name ($id) is already running."
    return 0
  fi
  if [[ "$state" != "stopped" ]]; then
    die "Cannot start instance in state: $state"
  fi

  info "Starting ${name:-$id} ($id)..."

  if ! dry_run_guard "aws ec2 start-instances --instance-ids $id"; then
    return 0
  fi

  aws_cmd ec2 start-instances --instance-ids "$id" >/dev/null
  wait_for_state "$id" "running" 120 || true

  local ip
  ip="$(wait_for_ip "$id" 20)" || true
  printf '\n' >&2

  log "Instance started: ${name:-$id} ($id)"
  if [[ -n "$ip" ]]; then
    printf '  Public IP: %s\n' "$ip"
    printf '  ec2 ssh %s\n\n' "${name:-$id}"
  fi
}

# ── ec2 stop ──────────────────────────────────────────────────────────
cmd_stop() {
  local identifier="${1:-}"
  if [[ -z "$identifier" ]]; then
    die "Usage: ec2 stop <name|instance-id>"
  fi

  local line
  line="$(resolve_one_instance "$identifier")"
  local id name state itype
  IFS=$'\t' read -r id name state itype _ _ <<< "$line"

  if [[ "$state" == "stopped" ]]; then
    info "$name ($id) is already stopped."
    return 0
  fi
  if [[ "$state" != "running" ]]; then
    die "Cannot stop instance in state: $state"
  fi

  printf '  Stopping: %s (%s) [%s]\n' "${name:-<unnamed>}" "$id" "$itype"

  if ! dry_run_guard "aws ec2 stop-instances --instance-ids $id"; then
    return 0
  fi

  confirm "Stop instance ${name:-$id}?" || return 1

  aws_cmd ec2 stop-instances --instance-ids "$id" >/dev/null
  log "Stop signal sent to $id"
  info "Instance will stop shortly. EBS volumes are preserved."
}

# ── ec2 terminate ─────────────────────────────────────────────────────
cmd_terminate() {
  local identifier="${1:-}"
  if [[ -z "$identifier" ]]; then
    die "Usage: ec2 terminate <name|instance-id>"
  fi

  local line
  line="$(resolve_one_instance "$identifier")"
  local id name state itype
  IFS=$'\t' read -r id name state itype _ _ <<< "$line"

  if [[ "$state" == "terminated" ]]; then
    info "$id is already terminated."
    return 0
  fi

  printf '\n'
  printf '  %b*** TERMINATE ***%b\n' "$RED" "$NC"
  printf '  Instance: %s (%s)\n' "${name:-<unnamed>}" "$id"
  printf '  Type:     %s\n' "$itype"
  printf '  State:    %s\n' "$state"
  printf '  %bThis will permanently destroy the instance and its root volume.%b\n' "$RED" "$NC"
  printf '\n'

  if ! dry_run_guard "aws ec2 terminate-instances --instance-ids $id"; then
    return 0
  fi

  # Require explicit confirmation — type instance name or id
  if [[ "$EC2_YES" != "true" ]]; then
    printf '%b' "${YELLOW}Type the instance name or ID to confirm: ${NC}"
    local reply
    read -r reply
    if [[ "$reply" != "$name" && "$reply" != "$id" ]]; then
      err "Confirmation failed. Aborting."
      return 1
    fi
  fi

  aws_cmd ec2 terminate-instances --instance-ids "$id" >/dev/null
  log "Terminate signal sent to $id"
}
