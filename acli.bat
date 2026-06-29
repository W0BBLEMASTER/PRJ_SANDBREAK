@echo off
setlocal enabledelayedexpansion

:: Directive 1: Staging Directory Initialization and Scoping
set "SANDBOX_ROOT=%~dp0.acli"
set "AGY_BIN_DIR=%SANDBOX_ROOT%\appdata\agy\bin"
set "AGY_EXE=%AGY_BIN_DIR%\agy.exe"

mkdir "%SANDBOX_ROOT%\home" 2>nul
mkdir "%SANDBOX_ROOT%\appdata" 2>nul

:: Directive 2: Hyper-Aggressive Environment Shadowing
set "LOCALAPPDATA=%SANDBOX_ROOT%\appdata"
set "USERPROFILE=%SANDBOX_ROOT%\home"
set "HOMEDRIVE=%~d0"
set "HOMEPATH=%~p0.acli\home"

:: *Missing Speculation Patch*: Ensure subagents can locate the un-PATH'd binary
set "AGY_BIN_PATH=%AGY_EXE%"
set "PATH=%AGY_BIN_DIR%;%PATH%"

:: Directive 3: Secure Payload Acquisition and Sanitization (Patched with existence check)
if exist "%AGY_EXE%" goto boot_agy

echo [ACLI] Virgin environment detected. Bootstrapping native Antigravity CLI...
echo [ACLI] Fetching dynamic distribution script...
curl.exe -fsSL "https://antigravity.google/cli/install.ps1" -o "%SANDBOX_ROOT%\appdata\install.ps1"

echo [ACLI] Executing payload staging (Bypassing PATH and Aliases)...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SANDBOX_ROOT%\appdata\install.ps1" --skip-path --skip-aliases

echo [ACLI] Purging installation artifacts...
del "%SANDBOX_ROOT%\appdata\install.ps1" 2>nul

:boot_agy
:: Directive 4: TUI Invocation and Parameter Passthrough
if exist "%AGY_EXE%" (
    "%AGY_EXE%" %*
) else (
    echo [ACLI-FATAL] Binary staging failed. Check network or manifest integrity.
)