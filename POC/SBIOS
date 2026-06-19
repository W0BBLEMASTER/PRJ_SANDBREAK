#!/bin/sh
# SBIOS: iSH Remote Daemon Client Protocol
# Bypasses 32-bit architecture constraints by bridging to a 64-bit host.
set -e

# Configuration
FB_ROOT="/home/userland/FAKEBOX"
FB_BIN="$FB_ROOT/bin"

echo "[*] Preparing FAKEBOX Client Environment for iSH..."
mkdir -p "$FB_BIN"

# 1. System Update and Dependencies
echo "[*] Syncing Alpine dependencies..."
apk update
apk add openssh-client bash sshpass

# 2. Remote Host Configuration
echo "[*] Configuring Remote Android Daemon (Termux) Bridge"
echo -n "Enter Android Host IP (e.g., 10.64.178.55): "
read DAEMON_IP
echo -n "Enter SSH Port (Default for Termux is 8022): "
read DAEMON_PORT
DAEMON_PORT=${DAEMON_PORT:-8022}

# 3. Client Wrapper Deployment
echo "[*] Deploying remote 'acli' wrapper..."
cat << EOF2 > "$FB_BIN/acli"
#!/bin/bash
# iSH to Android SSH Bridge for Antigravity CLI

REMOTE_IP="$DAEMON_IP"
REMOTE_PORT="$DAEMON_PORT"

# Bypass headless keyring bugs and enforce UTC on the remote daemon
DAEMON_ENV="GEMINI_FORCE_FILE_STORAGE=true TZ=UTC"

# Pipe the TUI seamlessly over SSH
ssh -o StrictHostKeyChecking=no \\
    -o UserKnownHostsFile=/dev/null \\
    -p "\$REMOTE_PORT" \\
    user@"\$REMOTE_IP" \\
    "\$DAEMON_ENV acli \$@"
EOF2

chmod +x "$FB_BIN/acli"

# 4. Session Persistence
echo "[*] Setting up persistence in ~/.bashrc and ~/.profile..."
for file in ~/.bashrc ~/.profile ~/.ashrc; do
    touch "$file"
    grep -q "FAKEBOX" "$file" 2>/dev/null || cat << 'EOF3' >> "$file"

# FAKEBOX Persistence
export PATH="/home/userland/FAKEBOX/bin:$PATH"
EOF3
done

echo "[✓] SBIOS Deployment finished. Type 'acli' to connect to the engine."
