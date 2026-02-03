#!/usr/bin/env bash
# Create and configure security group for data science EC2 instances
#
# Rules:
#   - SSH (22)          from your IP only
#   - HTTP (80)         from anywhere (web dashboard)
#   - HTTPS (443)       from anywhere (web dashboard)
#   - TCP 3000          from your IP only (OpenClaw dashboard)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Initialize environment
init_env

SG_NAME="${1:-datascience-sg}"
SG_DESCRIPTION="Security group for data science EC2 instances"

# Get caller's public IP
echo "Detecting your public IP..."
MY_IP=$(curl -s --fail ifconfig.me || curl -s --fail icanhazip.com)
if [ -z "$MY_IP" ]; then
  echo -e "${RED}ERROR: Could not detect public IP${NC}"
  exit 1
fi
echo -e "Your IP: ${GREEN}${MY_IP}${NC}"

# Check if security group already exists
EXISTING_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || echo "None")

if [ "$EXISTING_SG" != "None" ] && [ -n "$EXISTING_SG" ]; then
  echo -e "${YELLOW}Security group '$SG_NAME' already exists: $EXISTING_SG${NC}"
  echo "Updating ingress rules..."
  SG_ID="$EXISTING_SG"

  # Revoke all existing ingress rules
  EXISTING_RULES=$(aws ec2 describe-security-groups \
    --group-ids "$SG_ID" \
    --query 'SecurityGroups[0].IpPermissions' \
    --output json)

  if [ "$EXISTING_RULES" != "[]" ] && [ "$EXISTING_RULES" != "null" ]; then
    aws ec2 revoke-security-group-ingress \
      --group-id "$SG_ID" \
      --ip-permissions "$EXISTING_RULES" > /dev/null
    echo "Cleared existing ingress rules"
  fi
else
  echo "Creating security group '$SG_NAME'..."
  SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "$SG_DESCRIPTION" \
    --query 'GroupId' \
    --output text)
  echo -e "${GREEN}Created security group: $SG_ID${NC}"
fi

# Add ingress rules
echo ""
echo "Adding ingress rules..."

# SSH (port 22) - your IP only
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=${MY_IP}/32,Description=SSH from my IP}]" > /dev/null
echo -e "  ${GREEN}✓${NC} SSH (22)   ← ${MY_IP}/32"

# HTTP (port 80) - anywhere
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description=HTTP}]" > /dev/null
echo -e "  ${GREEN}✓${NC} HTTP (80)  ← 0.0.0.0/0"

# HTTPS (port 443) - anywhere
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0,Description=HTTPS}]" > /dev/null
echo -e "  ${GREEN}✓${NC} HTTPS (443) ← 0.0.0.0/0"

# OpenClaw dashboard (port 3000) - your IP only
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=3000,ToPort=3000,IpRanges=[{CidrIp=${MY_IP}/32,Description=OpenClaw dashboard from my IP}]" > /dev/null
echo -e "  ${GREEN}✓${NC} TCP (3000) ← ${MY_IP}/32"

echo ""
echo -e "${GREEN}Security group configured: $SG_ID${NC}"
echo ""
echo -e "${YELLOW}Update your config/.env:${NC}"
echo "  SECURITY_GROUP_ID=$SG_ID"
