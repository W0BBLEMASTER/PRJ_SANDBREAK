# Python Offset Modding: The iSH Native Execution Masterplan

## Core Directive: Binary Instrumentation
Given the explicit mandate to execute the Google Antigravity CLI natively within the 32-bit iSH environment without relying on external hypervisors, and given the absolute lack of open-source code for cross-compilation, the final strategy requires aggressive binary surgery.

Odo's proposed vector—**Python Offset Modding**—is the definitive path forward. We will write a custom Python instrumentation script designed to structurally alter the compiled 64-bit `linux_arm64` ELF binary at the hex level. This will dynamically patch the memory constraints and cryptographic lockouts, forcing the binary to conform to the 32-bit x86 iSH sandbox via QEMU-user.

## Phase 1: Virtual Address Space Reduction (The 4GB Cap)
The primary obstacle is the Go runtime requesting a 256TB contiguous Virtual Address block via `mmap`, which instantly crashes QEMU-user inside the 4GB iSH sandbox.
Our Python script must locate and patch the memory allocator constants deeply embedded in the ELF binary.

### Target Constants:
1. **`heapAddrBits`**: The constant dictating the total addressable memory. On aarch64, it is hardcoded to `48` (0x30). We must patch this byte to `32` (0x20).
2. **`heapArenaBytes`**: The size of individual garbage collection arenas. On 64-bit, this is 64MB (`0x4000000`). We must patch this to 4MB (`0x400000`) to match the 32-bit alignment structure.

### Python Methodology:
*   The Python script will ingest the `linux_arm64` binary as a raw bytearray.
*   We will utilize standard ELF parsing libraries (or raw struct unpacking) to index the `.rodata` and `.data` segments.
*   By searching for specific contiguous byte signatures known to represent the `runtime` package's initialization struct, we can dynamically calculate the offset for `heapAddrBits` and surgically overwrite the byte without breaking the binary's structural integrity.

## Phase 2: Hardware Cryptography Bypass (`sigill-fail-fast`)
The second critical obstacle is the binary intentionally panicking if AES-NI or ARM LSE hardware crypto extensions are not found by the host CPU. Because iSH translates x86 without these advanced extensions, the binary will trigger a fatal `SIGILL`.

### Target Routine:
The initialization routine checks the CPU feature flags. If the cryptographic flags evaluate to `false`, the execution branches to a panic loop emitting the `go/sigill-fail-fast` error string.

### Python Methodology:
*   The script will search the `.rodata` segment for the exact string: `FATAL ERROR: This binary was compiled with aes enabled, but this feature is not available on this processor`.
*   We will trace the cross-reference of this string's address back into the `.text` (executable) segment.
*   The Python script will analyze the ARM64 opcodes at this offset. We are looking for the conditional branch instruction (e.g., `CBZ` - Compare and Branch on Zero, or `TBNZ` - Test Bit and Branch if Non-Zero) that triggers the panic.
*   The script will perform a hex-patch, overwriting the conditional opcode with a `NOP` (No Operation - `0xD503201F` in ARM64) or an unconditional branch (`B`) that forces the execution path to skip the panic block entirely, thus falling back to software-based cryptography.

## Phase 3: Syscall Sanitization Hook (The `LD_PRELOAD` Generator)
Because QEMU-user will blindly pass `faccessat2` and `epoll` syscalls down to the incomplete iSH kernel, our Python script must also act as a payload generator.
*   The script will generate a tiny, optimized C file (`sandbreak_ish.c`).
*   This C file will contain `LD_PRELOAD` hooks specifically designed to intercept `faccessat2` and `SIGURG` signals.
*   The script will invoke `apk add gcc musl-dev` inside iSH, compile the hook locally into a 32-bit `sandbox.so`, and automatically prepend it to the final QEMU execution command.

## Execution Flow (The "SBIOS" Python Implementation)
When Odo runs the final Python script, the sequence will be:
1. `download_payload()`: Fetches the raw `linux_arm64` binary.
2. `patch_memory_arena()`: Scans offsets and overwrites `heapAddrBits` to 32.
3. `patch_crypto_lockout()`: Scans `.text` and NOPs the `sigill-fail-fast` branch.
4. `generate_sandbox()`: Compiles the `LD_PRELOAD` syscall interceptor.
5. `launch_antigravity()`: Executes the surgically modified binary natively within iSH using `qemu-aarch64 -E LD_PRELOAD=sandbox.so ./patched_agy`.

By systematically calculating these offsets and modifying the binary at the byte level via Python, we eliminate the need for source code recompilation and bypass the mathematical impossibilities of 64-on-32 emulation.
