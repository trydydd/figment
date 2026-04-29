#!/usr/bin/env bash
# Start Qwen3-Coder-Next-NVFP4 via vLLM (OpenAI-compatible API on port 8000).
#
# Requirements:
#   - Blackwell GPU (GB10, H100B, H200B — compute capability 10.0+)
#   - NVIDIA Container Toolkit installed on the host
#   - ~80 GB GPU/unified memory for weights + FP8 KV cache at 128K context
#
# Environment overrides:
#   HF_TOKEN            HuggingFace token (only needed if model is gated)
#   TENSOR_PARALLEL     number of GPUs to shard across  (default: 2)
#   MAX_MODEL_LEN       maximum context length in tokens (default: 131072)
#
# To use full 256K context (needs ~112 GB):
#   MAX_MODEL_LEN=262144 ./run_vllm.sh

MODEL="RedHatAI/Qwen3-Coder-Next-NVFP4"
TENSOR_PARALLEL="${TENSOR_PARALLEL:-2}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-131072}"

docker run --gpus all \
    --ipc=host \
    -p 8000:8000 \
    -v ~/.cache/huggingface:/root/.cache/huggingface \
    ${HF_TOKEN:+-e HF_TOKEN="$HF_TOKEN"} \
    vllm/vllm-openai:v0.20.0 \
    --model                "$MODEL" \
    --tensor-parallel-size "$TENSOR_PARALLEL" \
    --max-model-len        "$MAX_MODEL_LEN" \
    --kv-cache-dtype       fp8 \
    --enable-auto-tool-choice \
    --tool-call-parser     qwen3_coder
