#!/bin/sh
# SBIOS: UTM SE (Alpine ARM64) Deployer for FAKEBOX
# Reclaiming the Gemini CLI.
set -e

# Configuration
FB_ROOT="/home/userland/FAKEBOX"
FB_BIN="$FB_ROOT/bin"

echo "[*] Preparing FAKEBOX environment for UTM SE (ARM64)..."
mkdir -p "$FB_BIN" "$FB_ROOT/.gemini"

# 1. System Update and Dependencies
echo "[*] Syncing Alpine dependencies..."
apk update
apk add curl tar gzip bash

# 2. Fetch Upstream Binary (linux_arm64)
echo "[*] Fetching the engine payload (linux_arm64)..."
MANIFEST_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_arm64.json"
DOWNLOAD_URL=$(curl -fsSL "$MANIFEST_URL" | grep -o '"url":"[^"]*' | cut -d '"' -f 4)
curl -fsSL "$DOWNLOAD_URL" -o "$FB_ROOT/engine.tar.gz"

mkdir -p "$FB_ROOT/extract_tmp"
tar -xzf "$FB_ROOT/engine.tar.gz" -C "$FB_ROOT/extract_tmp"
RAW_BIN=$(find "$FB_ROOT/extract_tmp" -type f | head -n 1)

# 3. Deployment
echo "[*] Deploying acli..."
cp "$RAW_BIN" "$FB_BIN/acli"
chmod +x "$FB_BIN/acli"
rm -rf "$FB_ROOT/extract_tmp" "$FB_ROOT/engine.tar.gz"

# 4. Session Persistence
echo "[*] Setting up persistence in ~/.bashrc and ~/.profile..."
for file in ~/.bashrc ~/.profile ~/.ashrc; do
    touch "$file"
    grep -q "FAKEBOX" "$file" 2>/dev/null || cat << 'EOF2' >> "$file"

# FAKEBOX Persistence
export PATH="/home/userland/FAKEBOX/bin:$PATH"
EOF2
done

echo "[✓] SBIOS Deployment finished. Type 'acli' to begin."
