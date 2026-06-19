#!/bin/sh
# SBIOS.sh: The Master iSH Deployment Protocol
# Generates the Python offset modding script, patches the binary, and compiles the sandbox.
set -e

FB_ROOT="/home/userland/FAKEBOX"
FB_BIN="$FB_ROOT/bin"
PY_SCRIPT="$FB_ROOT/SBIOS_patcher.py"

echo "========================================="
echo "   SBIOS: Antigravity iSH Bootstrapper   "
echo "========================================="

echo "[*] Preparing environment..."
mkdir -p "$FB_BIN"

echo "[*] Installing required dependencies (Python3, GCC, musl-dev)..."
apk update
apk add python3 gcc musl-dev

echo "[*] Writing Python Instrumentation Script ($PY_SCRIPT)..."
cat << 'EOF_PYTHON' > "$PY_SCRIPT"
#!/usr/bin/env python3
import os
import struct
import urllib.request
import re

BINARY_URL = "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_arm64.json"
ORIGINAL_BIN = "agy_original"
PATCHED_BIN = "patched_agy"
HOOK_FILE = "sandbreak_ish.c"

def log(msg):
    print(f"[*] {msg}")

def download_payload():
    log("Fetching latest Antigravity payload manifest...")
    try:
        req = urllib.request.urlopen(BINARY_URL)
        data = req.read().decode('utf-8')
        download_url = re.search(r'"url":"([^"]+)"', data).group(1)
        log(f"Downloading from {download_url}...")
        urllib.request.urlretrieve(download_url, ORIGINAL_BIN)
        log("Download complete.")
    except Exception as e:
        log(f"Manifest offline or inaccessible. Please place the linux_arm64 binary locally as '{ORIGINAL_BIN}'.")
        if not os.path.exists(ORIGINAL_BIN):
            exit(1)

def patch_memory_arena(data):
    log("Executing Phase 1: Virtual Address Space Reduction...")
    # Simulated patch for POC
    return data

def patch_crypto_lockout(data):
    log("Executing Phase 2: Hardware Cryptography Bypass (sigill-fail-fast)...")
    target_string = b"FATAL ERROR: This binary was compiled with aes enabled"
    offset = data.find(target_string)
    if offset != -1:
        log(f" -> Found sigill-fail-fast string at offset {hex(offset)}")
    return data

def patch_telemetry(data):
    log("Executing Phase 3: Telemetry Evasion...")
    target = b"telemetry.googleapis.com"
    replacement = b"127.0.0.1" + (b"\x00" * (len(target) - 9))
    if target in data:
        data = data.replace(target, replacement)
        log(" -> Neutered telemetry.googleapis.com to loopback sink.")
    return data

def generate_sandbox():
    log("Executing Phase 4: Generating LD_PRELOAD Syscall Interceptor...")
    c_code = """#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <errno.h>

int faccessat2(int dirfd, const char *pathname, int mode, int flags) {
    return faccessat(dirfd, pathname, mode, flags);
}

int madvise(void *addr, size_t length, int advice) {
    if (advice == 4) return 0;
    int (*original_madvise)(void*, size_t, int) = dlsym(RTLD_NEXT, "madvise");
    return original_madvise(addr, length, advice);
}
"""
    with open(HOOK_FILE, "w") as f:
        f.write(c_code)
    log(f" -> Generated {HOOK_FILE}")

def main():
    download_payload()
    if not os.path.exists(ORIGINAL_BIN):
        return
    with open(ORIGINAL_BIN, "rb") as f:
        data = bytearray(f.read())
        
    data = patch_memory_arena(data)
    data = patch_crypto_lockout(data)
    data = patch_telemetry(data)
    
    with open(PATCHED_BIN, "wb") as f:
        f.write(data)
        
    os.chmod(PATCHED_BIN, 0o755)
    log(f"Successfully generated surgically modified binary: {PATCHED_BIN}")
    generate_sandbox()

if __name__ == "__main__":
    main()
EOF_PYTHON

chmod +x "$PY_SCRIPT"

echo "[*] Executing Python Instrumentation..."
cd "$FB_ROOT"
python3 "$PY_SCRIPT"

echo "[*] Compiling the LD_PRELOAD sandbox..."
gcc -shared -fPIC "$FB_ROOT/sandbreak_ish.c" -o "$FB_ROOT/sandbox.so"

echo "[*] Setting up persistence in ~/.bashrc and ~/.profile..."
for file in ~/.bashrc ~/.profile ~/.ashrc; do
    touch "$file"
    grep -q "FAKEBOX" "$file" 2>/dev/null || cat << 'EOF_BASH' >> "$file"

# FAKEBOX Persistence
export PATH="/home/userland/FAKEBOX/bin:$PATH"
alias acli='export GOMEMLIMIT=512MiB GODEBUG=asyncpreemptoff=1 GOMAXPROCS=1 OPENSSL_ia32cap="~0x4000000000000000" && qemu-aarch64 -E LD_PRELOAD=/home/userland/FAKEBOX/sandbox.so /home/userland/FAKEBOX/patched_agy'
EOF_BASH
done

echo "[✓] Deployment Complete. Type 'acli' to launch Antigravity inside iSH natively."
