#!/bin/bash

set -e

BASE_URL="${LLAMA_SERVER_URL:-http://localhost:8000}"
API_URL="${BASE_URL}/v1/models"
MAX_RETRIES=3
RETRY_DELAY=2
TIMEOUT=10
FORMAT="${FORMAT:-table}"
FILTER=""
SORT=""
VERBOSE=false

print_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

List available models from the llama-server API.

OPTIONS:
    -u URL           API base URL (default: http://localhost:8000)
    -f FORMAT        Output format: table, json, simple (default: table)
    -F FILTER        Filter models by name (substring match)
    -s SORT          Sort by: name, id, size (default: no sorting)
    -r NUM           Max retries (default: 3)
    -t SECONDS       Request timeout in seconds (default: 10)
    -v               Verbose output
    -h               Show this help message

ENVIRONMENT:
    LLAMA_ARG_API_KEY    API key for authentication (not required by default server)
    LLAMA_SERVER_URL     Base server URL (default: http://localhost:8000)

EXAMPLES:
    $(basename "$0")                          # List models in table format
    $(basename "$0") -F llama                 # Filter models containing "llama"
    $(basename "$0") -f simple -s name        # Simple list sorted by name
    $(basename "$0") -f json                  # Output raw JSON
EOF
}

check_server_reachable() {
    local base_url="${API_URL%/v1/models}"
    if ! curl -sS --max-time "$TIMEOUT" --connect-timeout 3 -f "${base_url}/health" >/dev/null 2>&1; then
        echo "Error: Server at ${base_url} is not reachable or health check failed" >&2
        return 1
    fi
    return 0
}

fetch_models() {
    local attempt=1
    local response
    local curl_args=(--max-time "$TIMEOUT" -H "Accept: application/json")

    if [ -n "$LLAMA_ARG_API_KEY" ]; then
        curl_args+=(-H "Authorization: Bearer $LLAMA_ARG_API_KEY")
    fi

    while [ $attempt -le $MAX_RETRIES ]; do
        [ "$VERBOSE" = true ] && echo "Attempt $attempt/$MAX_RETRIES: Fetching models from $API_URL" >&2

        response=$(curl -sS "${curl_args[@]}" "$API_URL" 2>&1) || {
            if [ $attempt -lt $MAX_RETRIES ]; then
                echo "Warning: Request failed, retrying in ${RETRY_DELAY}s..." >&2
                sleep $RETRY_DELAY
                ((attempt++))
                continue
            else
                echo "Error: Failed to connect to API after $MAX_RETRIES attempts" >&2
                exit 2
            fi
        }

        if command -v jq >/dev/null 2>&1; then
            if ! echo "$response" | jq . >/dev/null 2>&1; then
                if [ $attempt -lt $MAX_RETRIES ]; then
                    echo "Warning: Invalid JSON received, retrying in ${RETRY_DELAY}s..." >&2
                    sleep $RETRY_DELAY
                    ((attempt++))
                    continue
                else
                    echo "Error: Server returned invalid JSON response" >&2
                    echo "Raw response: $response" >&2
                    exit 3
                fi
            fi
        fi

        echo "$response"
        return 0
    done
}

format_table() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: 'jq' is required for table format" >&2
        exit 4
    fi

    echo "$1" | jq -r '.data[] | [.id, (.object // ""), (.owned_by // "N/A"), (.created // "N/A"), (.status.value // "N/A")] | @tsv' | \
    awk -F'\t' 'BEGIN {
        print "ID\t\t\t\t\t\tObject\t\tOwned_By\t\t\tCreated\t\tStatus"
        print "=========================================================================================================================="
    } {
        id = $1
        obj = $2
        owner = substr($3, 1, 20)
        created = strftime("%Y-%m-%d %H:%M:%S", $4)
        status = $5
        printf "%-36s %-12s %-18s %-19s %s\n", id, obj, owner, created, status
    }'
}

format_simple() {
    if command -v jq >/dev/null 2>&1; then
        echo "$1" | jq -r '.data[].id'
    else
        echo "$1"
    fi
}

apply_filter() {
    if [ -n "$FILTER" ]; then
        if command -v jq >/dev/null 2>&1; then
            echo "$1" | jq --arg filter "$FILTER" '.data |= map(select(.id | ascii_downcase | contains($filter | ascii_downcase)))'
        else
            echo "$1"
        fi
    else
        echo "$1"
    fi
}

apply_sort() {
    if [ -n "$SORT" ] && command -v jq >/dev/null 2>&1; then
        echo "$1" | jq --arg sort "$SORT" '.data |= sort_by(.[$sort])'
    else
        echo "$1"
    fi
}

while getopts "u:f:F:s:r:t:vh" opt; do
    case $opt in
        u) BASE_URL="${OPTARG%/}"; API_URL="${BASE_URL}/v1/models" ;;
        f) FORMAT="$OPTARG" ;;
        F) FILTER="$OPTARG" ;;
        s) SORT="$OPTARG" ;;
        r) MAX_RETRIES="$OPTARG" ;;
        t) TIMEOUT="$OPTARG" ;;
        v) VERBOSE=true ;;
        h) print_help; exit 0 ;;
        *) print_help; exit 1 ;;
    esac
done

if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

if [ -z "$LLAMA_ARG_API_KEY" ]; then
    if [ "$VERBOSE" = true ]; then
        echo "Warning: LLAMA_ARG_API_KEY not set, attempting without authentication" >&2
    fi
    unset LLAMA_ARG_API_KEY
fi

if [ "$VERBOSE" = true ]; then
    check_server_reachable || exit 1
fi

response=$(fetch_models)
response=$(apply_filter "$response")
response=$(apply_sort "$response")

case "$FORMAT" in
    table)  format_table "$response" ;;
    simple) format_simple "$response" ;;
    json)   echo "$response" ;;
    *)      echo "Error: Invalid format '$FORMAT'. Use 'table', 'json', or 'simple'" >&2
            exit 1 ;;
esac
