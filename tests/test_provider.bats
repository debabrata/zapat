#!/usr/bin/env bats
# Tests for lib/provider.sh and lib/providers/*.sh

load '../node_modules/bats-support/load'
load '../node_modules/bats-assert/load'

setup() {
    export TEST_DIR="$(mktemp -d)"
    export SCRIPT_DIR="$TEST_DIR"

    # Create provider directory structure mirroring the real one
    mkdir -p "$TEST_DIR/lib/providers"

    # Stub log functions (used by providers for warnings)
    cat > "$TEST_DIR/lib/common.sh" <<'STUBEOF'
log_info()  { echo "[INFO] $*"; }
log_warn()  { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*"; }
_log_structured() { echo "[STRUCTURED] $*"; }
STUBEOF

    # Copy real provider files into the test directory
    cp "$(dirname "$BATS_TEST_FILENAME")/../lib/provider.sh"          "$TEST_DIR/lib/provider.sh"
    cp "$(dirname "$BATS_TEST_FILENAME")/../lib/providers/claude.sh"  "$TEST_DIR/lib/providers/claude.sh"
    cp "$(dirname "$BATS_TEST_FILENAME")/../lib/providers/codex.sh"   "$TEST_DIR/lib/providers/codex.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Helper: source provider.sh in a subshell and print a value
_run_provider() {
    local provider="$1"
    local cmd="$2"
    AGENT_PROVIDER="$provider" bash -c "source $TEST_DIR/lib/provider.sh && $cmd"
}

# ─── Provider dispatch ────────────────────────────────────────────────────────

@test "provider dispatch: loads claude provider when AGENT_PROVIDER=claude" {
    run bash -c "AGENT_PROVIDER=claude source $TEST_DIR/lib/provider.sh && command -v provider_prereq_check"
    assert_success
}

@test "provider dispatch: loads codex provider when AGENT_PROVIDER=codex" {
    run bash -c "AGENT_PROVIDER=codex source $TEST_DIR/lib/provider.sh && command -v provider_prereq_check"
    assert_success
}

@test "provider dispatch: defaults to claude when AGENT_PROVIDER is unset" {
    run bash -c "unset AGENT_PROVIDER; source $TEST_DIR/lib/provider.sh && provider_get_launch_cmd 'claude-opus-4-6'"
    assert_success
    assert_output --partial "claude --model"
}

@test "provider dispatch: invalid provider name returns error" {
    run bash -c "AGENT_PROVIDER='../../../etc/passwd' source $TEST_DIR/lib/provider.sh"
    assert_failure
    assert_output --partial "invalid AGENT_PROVIDER"
}

@test "provider dispatch: unknown provider name returns error" {
    run bash -c "AGENT_PROVIDER=gpt4 source $TEST_DIR/lib/provider.sh"
    assert_failure
    assert_output --partial "unknown AGENT_PROVIDER"
}

@test "provider dispatch: path traversal with dots rejected" {
    run bash -c "AGENT_PROVIDER='../evil' source $TEST_DIR/lib/provider.sh"
    assert_failure
}

@test "provider dispatch: provider name with spaces rejected" {
    run bash -c "AGENT_PROVIDER='claude extra' source $TEST_DIR/lib/provider.sh"
    assert_failure
}

# ─── Credential isolation ─────────────────────────────────────────────────────

@test "credential isolation: claude provider unsets OPENAI_API_KEY" {
    run bash -c "
        export OPENAI_API_KEY=sk-test123
        AGENT_PROVIDER=claude source $TEST_DIR/lib/provider.sh
        echo \"OPENAI_KEY=\${OPENAI_API_KEY:-UNSET}\"
    "
    assert_success
    assert_output --partial "OPENAI_KEY=UNSET"
}

@test "credential isolation: claude provider preserves ANTHROPIC_API_KEY" {
    run bash -c "
        export ANTHROPIC_API_KEY=ant-test123
        AGENT_PROVIDER=claude source $TEST_DIR/lib/provider.sh
        echo \"ANTHROPIC_KEY=\${ANTHROPIC_API_KEY:-UNSET}\"
    "
    assert_success
    assert_output --partial "ANTHROPIC_KEY=ant-test123"
}

@test "credential isolation: codex provider unsets ANTHROPIC_API_KEY" {
    run bash -c "
        export ANTHROPIC_API_KEY=ant-test123
        AGENT_PROVIDER=codex source $TEST_DIR/lib/provider.sh
        echo \"ANTHROPIC_KEY=\${ANTHROPIC_API_KEY:-UNSET}\"
    "
    assert_success
    assert_output --partial "ANTHROPIC_KEY=UNSET"
}

@test "credential isolation: codex provider preserves CLAUDE_MODEL config var" {
    run bash -c "
        export CLAUDE_MODEL=claude-opus-4-6
        AGENT_PROVIDER=codex source $TEST_DIR/lib/provider.sh
        echo \"CLAUDE_MODEL=\${CLAUDE_MODEL:-UNSET}\"
    "
    assert_success
    assert_output --partial "CLAUDE_MODEL=claude-opus-4-6"
}

# ─── Claude provider functions ────────────────────────────────────────────────

@test "claude provider_get_idle_pattern returns non-empty regex" {
    run bash -c "AGENT_PROVIDER=claude source $TEST_DIR/lib/provider.sh && provider_get_idle_pattern"
    assert_success
    [ -n "$output" ]
}

@test "claude provider_get_idle_pattern matches ❯ prompt" {
    local pattern
    pattern=$(bash -c "AGENT_PROVIDER=claude source $TEST_DIR/lib/provider.sh && provider_get_idle_pattern")
    run bash -c "echo '❯' | grep -qE '$pattern'"
    assert_success
}

@test "claude provider_get_spinner_pattern returns non-empty regex" {
    run bash -c "AGENT_PROVIDER=claude source $TEST_DIR/lib/provider.sh && provider_get_spinner_pattern"
    assert_success
    [ -n "$output" ]
}

@test "claude provider_get_launch_cmd includes claude CLI" {
    run bash -c "AGENT_PROVIDER=claude source $TEST_DIR/lib/provider.sh && provider_get_launch_cmd 'claude-opus-4-6'"
    assert_success
    assert_output --partial "claude --model 'claude-opus-4-6'"
    assert_output --partial "--permission-mode bypassPermissions"
}

@test "claude provider_prereq_check succeeds when claude is in PATH" {
    # Create a fake claude in a temp bin dir
    local fake_bin="$TEST_DIR/fake-bin"
    mkdir -p "$fake_bin"
    touch "$fake_bin/claude" && chmod +x "$fake_bin/claude"
    run bash -c "PATH=$fake_bin:\$PATH AGENT_PROVIDER=claude source $TEST_DIR/lib/provider.sh && provider_prereq_check"
    assert_success
}

@test "claude provider_prereq_check fails when claude not in PATH" {
    run bash -c "PATH=/tmp AGENT_PROVIDER=claude source $TEST_DIR/lib/provider.sh && provider_prereq_check"
    assert_failure
}

@test "claude provider_get_model_shorthand: opus model" {
    run bash -c "AGENT_PROVIDER=claude source $TEST_DIR/lib/provider.sh && provider_get_model_shorthand 'claude-opus-4-6'"
    assert_success
    assert_output "opus"
}

@test "claude provider_get_model_shorthand: haiku model" {
    run bash -c "AGENT_PROVIDER=claude source $TEST_DIR/lib/provider.sh && provider_get_model_shorthand 'claude-haiku-4-5-20251001'"
    assert_success
    assert_output "haiku"
}

@test "claude provider_get_model_shorthand: sonnet model" {
    run bash -c "AGENT_PROVIDER=claude source $TEST_DIR/lib/provider.sh && provider_get_model_shorthand 'claude-sonnet-4-6'"
    assert_success
    assert_output "sonnet"
}

@test "claude provider_get_model_shorthand: unknown defaults to sonnet" {
    run bash -c "AGENT_PROVIDER=claude source $TEST_DIR/lib/provider.sh && provider_get_model_shorthand 'unknown-model'"
    assert_success
    assert_output "sonnet"
}

# ─── Claude provider_run_noninteractive ──────────────────────────────────────

@test "claude provider_run_noninteractive: uses correct command structure" {
    # Stub claude as a script that echoes its arguments
    local fake_bin="$TEST_DIR/fake-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/claude" <<'STUBEOF'
#!/usr/bin/env bash
echo "claude-called: $*"
STUBEOF
    chmod +x "$fake_bin/claude"

    # Create a prompt file
    local prompt_file="$TEST_DIR/test-prompt.txt"
    echo "test prompt" > "$prompt_file"

    run bash -c "
        PATH=$fake_bin:\$PATH
        AGENT_PROVIDER=claude source $TEST_DIR/lib/provider.sh
        provider_run_noninteractive '$prompt_file' 'claude-opus-4-6' 'Read,Glob' '5' '60'
    "
    assert_success
    assert_output --partial "claude-called:"
    assert_output --partial "--model"
    assert_output --partial "claude-opus-4-6"
    assert_output --partial "--allowedTools"
    assert_output --partial "--max-budget-usd"
}

# ─── Codex provider functions ─────────────────────────────────────────────────

@test "codex provider_get_launch_cmd includes codex CLI" {
    run bash -c "AGENT_PROVIDER=codex source $TEST_DIR/lib/provider.sh && provider_get_launch_cmd 'o4-mini'"
    assert_success
    assert_output --partial "codex --model 'o4-mini'"
    assert_output --partial "--dangerously-bypass-approvals-and-sandbox"
}

@test "codex provider_prereq_check fails when codex not in PATH" {
    run bash -c "PATH=/tmp AGENT_PROVIDER=codex source $TEST_DIR/lib/provider.sh && provider_prereq_check"
    assert_failure
}

@test "codex provider_get_model_shorthand: o4-mini" {
    run bash -c "AGENT_PROVIDER=codex source $TEST_DIR/lib/provider.sh && provider_get_model_shorthand 'o4-mini'"
    assert_success
    assert_output "o4-mini"
}

@test "codex provider_get_model_shorthand: codex-mini" {
    run bash -c "AGENT_PROVIDER=codex source $TEST_DIR/lib/provider.sh && provider_get_model_shorthand 'codex-mini'"
    assert_success
    assert_output "codex-mini"
}

# ─── Codex provider_run_noninteractive ───────────────────────────────────────

@test "codex provider_run_noninteractive: logs warning for allowedTools" {
    local fake_bin="$TEST_DIR/fake-bin"
    mkdir -p "$fake_bin"
    # Stub gtimeout/timeout to just run the command directly
    cat > "$fake_bin/gtimeout" <<'STUBEOF'
#!/usr/bin/env bash
shift  # remove timeout arg
exec "$@"
STUBEOF
    chmod +x "$fake_bin/gtimeout"
    # Stub codex
    cat > "$fake_bin/codex" <<'STUBEOF'
#!/usr/bin/env bash
echo "codex-called: $*"
STUBEOF
    chmod +x "$fake_bin/codex"

    local prompt_file="$TEST_DIR/test-prompt.txt"
    echo "test prompt" > "$prompt_file"

    # Source common.sh stub for log_warn
    run bash -c "
        PATH=$fake_bin:\$PATH
        source $TEST_DIR/lib/common.sh
        AGENT_PROVIDER=codex source $TEST_DIR/lib/provider.sh
        provider_run_noninteractive '$prompt_file' 'o4-mini' 'Read,Glob' '5' '60' 2>&1
    "
    assert_output --partial "allowedTools is not supported"
}

@test "codex provider_run_noninteractive: uses codex exec command" {
    local fake_bin="$TEST_DIR/fake-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/gtimeout" <<'STUBEOF'
#!/usr/bin/env bash
shift
exec "$@"
STUBEOF
    chmod +x "$fake_bin/gtimeout"
    cat > "$fake_bin/codex" <<'STUBEOF'
#!/usr/bin/env bash
echo "codex-called: $*"
STUBEOF
    chmod +x "$fake_bin/codex"

    local prompt_file="$TEST_DIR/test-prompt.txt"
    echo "test prompt" > "$prompt_file"

    run bash -c "
        PATH=$fake_bin:\$PATH
        source $TEST_DIR/lib/common.sh
        AGENT_PROVIDER=codex source $TEST_DIR/lib/provider.sh
        provider_run_noninteractive '$prompt_file' 'o4-mini' '' '' '60' 2>&1
    "
    assert_output --partial "codex-called:"
    assert_output --partial "exec"
    assert_output --partial "-m"
    assert_output --partial "o4-mini"
}

# ─── .env.example ────────────────────────────────────────────────────────────

@test ".env.example defines AGENT_PROVIDER" {
    grep -q '^AGENT_PROVIDER=' "$BATS_TEST_DIRNAME/../.env.example"
}

@test ".env.example AGENT_PROVIDER defaults to claude" {
    grep -q '^AGENT_PROVIDER=claude' "$BATS_TEST_DIRNAME/../.env.example"
}

@test ".env.example defines CODEX_MODEL" {
    grep -q '^CODEX_MODEL=' "$BATS_TEST_DIRNAME/../.env.example"
}
