#!/bin/bash
# A11H7.sh: Early Tooling + apt-mark hold openssh-client + Full Polyfill
set -e
unset LD_PRELOAD

FB_ROOT="/home/userland/FAKEBOX"
FB_BIN="$FB_ROOT/bin"
mkdir -p "$FB_BIN"

echo "[*] Setting OCF Berkeley Mirror..."
echo "deb http://mirrors.ocf.berkeley.edu/kali kali-rolling main contrib non-free non-free-firmware" | sudo tee /etc/apt/sources.list > /dev/null

echo "[*] Early Tooling Installation..."
sudo apt-get -o Acquire::ForceIPv4=true update -qq
sudo apt-get -o Acquire::ForceIPv4=true install -yq libc6-dev make gcc python3 curl bsdutils xdg-utils dialog apt-utils whiptail < /dev/null

echo "[*] Applying Apt-Mark Hold on openssh-client..."
sudo apt-mark hold openssh-client

echo "[*] Installing Node.js & Yarn..."
sudo apt-get -o Acquire::ForceIPv4=true install -yq nodejs npm < /dev/null
sudo npm install -g yarn < /dev/null

echo "[*] Installing Gemini CLI..."
YARN_BIN_DIR=$(yarn global bin 2>/dev/null || echo "/usr/local/bin")
export PATH="$FB_BIN:$YARN_BIN_DIR:$PATH"
yarn global add @google/gemini-cli@nightly

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
    if (flags & 0x100000) { flags &= ~0x100000; if (addr != NULL) flags |= MAP_FIXED; }
    if (addr != NULL && (uintptr_t)addr > 0x7FFFFFFFFFULL) addr = NULL;
    static void* (*real_mmap)(void*, size_t, int, int, int, off_t) = NULL;
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    void* res = real_mmap(addr, length, prot, flags, fd, offset);
    if (res == MAP_FAILED && addr != NULL) res = real_mmap(NULL, length, prot, flags & ~MAP_FIXED, fd, offset);
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
env -u LD_PRELOAD gcc -shared -fPIC "$FB_BIN/sandbreak.c" -o "$FB_BIN/sandbreak.so" -ldl

echo "[*] Injecting Full A112 TTY Polyfill..."
cat << 'EOF' > "$FB_BIN/tty-polyfill.js"
const cp = require('child_process');
require('tty').isatty = () => true;

process.on('SIGINT', () => process.exit(0));

['stdout', 'stderr'].forEach(s => {
  const origDesc = Object.getOwnPropertyDescriptor(process, s);
  if (origDesc) {
    Object.defineProperty(process, s, {
      get() {
        const stream = origDesc.get ? origDesc.get.call(process) : origDesc.value;
        if (stream && !stream.__hooked) {
          stream.__hooked = true;
          Object.defineProperty(stream, 'isTTY', { value: true, enumerable: true, configurable: true });
          
          let cols = 80; let rows = 24;
          
          function updateSize() {
            try {
              const out = cp.execSync('stty size < /dev/tty', { encoding: 'utf8' }).trim().split(/\s+/);
              if (out.length === 2) { rows = parseInt(out[0], 10); cols = parseInt(out[1], 10); }
            } catch (e) {
              cols = parseInt(process.env.COLUMNS || 80, 10); rows = parseInt(process.env.LINES || 24, 10);
            }
          }
          
          updateSize();
          
          process.on('SIGWINCH', () => {
             updateSize();
             if (stream.emit) {
                 stream.emit('resize');
             }
          });

          Object.defineProperty(stream, 'columns', { get: () => cols, set: (v) => { cols = v; }, enumerable: true, configurable: true });
          Object.defineProperty(stream, 'rows', { get: () => rows, set: (v) => { rows = v; }, enumerable: true, configurable: true });
          stream.getColorDepth = () => 24; stream.hasColors = () => true;
        }
        return stream;
      },
      enumerable: true, configurable: true
    });
  }
});

let lastKeyTime = 0, lastKeyBuf = null;
const originalStdinDesc = Object.getOwnPropertyDescriptor(process, 'stdin');
if (originalStdinDesc) {
  Object.defineProperty(process, 'stdin', {
    get() {
      const stdin = originalStdinDesc.get ? originalStdinDesc.get.call(process) : originalStdinDesc.value;
      if (stdin && !stdin.__hooked) {
        stdin.__hooked = true;
        Object.defineProperty(stdin, 'isTTY', { get: () => true, enumerable: true, configurable: true });
        
        let currentRaw = null;
        stdin.setRawMode = function(m) { 
          if (m === currentRaw) return this;
          currentRaw = m;
          try { cp.execSync(m ? 'stty -icanon -echo < /dev/tty' : 'stty icanon echo < /dev/tty'); } catch(e){}
          this.isRaw = m; 
          return this; 
        };
        
        const originalEmit = stdin.emit.bind(stdin);
        stdin.emit = function(event, ...args) {
          if (event === 'data' && this.isRaw && args[0]) {
            const now = Date.now();
            const isStr = typeof args[0] === 'string';
            const buf = isStr ? Buffer.from(args[0]) : (Buffer.isBuffer(args[0]) ? args[0] : null);
            
            if (buf) {
              if (lastKeyBuf && buf.equals(lastKeyBuf) && (now - lastKeyTime) < 40) return false;
              lastKeyTime = now; lastKeyBuf = buf;
              
              if (buf.length === 1 && buf[0] === 0x0a) {
                args[0] = isStr ? '\r' : Buffer.from([0x0d]);
              }
            }
          }
          return originalEmit(event, ...args);
        };
      }
      return stdin;
    },
    enumerable: true, configurable: true
  });
}
EOF

echo "[*] Deploying gcli..."
cat << EOF > "$FB_BIN/gcli"
#!/bin/bash
FB_BIN_DIR="$FB_BIN"
export PATH="\$FB_BIN_DIR:$YARN_BIN_DIR:\$PATH"
export LD_PRELOAD="\$FB_BIN_DIR/sandbreak.so"
export NODE_OPTIONS="--require \$FB_BIN_DIR/tty-polyfill.js"
export PROOT_NO_SECCOMP=1 
export DISPLAY=:0
export BROWSER=echo 
export LANG=C.UTF-8 
export TERM=xterm-256color 
export COLORTERM=truecolor 
export FORCE_COLOR=3

trap 'reset; stty sane 2>/dev/null; tput cnorm 2>/dev/null; exit 130' INT
trap 'reset; stty sane 2>/dev/null; tput cnorm 2>/dev/null' EXIT ERR HUP TERM

while true; do
  clear
  stty -icanon -echo 2>/dev/null || true
  gemini "\$@"
  EXIT_CODE=\$?
  if [ \$EXIT_CODE -ne 199 ]; then
    exit \$EXIT_CODE
  fi
  echo -e "\n[Savant] Restarting CLI...\n"
  sleep 1
done
EOF
chmod +x "$FB_BIN/gcli"
sudo ln -sf "$FB_BIN/gcli" /usr/local/bin/gcli || true

echo "[✓] A11 FAKEBOX Deployment complete."
