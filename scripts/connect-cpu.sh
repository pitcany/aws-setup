#!/usr/bin/env bash
# Start an existing stopped CPU instance and connect via SSH

set -euo pipefail

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Initialize environment and validate
init_env
check_ssh_key

# Find the CPU instance by name tag
echo "Looking for CPU instance '${CPU_INSTANCE_NAME}'..."

INSTANCE_INFO=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${CPU_INSTANCE_NAME}*" \
            "Name=instance-state-name,Values=stopped,running" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' \
  --output text)

if [ -z "$INSTANCE_INFO" ]; then
  echo -e "${RED}ERROR: No instance found with name '${CPU_INSTANCE_NAME}'${NC}"
  echo "Create one first with: ./scripts/launch-cpu.sh"
  exit 1
fi

# If multiple matches, show them and pick the first stopped one (or first running one)
INSTANCE_COUNT=$(echo "$INSTANCE_INFO" | wc -l | tr -d ' ')

if [ "$INSTANCE_COUNT" -gt 1 ]; then
  echo -e "${YELLOW}Found $INSTANCE_COUNT matching instances:${NC}"
  echo "$INSTANCE_INFO" | while IFS=$'\t' read -r id state name; do
    echo "  $name ($id) - $state"
  done
  echo ""
fi

# Prefer a stopped instance; fall back to running
INSTANCE_ID=$(echo "$INSTANCE_INFO" | awk '$2 == "stopped" { print $1; exit }')
INSTANCE_STATE="stopped"

if [ -z "$INSTANCE_ID" ]; then
  # No stopped instance — grab a running one
  INSTANCE_ID=$(echo "$INSTANCE_INFO" | awk '$2 == "running" { print $1; exit }')
  INSTANCE_STATE="running"
fi

if [ -z "$INSTANCE_ID" ]; then
  echo -e "${RED}ERROR: Could not select an instance${NC}"
  exit 1
fi

INSTANCE_NAME=$(echo "$INSTANCE_INFO" | awk -v id="$INSTANCE_ID" '$1 == id { print $3 }')
echo "Selected: ${INSTANCE_NAME} (${INSTANCE_ID}) - ${INSTANCE_STATE}"
echo ""

# Start the instance if stopped
if [ "$INSTANCE_STATE" == "stopped" ]; then
  echo -e "${GREEN}Starting instance...${NC}"
  aws ec2 start-instances --instance-ids "$INSTANCE_ID" > /dev/null

  echo -n "Waiting for instance to start"
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" &
  WAIT_PID=$!
  while kill -0 "$WAIT_PID" 2>/dev/null; do
    echo -n "."
    sleep 2
  done
  echo " ✓"
fi

# Get the public IP
IP=$(wait_for_instance_ip "$INSTANCE_ID")

if [ -z "$IP" ]; then
  echo -e "${RED}ERROR: Failed to get instance IP${NC}"
  exit 1
fi

# Determine SSH user from the instance's AMI
AMI_ID=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].ImageId' \
  --output text)
SSH_USER=$(get_ssh_user "$AMI_ID")

echo ""
echo -e "${GREEN}Instance is ready!${NC}"
echo "  Instance ID: $INSTANCE_ID"
echo "  Public IP:   $IP"
echo ""
echo -e "${GREEN}Connecting via SSH...${NC}"
echo ""

exec ssh -i "$SSH_KEY_PATH" "$SSH_USER@$IP"
