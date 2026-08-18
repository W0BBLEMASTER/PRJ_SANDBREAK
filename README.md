# SANDBREAK: Your Personal Cross-Platform CLI Powerhouse 🚀

Tired of Android's file system restrictions? Bored and want to turn your UserLAnd environment into a dedicated terminal for ADB operations and deep Android file system access? Looking for a completely isolated Antigravity CLI deployment on Windows without making a mess?

SANDBREAK is a personal project designed to transform your environments into a lean, mean, CLI machine. It operates as an uncompromising, secure staging layer for Antigravity, effectively sandboxing its execution and patching architecture-specific bugs in real-time.

## ✨ What is SANDBREAK?

SANDBREAK offers robust, specialized deployment scripts for both Android (UserLAnd) and Windows. It aims to:

1.  **Create a robust sandbox** around the Antigravity CLI, preventing environment contamination.
2.  **Patch Native Bugs in Real-Time:** On Android, it deploys a sophisticated memory monkey patch (`sandbreak.so`) via `LD_PRELOAD` to hotfix deep VA39 Google TCMalloc segfaults specific to PRoot environments.
3.  **Tame Unruly Terminal Interfaces:** Incorporates advanced Python-based regex TTY output filtering (`out_filter.py`) to silence the dreaded Bubbletea "1;1u" cursor query bleed, while meticulously ensuring the cursor blinks normally during typing.
4.  **Shadow Environments (Windows):** Hyper-aggressive environment shadowing on Windows (`acli.bat`) ensures the CLI runs entirely contained within an `.acli` directory, bypassing global `PATH` and `USERPROFILE` mutations.

## 🚀 The Architecture

### 🐧 Android / Linux (UserLAnd) -> `SANDBREAK2(p2bubble1_acli).sh`

The current Linux deployment script is a highly advanced automated architect. When executed, it:
- **Acquires Dependencies:** Quietly downloads necessary binaries (like `script`, `python3`, `adb`, `gcc`).
- **Downloads the Payload:** Pulls the latest official `arm64` Linux Antigravity binary.
- **Precision VA39 Memory Surgery:** Uses a Python heuristic patcher to dissect the raw ELF binary and rewrite `google_malloc` and `faccessat2` invocations that crash inside PRoot.
- **Sandbreak Arbitrator (`sandbreak.so`):** Compiles a bespoke shared object library for `LD_PRELOAD` that dynamically fixes `mmap` allocation rules.
- **The Wrapper (`acli`):** Generates a pristine wrapper script that creates a pseudo-terminal using `script -q`, pipes all output into a dynamic Python regex filter to eliminate terminal capability spam (like `\x1b[?u`), while properly allowing essential ANSI cursor movements and restoration. 

Execute the script:
```bash
sh SANDBREAK2(p2bubble1_acli).sh
```

### 🪟 Windows -> `acli.bat`

The Windows script is a surgical bootstrapper designed for total isolation.
- **Staging Directory:** Creates an `.acli` sandbox directory relative to the script.
- **Shadowing:** Overrides `LOCALAPPDATA`, `USERPROFILE`, `HOMEDRIVE`, and `HOMEPATH` for the execution context of the script.
- **Silent Bootstrapping:** If it detects a virgin environment, it transparently downloads and executes the official PowerShell installer using `--skip-path` and `--skip-aliases` to ensure zero global footprint.
- **TUI Invocation:** Proxies all command-line arguments flawlessly to the isolated `agy.exe` binary.

Execute the batch script:
```cmd
acli.bat
```

## ⚠️ Notes & Caveats

*   This is a personal project born out of boredom. It's functional but heavily tailored for specific edge cases (like the UserLAnd `mmap` and `1;1u` bugs).
*   The Android wrapper contains an auto-revive loop. If `agy` crashes with an unexpected signal, it restarts it and cleans up the cursor using `tput cnorm`.
*   Always ensure you have the necessary permissions granted to UserLAnd if attempting to run local `adb` commands against your own device.

Happy CLI-ing!
