#!/usr/bin/env bash
# Zapat - OpenAI Codex provider implementation

# Run agent in non-interactive mode using codex exec
# Note: --allowedTools and --max-budget-usd are not supported by Codex CLI
# Usage: provider_run_noninteractive prompt_file model allowed_tools budget timeout
provider_run_noninteractive() {
    local prompt_file="$1"
    local model="$2"
    local allowed_tools="$3"
    local budget="$4"
    local timeout="$5"

    if [[ -n "$allowed_tools" ]]; then
        log_warn "Codex provider: --allowedTools is not supported (ignoring: $allowed_tools)" 2>/dev/null || true
    fi
    if [[ -n "$budget" ]]; then
        log_warn "Codex provider: --max-budget-usd is not supported (ignoring: $budget)" 2>/dev/null || true
    fi

    local timeout_cmd
    if [[ "$(uname)" == "Darwin" ]]; then
        timeout_cmd="gtimeout"
    else
        timeout_cmd="timeout"
    fi

    $timeout_cmd "${timeout}" codex exec \
        -m "$model" \
        -q "$(cat "$prompt_file")"
}

# Return regex for detecting when Codex is idle at the input prompt
provider_get_idle_pattern() {
    echo "(\\\$|>|codex>)"
}

# Return regex for detecting active spinner/processing
provider_get_spinner_pattern() {
    echo "(Working|Thinking|Processing|Loading)"
}

# Return regex for detecting rate limit prompts
provider_get_rate_limit_pattern() {
    echo "(Rate limit|rate_limit|429|Too Many Requests|Retry after|quota exceeded)"
}

# Return regex for detecting account-level usage limits
provider_get_account_limit_pattern() {
    echo "(quota exceeded|billing|usage limit|You've reached|out of credits)"
}

# Return regex for detecting permission prompts
provider_get_permission_pattern() {
    echo "(Allow once|Allow always|Do you want to|approve this action)"
}

# Return the full CLI command string for launching an interactive Codex session
# Usage: provider_get_launch_cmd model
provider_get_launch_cmd() {
    local model="${1:-${CODEX_MODEL:-o4-mini}}"
    echo "codex --model '${model}' --dangerously-bypass-approvals-and-sandbox"
}

# Check if the codex CLI is available
# Returns: 0 if available, 1 if not
provider_prereq_check() {
    if command -v codex &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Convert a Codex model string to a short identifier
# Usage: provider_get_model_shorthand model_string
provider_get_model_shorthand() {
    local model="${1:-}"
    case "$model" in
        o4-mini*)   echo "o4-mini"   ;;
        codex-mini*) echo "codex-mini" ;;
        o3*)        echo "o3"        ;;
        o1*)        echo "o1"        ;;
        *)          echo "$model"    ;;
    esac
}
