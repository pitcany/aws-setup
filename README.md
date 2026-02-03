# AWS EC2 Data Science Environment

A budget-friendly, reusable setup for AWS EC2 instances tailored for data science work. This toolkit provides scripts and documentation to launch and manage CPU and GPU instances efficiently.

## Features

- **Cost-effective setup**: t3.medium for daily work (~$0.04/hr), GPU spot instances for training (~$0.24/hr)
- **Reusable scripts**: Shell scripts with configuration management and error handling
- **GPU spot instances**: On-demand GPU access with up to 70% cost savings
- **S3 integration**: Seamless data transfer between instances
- **Pre-configured**: Python 3.11, R 4.3.2, Jupyter, and popular data science packages

## Quick Start

### Prerequisites

- AWS account with billing enabled
- AWS CLI installed and configured
- IAM permissions for EC2, S3, and Service Quotas
- Terminal with SSH client

### Setup

1. **Clone this repository**
   ```bash
   git clone <repository-url>
   cd aws
   ```

2. **Configure your environment**
   ```bash
   # Copy example config file
   cp config/.env.example config/.env

   # Edit with your values
   nano config/.env
   ```

3. **Create SSH key pair** (if you don't have one)
   ```bash
   aws ec2 create-key-pair \
     --key-name my-datascience-key \
     --query 'KeyMaterial' \
     --output text > ~/.ssh/my-datascience-key.pem
   chmod 400 ~/.ssh/my-datascience-key.pem
   ```

4. **Create security group** (if you don't have one)
   ```bash
   SG_ID=$(aws ec2 create-security-group \
     --group-name datascience-sg \
     --description "Security group for data science EC2 instances" \
     --query 'GroupId' \
     --output text)

   # Allow SSH access
   aws ec2 authorize-security-group-ingress \
     --group-id $SG_ID \
     --protocol tcp \
     --port 22 \
     --cidr 0.0.0.0/0
   ```

5. **Update config/.env** with your security group ID and key name

## Usage

### Launch CPU Instance

```bash
# Launch on-demand CPU instance (default: t3.medium)
./scripts/launch-cpu.sh

# Launch CPU spot instance (~20-70% savings)
./scripts/launch-cpu.sh --spot

# Launch with custom settings
./scripts/launch-cpu.sh \
  --instance-type t3.large \
  --volume-size 50 \
  --ami-id ami-01234567890abcdef0
```

### Launch GPU Spot Instance

```bash
# Launch with default configuration
./scripts/gpu-spot.sh

# Launch with custom settings
./scripts/gpu-spot.sh \
  --instance-type g4dn.2xlarge \
  --volume-size 200 \
  --ami-id ami-01234567890abcdef0
```

### List All Instances

```bash
./scripts/list-instances.sh
```

### Manage Instances

```bash
# Stop an instance
aws ec2 stop-instances --instance-ids <INSTANCE_ID>

# Start an instance
aws ec2 start-instances --instance-ids <INSTANCE_ID>

# Terminate an instance (permanently delete)
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>
```

## Project Structure

```
aws/
├── scripts/
│   ├── gpu-spot.sh       # Launch GPU spot instances
│   ├── list-instances.sh # List all EC2 instances
│   └── lib.sh            # Shared library with common functions
├── docs/
│   └── setup-guide.md     # Complete setup documentation
├── config/
│   └── .env.example      # Example configuration file
├── personal/
│   └── aws-ec2-datascience-setup.md  # Personal reference (not in git)
├── .gitignore           # Excludes secrets and system files
└── README.md            # This file
```

## Configuration

The scripts read configuration from `config/.env` (if it exists). Create this file from the example:

```bash
cp config/.env.example config/.env
```

Required settings in `.env`:
- `KEY_NAME`: Your AWS key pair name
- `SECURITY_GROUP_ID`: Your security group ID
- `SSH_KEY_PATH`: Path to your private SSH key

Optional settings:
- `AWS_DEFAULT_REGION`: AWS region (default: us-west-2)
- `GPU_AMI_ID`: Deep Learning AMI ID (auto-detected if not set)
- `DEFAULT_GPU_INSTANCE_TYPE`: Default instance type (default: g4dn.xlarge)
- `DEFAULT_GPU_VOLUME_SIZE`: Default volume size in GB (default: 100)

**Security note**: Never commit `.env` files to git. Add `*.pem` and `.env` to your `.gitignore`.

## Documentation

Complete setup instructions and usage examples are in [docs/setup-guide.md](docs/setup-guide.md).

Topics covered:
- AWS prerequisites and CLI setup
- Creating key pairs and security groups
- Setting up S3 storage
- EBS snapshots and backups
- Elastic IP management
- GPU spot instance management
- Cost optimization tips
- Troubleshooting common issues
- Security best practices

## Cost Management

Keep your AWS costs low by following these practices:

1. **Stop instances when not in use**: Stopped instances only pay for storage (~$2/month for 20GB)
2. **Use spot instances for GPU**: Up to 70% savings vs on-demand pricing
3. **Monitor with AWS Budgets**: Set alerts at $10, $25, $50
4. **Terminate GPU instances immediately**: After training jobs complete

## Scripts Reference

### `scripts/gpu-spot.sh`

Launches a GPU spot instance with error handling and auto-detection of latest AMI.

**Usage:**
```bash
scripts/gpu-spot.sh [OPTIONS]
```

**Options:**
- `-h, --help`: Show help message
- `--instance-type TYPE`: Instance type (default: g4dn.xlarge)
- `--key-name NAME`: AWS key pair name
- `--ssh-key PATH`: Path to SSH private key
- `--ami-id ID`: AMI ID to use (auto-detected if not specified)
- `--volume-size SIZE`: Volume size in GB (default: 100)

**Example:**
```bash
./scripts/gpu-spot.sh --instance-type g4dn.2xlarge --volume-size 200
```

### `scripts/list-instances.sh`

Lists all EC2 instances with instance name, ID, type, state, and public IP.

**Usage:**
```bash
scripts/list-instances.sh
```

**Output:**
```
Instance Name      InstanceId           InstanceType   State.Name  PublicIpAddress
----------------- -------------------- -------------- ----------- --------------
gpu-training      i-0abc123def456     g4dn.xlarge     running      54.123.45.67
datascience-daily i-0xyz789ghi012     t3.medium       running      54.234.56.78
```

### `scripts/lib.sh`

Shared library containing common functions used by all scripts. Source this file in your scripts:

```bash
source scripts/lib.sh
```

**Available functions:**
- `load_config()`: Load configuration from .env file
- `check_aws_cli()`: Verify AWS CLI is installed and configured
- `check_ssh_key()`: Verify SSH key exists and has correct permissions
- `get_instance_ip()`: Get public IP for an instance
- `wait_for_instance_ip()`: Wait for instance to have a public IP
- `find_latest_ami()`: Find latest AMI for a given pattern
- `print_usage()`: Print usage information

## Troubleshooting

### Can't connect via SSH

1. Check instance is running: `aws ec2 describe-instances --instance-ids <INSTANCE_ID>`
2. Verify you're using the correct IP
3. Check security group allows port 22
4. Verify SSH key permissions: `chmod 400 ~/.ssh/my-datascience-key.pem`

### GPU instance won't launch

GPU spot capacity varies by availability zone. Try specifying a different AZ:

```bash
./scripts/gpu-spot.sh --instance-type g4dn.xlarge
# If "InsufficientInstanceCapacity" error, try:
aws ec2 run-instances ... --placement AvailabilityZone=us-west-2b ...
```

Check current spot prices:
```bash
aws ec2 describe-spot-price-history \
  --instance-types g4dn.xlarge \
  --product-descriptions "Linux/UNIX" \
  --start-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --query 'SpotPriceHistory[*].[AvailabilityZone,SpotPrice]' \
  --output table
```

### Out of memory

Consider upgrading to a larger instance type:
- `t3.large` (8GB RAM)
- `r6i.large` (16GB RAM)

## Security

### SSH Key Security

- Never commit `.pem` files to git
- Restrict file permissions: `chmod 400 ~/.ssh/my-datascience-key.pem`
- Store backups in a password manager or encrypted storage
- If compromised, delete the key pair in AWS and create a new one

### Restrict SSH Access

By default, the security group allows SSH from `0.0.0.0/0` (anywhere). To restrict to your IP only:

```bash
# Get your current public IP
MY_IP=$(curl -s ifconfig.me)

# Add rule for your IP
aws ec2 authorize-security-group-ingress \
  --group-id <SG_ID> \
  --protocol tcp \
  --port 22 \
  --cidr ${MY_IP}/32

# Remove the 0.0.0.0/0 rule (optional)
aws ec2 revoke-security-group-ingress \
  --group-id <SG_ID> \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
```

### Alternative: AWS Systems Manager Session Manager

For SSH-key-free access, use SSM Session Manager:

```bash
aws ssm start-session --target <INSTANCE_ID>
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This project is open source. See [LICENSE](LICENSE) file for details.

## Author

Created for data scientists who need flexible, cost-effective AWS infrastructure.

## Changelog

### Version 1.0.0 (Current)
- Initial release
- GPU spot instance launcher with error handling
- Instance listing script
- Configuration management via .env files
- Shared library with common AWS functions
- Complete setup documentation
