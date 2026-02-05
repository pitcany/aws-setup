#!/usr/bin/env bash
# cmd_network.sh — ssh and eip commands
# Sourced by bin/ec2; do not run directly.

# ── ec2 ssh ───────────────────────────────────────────────────────────
cmd_ssh() {
  local identifier="" print_only=false gen_config=false ssh_extra_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --print)       print_only=true; shift ;;
      --gen-config)  gen_config=true; shift ;;
      -h|--help)     _ssh_help; return 0 ;;
      -*)            ssh_extra_args+=("$1"); shift ;;
      *)
        if [[ -z "$identifier" ]]; then
          identifier="$1"; shift
        else
          ssh_extra_args+=("$1"); shift
        fi
        ;;
    esac
  done

  if [[ "$gen_config" == "true" ]]; then
    _ssh_gen_config
    return $?
  fi

  if [[ -z "$identifier" ]]; then
    die "Usage: ec2 ssh <name|instance-id> [--print] [-- extra-ssh-args]"
  fi

  local line
  line="$(resolve_one_instance "$identifier")"
  local id name state itype pip prip
  IFS=$'\t' read -r id name state itype pip prip <<< "$line"

  # If stopped, offer to start
  if [[ "$state" == "stopped" ]]; then
    warn "Instance $name ($id) is stopped."
    if confirm "Start it?"; then
      cmd_start "$id"
      # Re-resolve to get IP
      line="$(resolve_one_instance "$id")"
      IFS=$'\t' read -r id name state itype pip prip <<< "$line"
    else
      return 1
    fi
  fi

  if [[ "$state" != "running" ]]; then
    die "Instance is in state '$state' — cannot SSH"
  fi

  # Determine IP: prefer public, fall back to private
  local target_ip="${pip:-$prip}"
  if [[ -z "$target_ip" || "$target_ip" == "None" ]]; then
    # Try waiting for IP
    info "Waiting for IP assignment..."
    target_ip="$(wait_for_ip "$id" 12)" || true
    printf '\n' >&2
    if [[ -z "$target_ip" ]]; then
      target_ip="$prip"
    fi
  fi

  if [[ -z "$target_ip" || "$target_ip" == "None" ]]; then
    die "No IP available for instance $id"
  fi

  # Resolve SSH key
  local key_path
  key_path="$(resolve_ssh_key)"

  # Determine SSH user: check instance tags for preset, fall back to config
  local ssh_user="$CFG_SSH_DEFAULT_USER"
  # Try to detect from AMI name
  local ami_id
  ami_id="$(aws_cmd ec2 describe-instances \
    --instance-ids "$id" \
    --query 'Reservations[0].Instances[0].ImageId' \
    --output text 2>/dev/null || echo "")"
  if [[ -n "$ami_id" && "$ami_id" != "None" ]]; then
    local ami_name
    ami_name="$(aws_cmd ec2 describe-images \
      --image-ids "$ami_id" \
      --query 'Images[0].Name' \
      --output text 2>/dev/null || echo "")"
    case "$ami_name" in
      *ubuntu*|*Ubuntu*) ssh_user="ubuntu" ;;
      *amzn*|*Amazon*)   ssh_user="ec2-user" ;;
    esac
  fi

  # Build SSH command
  local ssh_cmd=(ssh -i "$key_path")

  # Add bastion/ProxyJump if configured
  if [[ -n "$CFG_SSH_BASTION_HOST" ]]; then
    local bastion_user="${CFG_SSH_BASTION_USER:-$ssh_user}"
    local bastion_key="${CFG_SSH_BASTION_KEY_PATH:-$key_path}"
    bastion_key="${bastion_key/#\~/$HOME}"
    ssh_cmd+=(-o "ProxyJump=${bastion_user}@${CFG_SSH_BASTION_HOST}")
    if [[ "$bastion_key" != "$key_path" ]]; then
      # If bastion uses a different key, we need ProxyCommand instead of ProxyJump.
      # Quote embedded paths to handle spaces/metacharacters safely.
      local proxy_cmd
      printf -v proxy_cmd 'ssh -i %q -W %%h:%%p %q@%q' "$bastion_key" "$bastion_user" "$CFG_SSH_BASTION_HOST"
      ssh_cmd=( ssh -i "$key_path" -o "ProxyCommand=${proxy_cmd}" )
    fi
  fi

  ssh_cmd+=("${ssh_extra_args[@]}" "${ssh_user}@${target_ip}")

  if [[ "$print_only" == "true" ]]; then
    printf '%s\n' "${ssh_cmd[*]}"
    return 0
  fi

  info "Connecting to ${name:-$id} ($target_ip)..."
  printf '  %b%s%b\n\n' "$DIM" "${ssh_cmd[*]}" "$NC"

  exec "${ssh_cmd[@]}"
}

