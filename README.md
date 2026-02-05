# EC2 Ops Kit

Fast, safe one-liner management for AWS EC2 instances — CPU and GPU.

```
ec2 up --preset gpu-t4 --name training --spot --ttl-hours 8
ec2 ssh training
ec2 stop training
ec2 cleanup
```

## Quick Start

```bash
# 1. Clone and bootstrap
cd aws-setup
./bootstrap.sh              # checks deps, guides setup

# 2. Configure
cp config.example.yaml config.yaml
# Edit config.yaml with your AWS settings (key, security group, region)

# 3. Use
./bin/ec2 list              # list your instances
./bin/ec2 presets            # show available presets
./bin/ec2 up --preset cpu-small --name dev-box
./bin/ec2 ssh dev-box
```

### Add to PATH (optional)

```bash
# Add to your shell profile:
export PATH="$PATH:/path/to/aws-setup/bin"

# Then use anywhere:
ec2 list
ec2 ssh dev-box
```

## Commands

| Command | Description |
|---------|-------------|
| `ec2 list` | List instances (Name, ID, state, type, IPs, AZ, launch time) |
| `ec2 info <name\|id>` | Detailed info about one instance (tags, volumes, cost hint) |
| `ec2 up` | Create instance from preset |
| `ec2 start <name\|id>` | Start a stopped instance |
| `ec2 stop <name\|id>` | Stop a running instance |
| `ec2 terminate <name\|id>` | Terminate an instance (requires confirmation) |
| `ec2 ssh <name\|id>` | SSH into an instance by name |
| `ec2 eip <action>` | Manage Elastic IPs (list/alloc/assoc/disassoc/release) |
| `ec2 spot <action>` | Spot management (list/prices/history/cancel/interruption) |
| `ec2 cleanup` | Scan for orphaned EIPs, volumes, expired instances |
| `ec2 presets` | List available instance presets |

### Global Options

```
--profile PROF    AWS profile (overrides config)
--region REG      AWS region (overrides config)
--dry-run         Preview destructive operations without executing
--yes, -y         Skip confirmation prompts
--config FILE     Path to config.yaml
--debug           Verbose debug output
```

## Cheatsheet

```bash
# ── List & Info ─────────────────────────────────────────────
ec2 list                                # all instances
ec2 list --state running                # running only
ec2 list --tag gpu                      # filter by name
ec2 info my-instance                    # detailed info + cost hint

# ── Create Instances ────────────────────────────────────────
ec2 up --preset cpu-small --name dev    # small CPU box
ec2 up --preset cpu-large --name batch  # big CPU box
ec2 up --preset gpu-t4 --name train --spot            # T4 GPU spot
ec2 up --preset gpu-a10 --name finetune --spot --ttl-hours 12  # A10G + TTL
ec2 up --preset cpu-small --name dev --volume 50      # extra 50GB volume

# ── Start / Stop / Terminate ───────────────────────────────
ec2 start dev                           # start stopped instance
ec2 stop dev                            # stop (preserves EBS)
ec2 terminate dev                       # destroy (requires confirmation)
ec2 --dry-run terminate dev             # preview without executing
ec2 --yes stop dev                      # skip confirmation

# ── SSH ─────────────────────────────────────────────────────
ec2 ssh dev                             # SSH into instance
ec2 ssh dev --print                     # print ssh command only
ec2 ssh dev -L 8888:localhost:8888      # port forward Jupyter
ec2 ssh --gen-config                    # generate ~/.ssh/config snippet

# ── Elastic IPs ─────────────────────────────────────────────
ec2 eip list                            # list all EIPs
ec2 eip alloc my-static-ip              # allocate new EIP
ec2 eip assoc eipalloc-abc123 dev       # associate with instance
ec2 eip disassoc eipassoc-abc123        # disassociate
ec2 eip release eipalloc-abc123         # release (delete)

# ── Spot Instances ──────────────────────────────────────────
ec2 spot list                           # list spot requests
ec2 spot prices                         # current spot prices
ec2 spot prices g4dn.xlarge g5.xlarge   # specific types
ec2 spot history g4dn.xlarge 48         # 48h price history
ec2 spot cancel sir-abc12345            # cancel spot request
ec2 spot interruption                   # handling guide

# ── Cleanup ─────────────────────────────────────────────────
ec2 cleanup                             # scan for orphans
ec2 cleanup --days 3                    # flag stopped > 3 days
ec2 cleanup --release-eips              # offer to release orphan EIPs
ec2 cleanup --delete-volumes            # offer to delete unattached vols
ec2 cleanup --terminate                 # offer to terminate expired

# ── Multi-profile / Multi-region ────────────────────────────
ec2 --profile work list                 # use 'work' AWS profile
ec2 --region eu-west-1 list             # override region
ec2 --profile prod --region us-east-1 cleanup
```

