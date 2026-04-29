#!/usr/bin/env bash

set -euo pipefail

if ! command -v zsh >/dev/null 2>&1; then
  echo "Error: zsh is required but was not found. This installer currently only supports installing the ai function for zsh." >&2
  echo "" >&2
  echo "Install zsh:" >&2
  echo "  macOS:  brew install zsh" >&2
  echo "  Ubuntu: sudo apt update && sudo apt install -y zsh" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but was not found." >&2
  echo "" >&2
  echo "Install jq:" >&2
  echo "  macOS:  brew install jq" >&2
  echo "  Ubuntu: sudo apt update && sudo apt install -y jq" >&2
  exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
NL2SHELL_SCRIPT="$SCRIPT_DIR/nl2shell.sh"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
START_MARKER="# >>> nl2shell zsh function >>>"
END_MARKER="# <<< nl2shell zsh function <<<"
DEFAULT_BASE_URL="https://api.deepseek.com"
DEFAULT_MODEL="deepseek-v4-flash"
DEFAULT_KEY_ENV="DEEPSEEK_API_KEY"

if [[ ! -f "$NL2SHELL_SCRIPT" ]]; then
  echo "Error: nl2shell.sh was not found next to this installer: $NL2SHELL_SCRIPT" >&2
  exit 1
fi

quote_shell() {
  printf "'%s'" "${1//\'/\'\\\'\'}"
}

read_with_default() {
  local var_name=$1
  local prompt=$2
  local default_value=$3
  local value

  read -r -p "$prompt [$default_value]: " value
  if [[ -z "$value" ]]; then
    value=$default_value
  fi
  printf -v "$var_name" '%s' "$value"
}

read_with_default BASE_URL "OpenAI-compatible base URL" "$DEFAULT_BASE_URL"
read_with_default MODEL "Model" "$DEFAULT_MODEL"

while true; do
  read -r -p "Use an API key environment variable? [Y/n]: " USE_KEY_ENV
  USE_KEY_ENV=${USE_KEY_ENV,,}
  if [[ -z "$USE_KEY_ENV" || "$USE_KEY_ENV" == "y" || "$USE_KEY_ENV" == "yes" || "$USE_KEY_ENV" == "n" || "$USE_KEY_ENV" == "no" ]]; then
    break
  fi
  echo "Please answer y or n." >&2
done

if [[ -z "$USE_KEY_ENV" || "$USE_KEY_ENV" == "y" || "$USE_KEY_ENV" == "yes" ]]; then
  while true; do
    read_with_default KEY_ENV "API key environment variable name" "$DEFAULT_KEY_ENV"
    if [[ "$KEY_ENV" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      break
    fi
    echo "Invalid environment variable name. Example: DEEPSEEK_API_KEY" >&2
  done

  API_KEY_SETUP="  api_key=\"\${${KEY_ENV}:-}\"
  if [[ -z \"\$api_key\" ]]; then
    print -u2 -- 'Error: environment variable ${KEY_ENV} is not set'
    return 1
  fi"
else
  while true; do
    read -r -s -p "API key: " API_KEY
    printf '\n'
    if [[ -n "$API_KEY" ]]; then
      break
    fi
    echo "API key cannot be empty." >&2
  done

  API_KEY_SETUP="  api_key=$(quote_shell "$API_KEY")"
fi

QUOTED_SCRIPT=$(quote_shell "$NL2SHELL_SCRIPT")
QUOTED_MODEL=$(quote_shell "$MODEL")
QUOTED_BASE_URL=$(quote_shell "$BASE_URL")

BLOCK="${START_MARKER}
ai () {
  local cmd start end elapsed api_key

  if (( \$# == 0 )); then
    print -r -- 'Usage: ai <natural language description>'
    print -r -- 'Example: ai list all files recursively sorted by size'
    return 1
  fi

  zmodload zsh/datetime 2>/dev/null || true
  start=\$EPOCHREALTIME
${API_KEY_SETUP}
  cmd=\"\$(command ${QUOTED_SCRIPT} --model ${QUOTED_MODEL} --base-url ${QUOTED_BASE_URL} --api-key \"\$api_key\" \"\$@\")\" || return
  end=\$EPOCHREALTIME
  elapsed=\$(printf '%.1f' \"\$(( end - start ))\" 2>/dev/null || print -r -- '?')
  print -Pn \"%F{yellow}[\${elapsed}s]%f  %B\"
  print -rn -- \"\$cmd\"
  print -P \"%b\"
  print -z -- \"\$cmd\"
}
${END_MARKER}
"

if [[ -f "$ZSHRC" ]]; then
  ZSHRC_CONTENT=$(<"$ZSHRC")
else
  ZSHRC_CONTENT=""
fi

if [[ "$ZSHRC_CONTENT" == *"$START_MARKER"* && "$ZSHRC_CONTENT" == *"$END_MARKER"* ]]; then
  ZSHRC_CONTENT="${ZSHRC_CONTENT%%$START_MARKER*}${BLOCK}${ZSHRC_CONTENT#*$END_MARKER}"
  printf '%s\n' "$ZSHRC_CONTENT" >"$ZSHRC"
else
  if [[ -n "$ZSHRC_CONTENT" ]]; then
    printf '\n' >>"$ZSHRC"
  fi
  printf '%s\n' "$BLOCK" >>"$ZSHRC"
fi

echo "Installed the ai function into $ZSHRC."
echo "Run this to load it in your current terminal:"
echo "  source $ZSHRC"
