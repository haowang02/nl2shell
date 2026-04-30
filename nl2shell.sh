#!/bin/bash

set -e

usage() {
  echo "Usage: nl2shell.sh --model MODEL --base-url URL --api-key KEY <natural language description>" >&2
  echo "Example: nl2shell.sh --model qwen3.6-plus --base-url https://coding.dashscope.aliyuncs.com/v1 --api-key sk-... list all files recursively sorted by size" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  -m, --model MODEL       Model name, required" >&2
  echo "  -b, --base-url URL      OpenAI-compatible base URL, required" >&2
  echo "  -k, --api-key KEY       API key, required" >&2
}

MODEL=
BASE_URL=
API_KEY=

ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
  -m | --model)
    if [ $# -lt 2 ]; then
      echo "Error: $1 requires a value" >&2
      usage
      exit 1
    fi
    MODEL=$2
    shift 2
    ;;
  -b | --base-url)
    if [ $# -lt 2 ]; then
      echo "Error: $1 requires a value" >&2
      usage
      exit 1
    fi
    BASE_URL=$2
    shift 2
    ;;
  -k | --api-key)
    if [ $# -lt 2 ]; then
      echo "Error: $1 requires a value" >&2
      usage
      exit 1
    fi
    API_KEY=$2
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    ARGS+=("$@")
    break
    ;;
  *)
    ARGS+=("$1")
    shift
    ;;
  esac
done

if [ ${#ARGS[@]} -eq 0 ]; then
  usage
  exit 1
fi

if [ -z "$API_KEY" ]; then
  echo "Error: --api-key is required" >&2
  exit 1
fi

if [ -z "$MODEL" ]; then
  echo "Error: --model is required" >&2
  exit 1
fi

if [ -z "$BASE_URL" ]; then
  echo "Error: --base-url is required" >&2
  exit 1
fi

BASE_URL=${BASE_URL%/}

for dep in curl jq; do
  if ! command -v "$dep" &>/dev/null; then
    echo "Error: required command '$dep' is not installed" >&2
    exit 1
  fi
done

PROMPT="${ARGS[*]}"

# ── Gather context ──
OS_NAME=$(uname -s)
if [ "$OS_NAME" = "Darwin" ]; then
  OS_VERSION=$(sw_vers -productVersion 2>/dev/null)
else
  OS_VERSION=$(lsb_release -d 2>/dev/null | cut -f2- || uname -r)
fi
SHELL_PATH=${SHELL:-/bin/sh}
SHELL_NAME=$(basename "$SHELL_PATH")
CUR_DATE=$(date "+%Y-%m-%d %H:%M:%S %Z")
USER_NAME=$(whoami)
FILE_LIST=$(ls -la 2>/dev/null | head -n 1000)

GIT_INFO=""
if git rev-parse --is-inside-work-tree &>/dev/null; then
  GIT_INFO="
- Git branch: $(git branch --show-current 2>/dev/null)"
fi

TOOLS=""
for tool in git docker kubectl npm yarn pnpm python3 python pip3 pip brew apt dnf node go rustc cargo make cmake gcc g++ fzf fd rg bat eza jq gh glow delta; do
  command -v "$tool" &>/dev/null && TOOLS="$TOOLS $tool"
done

SYSTEM_PROMPT="You are a command-line assistant. Convert the user's natural language request into a single shell command. Always output exactly one single-line shell command. Do not include line breaks or line-continuation characters. If multiple commands could satisfy the request, choose the simplest and most direct command. Output ONLY the raw shell command. No explanations, no markdown formatting, no code fences. Just the bare executable command.

Environment context:
- OS: $OS_NAME $OS_VERSION
- Shell: $SHELL_NAME
- User: $USER_NAME
- Home: $HOME
- Current directory: $PWD
- Date: $CUR_DATE$GIT_INFO
- Available tools: $TOOLS

Files in current directory (max 1000 lines):
$FILE_LIST"

PAYLOAD=$(jq -n \
  --arg sys "$SYSTEM_PROMPT" \
  --arg user "$PROMPT" \
  --arg model "$MODEL" \
  '{
        messages: [
            {content: $sys, role: "system"},
            {content: $user, role: "user"}
        ],
        model: $model
    }')

# echo $PAYLOAD | jq .

RESPONSE=$(curl -fsS -L -X POST "$BASE_URL/chat/completions" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer $API_KEY" \
  --data-raw "$PAYLOAD")

API_ERROR=$(echo "$RESPONSE" | jq -r '.error.message // empty')
if [ -n "$API_ERROR" ]; then
  echo "API Error: $API_ERROR" >&2
  exit 1
fi

CMD=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')

if [ -z "$CMD" ]; then
  echo "Error: Failed to generate command" >&2
  exit 1
fi

# Strip markdown code fences if present
CMD=$(echo "$CMD" | sed -e '/<think>/,/<\/think>/d' -e '/./,$!d' -e 's/^```[a-z]*[[:space:]]*//' -e 's/[[:space:]]*```$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

printf '%s\n' "$CMD"
