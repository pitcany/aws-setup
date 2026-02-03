#!/usr/bin/env bash
# List all EC2 instances with useful information

set -euo pipefail

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Initialize environment
init_env

echo -e "${GREEN}EC2 Instances:${NC}"
echo ""

aws ec2 describe-instances \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],InstanceId,InstanceType,State.Name,PublicIpAddress]' \
  --output table

echo ""
echo -e "Use scripts/launch-gpu.sh to launch GPU instances"
