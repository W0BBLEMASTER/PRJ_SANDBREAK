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
#include <signal.h>
#include <ucontext.h>

void sigsys_handler(int sig, siginfo_t *info, void *ucontext) {
    ucontext_t *uc = (ucontext_t *)ucontext;
    
    // Write out a debug message using async-signal-safe write()
    const char msg[] = "[*] sandbreak.so: Caught SIGSYS trap from emulator. Injecting -ENOSYS.\n";
    write(2, msg, sizeof(msg) - 1);
    
    // Inject -ENOSYS into the return register (X0)
    uc->uc_mcontext.regs[0] = -38;
    
    // IMPORTANT: Under QEMU user-mode emulation, the program counter (PC)
    // is advanced to the next instruction *before* the syscall is dispatched to the host.
    // If we advance the PC again here, we skip a valid instruction and cause a SIGSEGV.
    // Do NOT execute: uc->uc_mcontext.pc += 4;
}

__attribute__((constructor))
void sandbreak_init(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_flags = SA_SIGINFO | SA_RESTART;
    sa.sa_sigaction = sigsys_handler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGSYS, &sa, NULL);
}

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
