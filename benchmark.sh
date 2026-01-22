#!/bin/bash

# Llama.cpp Performance Benchmark Script for Strix Halo
# This script tests different configurations and measures performance

set -e

# Source .env file if it exists
if [ -f "$(dirname "$0")/.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.env"
fi

BASE_URL="${LLAMA_SERVER_URL:-http://localhost:8000}"
API_URL="${BASE_URL}/v1/chat/completions"
MODEL="${LLAMA_MODEL:-/models/GLM-4.7-Flash-UD-Q8_K_XL.gguf}"
API_KEY="${LLAMA_ARG_API_KEY:-}"

echo "=========================================="
echo "Llama.cpp Performance Benchmark"
echo "=========================================="
echo "Server: $BASE_URL"
echo "Model: $MODEL"
echo ""

# Test 1: Token generation speed (single request)
echo "Test 1: Single Request Speed"
echo "-------------------------------------------"
START=$(date +%s.%N)
CURL_OPTS="-sS -H \"Content-Type: application/json\""
if [ -n "$API_KEY" ]; then
  CURL_OPTS="$CURL_OPTS -H \"Authorization: Bearer $API_KEY\""
fi
RESPONSE=$(eval curl $CURL_OPTS \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Count to 100\"}],\"max_tokens\":200}" \
  "$API_URL")
END=$(date +%s.%N)
ELAPSED=$(awk "BEGIN {printf \"%.2f\", $END - $START}")
echo "Time: ${ELAPSED}s"

# Show detailed timing if available
PROMPT_MS=$(echo "$RESPONSE" | jq -r '.timings.prompt_ms // 0')
PRED_MS=$(echo "$RESPONSE" | jq -r '.timings.predicted_ms // 0')
if [ "$PRED_MS" != "null" ] && [ "$PRED_MS" != "0" ]; then
  TOKENS=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens // 0')
  TOKENS_PER_SEC=$(awk "BEGIN {printf \"%.2f\", ($TOKENS / ($PRED_MS / 1000))}")
  echo "Generation: ${TOKENS_PER_SEC} tokens/s"
fi

# Test 2: Long context processing
echo ""
echo "Test 2: Long Context Processing (1K tokens)"
echo "-------------------------------------------"
START=$(date +%s.%N)
LONG_PROMPT="Explain quantum computing. "$(
  for i in {1..100}; do
    echo -n "This is filler text to increase context size. "
  done
)
eval curl $CURL_OPTS \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"${LONG_PROMPT}\"}],\"max_tokens\":500}" \
  "$API_URL" | jq -r '.choices[0].message.content' > /dev/null
END=$(date +%s.%N)
ELAPSED=$(awk "BEGIN {printf \"%.2f\", $END - $START}")
echo "Time: ${ELAPSED}s"

# Test 3: Concurrent requests
echo ""
echo "Test 3: Concurrent Requests (4 parallel)"
echo "-------------------------------------------"
START=$(date +%s.%N)
for i in {1..4}; do
  eval curl $CURL_OPTS \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello ${i}\"}],\"max_tokens\":50}" \
    "$API_URL" &
done
wait
END=$(date +%s.%N)
ELAPSED=$(awk "BEGIN {printf \"%.2f\", $END - $START}")
echo "Total Time: ${ELAPSED}s"

# Test 4: Multiple rapid requests (single-threaded)
echo ""
echo "Test 4: Sequential Requests (5 requests)"
echo "-------------------------------------------"
START=$(date +%s.%N)
for i in {1..5}; do
  eval curl $CURL_OPTS \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Generate a poem\"}],\"max_tokens\":100}" \
    "$API_URL" | jq -r '.choices[0].message.content' > /dev/null
done
END=$(date +%s.%N)
ELAPSED=$(awk "BEGIN {printf \"%.2f\", $END - $START}")
echo "Total Time: ${ELAPSED}s"
AVG=$(awk "BEGIN {printf \"%.2f\", $ELAPSED / 5}")
echo "Average per request: ${AVG}s"

echo ""
echo "=========================================="
echo "Benchmark Complete"
echo "=========================================="
echo ""
echo "To apply performance tuning:"
echo "1. Edit performance.env for your use case"
echo "2. Restart docker compose: docker compose restart"
echo ""
echo "To monitor performance in real-time:"
echo "1. Check logs: docker compose logs -f"
echo "2. Monitor GPU: watch -n 1 'rocm-smi'"