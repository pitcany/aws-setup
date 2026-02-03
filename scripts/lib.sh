#!/usr/bin/env bash
# Shared library for AWS EC2 scripts
# Source this file in your scripts: source scripts/lib.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load configuration first (will set variables from .env if file exists)
# Handle different ways lib.sh might be sourced
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  config_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  config_dir="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"
fi
env_file="${config_dir}/config/.env"

if [ -f "$env_file" ]; then
  # shellcheck source=/dev/null
  source "$env_file"
fi

# Load configuration from .env file if it exists
load_config() {
  local config_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local env_file="${config_dir}/config/.env"

  if [ -f "$env_file" ]; then
    # shellcheck source=/dev/null
    source "$env_file"
  fi
}

# Check if AWS CLI is configured and working
check_aws_cli() {
  if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI is not installed${NC}"
    echo "Install from: https://aws.amazon.com/cli/"
    exit 1
  fi

  if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI is not configured${NC}"
    echo "Run: aws configure"
    exit 1
  fi
}

# Check if SSH key exists
check_ssh_key() {
  # Expand ~ to home directory
  local expanded_key_path="${SSH_KEY_PATH/#\~/$HOME}"

  if [ ! -f "$expanded_key_path" ]; then
    echo -e "${RED}ERROR: SSH key not found at $expanded_key_path${NC}"
    echo "Update SSH_KEY_PATH in config/.env or on command line"
    exit 1
  fi

  # Check permissions
  local key_perms=$(stat -f "%OLp" "$expanded_key_path" 2>/dev/null || stat -c "%a" "$expanded_key_path" 2>/dev/null)
  if [ "$key_perms" != "600" ] && [ "$key_perms" != "400" ]; then
    echo -e "${YELLOW}WARNING: SSH key has insecure permissions: $key_perms${NC}"
    echo "Recommended: chmod 400 $expanded_key_path"
  fi
}

# Get public IP for an instance
get_instance_ip() {
  local instance_id=$1
  aws ec2 describe-instances \
    --instance-ids "$instance_id" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text 2>/dev/null || echo "None"
}

# Wait for instance to have a public IP
wait_for_instance_ip() {
  local instance_id=$1
  local max_attempts=${2:-24}  # Default: 24 attempts
  local sleep_time=${3:-5}     # Default: 5 seconds

  echo -n "Waiting for public IP"

  for ((i=1; i<=max_attempts; i++)); do
    local ip=$(get_instance_ip "$instance_id")

    if [ "$ip" != "None" ] && [ -n "$ip" ]; then
      echo " ✓"
      echo "$ip"
      return 0
    fi

    echo -n "."
    sleep "$sleep_time"
  done

  echo ""
  echo -e "${RED}ERROR: Timeout waiting for instance IP${NC}"
  return 1
}

# Find latest AMI for a given pattern
find_latest_ami() {
  local ami_pattern=$1

  aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=$ami_pattern*" "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].[ImageId,Name]' \
    --output text
}

# Print usage information
print_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -h, --help              Show this help message"
  echo "  --region REGION         AWS region (default: $AWS_DEFAULT_REGION)"
  echo "  --instance-type TYPE    Instance type (default: $DEFAULT_GPU_INSTANCE_TYPE)"
  echo "  --key-name NAME        AWS key pair name (default: $KEY_NAME)"
  echo "  --ssh-key PATH         Path to SSH private key (default: $SSH_KEY_PATH)"
  echo "  --ami-id ID            AMI ID to use"
  echo "  --volume-size SIZE     Volume size in GB (default: $DEFAULT_GPU_VOLUME_SIZE)"
  echo ""
  echo "Configuration is loaded from config/.env if it exists"
}

# Initialize environment
init_env() {
  load_config
  check_aws_cli
}

# Set default values (used only if config doesn't set them)
# These are applied after config loading so they don't override config values
: "${AWS_DEFAULT_REGION:=us-west-2}"
: "${SSH_KEY_PATH:=~/.ssh/my-datascience-key.pem}"
: "${KEY_NAME:=my-datascience-key}"
: "${SECURITY_GROUP_ID:=sg-xxxxxxxx}"
: "${GPU_AMI_ID:=ami-xxxxxxxx}"
: "${DEFAULT_GPU_INSTANCE_TYPE:=g4dn.xlarge}"
: "${GPU_INSTANCE_NAME:=gpu-training}"
: "${DEFAULT_GPU_VOLUME_SIZE:=100}"
