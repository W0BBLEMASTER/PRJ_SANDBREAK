@echo off
setlocal enabledelayedexpansion

:: 1. Force the current temp folder into the PATH so sub-installs can find 'node'
set "BIN_DIR=%~dp0"
set "PATH=%BIN_DIR%;%PATH%"

:: 2. Fix the Node v24 punycode/esm noise
set NODE_OPTIONS=--no-deprecation --no-warnings

:: 3. Define local paths
set "NODE_EXE=%BIN_DIR%node.exe"
set "NPM_CMD=%BIN_DIR%npm.cmd"
set "TARGET=%BIN_DIR%gemini_app"

:: 4. Clean up failed locks from previous runs if they exist
if exist "%TARGET%\node_modules" (
    echo [CLEANUP] Removing stale locks...
    rmdir /s /q "%TARGET%" 2>nul
)

:: 5. THE FIX: Install with PATH awareness
if not exist "%TARGET%\node_modules\@google\gemini-cli" (
    echo [1/2] Force-installing Gemini CLI...
    mkdir "%TARGET%" 2>nul
    
    :: We use --ignore-scripts to skip tree-sitter compilation if possible
    :: or let the PATH injection handle it if it must compile.
    call "%NPM_CMD%" install @google/gemini-cli --prefix "%TARGET%" --no-save --no-audit --no-fund --quiet
)

:: 6. Direct Binary Execution
set "ENTRY=%TARGET%\node_modules\@google\gemini-cli\dist\index.js"

if exist "%ENTRY%" (
    echo [2/2] Launching...
    "%NODE_EXE%" "%ENTRY%" %*
) else (
    echo [FATAL] Install failed to produce index.js.
    echo Check if %BIN_DIR% is read-only.
    pause
)
