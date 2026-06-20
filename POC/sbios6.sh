#!/bin/sh
# sbios5.sh: The Master iSH Deployment Protocol (Fully Native Patching)
set -e

FB_ROOT="/home/userland/FAKEBOX"
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

    # B. VA39 TCMalloc Overrides (Optimized with array)
    import array
    arr = array.array('I', data[lo:hi])
    word_rewrites = {
        0xD2C20009: 0xD2C00409, 0xD2C2000A: 0xD2C0040A, 0xF2C20008: 0xF2DFF408,
        0xF2C20009: 0xF2DFF409, 0xD2C10009: 0xD2C00209, 0xD2C1000A: 0xD2C0020A,
        0xF2C38008: 0xF2DFF708, 0xF2C38009: 0xF2DFF709, 0x92560A6C: 0x925D0A6C,
        0x92560A6A: 0x925D0A6A, 0xD2C3000D: 0xD2C0060D, 0xD2C3000C: 0xD2C0060C,
        0xD2C08008: 0xD2C00108,
    }
    for i in range(len(arr)):
        w = arr[i]
        if (w & 0x7F800000) == 0x53000000:
            immr = (w >> 16) & 0x3F
            imms = (w >> 10) & 0x3F
            if immr == 42 and imms == 44:
                arr[i] = (w & ~((0x3F << 16) | (0x3F << 10))) | (35 << 16) | (37 << 10)
            elif immr == 22 and imms == 21:
                arr[i] = (w & ~((0x3F << 16) | (0x3F << 10))) | (29 << 16) | (28 << 10)
        elif w == 0x92D3800A and i + 1 < len(arr) and arr[i+1] == 0xF2E0000A:
            arr[i] = 0x9280000A
            arr[i+1] = 0xD35DFD4A
        elif w == 0xF2E00029:
            arr[i] = 0xD3596129
        elif w in word_rewrites:
            arr[i] = word_rewrites[w]
    data[lo:hi] = arr.tobytes()

    # C. faccessat2 -> faccessat (Optimized with fast substring search)
    def put(off, word): struct.pack_into("<I", data, off, word)
    prefix = b'\xe5\x03\x1f\xaa\xe6\x03\x1f\xaa\xe0\x36\x80\xd2'
    idx = 0
    while True:
        idx = data.find(prefix, idx)
        if idx == -1:
            break
        if idx % 4 == 0 and idx + 15 < len(data) and (data[idx + 15] & 0xFC) == 0x94:
            put(idx + 8, 0xD2800600)
        idx += 12

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

echo "[*] Deploying acli global wrapper script..."
cat << 'EOF_ACLI' > "$FB_BIN/acli"
#!/bin/sh
export GOMEMLIMIT=512MiB 
export GODEBUG=asyncpreemptoff=1 
export GOMAXPROCS=1 
export OPENSSL_ia32cap="~0x4000000000000000"
qemu-aarch64 -L /home/userland/FAKEBOX/sysroot /home/userland/FAKEBOX/patched_agy "$@"
EOF_ACLI

chmod +x "$FB_BIN/acli"

echo "[*] Setting up global symlink to /usr/local/bin/acli..."
ln -sf "$FB_BIN/acli" /usr/local/bin/acli || true

echo "[*] Setting up persistence in ~/.bashrc and ~/.profile..."
for file in ~/.bashrc ~/.profile ~/.ashrc; do
    touch "$file"
    grep -q "FAKEBOX" "$file" 2>/dev/null || cat << 'EOF_BASH' >> "$file"

# FAKEBOX Persistence
export PATH="/home/userland/FAKEBOX/bin:$PATH"
EOF_BASH
done

echo "[✓] Deployment Complete. Type 'acli' to launch Antigravity inside iSH natively."