## Presets

Presets are YAML files in `presets/`. Each defines an instance type, AMI, volume size, and more.

| Preset | Type | vCPU | RAM | GPU | Volume | Spot | Cost/hr |
|--------|------|------|-----|-----|--------|------|---------|
| `cpu-small` | t3.medium | 2 | 4 GB | — | 20 GB | Yes | ~$0.04 |
| `cpu-large` | c5.2xlarge | 8 | 16 GB | — | 100 GB | Yes | ~$0.34 |
| `gpu-t4` | g4dn.xlarge | 4 | 16 GB | T4 16GB | 100 GB | Yes | ~$0.53 |
| `gpu-a10` | g5.xlarge | 4 | 16 GB | A10G 24GB | 200 GB | Yes | ~$1.01 |

### Custom Presets

Create `presets/my-preset.yaml`:

```yaml
name: my-preset
description: "My custom instance"
instance_type: m5.xlarge
ami_pattern: "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
ami_owner: "099720109477"
ami_id: ""
volume_size: 50
root_device: /dev/sda1
ssh_user: ubuntu
spot_friendly: true
cost_per_hour: 0.192
```

## Configuration

Copy `config.example.yaml` to `config.yaml` and edit:

```yaml
aws:
  profile: default
  region: us-west-2

ssh:
  key_path: ~/.ssh/my-ec2-key.pem
  key_name: my-ec2-key
  default_user: ubuntu
  bastion_host: ""          # ProxyJump support
  bastion_user: ""

security:
  group_id: sg-xxxxxxxx

tags:
  Project: aws-setup
  Owner: me
  CostCenter: ""

defaults:
  ttl_hours: 0
  volume_type: gp3
```

## Safety

- **Terminate** requires typing the instance name or ID to confirm
- **Stop** requires `[y/N]` confirmation
- `--dry-run` previews any destructive operation without executing
- Every command prints the active AWS profile and region
- All resources are tagged with `Project`, `Owner`, `ManagedBy`
- TTL tags enable automatic detection of expired instances via `cleanup`

## GPU Notes

### AMIs

The GPU presets use the **Deep Learning Base OSS Nvidia Driver AMI (Ubuntu 22.04)** which comes with NVIDIA drivers pre-installed. After launching:

```bash
ec2 ssh my-gpu-box
nvidia-smi                  # should show your GPU
```

### Alternative AMIs

- **Deep Learning AMI (Ubuntu)**: Includes PyTorch, TensorFlow, etc.
- **Plain Ubuntu 22.04**: Use the `gpu_setup_userdata` field in presets to install NVIDIA drivers

### Driver Setup on Plain Ubuntu

If using a plain Ubuntu AMI, the preset includes a user-data script:

```bash
ec2 up --preset gpu-t4 --name my-gpu \
  --ami ami-0abcdef1234567890 \
  --user-data presets/gpu-setup.sh
```

## Project Structure

