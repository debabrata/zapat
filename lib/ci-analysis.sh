#!/usr/bin/env bash
# Zapat - CI Failure Analysis
# Classifies CI failures as trivial (lint/type/format) or substantive (logic/test).
# Source this file: source "$SCRIPT_DIR/lib/ci-analysis.sh"

# Classify a CI failure based on test result comments on a PR.
# Usage: classify_ci_failure "repo" "pr_number"
# Output: "trivial" or "substantive"
# Trivial failures: lint errors, type errors, format issues
# Substantive failures: test failures, build errors, runtime errors
classify_ci_failure() {
    local repo="$1" pr_number="$2"

    local allowed_types="${CI_AUTOFIX_TYPES:-lint,type,format}"

    # Fetch the most recent test result comment
    local test_comments
    test_comments=$(gh api "repos/${repo}/issues/${pr_number}/comments" \
        --jq '[.[] | select(.body | contains("agent-test-failed"))] | .[-1].body // ""' 2>/dev/null || echo "")

    if [[ -z "$test_comments" ]]; then
        echo "substantive"
        return
    fi

    # Normalize to lowercase for matching
    local lower_comments
    lower_comments=$(echo "$test_comments" | tr '[:upper:]' '[:lower:]')

    # Check for substantive failure indicators (these override trivial classification)
    local substantive_patterns=(
        "assertion.*fail"
        "expect.*to.*equal"
        "expect.*to.*be"
        "test.*fail"
        "runtime.*error"
        "segmentation fault"
        "undefined is not"
        "cannot read propert"
        "null pointer"
        "index out of"
        "connection refused"
        "timeout.*error"
        "logic.*error"
        "build.*fail"
        "compilation.*fail"
        "module not found"
        "import.*error"
        "syntax.*error"
    )

    for pattern in "${substantive_patterns[@]}"; do
        if echo "$lower_comments" | grep -qE "$pattern"; then
            echo "substantive"
            return
        fi
    done

    # Check for trivial failure indicators
    local has_trivial=false

    # Lint failures
    if echo "$allowed_types" | grep -q "lint"; then
        local lint_patterns=(
            "eslint"
            "tslint"
            "swiftlint"
            "pylint"
            "flake8"
            "rubocop"
            "lint.*error"
            "linting.*fail"
            "no-unused-var"
            "no-undef"
            "prefer-const"
            "eol-last"
            "trailing-space"
            "indent"
            "semi"
            "quotes"
        )
        for pattern in "${lint_patterns[@]}"; do
            if echo "$lower_comments" | grep -qiE "$pattern"; then
                has_trivial=true
                break
            fi
        done
    fi

    # Type errors
    if [[ "$has_trivial" == "false" ]] && echo "$allowed_types" | grep -q "type"; then
        local type_patterns=(
            "type.*error"
            "ts[0-9]"
            "type.*is not assignable"
            "property.*does not exist"
            "argument.*not assignable"
            "missing.*property"
            "implicit.*any"
        )
        for pattern in "${type_patterns[@]}"; do
            if echo "$lower_comments" | grep -qiE "$pattern"; then
                has_trivial=true
                break
            fi
        done
    fi

    # Format errors
    if [[ "$has_trivial" == "false" ]] && echo "$allowed_types" | grep -q "format"; then
        local format_patterns=(
            "prettier"
            "format.*error"
            "formatting"
            "swift-format"
            "clang-format"
            "black.*format"
            "autopep8"
        )
        for pattern in "${format_patterns[@]}"; do
            if echo "$lower_comments" | grep -qiE "$pattern"; then
                has_trivial=true
                break
            fi
        done
    fi

    if [[ "$has_trivial" == "true" ]]; then
        echo "trivial"
    else
        echo "substantive"
    fi
}

# Extract the failure context from the most recent test comment.
# Usage: extract_failure_context "repo" "pr_number"
# Output: the relevant failure text (truncated to ~2000 chars)
extract_failure_context() {
    local repo="$1" pr_number="$2"

    local test_comment
    test_comment=$(gh api "repos/${repo}/issues/${pr_number}/comments" \
        --jq '[.[] | select(.body | contains("agent-test-failed"))] | .[-1].body // ""' 2>/dev/null || echo "")

    if [[ -z "$test_comment" ]]; then
        echo "No test failure details found."
        return
    fi

    # Extract just the error section (between code fences if present)
    local context
    context=$(echo "$test_comment" | sed -n "/\`\`\`/,/\`\`\`/p" | head -80)

    if [[ -z "$context" ]]; then
        # No code fences, take the last 40 lines
        context=$(echo "$test_comment" | tail -40)
    fi

    # Truncate to ~2000 chars
    echo "$context" | head -c 2000
}
