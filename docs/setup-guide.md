# AWS EC2 Data Science Setup Guide: A Budget-Friendly Approach

As a data scientist, you need computing power that scales with your workload—lightweight for data exploration, heavy-duty for model training. This guide shows you how to set up a cost-effective AWS EC2 environment with a daily-driver CPU instance and on-demand GPU access for deep learning.

**What you'll build:**
- A t3.medium instance (~$0.04/hr) for everyday data science work
- GPU spot instances (~$0.24/hr) for deep learning, launched only when needed
- S3 storage for sharing data between instances
- Total cost: ~$10-15/month for moderate use

## Table of Contents

- [Prerequisites](#prerequisites)
- [Overview](#overview)
- [Setup from Scratch](#setup-from-scratch)
- [Quick Reference Commands](#quick-reference-commands)
- [Installed Software](#installed-software)
- [S3 Data Storage](#s3-data-storage)
- [EBS Snapshots (Backups)](#ebs-snapshots-backups)
- [Elastic IP Management](#elastic-ip-management)
- [GPU Spot Instance (For Deep Learning)](#gpu-spot-instance-for-deep-learning)
- [Cost Management Tips](#cost-management-tips)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)

---

## Prerequisites

Before starting, ensure you have:

- **AWS Account** with billing enabled
- **AWS CLI** installed and configured (`aws configure`)
- **IAM permissions** for EC2, S3, and Service Quotas (or use an Administrator role)
- **Terminal** with SSH client (built into macOS/Linux; use Git Bash or WSL on Windows)

### Verify AWS CLI Setup

```bash
# Check CLI is configured
aws sts get-caller-identity

# Should return your account ID and user/role ARN
```

### GPU Spot Instance Quota

New AWS accounts have 0 vCPU quota for GPU spot instances. To use GPU spot instances, request a quota increase:

```bash
# Check current quota
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-3819A6DF \
  --query 'Quota.Value'

# Request increase to 4 vCPUs (enough for g4dn.xlarge)
aws service-quotas request-service-quota-increase \
  --service-code ec2 \
  --quota-code L-3819A6DF \
  --desired-value 4
```

Approval typically takes a few hours to 1 business day.

---

## Overview

| Component | Details |
|-----------|---------|
| **Instance Type** | t3.medium (2 vCPU, 4GB RAM) |
| **AMI** | Amazon Linux 2023 (find latest with command below) |
| **Region** | us-west-2 (adjust for your region) |
| **EBS Storage** | 20GB gp3 (instance's hard drive) |
| **S3 Bucket** | For shared data storage |
| **Cost** | ~$0.042/hr (~$6.60/month at 160 hrs) |

> **Note**: AMI IDs are region-specific and updated regularly. Always find the latest AMI using the commands in [Setup from Scratch](#setup-from-scratch).

### EBS vs S3 Storage

| | EBS | S3 |
|---|---|---|
| **What it is** | Virtual hard drive attached to instance | Cloud object storage |
| **Contains** | OS, installed software, local working files | Data you explicitly upload/download |
| **Access** | Only the attached instance | Any instance, from anywhere |
| **Use for** | Running programs, temporary work | Sharing data between instances, backups |

Think of **EBS** as your laptop's internal SSD, and **S3** as Dropbox.

---

## Setup from Scratch

### 1. Create Key Pair

```bash
aws ec2 create-key-pair \
  --key-name my-datascience-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/my-datascience-key.pem
chmod 400 ~/.ssh/my-datascience-key.pem
```

### 2. Create Security Group

```bash
# Create security group
SG_ID=$(aws ec2 create-security-group \
  --group-name datascience-sg \
  --description "Security group for data science EC2 instances" \
  --query 'GroupId' \
  --output text)

echo "Created security group: $SG_ID"

# Allow SSH access
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
```

### 3. Create S3 Bucket

```bash
# Create a bucket (name must be globally unique)
BUCKET_NAME="my-datascience-$(date +%s)"
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

echo "Created bucket: $BUCKET_NAME"
```

### 4. Find Latest AMI

```bash
# Amazon Linux 2023 (for t3.medium)
aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023*-x86_64" "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].[ImageId,Name]' \
  --output text
```

### 5. Launch Instance

```bash
# Replace <AMI_ID> and <SG_ID> with values from previous steps
aws ec2 run-instances \
  --image-id <AMI_ID> \
  --instance-type t3.medium \
  --key-name my-datascience-key \
  --security-group-ids <SG_ID> \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=datascience-daily}]' \
  --query 'Instances[0].InstanceId' \
  --output text
```

### 6. Get Instance IP

```bash
# Wait for instance to start, then get public IP
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=datascience-daily" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text
```

### 7. Connect and Install Data Science Tools

```bash
ssh -i ~/.ssh/my-datascience-key.pem ec2-user@<INSTANCE_IP>
```

Once connected, run:

```bash
# Update system
sudo dnf update -y

# Install Python 3.11
sudo dnf install -y python3.11 python3.11-pip python3.11-devel
sudo dnf install -y gcc gcc-c++ make git

# Install R
sudo dnf install -y R-core R-core-devel
sudo dnf install -y libcurl-devel openssl-devel libxml2-devel

# Install Python packages
python3.11 -m pip install --user \
  numpy pandas scipy matplotlib seaborn \
  scikit-learn jupyter statsmodels pyarrow
```

---

## Quick Reference Commands

### Connect to Instance

```bash
ssh -i ~/.ssh/my-datascience-key.pem ec2-user@<INSTANCE_IP>
```

### SSH Config Shortcut (Optional)

Add this to `~/.ssh/config` for easier connections:

```
Host datascience
    HostName <INSTANCE_IP>
    User ec2-user
    IdentityFile ~/.ssh/my-datascience-key.pem

Host gpu
    HostName <GPU_IP>
    User ubuntu
    IdentityFile ~/.ssh/my-datascience-key.pem
```

Then connect with just: `ssh datascience` or `ssh gpu`

### Instance Management

```bash
# Check instance status
aws ec2 describe-instances \
  --instance-ids <INSTANCE_ID> \
  --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress]' \
  --output table

# Stop instance (saves money, keeps EBS data)
aws ec2 stop-instances --instance-ids <INSTANCE_ID>

# Start instance
aws ec2 start-instances --instance-ids <INSTANCE_ID>

# Terminate instance (permanently delete - cannot undo!)
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>
```

### Without an Elastic IP

If you don't have an Elastic IP attached, the public IP changes every time you stop/start:

```bash
# Start instance
aws ec2 start-instances --instance-ids <INSTANCE_ID>

# Wait for it to start, then get the new IP
aws ec2 describe-instances \
  --instance-ids <INSTANCE_ID> \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text
```

This applies to the GPU spot instance, which doesn't have an Elastic IP attached.

---

## Installed Software

### Python 3.11
- **numpy** - Numerical computing
- **pandas** - Data manipulation
- **scipy** - Scientific computing
- **matplotlib** - Plotting
- **seaborn** - Statistical visualization
- **scikit-learn** - Machine learning
- **statsmodels** - Statistical modeling
- **jupyter** - Interactive notebooks
- **pyarrow** - Columnar data / Parquet support

### R 4.3.2
- Base R with development tools
- Ready for package installation

**Install R packages** (run inside R):

```r
# Install common data science packages
install.packages(c("tidyverse", "data.table", "caret", "randomForest", "xgboost"))

# Install Bioconductor (for bioinformatics)
if (!require("BiocManager", quietly = TRUE))
    install.packages("BiocManager")
BiocManager::install()
```

### Usage on EC2

```bash
# Run Python
python3.11

# Run Jupyter (accessible via SSH tunnel)
python3.11 -m jupyter lab --no-browser --port=8888

# Run R
R
```

### Environment Persistence

- **Installed packages persist** across stop/start (stored on EBS)
- **Running processes are killed** when you stop the instance
- **In-memory data is lost** when you stop — save work to disk or S3 before stopping
- **Pip packages** installed with `--user` are stored in `~/.local/` on EBS

### Jupyter Notebook Access

To access Jupyter from your local machine:

```bash
# In a local terminal, create SSH tunnel
ssh -i ~/.ssh/my-datascience-key.pem -L 8888:localhost:8888 ec2-user@<INSTANCE_IP>

# On the EC2 instance, start Jupyter
python3.11 -m jupyter lab --no-browser --port=8888
```

Then open `http://localhost:8888` in your browser.

---

## S3 Data Storage

Use S3 to share data between your t3.medium and GPU instances.

### Upload Data

```bash
# Upload a single file
aws s3 cp data.parquet s3://<YOUR_BUCKET>/

# Upload a directory
aws s3 cp ./data/ s3://<YOUR_BUCKET>/data/ --recursive

# Sync a directory (only uploads changed files)
aws s3 sync ./data/ s3://<YOUR_BUCKET>/data/
```

### Download Data

```bash
# Download a single file
aws s3 cp s3://<YOUR_BUCKET>/data.parquet .

# Download a directory
aws s3 cp s3://<YOUR_BUCKET>/data/ ./data/ --recursive

# Sync from S3
aws s3 sync s3://<YOUR_BUCKET>/data/ ./data/
```

### List Contents

```bash
aws s3 ls s3://<YOUR_BUCKET>/
aws s3 ls s3://<YOUR_BUCKET>/ --recursive --human-readable
```

### Delete Files

```bash
# Delete a single file
aws s3 rm s3://<YOUR_BUCKET>/old-file.csv

# Delete a directory
aws s3 rm s3://<YOUR_BUCKET>/old-data/ --recursive
```

### S3 Pricing
- Storage: ~$0.023/GB/month
- Transfer out: First 100GB/month free, then ~$0.09/GB
- Transfer between S3 and EC2 in same region: **Free**

---

## EBS Snapshots (Backups)

Create snapshots of your EBS volume to backup your instance's state (OS, installed software, data).

### Create a Snapshot

```bash
# Get your instance's volume ID
VOLUME_ID=$(aws ec2 describe-instances \
  --instance-ids <INSTANCE_ID> \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' \
  --output text)

# Create snapshot
aws ec2 create-snapshot \
  --volume-id $VOLUME_ID \
  --description "datascience-daily backup $(date +%Y-%m-%d)" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=datascience-backup}]' \
  --query 'SnapshotId' \
  --output text
```

### List Snapshots

```bash
aws ec2 describe-snapshots \
  --owner-ids self \
  --query 'Snapshots[*].[SnapshotId,StartTime,Description,State]' \
  --output table
```

### Restore from Snapshot

```bash
# Create a new volume from snapshot
aws ec2 create-volume \
  --snapshot-id <SNAPSHOT_ID> \
  --availability-zone us-west-2a \
  --volume-type gp3 \
  --query 'VolumeId' \
  --output text
```

### Delete Old Snapshots

```bash
aws ec2 delete-snapshot --snapshot-id <SNAPSHOT_ID>
```

### Snapshot Pricing
- ~$0.05/GB/month (only charged for used space, not provisioned size)

---

## Elastic IP Management

By default, your instance's public IP changes every time you stop/start. An Elastic IP gives you a static address.

### Create and Attach an Elastic IP

```bash
# 1. Allocate an Elastic IP
aws ec2 allocate-address --query '[AllocationId,PublicIp]' --output text
# Returns: eipalloc-xxx    x.x.x.x

# 2. Associate it with an instance (instance must exist, can be stopped or running)
aws ec2 associate-address --instance-id <INSTANCE_ID> --allocation-id <ALLOCATION_ID>
```

### Move Elastic IP Between Instances

```bash
# Disassociate from current instance
aws ec2 disassociate-address --association-id <ASSOCIATION_ID>

# Associate with different instance
aws ec2 associate-address --instance-id <NEW_INSTANCE_ID> --allocation-id <ALLOCATION_ID>
```

### Elastic IP Pricing
- **Free** when attached to a running instance
- **$0.005/hr** (~$3.60/month) when not attached or instance is stopped

### Release Elastic IP (if no longer needed)

```bash
aws ec2 release-address --allocation-id <ALLOCATION_ID>
```

---

## GPU Spot Instance (For Deep Learning)

Use a GPU spot instance when you need to train deep learning models. Spot instances are significantly cheaper than on-demand (~55% savings) but can be interrupted with 2-minute warning.

### GPU Instance Specs (g4dn.xlarge)

| Property | Value |
|----------|-------|
| **GPU** | 1x NVIDIA T4 (16GB VRAM) |
| **vCPU** | 4 |
| **RAM** | 16GB |
| **On-Demand Price** | ~$0.526/hr |
| **Spot Price** | ~$0.24/hr (varies by AZ) |
| **AMI** | Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04) |

### Check Current Spot Prices

```bash
aws ec2 describe-spot-price-history \
  --instance-types g4dn.xlarge \
  --product-descriptions "Linux/UNIX" \
  --start-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --query 'SpotPriceHistory[*].[AvailabilityZone,SpotPrice]' \
  --output table
```

### Find Latest Deep Learning AMI

```bash
aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)*" \
             "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].[ImageId,Name]' \
  --output text
```

### Launch GPU Spot Instance

```bash
# Launch g4dn.xlarge spot instance with Deep Learning AMI
aws ec2 run-instances \
  --image-id <DEEP_LEARNING_AMI_ID> \
  --instance-type g4dn.xlarge \
  --key-name my-datascience-key \
  --security-group-ids <SG_ID> \
  --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time"}}' \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":100,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=gpu-training}]' \
  --query 'Instances[0].[InstanceId,SpotInstanceRequestId]' \
  --output text
```

### If You Get "InsufficientInstanceCapacity" Error

GPU spot capacity varies by availability zone. If you get a capacity error, specify a different AZ:

```bash
# Try a specific availability zone (e.g., us-west-2a)
aws ec2 run-instances \
  --image-id <DEEP_LEARNING_AMI_ID> \
  --instance-type g4dn.xlarge \
  --key-name my-datascience-key \
  --security-group-ids <SG_ID> \
  --placement AvailabilityZone=us-west-2a \
  --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time"}}' \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":100,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=gpu-training}]' \
  --query 'Instances[0].[InstanceId,SpotInstanceRequestId]' \
  --output text
```

If that fails, try other AZs in your region (e.g., `us-west-2b`, `us-west-2c`). Check current spot prices to see which AZs have capacity:

```bash
aws ec2 describe-spot-price-history \
  --instance-types g4dn.xlarge \
  --product-descriptions "Linux/UNIX" \
  --start-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --query 'SpotPriceHistory[*].[AvailabilityZone,SpotPrice]' \
  --output table
```

### Connect to GPU Instance

```bash
# Get instance IP (Ubuntu uses 'ubuntu' user, not 'ec2-user')
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=gpu-training" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text

# SSH into GPU instance
ssh -i ~/.ssh/my-datascience-key.pem ubuntu@<GPU_INSTANCE_IP>
```

### Verify GPU Access

```bash
# Check NVIDIA driver and GPU
nvidia-smi

# Test PyTorch GPU access
python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'GPU: {torch.cuda.get_device_name(0)}')"
```

### Pre-installed on Deep Learning AMI
- NVIDIA drivers and CUDA toolkit
- PyTorch, TensorFlow
- Python 3.10 with conda
- Jupyter

### Typical GPU Workflow

1. **Prepare data** on your t3.medium instance or locally
2. **Upload to S3**: `aws s3 cp data.parquet s3://<YOUR_BUCKET>/`
3. **Launch GPU spot instance**
4. **Download data**: `aws s3 cp s3://<YOUR_BUCKET>/data.parquet .`
5. **Train model**, save checkpoints frequently to S3
6. **Upload results**: `aws s3 cp model.pt s3://<YOUR_BUCKET>/`
7. **Terminate GPU instance** immediately when done

### Handle Spot Interruption

Spot instances can be terminated with 2-minute warning. Protect your work:

```python
# In your training script, save checkpoints frequently
import torch
import boto3

def save_checkpoint(model, optimizer, epoch, bucket_name, path='checkpoint.pt'):
    torch.save({
        'epoch': epoch,
        'model_state_dict': model.state_dict(),
        'optimizer_state_dict': optimizer.state_dict(),
    }, path)
    # Upload to S3 immediately
    s3 = boto3.client('s3')
    s3.upload_file(path, bucket_name, f'checkpoints/checkpoint_epoch_{epoch}.pt')

# Save every N epochs or every N minutes
for epoch in range(num_epochs):
    train_one_epoch(model, optimizer, dataloader)
    if epoch % 5 == 0:  # Every 5 epochs
        save_checkpoint(model, optimizer, epoch, '<YOUR_BUCKET>')
```

### Terminate GPU Instance When Done

**Important**: Always terminate GPU instances when finished to avoid charges!

```bash
# Find and terminate GPU instance
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=gpu-training" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

aws ec2 terminate-instances --instance-ids $INSTANCE_ID
```

---

## Cost Management Tips

1. **Stop when not using**: Stopped instances only pay for storage (~$2/month for 20GB)
2. **Use Spot for GPU**: Up to 70% savings for training jobs
3. **Monitor with AWS Budgets**: Set up alerts at $10, $25, $50
4. **Check running instances regularly**:
   ```bash
   aws ec2 describe-instances \
     --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name]' \
     --output table
   ```

---

## Troubleshooting

### Can't connect via SSH
1. Check instance is running: `aws ec2 describe-instances --instance-ids <INSTANCE_ID>`
2. Verify you're using the correct IP (Elastic IP is static; without Elastic IP, get current IP after each start)
3. Verify security group allows port 22
4. Check key file permissions: `chmod 400 ~/.ssh/my-datascience-key.pem`
5. **Alternative**: Use SSM Session Manager (no SSH keys or open ports needed):
   ```bash
   aws ssm start-session --target <INSTANCE_ID>
   ```

### Disk full
```bash
# Check disk usage
df -h

# Clean package cache
sudo dnf clean all
pip3.11 cache purge
```

### Out of memory
Consider upgrading to t3.large (8GB RAM) or r6i.large for memory-intensive work.

---

## Security Considerations

### SSH Access

The security group allows SSH from `0.0.0.0/0` (anywhere). This is convenient but less secure.

**To restrict SSH to your current IP only:**

```bash
# Get your current public IP
MY_IP=$(curl -s ifconfig.me)

# Add rule for your IP
aws ec2 authorize-security-group-ingress \
  --group-id <SG_ID> \
  --protocol tcp \
  --port 22 \
  --cidr ${MY_IP}/32

# Remove the 0.0.0.0/0 rule (optional, for tighter security)
aws ec2 revoke-security-group-ingress \
  --group-id <SG_ID> \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
```

**Note**: If your IP changes (e.g., home router restarts), you'll need to update the security group rule.

### Key File Security

- **Never commit `.pem` files to git** — add `*.pem` to `.gitignore`
- **Restrict file permissions**: `chmod 400` ensures only you can read the key
- **Store securely**: Keep backups in a password manager or encrypted storage
- **If compromised**: Delete the key pair in AWS and create a new one

### Alternative: AWS Systems Manager Session Manager

For SSH-key-free access, consider using SSM Session Manager:

```bash
# Connect without SSH keys (requires SSM agent on instance and IAM permissions)
aws ssm start-session --target <INSTANCE_ID>
```

This avoids managing SSH keys and doesn't require port 22 to be open.

---

## Conclusion

You now have a flexible, cost-effective data science environment on AWS:

- **Daily work**: t3.medium at ~$0.04/hr with Python, R, and Jupyter
- **Deep learning**: GPU spot instances at ~$0.24/hr, launched on-demand
- **Data sharing**: S3 bucket for seamless data transfer between instances
- **Cost control**: Stop instances when idle, use spot pricing, monitor with budgets

The key to keeping costs low is discipline: stop your instances when you're not using them, and always terminate GPU instances immediately after training jobs complete.

Happy modeling!

---

*Last updated: January 2026*
