#!/usr/bin/env bash
# Launch a CPU EC2 instance (for data science work)

set -euo pipefail

# Source shared library
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
    --spot)
      USE_SPOT="true"
      shift
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
: "${INSTANCE_TYPE:=${DEFAULT_CPU_INSTANCE_TYPE:-t3.medium}}"
: "${KEY_NAME:=${KEY_NAME:-my-datascience-key}}"
: "${SSH_KEY_PATH:=${SSH_KEY_PATH:-~/.ssh/my-datascience-key.pem}}"
: "${AMI_ID:=${CPU_AMI_ID:-ami-xxxxxxxx}}"
: "${VOLUME_SIZE:=${DEFAULT_CPU_VOLUME_SIZE:-20}}"
: "${AWS_REGION:=${AWS_DEFAULT_REGION:-us-west-2}}"
: "${CPU_INSTANCE_NAME:=${CPU_INSTANCE_NAME:-datascience-daily}}"
: "${USE_SPOT:=false}"

# If AMI_ID is still placeholder, try to find latest
if [[ "$AMI_ID" == *"ami-xxxxxxxx"* ]]; then
  echo -e "${YELLOW}WARNING: AMI ID not configured${NC}"
  echo "Searching for latest Ubuntu 22.04 LTS AMI..."

  AMI_ID=$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
              "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)

  if [[ "$AMI_ID" == "None" ]] || [[ -z "$AMI_ID" ]]; then
    echo -e "${RED}ERROR: Could not find Ubuntu 22.04 LTS AMI${NC}"
    exit 1
  fi

  echo "Using AMI: $AMI_ID"
fi

echo -e "${GREEN}Launching CPU instance...${NC}"
echo "  Instance type: $INSTANCE_TYPE"
echo "  AMI ID: $AMI_ID"
echo "  Volume size: ${VOLUME_SIZE}GB"

if [[ "$USE_SPOT" == "true" ]]; then
  echo "  Market: Spot instance (~20-70% savings)"
  SPOT_OPTIONS="--instance-market-options '{\"MarketType\":\"spot\",\"SpotOptions\":{\"SpotInstanceType\":\"one-time\"}}'"
  SPOT_TAG="CPU spot"
else
  echo "  Market: On-demand instance"
  SPOT_OPTIONS=""
  SPOT_TAG="CPU on-demand"
fi

echo ""

# Launch instance
if [[ "$USE_SPOT" == "true" ]]; then
  INSTANCE_ID=$(aws ec2 run-instances \
    --instance-type "$INSTANCE_TYPE" \
    $SPOT_OPTIONS \
    --image-id "$AMI_ID" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":$VOLUME_SIZE,\"VolumeType\":\"gp3\"}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$CPU_INSTANCE_NAME-$SPOT_TAG}]" \
    --query "Instances[0].InstanceId" \
    --output text)
else
  INSTANCE_ID=$(aws ec2 run-instances \
    --instance-type "$INSTANCE_TYPE" \
    --image-id "$AMI_ID" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":$VOLUME_SIZE,\"VolumeType\":\"gp3\"}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$CPU_INSTANCE_NAME-$SPOT_TAG}]" \
    --query "Instances[0].InstanceId" \
    --output text)
fi

if [ -z "$INSTANCE_ID" ]; then
  echo -e "${RED}ERROR: Failed to launch instance${NC}"
  exit 1
fi

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

SSH_USER=$(get_ssh_user "$AMI_ID")

echo -e "${GREEN}Connect with:${NC}"
echo "  ssh -i $SSH_KEY_PATH $SSH_USER@$IP"
echo ""

echo -e "${YELLOW}Manage instance:${NC}"
echo "  Stop:  aws ec2 stop-instances --instance-ids $INSTANCE_ID"
echo "  Start: aws ec2 start-instances --instance-ids $INSTANCE_ID"
echo "  Terminate: aws ec2 terminate-instances --instance-ids $INSTANCE_ID"
