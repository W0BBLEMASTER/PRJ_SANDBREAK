#!/bin/sh
# sbios5.sh: The Master iSH Deployment Protocol (Fully Native Patching)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

echo "[*] Writing Fast C Patcher..."
cat << 'EOF_C' > "$FB_ROOT/patcher.c"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

void patch_fips(uint8_t *data, size_t size) {
    uint8_t fips_p[] = {0xe0, 0x00, 0x00, 0x35, 0x20, 0x00, 0x80, 0x52, 0xf4, 0x4f, 0x43, 0xa9, 0xf6, 0x57, 0x42, 0xa9, 0xf8, 0x5f, 0x41, 0xa9};
    uint8_t fips_r[] = {0x1f, 0x20, 0x03, 0xd5, 0x20, 0x00, 0x80, 0x52, 0xf4, 0x4f, 0x43, 0xa9, 0xf6, 0x57, 0x42, 0xa9, 0xf8, 0x5f, 0x41, 0xa9};
    for (size_t i = 0; i < size - sizeof(fips_p); i++) {
        if (memcmp(data + i, fips_p, sizeof(fips_p)) == 0) {
            memcpy(data + i, fips_r, sizeof(fips_r));
            printf("[*] FIPS bypass applied.\n");
            break;
        }
    }
}

void patch_telemetry(uint8_t *data, size_t size) {
    const char *target = "telemetry.googleapis.com";
    const char *replacement = "127.0.0.1";
    size_t target_len = strlen(target);
    for (size_t i = 0; i < size - target_len; i++) {
        if (memcmp(data + i, target, target_len) == 0) {
            memset(data + i, 0, target_len);
            memcpy(data + i, replacement, strlen(replacement));
            printf("[*] Telemetry evasion applied.\n");
        }
    }
}

size_t find_section_google_malloc(uint8_t *data, size_t size, size_t *sec_size) {
    if (size < 64 || memcmp(data, "\x7f""ELF", 4) != 0) return 0;
    uint64_t e_shoff = *(uint64_t*)(data + 40);
    uint16_t e_shentsize = *(uint16_t*)(data + 58);
    uint16_t e_shnum = *(uint16_t*)(data + 60);
    uint16_t e_shstrndx = *(uint16_t*)(data + 62);
    if (e_shoff + e_shstrndx * e_shentsize >= size) return 0;
    uint64_t shstr_base = e_shoff + e_shstrndx * e_shentsize;
    uint64_t shstr_off = *(uint64_t*)(data + shstr_base + 24);
    for (int i = 0; i < e_shnum; i++) {
        uint64_t base = e_shoff + i * e_shentsize;
        if (base + 64 > size) continue;
        uint32_t sh_name = *(uint32_t*)(data + base);
        uint64_t sh_offset = *(uint64_t*)(data + base + 24);
        uint64_t sh_size_val = *(uint64_t*)(data + base + 32);
        if (shstr_off + sh_name < size) {
            char *name = (char*)(data + shstr_off + sh_name);
            if (strcmp(name, "google_malloc") == 0) {
                *sec_size = sh_size_val;
                return sh_offset;
            }
        }
    }
    return 0;
}

