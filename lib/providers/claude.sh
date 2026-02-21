#!/usr/bin/env bash
# Zapat - Claude Code provider implementation

# Run agent in non-interactive mode using claude -p
# Usage: provider_run_noninteractive prompt_file model allowed_tools budget timeout
provider_run_noninteractive() {
    local prompt_file="$1"
    local model="$2"
    local allowed_tools="$3"
    local budget="$4"
    local timeout="$5"

    local timeout_cmd
    if [[ "$(uname)" == "Darwin" ]]; then
        timeout_cmd="gtimeout"
    else
        timeout_cmd="timeout"
    fi

    $timeout_cmd "${timeout}" claude \
        -p "$(cat "$prompt_file")" \
        --model "$model" \
        --allowedTools "$allowed_tools" \
        --max-budget-usd "$budget"
}

# Return regex for detecting when Claude is idle at the input prompt
provider_get_idle_pattern() {
    echo "^❯"
}

# Return regex for detecting active spinner/processing
provider_get_spinner_pattern() {
    echo "(⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏|Working|Thinking)"
}

# Return regex for detecting rate limit prompts
provider_get_rate_limit_pattern() {
    echo "(Switch to extra|Rate limit|rate_limit|429|Too Many Requests|Retry after)"
}

# Return regex for detecting account-level usage limits
provider_get_account_limit_pattern() {
    echo "(out of extra usage|resets [0-9]|usage limit|plan limit|You've reached)"
}

# Return regex for detecting permission prompts
provider_get_permission_pattern() {
    echo "(Allow once|Allow always|Do you want to allow|Do you want to (create|make|run|write|edit)|wants to use the .* tool|approve this action|Waiting for team lead approval)"
}

# Return the full CLI command string for launching an interactive Claude session
# Usage: provider_get_launch_cmd model
provider_get_launch_cmd() {
    local model="${1:-${CLAUDE_MODEL:-claude-opus-4-6}}"
    echo "claude --model '${model}' --dangerously-skip-permissions --permission-mode bypassPermissions"
}

# Check if the claude CLI is available
# Returns: 0 if available, 1 if not
provider_prereq_check() {
    if command -v claude &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Convert a Claude model string to a short identifier used in prompts
# Usage: provider_get_model_shorthand model_string
provider_get_model_shorthand() {
    local model="${1:-}"
    case "$model" in
        *opus*)   echo "opus"   ;;
        *haiku*)  echo "haiku"  ;;
        *sonnet*) echo "sonnet" ;;
        *)        echo "sonnet" ;;
    esac
}
