# iSH-Exclusive Deployment Protocol: Deep Research Parameters

## Core Directive
The objective is strictly bound to executing the Google Antigravity CLI (`gemini` / `agy`) environment **natively inside the iSH application (usermode 32-bit x86 Alpine emulator)** on iOS. Alternative virtualization platforms (e.g., UTM SE) are explicitly rejected. 

Given that Google's manifest servers strictly return HTTP 404 for `linux_386` and `linux_x86`, and the codebase is closed-source (preventing self-compilation), we must research exotic translation and emulation workarounds to force execution within iSH's architectural boundaries.

## Research Vectors & Critical Questions

### 1. Nested Emulation: QEMU-User within iSH
*   **The Inception Protocol:** Can we install `qemu-aarch64` or `qemu-x86_64` (usermode emulators) via Alpine's `apk` package manager directly *inside* iSH?
*   **Execution Viability:** If we download the official `linux_arm64` binary into iSH, can we execute it by wrapping it in QEMU? (e.g., `qemu-aarch64 ./gemini`). 
*   **Syscall Passthrough:** How does QEMU-user handle system call translation when running on top of iSH's already incomplete syscall translation layer? Will `faccessat2`, `epoll`, and `futex` crash the nested emulator, or will QEMU gracefully map them back to iSH's fakefs and lock implementations?

### 2. Architecture Bridging: Box86 / Box64 / FEX-Emu
*   **64-bit on 32-bit Execution:** Is there a viable way to execute a 64-bit ELF binary (like the `linux_amd64` Antigravity payload) within a strictly 32-bit x86 environment? 
*   Can translators like `box64` or `FEX-Emu` be compiled and run inside iSH to bridge the 32-bit x86 host environment to a 64-bit binary, bypassing the RAM addressing constraints?

### 3. Client-Server Architecture (The Remote Daemon Approach)
*   If executing the heavy multi-agent Go orchestration engine natively in iSH is physically impossible due to the 4 GB memory ceiling of 32-bit architecture, does Antigravity support a headless daemon mode?
*   **Remote Bridging:** Can the heavy Antigravity engine run continuously on a secondary device (like the user's Android phone via Termux or a cloud instance), while iSH runs a lightweight SSH tunnel, `socat` relay, or dedicated UI proxy to interact with it?
*   How can we configure the Antigravity UI (Bubbletea) to render locally in iSH while the AST parsing and LLM vector processing happens remotely?

### 4. Community Mirrors and Legacy 32-bit Artifacts
*   Are there unofficial community mirrors or GitHub Actions pipelines that have successfully reverse-engineered and compiled a 32-bit x86 version of the Antigravity engine?
*   Did early versions of the Antigravity CLI (or late versions of the Gemini CLI) maintain a 32-bit build before the multi-agent architecture became too bloated? If so, what is the exact version number, and does the Google Cloud Run server still host its manifest?

### 5. Advanced iSH Syscall Patching
*   If we manage to initiate execution via `qemu-aarch64` within iSH, we will almost certainly hit the `SIGURG` (asynchronous preemption) crash. 
*   Does `export GODEBUG=asyncpreemptoff=1` still function when passed through QEMU-user inside iSH?
*   What specific `LD_PRELOAD` hooks (similar to the `sandbreak.c` arbitrator) must be compiled natively in iSH x86 to intercept and sanitize memory allocation calls before they hit the QEMU-user layer?
