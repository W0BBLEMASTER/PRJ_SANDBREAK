#!/bin/bash
# SANDBREAK2: Stable Native Deployer for Fresh UserLAnd Kali
set -e

# Configuration
FB_ROOT="/home/userland/FAKEBOX"
FB_BIN="$FB_ROOT/bin"

echo "[*] Preparing FAKEBOX environment..."
mkdir -p "$FB_BIN" "$FB_ROOT/.gemini"

# 1. System Update and Dependencies
echo "[*] Syncing system dependencies..."
export DEBIAN_FRONTEND=noninteractive
sudo rm -f /var/lib/dpkg/info/openssh-client.*
sudo dpkg --remove --force-remove-reinstreq openssh-client 2>/dev/null || true
sudo apt-mark hold openssh-client
sudo dpkg --configure -a
sudo apt-get install -f -yq
sudo apt-get update -qq
sudo apt-get install -yq adb git python3 curl gcc libc6-dev bsdutils < /dev/null

# 2. Fetch Upstream Binary
echo "[*] Fetching official Linux arm64 binary..."
MANIFEST_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_arm64.json"
DOWNLOAD_URL=$(curl -fsSL "$MANIFEST_URL" | grep -oP '"url":\s*"\K[^"]+')
curl -fsSL "$DOWNLOAD_URL" -o "$FB_ROOT/agy.tar.gz"
mkdir -p "$FB_ROOT/extract_tmp"
tar -xzf "$FB_ROOT/agy.tar.gz" -C "$FB_ROOT/extract_tmp"
AGY_RAW=$(find "$FB_ROOT/extract_tmp" -type f \( -name "antigravity" -o -name "agy" \) | head -n 1)

# 3. Correctly Scoped Binary Patching (Fixes Segfaults)
echo "[*] Applying precision VA39 memory surgery..."
cat << 'EOF' > "$FB_ROOT/patcher.py"
import sys, shutil, struct, pathlib

src = pathlib.Path(sys.argv[1])
dst = pathlib.Path(sys.argv[2])
shutil.copyfile(src, dst)
data = bytearray(dst.read_bytes())

def get(off): return struct.unpack_from("<I", data, off)[0]
def put(off, word): struct.pack_into("<I", data, off, word)

def find_section(name_target):
    if data[:4] != b"\x7fELF": return None, None
    e_shoff = struct.unpack_from("<Q", data, 40)[0]
    e_shentsize = struct.unpack_from("<H", data, 58)[0]
    e_shnum = struct.unpack_from("<H", data, 60)[0]
    e_shstrndx = struct.unpack_from("<H", data, 62)[0]
    shstr_base = e_shoff + e_shstrndx * e_shentsize
    shstr_off = struct.unpack_from("<Q", data, shstr_base + 24)[0]
    for i in range(e_shnum):
        base = e_shoff + i * e_shentsize
        sh_name = struct.unpack_from("<I", data, base)[0]
        sh_offset = struct.unpack_from("<Q", data, base + 24)[0]
        sh_size = struct.unpack_from("<Q", data, base + 32)[0]
        nend = data.index(b"\x00", shstr_off + sh_name)
        section = data[shstr_off + sh_name : nend].decode("utf-8", errors="replace")
        if section == name_target:
            return sh_offset, sh_offset + sh_size
    return None, None

sec_lo, sec_hi = find_section("google_malloc")
if sec_lo is not None:
    lo, hi = sec_lo, sec_hi
else:
    lo, hi = 0, len(data)

# A. FIPS Bypass
fips_p = bytes.fromhex('e000003520008052f44f43a9f65742a9f85f41a9')
fips_r = bytes.fromhex('1f2003d520008052f44f43a9f65742a9f85f41a9')
if fips_p in data:
    data = data.replace(fips_p, fips_r)

