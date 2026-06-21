#!/bin/sh
# sbios5.sh: The Master iSH Deployment Protocol (Fully Native Patching)
set -e

FB_ROOT="$HOME/FAKEBOX"
FB_BIN="$FB_ROOT/bin"
PY_SCRIPT="$FB_ROOT/SBIOS_patcher.py"

echo "========================================="
echo "   SBIOS 5: Antigravity iSH Bootstrapper"
echo "========================================="

echo "[*] Preparing environment..."
mkdir -p "$FB_BIN"

echo "[*] Installing required dependencies (Python3, GCC, musl-dev, curl, ca-certificates, qemu-aarch64)..."
apk update
apk add python3 gcc musl-dev curl ca-certificates qemu-aarch64

echo "[*] Deploying ARM64 glibc sysroot for dynamic linking..."
SYSROOT_DIR="$FB_ROOT/sysroot"
mkdir -p "$SYSROOT_DIR"
if [ ! -f "$SYSROOT_DIR/lib/ld-linux-aarch64.so.1" ]; then
    echo "[*] Downloading Ubuntu base ARM64 rootfs..."
    curl -sL "https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.5-base-arm64.tar.gz" -o "$FB_ROOT/sysroot.tar.gz"
    echo "[*] Extracting sysroot libraries..."
    tar -xzf "$FB_ROOT/sysroot.tar.gz" -C "$SYSROOT_DIR" || true
    rm "$FB_ROOT/sysroot.tar.gz"
fi

echo "[*] Symlinking ARM64 dynamic linker to root filesystem..."
mkdir -p /lib
ln -sf "$SYSROOT_DIR/lib/ld-linux-aarch64.so.1" /lib/ld-linux-aarch64.so.1 || true

echo "[*] Writing Python Instrumentation Script ($PY_SCRIPT)..."
cat << 'EOF_PYTHON' > "$PY_SCRIPT"
#!/usr/bin/env python3
import os
import struct
import json
import re
import tarfile

ORIGINAL_BIN = "agy_original"
PATCHED_BIN = "patched_agy"

def log(msg):
    print(f"[*] {msg}")

def download_payload():
    log("Fetching the static linux_arm64 payload directly from GCS...")
    try:
        url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/1.0.10-6349723456634880/linux-arm/cli_linux_arm64.tar.gz"
        os.system(f'curl -sL "{url}" -o agy.tar.gz')
        log("Extracting payload...")
        
        with tarfile.open("agy.tar.gz", "r:gz") as tar:
            tar.extractall("extract_tmp")
            
        for root, dirs, files in os.walk("extract_tmp"):
            for file in files:
                if file in ["agy", "antigravity"]:
                    os.rename(os.path.join(root, file), ORIGINAL_BIN)
                    
        os.system("rm -rf extract_tmp agy.tar.gz")
        log(f"Successfully staged {ORIGINAL_BIN}")
    except Exception as e:
        log(f"Download failed: {e}. Please place the linux_arm64 binary locally as '{ORIGINAL_BIN}'.")
        if not os.path.exists(ORIGINAL_BIN):
            exit(1)

def apply_real_hex_patches(data):
    log("Applying precision VA39 memory surgery & telemetry evasion...")
    
    # Telemetry evasion
    target = b"telemetry.googleapis.com"
    replacement = b"127.0.0.1" + (b"\x00" * (len(target) - 9))
    if target in data:
        data = data.replace(target, replacement)
        log(" -> Neutered telemetry.googleapis.com to loopback sink.")

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

    log(" -> Memory and syscall patches applied.")
    return data

def main():
    download_payload()
    if not os.path.exists(ORIGINAL_BIN):
        return
    with open(ORIGINAL_BIN, "rb") as f:
        data = bytearray(f.read())
        
    data = apply_real_hex_patches(data)
    
    with open(PATCHED_BIN, "wb") as f:
        f.write(data)
        
    os.chmod(PATCHED_BIN, 0o755)
    log(f"Successfully generated surgically modified binary: {PATCHED_BIN}")

if __name__ == "__main__":
    main()
EOF_PYTHON

chmod +x "$PY_SCRIPT"

echo "[*] Executing Python Instrumentation..."
cd "$FB_ROOT"
python3 "$PY_SCRIPT"

echo "[*] Deploying ARM64 sandbreak hook..."
cp "$(dirname "$0")/sandbreak.so" "$FB_BIN/sandbreak.so"
chmod +x "$FB_BIN/sandbreak.so"

echo "[*] Deploying acli global wrapper script..."
cat << 'EOF_ACLI' > "$FB_BIN/acli"
#!/bin/sh
export GOMEMLIMIT=512MiB 
export GODEBUG=asyncpreemptoff=1 
export GOMAXPROCS=1 
export OPENSSL_ia32cap="~0x4000000000000000"
qemu-aarch64 -E LD_PRELOAD="$HOME/FAKEBOX/bin/sandbreak.so" -L "$HOME/FAKEBOX/sysroot" "$HOME/FAKEBOX/patched_agy" "$@"
EOF_ACLI

chmod +x "$FB_BIN/acli"

echo "[*] Setting up global symlink to /usr/local/bin/acli..."
ln -sf "$FB_BIN/acli" /usr/local/bin/acli || true

echo "[*] Setting up persistence in ~/.bashrc and ~/.profile..."
for file in ~/.bashrc ~/.profile ~/.ashrc; do
    touch "$file"
    grep -q "FAKEBOX" "$file" 2>/dev/null || cat << 'EOF_BASH' >> "$file"

# FAKEBOX Persistence
export PATH="$HOME/FAKEBOX/bin:\$PATH"
EOF_BASH
done

echo "[✓] Deployment Complete. Type 'acli' to launch Antigravity inside iSH natively."
