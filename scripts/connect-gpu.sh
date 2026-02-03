#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

init_env
check_ssh_key

echo "Looking for running GPU instance '${GPU_INSTANCE_NAME}'..."

INSTANCE_INFO=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${GPU_INSTANCE_NAME}*" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,PublicIpAddress,Tags[?Key==`Name`].Value|[0],ImageId]' \
  --output text)

if [ -z "$INSTANCE_INFO" ]; then
  echo -e "${RED}ERROR: No running GPU instance found${NC}"
  echo "Launch one first with: ./scripts/launch-gpu.sh"
  exit 1
fi

INSTANCE_COUNT=$(echo "$INSTANCE_INFO" | wc -l | tr -d ' ')

if [ "$INSTANCE_COUNT" -gt 1 ]; then
  echo -e "${YELLOW}Found $INSTANCE_COUNT running GPU instances:${NC}"
  echo "$INSTANCE_INFO" | while IFS=$'\t' read -r id ip name _ami; do
    echo "  $name ($id) - $ip"
  done
  echo ""
  echo "Connecting to the first one."
  echo ""
fi

read -r INSTANCE_ID IP INSTANCE_NAME AMI_ID <<< "$(echo "$INSTANCE_INFO" | head -1)"

SSH_USER=$(get_ssh_user "$AMI_ID")

echo -e "${GREEN}Connecting to GPU instance${NC}"
echo "  Instance:  $INSTANCE_NAME ($INSTANCE_ID)"
echo "  Public IP: $IP"
echo ""

exec ssh -i "$SSH_KEY_PATH" "$SSH_USER@$IP"
