---
name: aws-s3
description: |
  Handles S3 bucket operations for data storage and transfer between EC2 instances in the EC2 Ops Kit project.
  Use when: working with S3 buckets, uploading/downloading data for training workflows, syncing files between instances, managing checkpoints, or adding S3 integration to the CLI.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# AWS S3 Skill

S3 is used in this project as the data bridge between CPU and GPU EC2 instances. There is no `ec2 s3` CLI command — all S3 operations use the AWS CLI directly. The project documents S3 workflows in `docs/setup-guide.md` and references S3 in the legacy config at `config/.env.example` (`S3_BUCKET_NAME`).

## Quick Start

### Upload data before GPU training

```bash
# Single file
aws s3 cp data.parquet s3://my-bucket/

# Directory (recursive)
aws s3 cp ./data/ s3://my-bucket/data/ --recursive

# Sync (only changed files — faster for repeated transfers)
aws s3 sync ./data/ s3://my-bucket/data/
```

### Download on GPU instance

```bash
aws s3 cp s3://my-bucket/data.parquet .
aws s3 sync s3://my-bucket/data/ ./data/
```

### Checkpoint to S3 during training (Python)

```python
import boto3

s3 = boto3.client('s3')
s3.upload_file('checkpoint.pt', 'my-bucket', 'checkpoints/epoch_10.pt')
```

## Key Concepts

| Concept | Usage | Example |
|---------|-------|---------|
| `aws s3 cp` | Single file transfer | `aws s3 cp model.pt s3://bucket/` |
| `aws s3 sync` | Incremental directory sync | `aws s3 sync ./data/ s3://bucket/data/` |
| `aws s3 ls` | List bucket contents | `aws s3 ls s3://bucket/ --recursive` |
| `aws s3 rm` | Delete objects | `aws s3 rm s3://bucket/old/ --recursive` |
| `aws s3api` | Low-level API (create bucket, etc.) | `aws s3api create-bucket --bucket name` |
| Same-region transfer | Free between EC2 and S3 | Keep bucket and instances in same region |

## Common Patterns

### Data science pipeline (CPU -> S3 -> GPU)

**When:** Training models on GPU spot instances with data prepared on CPU.

```bash
# On CPU instance: upload training data
aws s3 sync ./prepared-data/ s3://my-bucket/training/

# Launch GPU spot
ec2 up --preset gpu-t4 --name train --spot --ttl-hours 8
ec2 ssh train

# On GPU instance: pull data, train, push results
aws s3 sync s3://my-bucket/training/ ./data/
python train.py
aws s3 cp model.pt s3://my-bucket/models/
```

### Bucket creation (one-time setup)

```bash
BUCKET_NAME="my-datascience-$(date +%s)"
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2
```

## WARNING: No S3 CLI Integration

This project has **no `ec2 s3` command**. S3 is documented but not wired into the CLI. If adding S3 commands, follow the pattern in `lib/cmd_instances.sh` — create `lib/cmd_s3.sh` with `cmd_s3()`, add routing in `bin/ec2`, and source it. See the **aws-ec2** skill for the command-addition workflow.

## See Also

- [patterns](references/patterns.md) — Transfer patterns, cost, security, anti-patterns
- [workflows](references/workflows.md) — Training pipeline, backup, bucket lifecycle

## Related Skills

- See the **aws-cli** skill for `--query`, `--output`, profile/region flags
- See the **aws-ec2** skill for instance lifecycle (launch GPU -> transfer data -> terminate)
- See the **aws-spot** skill for spot interruption handling with S3 checkpoints
- See the **bash** skill for scripting S3 operations with proper quoting and error handling
