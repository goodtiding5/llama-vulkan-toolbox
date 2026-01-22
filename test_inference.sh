#!/bin/bash

set -e

BASE_URL="${LLAMA_SERVER_URL:-http://localhost:8000}"
API_URL="${BASE_URL}/v1/chat/completions"
MODEL="${LLAMA_MODEL:-GLM-4.7-Flash-UD-Q4_K_XL}"
PROMPT="${1:-${PROMPT}}"
MAX_TOKENS="${MAX_TOKENS:-2048}"
TEMPERATURE="${TEMPERATURE:-0.7}"
STREAM="${STREAM:-false}"
VERBOSE=false

print_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [PROMPT]

Send a prompt to the llama-server API and get a completion.

OPTIONS:
    -u URL          API base URL (default: http://localhost:8000)
    -m MODEL        Model to use (default: GLM-4.7-Flash-UD-Q4_K_XL)
    -t TOKENS       Max tokens in response (default: 2048)
    -T TEMP         Temperature 0.0-2.0 (default: 0.7)
    -s              Enable streaming output
    -v              Verbose output
    -h              Show this help message

ARGUMENTS:
    PROMPT          The prompt to send (can also be set via PROMPT env var)

ENVIRONMENT:
    LLAMA_ARG_API_KEY   API key for authentication (optional)
    LLAMA_SERVER_URL    Base server URL
    LLAMA_MODEL         Default model to use
    PROMPT              Default prompt text
    MAX_TOKENS          Default max tokens
    TEMPERATURE         Default temperature

EXAMPLES:
    $(basename "$0") "Hello, how are you?"
    $(basename "$0") -m Qwen3-Coder -s "Write a Python function"
    PROMPT="Explain quantum physics" $(basename "$0")
EOF
}

check_server_reachable() {
    if ! curl -sS --max-time 5 --connect-timeout 3 -f "${BASE_URL}/health" >/dev/null 2>&1; then
        echo "Error: Server at ${BASE_URL} is not reachable or health check failed" >&2
        return 1
    fi
    return 0
}

send_completion() {
    local prompt="$1"
    local curl_args=(--max-time 60 -H "Content-Type: application/json")
    local stream_arg=false

    if [ "$STREAM" = "true" ]; then
        stream_arg=true
    fi

    if [ -n "$LLAMA_ARG_API_KEY" ]; then
        curl_args+=(-H "Authorization: Bearer $LLAMA_ARG_API_KEY")
    fi

    local json_data=$(cat << EOF
{
  "model": "$MODEL",
  "messages": [
    {"role": "user", "content": $(echo "$prompt" | jq -Rs .)}
  ],
  "max_tokens": $MAX_TOKENS,
  "temperature": $TEMPERATURE,
  "stream": $stream_arg
}
EOF
)

    [ "$VERBOSE" = true ] && echo "Sending request to $API_URL" >&2
    [ "$VERBOSE" = true ] && echo "JSON data: $json_data" >&2

    curl -sS "${curl_args[@]}" -d "$json_data" "$API_URL"
}

extract_response() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: 'jq' is required to parse response" >&2
        exit 2
    fi

    local response="$1"

    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        echo "Error from API:" >&2
        echo "$response" | jq -r '.error.message' >&2
        exit 3
    fi

    echo "$response" | jq -r '.choices[0].message.reasoning_content // .choices[0].message.content // .choices[0].text // .content // empty'
}

while getopts "u:m:t:T:svh" opt; do
    case $opt in
        u) BASE_URL="${OPTARG%/}"; API_URL="${BASE_URL}/v1/chat/completions" ;;
        m) MODEL="$OPTARG" ;;
        t) MAX_TOKENS="$OPTARG" ;;
        T) TEMPERATURE="$OPTARG" ;;
        s) STREAM=true ;;
        v) VERBOSE=true ;;
        h) print_help; exit 0 ;;
        *) print_help; exit 1 ;;
    esac
done

shift $((OPTIND - 1))

if [ -n "$1" ]; then
    PROMPT="$1"
fi

if [ -z "$PROMPT" ]; then
    echo "Error: No prompt provided" >&2
    print_help
    exit 1
fi

if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

if [ -z "$LLAMA_ARG_API_KEY" ]; then
    if [ "$VERBOSE" = true ]; then
        echo "Warning: LLAMA_ARG_API_KEY not set, proceeding without authentication" >&2
    fi
    unset LLAMA_ARG_API_KEY
fi

if [ "$VERBOSE" = true ]; then
    check_server_reachable || exit 1
fi

if [ "$STREAM" = "true" ]; then
    curl_args=(--max-time 60 -H "Content-Type: application/json" -N)
    if [ -n "$LLAMA_ARG_API_KEY" ]; then
        curl_args+=(-H "Authorization: Bearer $LLAMA_ARG_API_KEY")
    fi

    json_data=$(cat << EOF
{
  "model": "$MODEL",
  "messages": [
    {"role": "user", "content": $(echo "$PROMPT" | jq -Rs .)}
  ],
  "max_tokens": $MAX_TOKENS,
  "temperature": $TEMPERATURE,
  "stream": true
}
EOF
)

    [ "$VERBOSE" = true ] && echo "Streaming response from $MODEL..." >&2
    curl -sS "${curl_args[@]}" -d "$json_data" "$API_URL" | while read -r line; do
        if echo "$line" | jq -e '.choices[0].delta.content' >/dev/null 2>&1 2>/dev/null; then
            echo "$line" | jq -r '.choices[0].delta.content' | tr -d '\n'
            echo -n ""
        fi
    done
    echo
else
    response=$(send_completion "$PROMPT")
    content=$(extract_response "$response")

    if [ -n "$content" ]; then
        echo "$content"
    else
        echo "Error: No content in response" >&2
        [ "$VERBOSE" = true ] && echo "Raw response: $response" >&2
        exit 4
    fi
fi