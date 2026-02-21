#!/usr/bin/env bash
# Zapat - Provider Dispatcher
# Reads AGENT_PROVIDER, validates it, sources the correct provider implementation,
# and applies credential isolation.

_PROVIDER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_load_provider() {
    local provider="${AGENT_PROVIDER:-claude}"

    # Security: reject path traversal and non-alphanumeric characters
    if [[ ! "$provider" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        echo "[ERROR] provider.sh: invalid AGENT_PROVIDER value: '$provider'" >&2
        return 1
    fi

    # Whitelist of known providers
    case "$provider" in
        claude|codex) ;;
        *)
            echo "[ERROR] provider.sh: unknown AGENT_PROVIDER: '$provider'. Supported: claude, codex" >&2
            return 1
            ;;
    esac

    local provider_file="${_PROVIDER_SCRIPT_DIR}/providers/${provider}.sh"
    if [[ ! -f "$provider_file" ]]; then
        echo "[ERROR] provider.sh: provider file not found: $provider_file" >&2
        return 1
    fi

    # Credential isolation: unset credentials belonging to the inactive provider
    case "$provider" in
        claude)
            # Using Claude — ensure Codex/OpenAI credentials are not exposed
            unset OPENAI_API_KEY 2>/dev/null || true
            ;;
        codex)
            # Using Codex — ensure Anthropic credentials are not exposed
            # Only unset credential vars, not config vars like CLAUDE_MODEL
            unset ANTHROPIC_API_KEY 2>/dev/null || true
            unset CLAUDE_API_KEY 2>/dev/null || true
            unset ANTHROPIC_AUTH_TOKEN 2>/dev/null || true
            ;;
    esac

    source "$provider_file"
}

_load_provider
