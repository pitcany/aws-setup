# S3 Patterns Reference

## Contents
- Transfer Patterns
- Bucket Configuration
- Checkpoint Pattern (Python)
- Cost Optimization
- Security Patterns
- Anti-Patterns

## Transfer Patterns

### `aws s3 cp` vs `aws s3 sync`

Use `cp` for single files, `sync` for directories. `sync` only transfers changed files — critical for large datasets.

```bash
# DO — sync for directories (incremental, skips unchanged)
aws s3 sync ./data/ s3://my-bucket/data/

# DON'T — cp --recursive re-uploads everything every time
aws s3 cp ./data/ s3://my-bucket/data/ --recursive
```

**Why:** A 10GB dataset with 1 file changed means `sync` transfers ~1 file; `cp --recursive` re-uploads all 10GB. On metered egress or slow networks, this adds up fast.

### Exclude patterns

```bash
# Sync but skip checkpoints and temp files
aws s3 sync ./data/ s3://my-bucket/data/ \
  --exclude "*.tmp" \
  --exclude "__pycache__/*" \
  --exclude ".git/*"

# Only sync parquet files
aws s3 sync ./data/ s3://my-bucket/data/ \
  --exclude "*" --include "*.parquet"
```

### Parallel uploads for large files

```bash
# Tune multipart settings for large files (>100MB)
aws configure set default.s3.multipart_threshold 64MB
aws configure set default.s3.multipart_chunksize 16MB
aws configure set default.s3.max_concurrent_requests 20
```

Default is 8MB threshold and 10 concurrent requests. Increase for GPU training artifacts (model checkpoints can be several GB).

## Bucket Configuration

### Region matters — keep bucket and instances together

```bash
# DO — same region as EC2 instances (free transfer, lower latency)
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

# DON'T — bucket in different region than instances
# Cross-region transfer costs ~$0.02/GB and is slower
```

The project's default region is in `config.yaml` under `aws.region` (default: `us-west-2`). See the **aws-cli** skill for profile/region resolution.

### Legacy config reference

The legacy `config/.env.example` stores the bucket name as `S3_BUCKET_NAME`. The new `config.yaml` does **not** have an S3 section — bucket names are passed directly to `aws s3` commands.

## Checkpoint Pattern (Python)

From `docs/setup-guide.md` — save model checkpoints to S3 during training to survive spot interruptions:

```python
import torch
import boto3

def save_checkpoint(model, optimizer, epoch, bucket_name, path='checkpoint.pt'):
    torch.save({
        'epoch': epoch,
        'model_state_dict': model.state_dict(),
        'optimizer_state_dict': optimizer.state_dict(),
    }, path)
    s3 = boto3.client('s3')
    s3.upload_file(path, bucket_name, f'checkpoints/checkpoint_epoch_{epoch}.pt')

# Save every 5 epochs
for epoch in range(num_epochs):
    train_one_epoch(model, optimizer, dataloader)
    if epoch % 5 == 0:
        save_checkpoint(model, optimizer, epoch, 'my-bucket')
```

See the **aws-spot** skill for spot interruption handling — checkpoint frequency should match your tolerance for lost work (2-minute warning on interruption).

## Cost Optimization

| Operation | Cost |
|-----------|------|
| Storage | ~$0.023/GB/month (S3 Standard) |
| PUT/COPY/POST | $0.005 per 1,000 requests |
| GET/SELECT | $0.0004 per 1,000 requests |
| Transfer EC2 -> S3 (same region) | **Free** |
| Transfer S3 -> EC2 (same region) | **Free** |
| Transfer S3 -> internet | First 100GB/month free, then ~$0.09/GB |

**Key insight:** Same-region transfers are free. NEVER put your S3 bucket in a different region than your EC2 instances.

### Clean up after training

```bash
# List what's consuming space
aws s3 ls s3://my-bucket/ --recursive --human-readable --summarize

# Delete old checkpoints (keep only latest)
aws s3 rm s3://my-bucket/checkpoints/ --recursive --exclude "checkpoint_final.pt"
```

## Security Patterns

### WARNING: Never hardcode bucket names in scripts

```bash
# BAD — hardcoded bucket name
aws s3 cp model.pt s3://yannik-private-data/models/

# GOOD — use a variable or config
BUCKET="${S3_BUCKET_NAME:-my-default-bucket}"
aws s3 cp model.pt "s3://${BUCKET}/models/"
```

**Why:** Hardcoded bucket names leak into git history. Use environment variables or the `S3_BUCKET_NAME` from `config/.env`.

### WARNING: Public access is off by default — keep it that way

```bash
# NEVER do this for data science buckets
aws s3api put-bucket-acl --bucket my-bucket --acl public-read

# DO — verify bucket is not public
aws s3api get-public-access-block --bucket my-bucket
```

**Why:** Training data, model weights, and checkpoints may contain sensitive information. Public buckets are the #1 cause of AWS data breaches.

## Anti-Patterns

### WARNING: Sync without `--delete` accumulates stale files

**The Problem:**

```bash
# BAD — old files persist on destination even after local deletion
aws s3 sync ./data/ s3://my-bucket/data/
# Local: file_v2.parquet (file_v1 deleted)
# S3:   file_v1.parquet, file_v2.parquet  <- stale file remains
```

**Why This Breaks:** Storage costs grow, and downstream jobs may process stale data.

**The Fix:**

```bash
# GOOD — mirror local state exactly (deletes removed files from S3)
aws s3 sync ./data/ s3://my-bucket/data/ --delete

# SAFER — dry run first to see what would be deleted
aws s3 sync ./data/ s3://my-bucket/data/ --delete --dryrun
```

**When You Might Be Tempted:** When you just want to "push changes" without thinking about removed files. Always use `--dryrun` first.

### WARNING: Using `s3://` paths without quoting

```bash
# BAD — glob expansion can break paths with special chars
aws s3 cp $file s3://$bucket/$prefix/

# GOOD — always quote
aws s3 cp "$file" "s3://${bucket}/${prefix}/"
```

See the **bash** skill — the project enforces `"$var"` quoting everywhere. This applies to S3 paths too.
