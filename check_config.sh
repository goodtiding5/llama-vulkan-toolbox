#!/bin/bash

# Llama.cpp Performance Tuning Check Script
# Validates if optimizations are actually applied

set -e

echo "=========================================="
echo "Llama.cpp Configuration Check"
echo "=========================================="

# Check if server is running
echo ""
echo "1. Checking server health..."
if curl -sS -f http://localhost:8000/health >/dev/null 2>&1; then
    echo "✓ Server is running"
else
    echo "✗ Server is not responding"
    exit 1
fi

# Check GPU offloading
echo ""
echo "2. Checking GPU offloading status..."
GPU_LAYERS=$(docker compose exec server env | grep LLAMA_ARG_N_GPU_LAYERS | cut -d= -f2)
echo "   N_GPU_LAYERS: $GPU_LAYERS"
if [ "$GPU_LAYERS" = "-1" ] || [ "$GPU_LAYERS" = "99" ]; then
    echo "   ✓ GPU offloading enabled"
else
    echo "   ✗ GPU offloading may not be optimal"
fi

# Check flash attention
echo ""
echo "3. Checking Flash Attention..."
FLASH_ATTN=$(docker compose exec server env | grep LLAMA_ARG_FLASH_ATTN | cut -d= -f2)
echo "   FLASH_ATTN: $FLASH_ATTN"
if [ "$FLASH_ATTN" = "on" ] || [ "$FLASH_ATTN" = "true" ] || [ "$FLASH_ATTN" = "1" ]; then
    echo "   ✓ Flash Attention enabled"
else
    echo "   ✗ Flash Attention NOT enabled (major speed impact)"
fi

# Check thread settings
echo ""
echo "4. Checking CPU thread settings..."
THREADS=$(docker compose exec server env | grep LLAMA_ARG_THREADS | cut -d= -f2)
THREADS_BATCH=$(docker compose exec server env | grep LLAMA_ARG_THREADS_BATCH | cut -d= -f2)
echo "   THREADS: $THREADS"
echo "   THREADS_BATCH: $THREADS_BATCH"
if [ "$THREADS_BATCH" -ge 24 ]; then
    echo "   ✓ Sufficient threads for batch processing"
else
    echo "   ⚠ Thread count might be low for Strix Halo"
fi

# Check context size
echo ""
echo "5. Checking context size..."
CTX_SIZE=$(docker compose exec server env | grep LLAMA_ARG_CTX_SIZE | cut -d= -f2)
echo "   CTX_SIZE: $CTX_SIZE tokens"
if [ "$CTX_SIZE" -ge 32768 ]; then
    echo "   ✓ Good context size"
fi

# Check batch settings
echo ""
echo "6. Checking batch settings..."
BATCH_SIZE=$(docker compose exec server env | grep LLAMA_ARG_BATCH_SIZE | cut -d= -f2)
UBATCH_SIZE=$(docker compose exec server env | grep LLAMA_ARG_UBATCH_SIZE | cut -d= -f2)
echo "   BATCH_SIZE: $BATCH_SIZE"
echo "   UBATCH_SIZE: $UBATCH_SIZE"
if [ "$UBATCH_SIZE" -lt "$BATCH_SIZE" ]; then
    echo "   ✓ Ubatch size is smaller than batch size (correct)"
else
    echo "   ⚠ Ubatch size should be smaller than batch size"
fi

# Check KV cache
echo ""
echo "7. Checking KV cache settings..."
CACHE_RAM=$(docker compose exec server env | grep LLAMA_ARG_CACHE_RAM | cut -d= -f2)
CACHE_TYPE_K=$(docker compose exec server env | grep LLAMA_ARG_CACHE_TYPE_K | cut -d= -f2)
echo "   CACHE_RAM: $CACHE_RAM MiB"
echo "   CACHE_TYPE_K: $CACHE_TYPE_K"
if [ "$CACHE_RAM" = "-1" ]; then
    echo "   ✓ Unlimited KV cache (uses all VRAM)"
