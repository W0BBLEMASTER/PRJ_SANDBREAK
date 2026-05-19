#!/bin/bash
# A10-2.sh: Fakebox (gcli2)
# Exact A9A82 Baseline + Type-Safe Input Fix + BROWSER=echo

export DEBIAN_FRONTEND=noninteractive
export PROOT_NO_SECCOMP=1
unset NODE_OPTIONS
unset LD_PRELOAD
mkdir -p "$HOME/FAKEBOX/bin"

sudo apt-get -o Acquire::ForceIPv4=true update -qq
sudo apt-get -o Acquire::ForceIPv4=true install -yq python3 curl nodejs npm gcc bsdutils xdg-utils dialog apt-utils whiptail --allow-unauthenticated < /dev/null

rm -rf "$HOME/FAKEBOX/.gemini"

cat << 'EOF' > "$HOME/FAKEBOX/bin/sandbreak.c"
#define _GNU_SOURCE
#include <errno.h>
#include <stddef.h>
#include <string.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <sys/syscall.h>
#include <stdarg.h>

int set_robust_list(void *h, size_t l) { return 0; }
int faccessat2(int d, const char *p, int m, int f) { errno = 38; return -1; }

static int check_usb(const char *pathname) {
    if (pathname && (strstr(pathname, "bus/usb") || strstr(pathname, "usb"))) { return -1; }
    return 0;
}

typedef int (*orig_openat_t)(int, const char *, int, mode_t);
int openat(int dirfd, const char *pathname, int flags, ...) {
    if (check_usb(pathname) == -1) { errno = ENOENT; return -1; }
    orig_openat_t orig_openat = (orig_openat_t)dlsym(RTLD_NEXT, "openat");
    mode_t mode = 0; if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = va_arg(args, mode_t); va_end(args); }
    return orig_openat(dirfd, pathname, flags, mode);
}

typedef int (*orig_open_t)(const char *, int, mode_t);
int open(const char *pathname, int flags, ...) {
    if (check_usb(pathname) == -1) { errno = ENOENT; return -1; }
    orig_open_t orig_open = (orig_open_t)dlsym(RTLD_NEXT, "open");
    mode_t mode = 0; if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = va_arg(args, mode_t); va_end(args); }
    return orig_open(pathname, flags, mode);
}

long syscall(long number, ...) {
    va_list args; va_start(args, number);
    long arg1 = va_arg(args, long); long arg2 = va_arg(args, long); long arg3 = va_arg(args, long);
    long arg4 = va_arg(args, long); long arg5 = va_arg(args, long); long arg6 = va_arg(args, long);
    va_end(args);
    if (number == SYS_openat && check_usb((const char *)arg2) == -1) { errno = ENOENT; return -1; }
    typedef long (*orig_syscall_t)(long, long, long, long, long, long, long);
    orig_syscall_t orig_syscall = (orig_syscall_t)dlsym(RTLD_NEXT, "syscall");
    return orig_syscall(number, arg1, arg2, arg3, arg4, arg5, arg6);
}
EOF
gcc -shared -fPIC "$HOME/FAKEBOX/bin/sandbreak.c" -o "$HOME/FAKEBOX/bin/sandbreak.so" -ldl

cat << 'EOF' > "$HOME/FAKEBOX/bin/tty-polyfill.js"
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
          try {
            const out = cp.execSync('stty size < /dev/tty', { encoding: 'utf8' }).trim().split(/\s+/);
            if (out.length === 2) { rows = parseInt(out[0], 10); cols = parseInt(out[1], 10); }
          } catch (e) {
            cols = parseInt(process.env.COLUMNS || 80, 10); rows = parseInt(process.env.LINES || 24, 10);
          }
          
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

if ! command -v yarn &> /dev/null; then
  sudo npm install -g yarn < /dev/null
fi
YARN_BIN_DIR=$(yarn global bin 2>/dev/null || echo "/usr/local/bin")
export PATH="$HOME/FAKEBOX/bin:$YARN_BIN_DIR:$PATH"
yarn global add @google/gemini-cli@nightly

sudo tee /usr/local/bin/gcli2 > /dev/null << 'EOF'
#!/bin/bash
YARN_BIN_DIR=$(yarn global bin 2>/dev/null || echo "/usr/local/bin")
FB_BIN_DIR="$HOME/FAKEBOX/bin"

export HOME="$HOME/FAKEBOX"
export PATH="$FB_BIN_DIR:$YARN_BIN_DIR:$PATH"
export NODE_OPTIONS="--require $FB_BIN_DIR/tty-polyfill.js"
export LD_PRELOAD="$FB_BIN_DIR/sandbreak.so"
export PROOT_NO_SECCOMP=1 
export NODE_TLS_REJECT_UNAUTHORIZED=0
export DISPLAY=:0
export BROWSER=echo 
export LANG=C.UTF-8 
export TERM=xterm-256color 
export COLORTERM=truecolor 
export FORCE_COLOR=3
export GEMINI_CLI_NO_RELAUNCH=1 

trap 'reset; stty sane 2>/dev/null; tput cnorm 2>/dev/null' EXIT ERR HUP INT TERM

while true; do
  stty -icanon -echo 2>/dev/null
  gemini "$@"
  EXIT_CODE=$?
  if [ $EXIT_CODE -ne 199 ]; then
    exit $EXIT_CODE
  fi
  echo -e "\n[Savant] Restarting CLI...\n"
done
EOF
sudo chmod +x /usr/local/bin/gcli2
echo "A10-2 (Fakebox) Deployed."