#!/bin/bash
# SANDBREAK_ANDROID_32B: Deployer for Android 5.0 Linux Deploy (32-bit ARM)
set -e

# Configuration
FB_ROOT="/home/userland/FAKEBOX"
FB_BIN="$FB_ROOT/bin"

echo "[*] Preparing FAKEBOX environment (32-bit)..."
mkdir -p "$FB_BIN" "$FB_ROOT/.gemini"

# 1. System Update and Dependencies
echo "[*] Syncing system dependencies..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -yq adb git python3 curl gcc libc6-dev bsdutils < /dev/null

# 2. Fetch Upstream Binary (32-bit ARM)
echo "[*] Fetching official Linux arm (32-bit) binary..."
MANIFEST_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_arm.json"
DOWNLOAD_URL=$(curl -fsSL "$MANIFEST_URL" | grep -oP '"url":\s*"\K[^"]+')
curl -fsSL "$DOWNLOAD_URL" -o "$FB_ROOT/agy.tar.gz"
mkdir -p "$FB_ROOT/extract_tmp"
tar -xzf "$FB_ROOT/agy.tar.gz" -C "$FB_ROOT/extract_tmp"
AGY_RAW=$(find "$FB_ROOT/extract_tmp" -type f \( -name "antigravity" -o -name "agy" \) | head -n 1)
cp "$AGY_RAW" "$FB_BIN/agy"
chmod +x "$FB_BIN/agy"
rm -rf "$FB_ROOT/extract_tmp" "$FB_ROOT/agy.tar.gz"

# 3. Sandbreak Arbitrator Hooks (32-bit compatible)
echo "[*] Compiling sandbreak arbitrator for 32-bit..."
cat << 'C_EOF' > "$FB_BIN/sandbreak_32.c"
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

long syscall(long n, ...) {
    va_list args; va_start(args, n);
    long a1 = va_arg(args, long); long a2 = va_arg(args, long); long a3 = va_arg(args, long);
    long a4 = va_arg(args, long); long a5 = va_arg(args, long); long a6 = va_arg(args, long);
    va_end(args);
    if (n == SYS_mmap2 || n == SYS_mmap) return (long)handle_mmap_logic((void*)a1, (size_t)a2, (int)a3, (int)a4, (int)a5, (off_t)a6);
    static long (*orig)(long, long, long, long, long, long, long) = NULL;
    if (!orig) orig = dlsym(RTLD_NEXT, "syscall");
    return orig(n, a1, a2, a3, a4, a5, a6);
}
C_EOF
gcc -shared -fPIC -m32 "$FB_BIN/sandbreak_32.c" -o "$FB_BIN/sandbreak_32.so" -ldl || gcc -shared -fPIC "$FB_BIN/sandbreak_32.c" -o "$FB_BIN/sandbreak_32.so" -ldl
echo "[✓] 32-bit Arbitrator ready."

# 4. Final Launcher Deployment
echo "[*] Deploying acli wrapper..."
cat << 'WRAPPER_EOF' > "$FB_BIN/acli"
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

for i in {1..10}; do
    LD_PRELOAD="$FB_BIN_DIR/sandbreak_32.so" "$FB_BIN_DIR/agy" "$@"
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 139 ]; then
        exit $EXIT_CODE
    fi
done
WRAPPER_EOF
chmod +x "$FB_BIN/acli"

# Global Symlink
sudo ln -sf "$FB_BIN/acli" /usr/local/bin/acli || true

# 5. Session Persistence
echo "[*] Adding environment persistence to ~/.bashrc..."
grep -q "FAKEBOX" ~/.bashrc || cat << 'BASHRC_EOF' >> ~/.bashrc

# FAKEBOX Persistence
export PROOT_NO_SECCOMP=1
export PATH="/home/userland/FAKEBOX/bin:$PATH"
alias acli='/home/userland/FAKEBOX/bin/acli'
BASHRC_EOF

echo "[✓] SANDBREAK 32B Deployment finished."