_ssh_gen_config() {
  info "Generating SSH config snippet for running instances..."

  local result
  result="$(aws_cmd ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" \
              "Name=tag:Project,Values=${CFG_TAG_PROJECT}" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0], PublicIpAddress, PrivateIpAddress, KeyName]' \
    --output text 2>/dev/null || echo "")"

  if [[ -z "$result" ]]; then
    info "No running instances found."
    return 0
  fi

  local key_path
  key_path="$(resolve_ssh_key)"

  printf '\n# --- EC2 Ops Kit (auto-generated) ---\n'
  printf '%s\n' "$result" | while IFS=$'\t' read -r name pip prip keyname; do
    [[ -z "$name" || "$name" == "None" ]] && continue
    local ip="${pip:-$prip}"
    [[ -z "$ip" || "$ip" == "None" ]] && continue
    local host_alias
    host_alias="$(printf '%s' "$name" | tr ' ' '-')"
    printf '\nHost %s\n' "$host_alias"
    printf '  HostName %s\n' "$ip"
    printf '  User %s\n' "$CFG_SSH_DEFAULT_USER"
    printf '  IdentityFile %s\n' "$key_path"
    printf '  StrictHostKeyChecking no\n'
    printf '  UserKnownHostsFile /dev/null\n'
    if [[ -n "$CFG_SSH_BASTION_HOST" ]]; then
      printf '  ProxyJump %s@%s\n' "${CFG_SSH_BASTION_USER:-$CFG_SSH_DEFAULT_USER}" "$CFG_SSH_BASTION_HOST"
    fi
  done
  printf '\n# --- End EC2 Ops Kit ---\n\n'

  info "Paste the above into ~/.ssh/config (or use: ec2 ssh --gen-config >> ~/.ssh/config)"
}

_ssh_help() {
  cat <<'HELP'
Usage: ec2 ssh <name|instance-id> [OPTIONS]

SSH into an EC2 instance by Name tag or instance ID.

Options:
  --print           Print the ssh command instead of executing
  --gen-config      Generate ~/.ssh/config snippet for all running instances
  -h, --help        Show this help

Extra SSH arguments can be passed directly:
  ec2 ssh mybox -L 8888:localhost:8888   # Port forward
  ec2 ssh mybox -- -v                    # Verbose SSH
HELP
}

# ── ec2 eip ───────────────────────────────────────────────────────────
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

_eip_list() {
  local result
  result="$(aws_cmd ec2 describe-addresses \
    --query 'Addresses[].[AllocationId, PublicIp, (Tags[?Key==`Name`].Value)[0], InstanceId, AssociationId, Domain]' \
    --output text 2>/dev/null || echo "")"

  if [[ -z "$result" ]]; then
    info "No Elastic IPs found."
    return 0
  fi

  printf '\n'
  printf '  %-24s %-15s %-20s %-19s %-24s %s\n' \
    "ALLOCATION ID" "PUBLIC IP" "NAME" "INSTANCE" "ASSOCIATION" "DOMAIN"
  printf '  %s\n' "$(printf '%0.s─' {1..120})"

  printf '%s\n' "$result" | while IFS=$'\t' read -r alloc ip name inst assoc domain; do
    local status=""
    if [[ -z "$inst" || "$inst" == "None" ]]; then
      status="${YELLOW}unassociated${NC}"
    else
      status="${GREEN}$inst${NC}"
    fi
    printf '  %-24s %-15s %-20s %-30b %-24s %s\n' \
      "$alloc" "$ip" "${name:-<unnamed>}" "$status" "${assoc:--}" "${domain:--}"
  done
  printf '\n'
}