```
aws-setup/
├── bin/
│   └── ec2                     # Main CLI entrypoint
├── lib/
│   ├── core.sh                 # Shared utilities, config, YAML parsing
│   ├── cmd_instances.sh        # list, info, up, start, stop, terminate
│   ├── cmd_network.sh          # ssh, eip
│   ├── cmd_spot.sh             # spot management
│   └── cmd_cleanup.sh          # orphan scanner
├── presets/
│   ├── cpu-small.yaml          # t3.medium
│   ├── cpu-large.yaml          # c5.2xlarge
│   ├── gpu-t4.yaml             # g4dn.xlarge (NVIDIA T4)
│   └── gpu-a10.yaml            # g5.xlarge (NVIDIA A10G)
├── scripts/                    # Legacy scripts (preserved)
│   ├── lib.sh
│   ├── launch-cpu.sh
│   ├── launch-gpu.sh
│   └── ...
├── tests/
│   ├── run_tests.sh            # Test runner
│   ├── test_cli.sh             # CLI parsing tests
│   ├── test_config.sh          # Config parsing tests
│   └── test_presets.sh         # Preset loading tests
├── config/
│   └── .env.example            # Legacy config template
├── docs/
│   └── setup-guide.md          # Detailed setup guide
├── config.example.yaml         # New config template
├── bootstrap.sh                # Dependency checker + setup wizard
├── README.md                   # This file
├── LICENSE                     # MIT
└── .gitignore
```

## Dependencies

**Required:**
- AWS CLI v2
- jq
- bash 4+

**Optional:**
- Python 3 + boto3 (richer output)
- shellcheck (lint checks in tests)

## IAM Permissions

Least-privilege permissions needed:

```
ec2:DescribeInstances           ec2:RunInstances
ec2:StartInstances              ec2:StopInstances
ec2:TerminateInstances          ec2:CreateTags
ec2:DescribeImages              ec2:DescribeAddresses
ec2:AllocateAddress             ec2:AssociateAddress
ec2:DisassociateAddress         ec2:ReleaseAddress
ec2:DescribeVolumes             ec2:CreateVolume
ec2:AttachVolume                ec2:DeleteVolume
ec2:DescribeSpotInstanceRequests
ec2:DescribeSpotPriceHistory
ec2:CancelSpotInstanceRequests
ec2:DescribeSecurityGroups
sts:GetCallerIdentity
```

## Testing

```bash
./tests/run_tests.sh
```

Runs:
- **Lint**: shellcheck on all scripts
- **Config parsing**: YAML parser unit tests
- **Preset loading**: Validates all preset files
- **CLI parsing**: Command routing, flag parsing, utilities

Tests run in mock mode — no AWS API calls are made.

## Known Limitations

- YAML parser handles flat and one-level nested structures only (sufficient for config/presets)
- Cost estimates are approximate (based on on-demand us-west-2 rates)
- Spot price comparison uses current on-demand estimates, not real-time pricing
- `cleanup` uses launch time as proxy for stop time (AWS doesn't expose exact stop timestamp easily)
- The `--gen-config` SSH feature generates a point-in-time snapshot; IPs change on restart
- Bastion/ProxyJump with different keys requires ProxyCommand instead of ProxyJump

## Legacy Scripts

The original `scripts/` directory is preserved for backward compatibility. The new `bin/ec2` CLI supersedes these scripts with a unified interface:

| Legacy Script | New Equivalent |
|--------------|----------------|
| `scripts/launch-cpu.sh` | `ec2 up --preset cpu-small --name <name>` |
| `scripts/launch-gpu.sh` | `ec2 up --preset gpu-t4 --name <name> --spot` |
| `scripts/list-instances.sh` | `ec2 list` |
| `scripts/connect-cpu.sh` | `ec2 ssh <name>` |
| `scripts/connect-gpu.sh` | `ec2 ssh <name>` |
| `scripts/setup-security-group.sh` | Still useful; run directly |

## Changelog

### Version 2.0.0 (Current)
- Unified `bin/ec2` CLI with subcommands
- YAML-based config and presets system
- EIP management (allocate, associate, disassociate, release)
- Spot instance management (prices, history, cancellation, interruption guide)
- Orphan resource cleanup scanner (EIPs, volumes, TTL-expired instances)
- SSH by instance name with bastion/ProxyJump support
- Dry-run mode for destructive operations
- Multi-profile and multi-region support
- Automatic resource tagging (Project, Owner, ManagedBy, TTL)
- Mock-mode test suite
- Bootstrap setup wizard

### Version 1.0.0
- Initial release
- GPU spot instance launcher with error handling
- Instance listing script
- Configuration management via .env files
- Shared library with common AWS functions
- Complete setup documentation

## License

This project is open source. See [LICENSE](LICENSE) file for details.
