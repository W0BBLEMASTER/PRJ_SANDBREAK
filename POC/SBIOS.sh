#!/bin/sh
# SBIOS: iSH/Alpine x86 Deployer for FAKEBOX
set -e

# Configuration
FB_ROOT="/home/userland/FAKEBOX"
FB_BIN="$FB_ROOT/bin"

echo "[*] Preparing FAKEBOX environment for iOS (iSH)..."
mkdir -p "$FB_BIN" "$FB_ROOT/.gemini"

# 1. System Update and Dependencies (Alpine)
echo "[*] Syncing system dependencies via apk..."
apk update
apk add git python3 curl gcc musl-dev bash

# 2. Fetch Upstream Binary (386)
echo "[*] Fetching official Linux 386 binary..."
MANIFEST_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_386.json"
DOWNLOAD_URL=$(curl -fsSL "$MANIFEST_URL" | grep '"url"' | cut -d '"' -f 4)
curl -fsSL "$DOWNLOAD_URL" -o "$FB_ROOT/agy.tar.gz"
mkdir -p "$FB_ROOT/extract_tmp"
tar -xzf "$FB_ROOT/agy.tar.gz" -C "$FB_ROOT/extract_tmp"
AGY_RAW=$(find "$FB_ROOT/extract_tmp" -type f \( -name "antigravity" -o -name "agy" \) | head -n 1)

# 3. Binary Patching
echo "[*] Skipping ARM64 memory surgery (x86 architecture detected)..."
cp "$AGY_RAW" "$FB_BIN/agy"
chmod +x "$FB_BIN/agy"
rm -rf "$FB_ROOT/extract_tmp"

# 4. Sandbreak Arbitrator Hooks (Adapted for x86/iSH)
echo "[*] Compiling sandbreak arbitrator..."
cat << 'EOF2' > "$FB_BIN/sandbreak.c"
#define _GNU_SOURCE
#include <errno.h>
#include <stddef.h>
#include <string.h>
#include <dlfcn.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <stdint.h>
#include <unistd.h>
#include <stdarg.h>

static void* handle_mmap_logic(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    if (flags & 0x100000) { 
        flags &= ~0x100000;
        if (addr != NULL) flags |= MAP_FIXED;
    }
    static void* (*real_mmap)(void*, size_t, int, int, int, off_t) = NULL;
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    void* res = real_mmap(addr, length, prot, flags, fd, offset);
    if (res == MAP_FAILED && addr != NULL) {
        res = real_mmap(NULL, length, prot, flags & ~MAP_FIXED, fd, offset);
    }
    return res;
}

void *mmap(void *a, size_t l, int p, int f, int d, off_t o) { return handle_mmap_logic(a, l, p, f, d, o); }
void *mmap64(void *a, size_t l, int p, int f, int d, off_t o) { return handle_mmap_logic(a, l, p, f, d, o); }

int faccessat2(int d, const char *p, int m, int f) { errno = ENOSYS; return -1; }
EOF2
gcc -shared -fPIC "$FB_BIN/sandbreak.c" -o "$FB_BIN/sandbreak.so" -ldl || echo "[!] Failed to compile sandbreak.so, acli might run without hooks."
echo "[✓] Arbitrator ready."

# 5. Final Launcher Deployment
echo "[*] Deploying acli wrapper..."
cat << 'EOF2' > "$FB_BIN/acli"
#!/bin/bash
FB_BIN_DIR="/home/userland/FAKEBOX/bin"

export HOME="/home/userland/FAKEBOX"
export PATH="$FB_BIN_DIR:$PATH"
export PROOT_NO_SECCOMP=1 
export DISPLAY=:0
export BROWSER=echo 
export LANG=C.UTF-8 
export TERM=xterm-256color 
export COLORTERM=truecolor 
export FORCE_COLOR=3
export GODEBUG=netdns=go

trap 'reset 2>/dev/null; stty sane 2>/dev/null; tput cnorm 2>/dev/null' EXIT ERR HUP INT TERM

stty -icanon -echo 2>/dev/null || true

for i in 1 2 3 4 5 6 7 8 9 10; do
    if [ -f "$FB_BIN_DIR/sandbreak.so" ]; then
        LD_PRELOAD="$FB_BIN_DIR/sandbreak.so" "$FB_BIN_DIR/agy" "$@"
    else
        "$FB_BIN_DIR/agy" "$@"
    fi
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 139 ]; then
        exit $EXIT_CODE
    fi
done
EOF2
chmod +x "$FB_BIN/acli"

# Global Symlink (iSH doesn't use sudo)
ln -sf "$FB_BIN/acli" /usr/local/bin/acli || true

# 6. Session Persistence
echo "[*] Adding environment persistence to ~/.bashrc and ~/.profile..."
for file in ~/.bashrc ~/.profile; do
    grep -q "FAKEBOX" "$file" 2>/dev/null || cat << 'EOF2' >> "$file"

# FAKEBOX Persistence
export PROOT_NO_SECCOMP=1
export PATH="/home/userland/FAKEBOX/bin:$PATH"
alias acli='/home/userland/FAKEBOX/bin/acli'
EOF2
done

echo "[✓] SBIOS Deployment finished."
