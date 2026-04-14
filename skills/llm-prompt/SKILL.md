---
name: llm-prompt
description: >
  Use this skill to send a prompt to an external LLM via NVIDIA NIM — Mistral, Llama, or
  Gemma models. Activate when the user asks to delegate analysis, summarization, or generation
  to an external model. Trigger phrases: "ask the LLM", "prompt Mistral", "send to NIM",
  "analyze with external model", "use NVIDIA NIM", "frag das LLM", "prompt Llama", "call
  external LLM", "summarize with Mistral". Requires NVIDIA_API_KEY env var. Replaces the
  prompt MCP tool.
---

# LLM Prompt Skill (NVIDIA NIM)

Send prompts to external LLMs via NVIDIA NIM API. Useful for delegating large-file analysis,
summarization, or generation tasks to a cost-efficient model without burning Opus context.

## Prerequisites

- `NVIDIA_API_KEY` set in environment (`~/.zshrc` or `.env`)
- `curl` and `python3` in PATH

## Model Aliases

| Alias | Model ID |
|---|---|
| `mistral` (default) | `mistralai/mistral-small-3.1-24b-instruct-2503` |
| `mistral-medium` | `mistralai/mistral-medium-3-instruct` |
| `mistral-large` | `mistralai/mistral-large-3-675b-instruct-2512` |
| `llama` | `meta/llama-3.3-70b-instruct` |
| `gemma` | `google/gemma-3-27b-it` |

## Commands

**Simple prompt (print to stdout):**
```bash
curl -s -X POST https://integrate.api.nvidia.com/v1/chat/completions \
  -H "Authorization: Bearer $NVIDIA_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"mistralai/mistral-small-3.1-24b-instruct-2503\",
    \"messages\": [{\"role\": \"user\", \"content\": \"<prompt_text>\"}],
    \"max_tokens\": 4096,
    \"temperature\": 0.15
  }" | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"
```

**With input file (prepend file content to prompt):**
```bash
FILE_CONTENT=$(cat <input_file>)
FULL_PROMPT="<instructions>

---

$FILE_CONTENT"

curl -s -X POST https://integrate.api.nvidia.com/v1/chat/completions \
  -H "Authorization: Bearer $NVIDIA_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "import json,sys; print(json.dumps({'model':'mistralai/mistral-small-3.1-24b-instruct-2503','messages':[{'role':'user','content':sys.argv[1]}],'max_tokens':4096,'temperature':0.15}))" "$FULL_PROMPT")" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"
```

**Write response to file:**
```bash
# Append > <output_file> or use tee
curl -s ... | python3 -c "..." > /tmp/llm_response.md
```

## Examples

```bash
# Summarize a large log file with Mistral (default)
FILE_CONTENT=$(cat /tmp/proxy_log.md)
curl -s -X POST https://integrate.api.nvidia.com/v1/chat/completions \
  -H "Authorization: Bearer $NVIDIA_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "
import json, sys
content = 'Summarize the cache rebuild events in this proxy log:\n\n---\n\n' + sys.argv[1]
print(json.dumps({'model':'mistralai/mistral-small-3.1-24b-instruct-2503','messages':[{'role':'user','content':content}],'max_tokens':4096,'temperature':0.15}))
" "$FILE_CONTENT")" | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"

# Quick prompt to Llama
curl -s -X POST https://integrate.api.nvidia.com/v1/chat/completions \
  -H "Authorization: Bearer $NVIDIA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"meta/llama-3.3-70b-instruct","messages":[{"role":"user","content":"What is 42?"}],"max_tokens":256,"temperature":0.15}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"
```

## Error Handling

If response status != 200, the raw response body contains the error. Check:
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" ... | tail -1
```