_eip_allocate() {
  local name="${1:-}"

  info "Allocating new Elastic IP..."

  if ! dry_run_guard "aws ec2 allocate-address"; then
    return 0
  fi

  local result
  result="$(aws_cmd ec2 allocate-address \
    --domain vpc \
    --output json 2>&1)" || die "Failed to allocate EIP:\n$result"

  local alloc_id ip
  alloc_id="$(printf '%s' "$result" | jq -r '.AllocationId')"
  ip="$(printf '%s' "$result" | jq -r '.PublicIp')"

  # Tag it
  local tag_args=("Key=Project,Value=${CFG_TAG_PROJECT}" "Key=Owner,Value=${CFG_TAG_OWNER}" "Key=ManagedBy,Value=ec2-ops-kit")
  if [[ -n "$name" ]]; then
    tag_args+=("Key=Name,Value=${name}")
  fi

  aws_cmd ec2 create-tags --resources "$alloc_id" --tags "${tag_args[@]}" 2>/dev/null || true

  log "Elastic IP allocated:"
  printf '  Allocation ID: %s\n' "$alloc_id"
  printf '  Public IP:     %s\n' "$ip"
  printf '\n  Associate with: ec2 eip assoc %s <instance-name-or-id>\n\n' "$alloc_id"
}

_eip_associate() {
  local alloc_id="${1:-}"
  local identifier="${2:-}"

  if [[ -z "$alloc_id" || -z "$identifier" ]]; then
    die "Usage: ec2 eip assoc <allocation-id> <instance-name-or-id>"
  fi

  local line
  line="$(resolve_one_instance "$identifier")"
  local inst_id name
  IFS=$'\t' read -r inst_id name _ _ _ _ <<< "$line"

  info "Associating $alloc_id with ${name:-$inst_id}..."

  if ! dry_run_guard "aws ec2 associate-address --allocation-id $alloc_id --instance-id $inst_id"; then
    return 0
  fi

  local result
  result="$(aws_cmd ec2 associate-address \
    --allocation-id "$alloc_id" \
    --instance-id "$inst_id" \
    --output json 2>&1)" || die "Failed to associate EIP:\n$result"

  local assoc_id
  assoc_id="$(printf '%s' "$result" | jq -r '.AssociationId')"

  log "EIP associated:"
  printf '  Association ID: %s\n' "$assoc_id"
  printf '  Instance:       %s (%s)\n\n' "${name:-<unnamed>}" "$inst_id"
}

_eip_disassociate() {
  local assoc_id="${1:-}"

  if [[ -z "$assoc_id" ]]; then
    die "Usage: ec2 eip disassoc <association-id>
List associations with: ec2 eip list"
  fi

  info "Disassociating $assoc_id..."

  if ! dry_run_guard "aws ec2 disassociate-address --association-id $assoc_id"; then
    return 0
  fi

  confirm "Disassociate EIP?" || return 1

  aws_cmd ec2 disassociate-address --association-id "$assoc_id" 2>/dev/null
  log "EIP disassociated: $assoc_id"
}

_eip_release() {
  local alloc_id="${1:-}"

  if [[ -z "$alloc_id" ]]; then
    die "Usage: ec2 eip release <allocation-id>"
  fi

  printf '  %bRelease (delete) Elastic IP: %s%b\n' "$RED" "$alloc_id" "$NC"

  if ! dry_run_guard "aws ec2 release-address --allocation-id $alloc_id"; then
    return 0
  fi

  confirm "Release this Elastic IP permanently?" || return 1

  aws_cmd ec2 release-address --allocation-id "$alloc_id" 2>/dev/null
  log "EIP released: $alloc_id"
}

_eip_help() {
  cat <<'HELP'
Usage: ec2 eip <action> [ARGS]

Manage Elastic IPs (EIPs).

Actions:
  list                              List all EIPs
  alloc [name]                      Allocate a new EIP
  assoc <alloc-id> <name|inst-id>   Associate EIP with instance
  disassoc <assoc-id>               Disassociate EIP from instance
  release <alloc-id>                Release (delete) an EIP

Examples:
  ec2 eip list
  ec2 eip alloc my-static-ip
  ec2 eip assoc eipalloc-abc123 mybox
  ec2 eip release eipalloc-abc123
HELP
}
