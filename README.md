# nl2shell.sh

`nl2shell.sh` converts a natural language request into a single shell command by calling an OpenAI-compatible chat completions API.

## Requirements

- `curl`
- `jq`

```

## Install In zsh

Add a function to `~/.zshrc`.

```zsh
ai () {
	local cmd start end elapsed
	if (( $# == 0 ))
	then
		print -r -- 'Usage: ai <natural language description>'
		print -r -- 'Example: ai list all files recursively sorted by size'
		return
	fi
	start=$EPOCHREALTIME
	# Change this line to use your script path, model, base URL, and API key.
	cmd="$(command /path/to/nl2shell.sh --model qwen3.6-plus --base-url https://coding.dashscope.aliyuncs.com/v1 --api-key $ALI_API_KEY "$@")" || return
	end=$EPOCHREALTIME
	elapsed=$(printf '%.1f' "$(( end - start ))" 2>/dev/null || print -r -- '?')
	print -Pn "%F{yellow}[${elapsed}s]%f  %B"
	print -rn -- "$cmd"
	print -P "%b"
	print -z -- "$cmd"
}
```

Reload zsh config:

```zsh
source ~/.zshrc
```

Use it:

```zsh
ai show disk usage sorted by size
```

In zsh, the generated command is inserted into the prompt buffer with `print -z`, so you can edit it before pressing Enter.
