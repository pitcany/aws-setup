#!/usr/bin/env bash
# Launch a GPU spot instance (g4dn.xlarge with NVIDIA T4)

set -euo pipefail

# Source the shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      print_usage
      exit 0
      ;;
    --instance-type)
      INSTANCE_TYPE="$2"
      shift 2
      ;;
    --key-name)
      KEY_NAME="$2"
      shift 2
      ;;
    --ssh-key)
      SSH_KEY_PATH="$2"
      shift 2
      ;;
    --ami-id)
      AMI_ID="$2"
      shift 2
      ;;
    --volume-size)
      VOLUME_SIZE="$2"
      shift 2
      ;;
    *)
      echo -e "${RED}ERROR: Unknown option: $1${NC}"
      print_usage
      exit 1
      ;;
  esac
done

# Initialize environment and validate
init_env
check_ssh_key

# Use provided values or fall back to config or hardcoded defaults
: "${INSTANCE_TYPE:=${DEFAULT_GPU_INSTANCE_TYPE:-g4dn.xlarge}}"
: "${KEY_NAME:=${KEY_NAME:-my-datascience-key}}"
: "${SSH_KEY_PATH:=${SSH_KEY_PATH:-~/.ssh/my-datascience-key.pem}}"
: "${AMI_ID:=${GPU_AMI_ID:-ami-xxxxxxxx}}"
: "${VOLUME_SIZE:=${DEFAULT_GPU_VOLUME_SIZE:-100}}"
: "${AWS_REGION:=${AWS_DEFAULT_REGION:-us-west-2}}"

# If AMI_ID is still placeholder, try to find latest
if [[ "$AMI_ID" == *"ami-xxxxxxxx"* ]]; then
  echo -e "${YELLOW}WARNING: AMI ID not configured${NC}"
  echo "Searching for latest Deep Learning AMI..."

  LATEST_AMI=$(find_latest_ami "Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)")
  AMI_ID=$(echo "$LATEST_AMI" | cut -f1)

  if [[ "$AMI_ID" == "None" ]] || [[ -z "$AMI_ID" ]]; then
    echo -e "${RED}ERROR: Could not find Deep Learning AMI${NC}"
    exit 1
  fi

  echo "Using AMI: $AMI_ID"
fi

echo -e "${GREEN}Launching GPU spot instance...${NC}"
echo "  Instance type: $INSTANCE_TYPE"
echo "  AMI ID: $AMI_ID"
echo "  Volume size: ${VOLUME_SIZE}GB"
echo ""

# Launch the instance
INSTANCE_ID=$(aws ec2 run-instances \
  --instance-type "$INSTANCE_TYPE" \
  --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time"}}' \
  --image-id "$AMI_ID" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SECURITY_GROUP_ID" \
  --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$VOLUME_SIZE,\"VolumeType\":\"gp3\"}}]" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$GPU_INSTANCE_NAME}]" \
  --query "Instances[0].[InstanceId,SpotInstanceRequestId]" \
  --output text)

if [ -z "$INSTANCE_ID" ]; then
  echo -e "${RED}ERROR: Failed to launch instance${NC}"
  exit 1
fi

INSTANCE_ID=$(echo "$INSTANCE_ID" | cut -f1)

echo -e "${GREEN}Instance launched successfully${NC}"
echo "Instance ID: $INSTANCE_ID"
echo ""

# Wait for public IP
echo "Waiting for public IP..."
IP=$(wait_for_instance_ip "$INSTANCE_ID")

if [ -z "$IP" ]; then
  echo -e "${RED}ERROR: Failed to get instance IP${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}Instance is ready!${NC}"
echo "  Instance ID: $INSTANCE_ID"
echo "  Public IP:   $IP"
echo ""
echo -e "${GREEN}Connect with:${NC}"
echo "  ssh -i $SSH_KEY_PATH ubuntu@$IP"
echo ""
echo -e "${YELLOW}Terminate with:${NC}"
echo "  aws ec2 terminate-instances --instance-ids $INSTANCE_ID"
