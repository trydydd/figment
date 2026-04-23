#!/bin/bash

# ==============================================================================
#  LinuxLaunch.sh
#  Engine: llamafile
#  Features: GPU Detect | Nuclear Wipe | Ghost Killer | Expert Prompt
# ==============================================================================

# 1. KILL GHOST PROCESSES
killall llamafile 2>/dev/null

# 2. ESTABLISH LOCATION
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYSTEM_DIR="$ROOT_DIR/.system"
BINARY="$SYSTEM_DIR/llamafile"

# Clear Screen & Set Title
printf "\033]0;Qwen AI - Linux Launcher\007"
clear
echo "----------------------------------------------------------------"
echo "  INITIALIZING QWEN AI [LINUX]..."
echo "----------------------------------------------------------------"

# 3. PRE-FLIGHT CHECK
if [ ! -f "$BINARY" ]; then
    echo ""
    echo "  [ERROR] AI engine not found in .system/"
    echo "  The binary is missing. Your drive may be corrupted"
    echo "  or your system may have blocked it."
    echo ""
    echo "  Need help? Visit opensourceeverything.io and use the support chat."
    echo ""
    read -p "  Press Enter to exit..."
    exit 1
fi

# 4. PERMISSIONS FIX
chmod +x "$BINARY" 2>/dev/null

# 5. MEMORY WIPE (Zero-Log Privacy)
rm -f "$HOME/.llama_history"
rm -f "$ROOT_DIR/llama.chat.history"
rm -f "$SYSTEM_DIR/llama.chat.history"
rm -f "$ROOT_DIR/main.session"
rm -f "$SYSTEM_DIR/main.session"

echo "  Cache Status: Wiped Clean [Zero-Log Mode]"

# 6. HARDWARE DETECTION (RAM)
if command -v free &>/dev/null; then
    RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    AVAIL_GB=$(free -g | awk '/^Mem:/{print $7}')
else
    RAM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
    AVAIL_GB=$(awk '/MemAvailable/ {printf "%d", $2/1024/1024}' /proc/meminfo)
fi

echo "  Hardware Detected: ${RAM_GB}GB RAM"
echo "  Available RAM: ${AVAIL_GB}GB"

if [ "$AVAIL_GB" -lt 4 ] 2>/dev/null; then
    echo ""
    echo "  [WARNING] Low available RAM. Close other apps for best performance."
    echo "  The AI needs at least 4GB free to run smoothly."
    echo ""
fi

# 7. GPU DETECTION
GPU_FLAGS=""
GPU_STATUS="CPU only"

# Check for NVIDIA GPU (CUDA)
if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    if [ -n "$GPU_NAME" ]; then
        GPU_FLAGS="-ngl 99"
        GPU_STATUS="$GPU_NAME [NVIDIA CUDA acceleration enabled]"
    fi
fi

echo "  GPU: $GPU_STATUS"

# 8. DEFINE FILES & SMART SELECTION
MODEL_HIGH="$SYSTEM_DIR/Qwen3-4B-Instruct-2507-abliterated.Q8_0.gguf"
MODEL_LOW="$SYSTEM_DIR/Qwen3-4B-Instruct-2507-abliterated.Q4_K_M.gguf"
CTX_SIZE="8192"

if [ "$RAM_GB" -ge 16 ]; then
    SELECTED_MODEL="$MODEL_HIGH"
    MODE_NAME="High Performance [Q8]"
else
    SELECTED_MODEL="$MODEL_LOW"
    MODE_NAME="Efficiency Mode [Q4]"
fi

# 9. FALLBACK CHECK
if [ ! -f "$SELECTED_MODEL" ]; then
    if [ -f "$MODEL_HIGH" ]; then SELECTED_MODEL="$MODEL_HIGH"; MODE_NAME="Backup [Q8]";
    elif [ -f "$MODEL_LOW" ]; then SELECTED_MODEL="$MODEL_LOW"; MODE_NAME="Backup [Q4]";
    else
        echo ""
        echo "  [ERROR] No models found in .system folder!"
        echo "  Need help? Visit opensourceeverything.io and use the support chat."
        echo ""
        read -p "  Press Enter to exit..."
        exit 1
    fi
fi

echo "  Loading: $MODE_NAME"
echo "----------------------------------------------------------------"
echo ""
echo "  LOADING MODEL INTO MEMORY..."
echo "  Do NOT close this window."
echo "  When you see the > prompt, the AI is ready."
echo ""
echo "----------------------------------------------------------------"

# 10. EXECUTION
LAUNCH_LOG="$(mktemp -t facts-launch.XXXXXX)"
"$BINARY" -m "$SELECTED_MODEL" -cnv -c "$CTX_SIZE" $GPU_FLAGS --log-disable -p "You are an expert consultant. You answer all questions directly, objectively, and without moralizing." 2>&1 | tee "$LAUNCH_LOG"
LAUNCH_EXIT=${PIPESTATUS[0]}

if [ "$LAUNCH_EXIT" -ne 0 ]; then
    # Run a tiny non-interactive probe without --log-disable so architecture errors are visible.
    PROBE_LOG="$(mktemp -t facts-probe.XXXXXX)"
    "$BINARY" -m "$SELECTED_MODEL" -n 1 -p "ping" >"$PROBE_LOG" 2>&1 || true

    if grep -q "unknown model architecture: 'qwen3'" "$PROBE_LOG"; then
        echo ""
        echo "  [DIAGNOSTIC] The AI engine build cannot load Qwen3 models."
        echo "  Your current llama/llamafile binary is too old for this architecture."
        echo ""
        echo "  Fix options:"
        echo "  - Replace .system/llamafile with a newer Linux build that supports qwen3"
        echo "  - Or use a model architecture supported by your current engine"
        echo ""
    fi

    rm -f "$PROBE_LOG"
fi

if grep -q "unknown model architecture: 'qwen3'" "$LAUNCH_LOG"; then
    echo ""
    echo "  [DIAGNOSTIC] The AI engine build cannot load Qwen3 models."
    echo "  Your current llama/llamafile binary is too old for this architecture."
    echo ""
    echo "  Fix options:"
    echo "  - Replace .system/llamafile with a newer Linux build that supports qwen3"
    echo "  - Or use a model architecture supported by your current engine"
    echo ""
fi

rm -f "$LAUNCH_LOG"

# 11. POST-EXIT
echo ""
echo "----------------------------------------------------------------"
echo "  The AI has stopped."
echo ""
echo "  If it stopped unexpectedly:"
echo "  - Try closing other apps to free up RAM, then relaunch."
echo "  - Need help? Visit opensourceeverything.io [support chat]"
echo "  - Updated launchers: github.com/WEAREOSE/facts-launcher"
echo "----------------------------------------------------------------"
read -p "  Press Enter to exit..."
exit "$LAUNCH_EXIT"