void patch_va39(uint8_t *data, size_t size) {
    size_t sec_size = 0;
    size_t lo = find_section_google_malloc(data, size, &sec_size);
    size_t hi = lo + sec_size;
    if (lo == 0) { lo = 0; hi = size; }
    
    for (size_t off = lo; off < hi; off += 4) {
        if (off + 4 > size) break;
        uint32_t w = *(uint32_t*)(data + off);
        
        if ((w & 0x7F800000) == 0x53000000) {
            uint32_t immr = (w >> 16) & 0x3F;
            uint32_t imms = (w >> 10) & 0x3F;
            if (immr == 42 && imms == 44) {
                w = (w & ~((0x3F << 16) | (0x3F << 10))) | (35 << 16) | (37 << 10);
                *(uint32_t*)(data + off) = w;
            } else if (immr == 22 && imms == 21) {
                w = (w & ~((0x3F << 16) | (0x3F << 10))) | (29 << 16) | (28 << 10);
                *(uint32_t*)(data + off) = w;
            }
        }
        
        if (w == 0xF2E00029) {
            *(uint32_t*)(data + off) = 0xD3596129;
            continue;
        }
        
        switch (w) {
            case 0xD2C20009: *(uint32_t*)(data + off) = 0xD2C00409; break;
            case 0xD2C2000A: *(uint32_t*)(data + off) = 0xD2C0040A; break;
            case 0xF2C20008: *(uint32_t*)(data + off) = 0xF2DFF408; break;
            case 0xF2C20009: *(uint32_t*)(data + off) = 0xF2DFF409; break;
            case 0xD2C10009: *(uint32_t*)(data + off) = 0xD2C00209; break;
            case 0xD2C1000A: *(uint32_t*)(data + off) = 0xD2C0020A; break;
            case 0xF2C38008: *(uint32_t*)(data + off) = 0xF2DFF708; break;
            case 0xF2C38009: *(uint32_t*)(data + off) = 0xF2DFF709; break;
            case 0x92560A6C: *(uint32_t*)(data + off) = 0x925D0A6C; break;
            case 0x92560A6A: *(uint32_t*)(data + off) = 0x925D0A6A; break;
            case 0xD2C3000D: *(uint32_t*)(data + off) = 0xD2C0060D; break;
            case 0xD2C3000C: *(uint32_t*)(data + off) = 0xD2C0060C; break;
            case 0xD2C08008: *(uint32_t*)(data + off) = 0xD2C00108; break;
        }
    }
    for (size_t off = lo; off < hi - 4; off += 4) {
        if (off + 8 > size) break;
        if (*(uint32_t*)(data + off) == 0x92D3800A && *(uint32_t*)(data + off + 4) == 0xF2E0000A) {
            *(uint32_t*)(data + off) = 0x9280000A;
            *(uint32_t*)(data + off + 4) = 0xD35DFD4A;
        }
    }
}

void patch_faccessat(uint8_t *data, size_t size) {
    for (size_t off = 0; off < size - 12; off += 4) {
        if (*(uint32_t*)(data + off) == 0xAA1F03E5 && *(uint32_t*)(data + off + 4) == 0xAA1F03E6 && 
            *(uint32_t*)(data + off + 8) == 0xD28036E0 && (*(uint32_t*)(data + off + 12) & 0xFC000000) == 0x94000000) {
            *(uint32_t*)(data + off + 8) = 0xD2800600;
        }
    }
}

int main(int argc, char **argv) {
    FILE *f = fopen("agy_original", "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    size_t size = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *data = malloc(size);
    fread(data, 1, size, f);
    fclose(f);
    
    patch_telemetry(data, size);
    patch_fips(data, size);
    patch_va39(data, size);
    patch_faccessat(data, size);
    
    FILE *out = fopen("patched_agy", "wb");
    fwrite(data, 1, size, out);
    fclose(out);
    free(data);
    printf("[✓] C binary patch applied successfully.\n");
    return 0;
}
EOF_C

echo "[*] Compiling Fast C Patcher..."
gcc -O3 "$FB_ROOT/patcher.c" -o "$FB_ROOT/patcher"

echo "[*] Fetching the payload directly from GCS..."
curl -sL "https://storage.googleapis.com/antigravity-public/antigravity-cli/1.0.10-6349723456634880/linux-arm/cli_linux_arm64.tar.gz" -o "$FB_ROOT/agy.tar.gz"
mkdir -p "$FB_ROOT/extract_tmp"
tar -xzf "$FB_ROOT/agy.tar.gz" -C "$FB_ROOT/extract_tmp"
find "$FB_ROOT/extract_tmp" -type f \( -name "antigravity" -o -name "agy" \) -exec mv {} "$FB_ROOT/agy_original" \;
rm -rf "$FB_ROOT/extract_tmp" "$FB_ROOT/agy.tar.gz"

echo "[*] Executing C Instrumentation..."
cd "$FB_ROOT"
./patcher
chmod +x "$FB_ROOT/patched_agy"

echo "[*] Deploying ARM64 sandbreak hook..."
cp "$SCRIPT_DIR/sandbreak.so" "$FB_BIN/sandbreak.so"
chmod +x "$FB_BIN/sandbreak.so"

echo "[*] Deploying acli global wrapper script..."
cat << 'EOF_ACLI' > "$FB_BIN/acli"
#!/usr/bin/env sh
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
