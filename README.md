# SANDBREAK: Your Personal Android CLI Powerhouse 🚀

Tired of Android's file system restrictions? Bored and want to turn your UserLAnd environment into a dedicated terminal for ADB operations and deep Android file system access? SANDBREAK is a personal project designed to transform your UserLAnd setup into a lean, mean, CLI machine.

## ✨ What is SANDBREAK?

SANDBREAK is a two-stage setup process for the UserLAnd app on Android. It aims to:

1.  **Create a robust Linux sandbox** on your Android device.
2.  **Install ADB** directly within that sandbox, allowing you to run ADB commands against your own device from within UserLAnd.
3.  **Configure your shell** to make GeminiCLI the primary, and effectively *only*, application that launches when you open your UserLAnd session.
4.  **Unlock access** to those hard-to-reach Android directories like `/OBB` and `/DATA`.

It's your personal command-line gateway to your Android device, built out of curiosity and a desire to bypass limitations.

## 🛠️ Prerequisites

*   An Android device.
*   The **UserLAnd** app installed from the Google Play Store.
*   Sufficient storage space and necessary app permissions granted to UserLAnd.

## 🚀 Setup: Two Stages to CLI Mastery

Follow these steps in order within your UserLAnd Linux distribution's terminal:

### Stage 1: Sandbox & ADB Setup (`SANDBREAK1.SH`)

This script prepares your UserLAnd environment, updates packages, installs Node.js (for GeminiCLI), installs GeminiCLI itself, and sets up ADB for on-device access.

Execute the script:
```bash
sh Sources/SANDBREAK/SANDBREAK1.SH
```

### Stage 2: GeminiCLI Focus (`SANDBREAK2.SH`)

This script configures your shell profile to ensure that GeminiCLI is the main application that launches upon starting your UserLAnd session.

Execute the second script:
```bash
sh Sources/SANDBREAK/SANDBREAK2.SH
```

## 💡 Usage

Once both stages are complete, when you launch your UserLAnd session, you should be greeted by the GeminiCLI interface. From here, you can:

*   Run standard Linux commands.
*   Execute ADB commands against your device (e.g., `adb devices`, `adb pull /sdcard/Android/obb/some_game/main.obb .`).
*   Access and manage files in restricted directories like `/sdcard/Android/obb/` or `/sdcard/Android/data/`.

## ⚠️ Notes & Caveats

*   This is a personal project born out of boredom. It's functional but might have quirks.
*   `SANDBREAK2.SH` is designed to make GeminiCLI the *only* bootable app. Exiting GeminiCLI might effectively close your UserLAnd session or require re-launching it.
*   Compatibility may vary depending on your Android version, device manufacturer, and UserLAnd version.
*   Always ensure you have the necessary permissions granted to UserLAnd.

Happy CLI-ing!
