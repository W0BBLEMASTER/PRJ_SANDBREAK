# Antigravity CLI (agy) & iSH Deployment: Deep Research Protocol

## Core Objective
Determine the viability of running Google's Antigravity CLI (`acli` / `agy`) natively on iOS via iSH (32-bit x86 Alpine Linux emulator) or an alternative iOS environment, and identify what critical components we are missing to make this happen.

## Research Vectors & Critical Questions

### 1. Source Code & Compilation (The "Missing Repo" Theory)
*   **Is `antigravity-cli` Open Source?** Is there a public Google GitHub repository for the Antigravity CLI (`acli` / `agy`), or is it strictly proprietary/internal? 
*   **Cross-Compilation to x86:** If the source is available, can we simply compile it using `GOOS=linux GOARCH=386`? 
*   **The FIPS & Memory Surgery Question:** The precompiled ARM64 binaries required intense hex-patching (FIPS bypass, VA39 TCMalloc overrides, `faccessat2` patches) to run on Android. Are these issues artifacts of Google's *internal* proprietary build toolchain? If we compile from source using standard `golang`, do we bypass these sandbox-crashing features entirely?

### 2. Go Binaries vs. iSH Syscall Emulation
*   **Go Runtime Compatibility:** Modern versions of Go (1.18+) rely heavily on newer Linux kernel syscalls (like `epoll`, `futex`, `clone`). iSH's syscall translation layer is famously incomplete. Will a Go-compiled `linux/386` binary immediately crash in iSH due to an unimplemented syscall?
*   **Workarounds:** If Go binaries fail in iSH, what is the standard workaround? Do we need to compile with an older Go version, use `GODEBUG=asyncpreemptoff=1`, or patch iSH's syscalls?

### 3. The Auto-Updater Manifest Server
*   **Hidden Architectures:** We know `linux_amd64.json` and `linux_arm64.json` return HTTP 200, while `linux_386.json` and `linux_x86.json` return 404. Are there other naming conventions for 32-bit x86 used by Google's build servers?
*   **Server Endpoints:** What other endpoints exist on `https://antigravity-cli-auto-updater-974169037036.us-central1.run.app`? Is there a directory listing, an API for requesting specific architectures, or an open-source mirror linked in its headers?

### 4. Alternative iOS Execution Environments
*   **If iSH Fails:** If the 32-bit x86 emulation of iSH is fundamentally incompatible with the Go runtime, what are our alternatives on a non-jailbroken iPhone?
*   **A-Shell / Blink:** Can we compile Antigravity CLI to WebAssembly (`GOOS=js GOARCH=wasm` or `GOOS=wasip1`) and run it inside A-Shell or Blink shell natively on iOS?
*   **UTM SE:** Is running an ARM64 Alpine Linux VM via UTM SE (which is now allowed on the App Store without JIT) the only viable way to execute the precompiled `linux_arm64` binary on an iPhone?

### 5. The "What Are We Missing?" Synthesis
*   Why would Google create an update server that lacks a 32-bit x86 build in 2026? 
*   Did the developers anticipate this tool being used strictly on 64-bit cloud containers and modern Android/Linux devices, leaving out legacy architectures? 
*   Is there a lightweight "agent-only" variant of Antigravity designed for edge devices?