# B. VA39 TCMalloc Overrides
for off in range(lo, hi, 4):
    w = get(off)
    if (w & 0x7F800000) == 0x53000000:
        immr = (w >> 16) & 0x3F
        imms = (w >> 10) & 0x3F
        if immr == 42 and imms == 44:
            put(off, (w & ~((0x3F << 16) | (0x3F << 10))) | (35 << 16) | (37 << 10))
        elif immr == 22 and imms == 21:
            put(off, (w & ~((0x3F << 16) | (0x3F << 10))) | (29 << 16) | (28 << 10))

for off in range(lo, hi - 4, 4):
    if get(off) == 0x92D3800A and get(off + 4) == 0xF2E0000A:
        put(off, 0x9280000A)
        put(off + 4, 0xD35DFD4A)

for off in range(lo, hi, 4):
    if get(off) == 0xF2E00029:
        put(off, 0xD3596129)

word_rewrites = {
    0xD2C20009: 0xD2C00409, 0xD2C2000A: 0xD2C0040A, 0xF2C20008: 0xF2DFF408,
    0xF2C20009: 0xF2DFF409, 0xD2C10009: 0xD2C00209, 0xD2C1000A: 0xD2C0020A,
    0xF2C38008: 0xF2DFF708, 0xF2C38009: 0xF2DFF709, 0x92560A6C: 0x925D0A6C,
    0x92560A6A: 0x925D0A6A, 0xD2C3000D: 0xD2C0060D, 0xD2C3000C: 0xD2C0060C,
    0xD2C08008: 0xD2C00108,
}
for off in range(lo, hi, 4):
    w = get(off)
    if w in word_rewrites:
        put(off, word_rewrites[w])

# C. faccessat2 -> faccessat
for off in range(0, len(data) - 12, 4):
    if get(off) == 0xAA1F03E5 and get(off + 4) == 0xAA1F03E6 and get(off + 8) == 0xD28036E0 and (get(off + 12) & 0xFC000000) == 0x94000000:
        put(off + 8, 0xD2800600)

dst.write_bytes(data)
dst.chmod(0o755)
EOF
python3 "$FB_ROOT/patcher.py" "$AGY_RAW" "$FB_BIN/agy"
rm -rf "$FB_ROOT/extract_tmp" "$FB_ROOT/patcher.py"
echo "[✓] Patching complete."

# 4. Sandbreak Arbitrator Hooks
echo "[*] Compiling sandbreak arbitrator..."
cat << 'EOF' > "$FB_BIN/sandbreak.c"
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
    if (addr != NULL && (uintptr_t)addr > 0x7FFFFFFFFFULL) {
        addr = NULL;
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
    if (n == SYS_mmap) return (long)handle_mmap_logic((void*)a1, (size_t)a2, (int)a3, (int)a4, (int)a5, (off_t)a6);
    static long (*orig)(long, long, long, long, long, long, long) = NULL;
    if (!orig) orig = dlsym(RTLD_NEXT, "syscall");
    return orig(n, a1, a2, a3, a4, a5, a6);
}
EOF
gcc -shared -fPIC "$FB_BIN/sandbreak.c" -o "$FB_BIN/sandbreak.so" -ldl
echo "[✓] Arbitrator ready."

# 5. Final Launcher Deployment
echo "[*] Deploying acli wrapper..."
cat << 'EOF' > "$FB_BIN/acli"
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
    LD_PRELOAD="$FB_BIN_DIR/sandbreak.so" "$FB_BIN_DIR/agy" "$@"
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 139 ]; then
        exit $EXIT_CODE
    fi
done
EOF
chmod +x "$FB_BIN/acli"

# Global Symlink
sudo ln -sf "$FB_BIN/acli" /usr/local/bin/acli || true

# 6. Session Persistence
echo "[*] Adding environment persistence to ~/.bashrc..."
grep -q "FAKEBOX" ~/.bashrc || cat << 'EOF' >> ~/.bashrc

# FAKEBOX Persistence
export PROOT_NO_SECCOMP=1
export PATH="/home/userland/FAKEBOX/bin:$PATH"
alias acli='/home/userland/FAKEBOX/bin/acli'
EOF

echo "[✓] SANDBREAK2 Deployment finished."
