#!/usr/bin/env bats

# Tests for substitute_prompt shared footer functionality in lib/common.sh

load '../node_modules/bats-support/load'
load '../node_modules/bats-assert/load'

setup() {
    export AUTOMATION_DIR="$BATS_TEST_TMPDIR/zapat"
    mkdir -p "$AUTOMATION_DIR/state"
    mkdir -p "$AUTOMATION_DIR/logs"
    mkdir -p "$AUTOMATION_DIR/config"
    mkdir -p "$BATS_TEST_TMPDIR/prompts"

    # Create minimal repos.conf so read_repos doesn't fail
    echo "" > "$AUTOMATION_DIR/config/repos.conf"

    source "$BATS_TEST_DIRNAME/../lib/common.sh"
}

teardown() {
    rm -rf "$BATS_TEST_TMPDIR/zapat"
    rm -rf "$BATS_TEST_TMPDIR/prompts"
}

# --- Shared Footer Tests ---

@test "substitute_prompt replaces {{SHARED_FOOTER}} with footer contents" {
    # Create a template with opt-in marker
    printf "Hello {{NAME}}\n{{SHARED_FOOTER}}" > "$BATS_TEST_TMPDIR/prompts/test-template.txt"

    # Create a shared footer
    echo "---FOOTER---" > "$BATS_TEST_TMPDIR/prompts/_shared-footer.txt"

    run substitute_prompt "$BATS_TEST_TMPDIR/prompts/test-template.txt" "NAME=World"
    assert_success
    assert_output --partial "Hello World"
    assert_output --partial "---FOOTER---"
}

@test "substitute_prompt does NOT inject footer without {{SHARED_FOOTER}} marker" {
    # Create a template WITHOUT the marker
    echo "Hello {{NAME}}" > "$BATS_TEST_TMPDIR/prompts/test-template.txt"

    # Create a shared footer
    echo "---FOOTER---" > "$BATS_TEST_TMPDIR/prompts/_shared-footer.txt"

    run substitute_prompt "$BATS_TEST_TMPDIR/prompts/test-template.txt" "NAME=World"
    assert_success
    assert_output --partial "Hello World"
    refute_output --partial "---FOOTER---"
}

@test "substitute_prompt works when footer file is missing (graceful fallback)" {
    # Create a template with marker but no footer file
    printf "Hello {{NAME}}\n{{SHARED_FOOTER}}" > "$BATS_TEST_TMPDIR/prompts/test-template.txt"

    # Ensure no footer file exists
    rm -f "$BATS_TEST_TMPDIR/prompts/_shared-footer.txt"

    run substitute_prompt "$BATS_TEST_TMPDIR/prompts/test-template.txt" "NAME=World"
    assert_success
    assert_output --partial "Hello World"
}

@test "substitute_prompt applies placeholder substitution to footer content" {
    # Create a template with marker
    printf "Template for {{REPO}}\n{{SHARED_FOOTER}}" > "$BATS_TEST_TMPDIR/prompts/test-template.txt"

    # Create footer with a placeholder
    echo "Footer: {{REPO}}" > "$BATS_TEST_TMPDIR/prompts/_shared-footer.txt"

    run substitute_prompt "$BATS_TEST_TMPDIR/prompts/test-template.txt" "REPO=my-org/my-repo"
    assert_success
    assert_output --partial "Template for my-org/my-repo"
    assert_output --partial "Footer: my-org/my-repo"
}

@test "substitute_prompt footer preserves auto-injected variables" {
    # Create a template with marker
    printf "Main content\n{{SHARED_FOOTER}}" > "$BATS_TEST_TMPDIR/prompts/test-template.txt"

    # Create footer with auto-injected placeholder
    printf "\n## Repository Map\n{{REPO_MAP}}" > "$BATS_TEST_TMPDIR/prompts/_shared-footer.txt"

    run substitute_prompt "$BATS_TEST_TMPDIR/prompts/test-template.txt"
    assert_success
    assert_output --partial "Main content"
    assert_output --partial "## Repository Map"
}