fi

# Check continuous batching
echo ""
echo "8. Checking continuous batching..."
CONT_BATCHING=$(docker compose exec server env | grep LLAMA_ARG_CONT_BATCHING | cut -d= -f2)
echo "   CONT_BATCHING: $CONT_BATCHING"
if [ "$CONT_BATCHING" = "on" ] || [ "$CONT_BATCHING" = "true" ]; then
    echo "   ✓ Continuous batching enabled"
else
    echo "   ⚠ Continuous batching not enabled"
fi

# Test actual token speed
echo ""
echo "9. Measuring actual token generation speed..."
START_TIME=$(date +%s)
RESPONSE=$(curl -sS -H "Content-Type: application/json" \
  -d '{"model":"Qwen3-Coder-30B-A3B-Instruct-UD-Q8_K_XL","messages":[{"role":"user","content":"Generate 100 words"}],"max_tokens":100}' \
  http://localhost:8000/v1/chat/completions)
END_TIME=$(date +%s)

PROMPT_MS=$(echo "$RESPONSE" | jq -r '.timings.prompt_ms // 0')
PREDICTED_MS=$(echo "$RESPONSE" | jq -r '.timings.predicted_ms // 0')
PROMPT_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.prompt_tokens // 0')
COMPLETION_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens // 0')
TOTAL_MS=$(( (${ELAPSED:-0} * 1000) + PROMPT_MS + PREDICTED_MS ))

echo "   Prompt time: ${PROMPT_MS}ms (${PROMPT_TOKENS} tokens)"
echo "   Generation time: ${PREDICTED_MS}ms (${COMPLETION_TOKENS} tokens)"

if [ "$COMPLETION_TOKENS" != "null" ] && [ "$COMPLETION_TOKENS" != "0" ] && [ "$PREDICTED_MS" != "null" ] && [ "$PREDICTED_MS" != "0" ]; then
    TOKENS_PER_SEC=$(awk "BEGIN {printf \"%.2f\", ($COMPLETION_TOKENS / ($PREDICTED_MS / 1000))}")
    echo "   Generation speed: ${TOKENS_PER_SEC} tokens/s"

    SLOW=$(awk "BEGIN {print ($TOKENS_PER_SEC < 20)}")
    MODERATE=$(awk "BEGIN {print ($TOKENS_PER_SEC < 40)}")

    if [ "$SLOW" = "1" ]; then
        echo "   ⚠ Slow: < 20 tokens/s"
        echo "   → Recommend: Check GPU offloading, flash attention, or use Q4 quant model"
    elif [ "$MODERATE" = "1" ]; then
        echo "   ⚠ Moderate: 20-40 tokens/s"
        echo "   → Can be improved with Q4 model or tuning"
    else
        echo "   ✓ Good: > 40 tokens/s"
    fi
fi

echo ""
echo "=========================================="
echo "Recommendations"
echo "=========================================="

# Model recommendations
echo ""
echo "Model Quantization:"
echo "  Current: Q8_K_XL (slower, higher quality)"
echo "  Recommended: Q4_K_XL (2-3x faster, minimal quality loss)"
echo ""
echo "To switch to Q4 model, update the model path in .env or docker-compose.yml:"
echo '  LLAMA_ARG_MODEL=/models/Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf'

# GPU recommendations
echo ""
echo "GPU Optimization:"
if [ "$FLASH_ATTN" != "on" ]; then
    echo "  ⚠ Flash Attention is NOT enabled!"
    echo "  This is a major performance bottleneck."
    echo "  Ensure: LLAMA_ARG_FLASH_ATTN=on in docker-compose.yml"
fi

echo ""
echo "To apply changes:"
echo "  1. Edit docker-compose.yml or performance.env"
echo "  2. docker compose restart"
echo "  3. Run this check again: ./check_config.sh"
echo "  4. Re-run benchmark: ./benchmark.sh"