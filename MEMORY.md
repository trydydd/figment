# MEMORY

## What We Changed

### 1) Added automated USB builder script
- Created `BuildYourOwn.sh` to automate the README build process.
- It can:
  - copy repo files to a mounted USB target
  - create `.system/`
  - download required engine + model files
  - optionally format the drive as exFAT

### 2) Added `formatme` marker behavior
- Script now checks for `TARGET/formatme`.
- If present, formatting runs without an interactive confirmation prompt.
- If `--format-device` is not provided, the script attempts to auto-detect the device from the mount path.

### 3) Added local model reuse
- Before downloading model files, script checks:
  1. `~/Download`
  2. `~/Downloads`
- If models are found locally, they are copied into `.system/` instead of downloading.

### 4) Split engine downloads by platform compatibility
- `BuildYourOwn.sh` now downloads two engine binaries:
  - `.system/llamafile` (Linux engine)
- The current implementation is now Linux-only.

### 5) Improved Linux launcher diagnostics
- Updated `LinuxLaunch.sh` to provide more actionable error output.
- Added a post-failure probe that reveals unsupported model architecture errors (for example, `qwen3`) that were previously hidden by `--log-disable`.
- Launcher now runs `.system/llamafile` directly.

### 6) Added user setup documentation
- Added `USB_SETUP_README.md` with terminal-first instructions for:
  - finding USB mount path/device on Linux
  - running `BuildYourOwn.sh` with correct `--target` syntax
  - optional formatting
  - `formatme` mode
  - common mistakes

### 7) Reduced scope to Linux-only
- Removed `MacLaunch.command` and `WindowsLaunch.bat`.
- Refactored `BuildYourOwn.sh` to download only the Linux engine and to run only on Linux.
- Removed Mac/Windows references from docs and setup instructions.

## Why
- The initial launcher error was too generic and made root-cause diagnosis difficult.
- Runtime testing showed model load failures tied to engine/model architecture compatibility.
- Users needed a repeatable, low-friction terminal workflow to identify their USB and run setup safely.
- Local model reuse reduces repeated multi-GB downloads and setup time.
- Reducing the current implementation to Linux-only cuts platform-specific complexity while the orchestrator architecture is still being defined.
