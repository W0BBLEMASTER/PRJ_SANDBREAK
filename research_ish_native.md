# The iSH-Native Execution Mandate: Forcing 64-bit Antigravity into a 32-bit iOS Sandbox

## Core Directive (NON-NEGOTIABLE)
The objective is the absolute, native execution of the Google Antigravity CLI (`agy`) strictly within the iSH emulator (32-bit x86 Alpine Linux) on a single iOS device. 

All secondary device bridging (Client-Server/Remote Daemon) and external hypervisors (UTM SE) are explicitly banned. The deployment must be self-contained on the iPhone. We must bypass the 4GB memory ceiling and 32-bit instruction set limitations using extreme binary translation, memory instrumentation, or environment spoofing.

## Advanced Research Vectors for Native Emulation

### 1. Manipulating the Go Memory Arena (The QEMU-User Bypass)
The primary reason QEMU-user fails to run the 64-bit `linux_arm64` binary inside the 32-bit iSH host is because modern 64-bit Go runtimes request a massive (often 16TB) contiguous Virtual Address (VA) block during initialization for garbage collection arenas, which instantly exceeds iSH's 4GB limit.
*   **Environmental Overrides:** Does exporting `GOMEMLIMIT=512MiB` or drastically reducing `GOGC` prevent the Go runtime from requesting the massive 16TB VA block at initialization? If so, will this allow `qemu-aarch64` to successfully map the guest process within iSH's memory bounds?
*   **Binary Surgery (Arena Patching):** If environmental variables are ignored during early `mmap` initialization, can we locate the `runtime.mallocinit` or arena mapping functions within the stripped binary and hex-patch the requested allocation size down from 16TB to a manageable 512MB?

### 2. Binary Lifting and Transpilation to 32-bit
Since we cannot compile from source, can we translate the compiled machine code?
*   **Intermediate Representation (IR) Lifting:** Can advanced reverse-engineering frameworks (such as McSema, rev.ng, or Ghidra's decompiler) lift the `linux_arm64` or `linux_amd64` ELF binary into LLVM Intermediate Representation (IR)?
*   **Recompilation:** Once lifted to LLVM IR, can the code be recompiled natively targeting `i686` (32-bit x86)? This would entirely eliminate the need for QEMU-user, allowing native execution within iSH. How does lifting handle Go's custom ABI and stack management?

### 3. LD_PRELOAD Memory Interception for QEMU
If we must use `qemu-aarch64` inside iSH, we need to intercept the memory allocations before QEMU requests them from the iSH kernel.
*   **The Mmap Arbitrator:** If we write a custom `LD_PRELOAD` shared library in native 32-bit x86 and hook it to the `qemu-aarch64` invocation, can we intercept QEMU's `mmap` requests? 
*   When QEMU attempts to reserve the massive `PROT_NONE` guest address space, can our hook dynamically lie to QEMU, returning a success code while only actually reserving a tiny fraction of the memory, thus tricking the emulator into booting the binary?

### 4. Bypassing go/sigill-fail-fast (Hardware Crypto Lockout)
The `linux_arm64` binary expects hardware cryptographic extensions and intentionally panics (`SIGILL`) if they are absent.
*   If we use QEMU-user, how severely does emulating these crypto extensions (e.g., `-cpu max`) degrade performance inside iSH?
*   Can we hex-patch the `go/sigill-fail-fast` initialization checks out of the binary entirely, forcing the runtime to fall back to software-based cryptography natively, avoiding the QEMU translation penalty?

### 5. iSH Custom Kernel Hooks
iSH is open-source. Instead of fighting the emulator, can we modify it?
*   Can we compile a custom build of the iSH iOS app (sideloaded via AltStore/TrollStore) that expands the fakefs system to perfectly emulate `faccessat2` and `epoll` exactly as the Go runtime expects?
*   Can iSH be modified to handle `SIGURG` asynchronous preemption gracefully, eliminating the need to handicap the Go runtime with `GODEBUG=asyncpreemptoff=1`?
