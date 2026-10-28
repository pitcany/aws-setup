#!/bin/bash
# hf2local.sh — first-boot bootstrap for the hf2local-build / hf2local-gpu presets
#
#   ec2 up --preset hf2local-build --name hf2l --spot --ttl-hours 8 --user-data userdata/hf2local.sh
#
# Installs the toolchain hf2local expects and points its env overrides at /data.
# hf2local itself is not installed here: it lives in a private repo, so install it
# from your checkout once you are logged in (see the preset's post_launch_hint).
set -euo pipefail
exec > >(tee -a /var/log/hf2local-bootstrap.log) 2>&1

# ── System packages ───────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y build-essential cmake git git-lfs rsync tmux htop curl

# ── Data directory (HF cache + converted packs) ───────────────────────
install -d -o ubuntu -g ubuntu /data /data/hf /data/converted

# ── uv + Python 3.12 venv ─────────────────────────────────────────────
sudo -u ubuntu -H bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
UV=/home/ubuntu/.local/bin/uv
install -d -o ubuntu -g ubuntu /opt/hf2local
sudo -u ubuntu -H "$UV" venv --python 3.12 /opt/hf2local
if command -v nvidia-smi >/dev/null 2>&1; then
  torch_index="https://download.pytorch.org/whl/cu128"
else
  torch_index="https://download.pytorch.org/whl/cpu"
fi
sudo -u ubuntu -H "$UV" pip install --python /opt/hf2local/bin/python \
  --index-url "$torch_index" torch
sudo -u ubuntu -H "$UV" pip install --python /opt/hf2local/bin/python \
  transformers accelerate sentencepiece protobuf "huggingface_hub[hf_transfer]"

# ── llama.cpp (converter + llama-completion / llama-speculative for validate-gguf) ──
sudo -u ubuntu -H git clone --depth 1 https://github.com/ggml-org/llama.cpp /home/ubuntu/llama.cpp
sudo -u ubuntu -H cmake -S /home/ubuntu/llama.cpp -B /home/ubuntu/llama.cpp/build -DCMAKE_BUILD_TYPE=Release
sudo -u ubuntu -H cmake --build /home/ubuntu/llama.cpp/build -j "$(nproc)"

# ── hf2local env overrides (replace the desktop's /mnt/storage, conda envs, lease) ──
cat > /etc/profile.d/hf2local.sh <<'PROFILE'
export PATH="/opt/hf2local/bin:/home/ubuntu/llama.cpp/build/bin:$PATH"
export HF_HOME=/data/hf
export HF_HUB_ENABLE_HF_TRANSFER=1
export HF2LOCAL_OUT=/data/converted
export HF2LOCAL_TORCH_PYTHON=/opt/hf2local/bin/python
export HF2LOCAL_LEASE=off
export LLAMA_CPP_DIR=/home/ubuntu/llama.cpp
PROFILE

echo "hf2local bootstrap: done"
