#!/usr/bin/env bash
# Zapat - Human Handoff Context Generator
# Produces structured PR comments when the pipeline escalates to a human.
# Source this file: source "$SCRIPT_DIR/lib/handoff.sh"

# Generate a structured handoff context comment.
# Usage: generate_handoff_context "reason" "repo" "pr_number" ["extra_context"]
# Reasons: max_rework, rebase_conflict, high_risk, ci_fix_exhausted
# Output: markdown string for a GitHub PR comment
generate_handoff_context() {
    local reason="$1" repo="$2" pr_number="$3" extra_context="${4:-}"
    local project="${CURRENT_PROJECT:-default}"

    # --- Gather common context ---
    local pr_json pr_title pr_branch
    pr_json=$(gh pr view "$pr_number" --repo "$repo" \
        --json title,headRefName,commits,files,additions,deletions,labels,reviews 2>/dev/null || echo "{}")
    pr_title=$(echo "$pr_json" | jq -r '.title // "Unknown"')
    pr_branch=$(echo "$pr_json" | jq -r '.headRefName // "unknown"')
    local files_changed additions deletions
    files_changed=$(echo "$pr_json" | jq -r '.files | length' 2>/dev/null || echo "0")
    additions=$(echo "$pr_json" | jq -r '.additions // 0')
    deletions=$(echo "$pr_json" | jq -r '.deletions // 0')

    # --- Gather review history ---
    local reviews_summary=""
    local review_states
    review_states=$(echo "$pr_json" | jq -r '[.reviews[].state] | group_by(.) | map("\(.[0]): \(length)") | join(", ")' 2>/dev/null || echo "none")
    if [[ -n "$review_states" && "$review_states" != "none" ]]; then
        reviews_summary="Review history: ${review_states}"
    fi

    # --- Gather unresolved review comments ---
    local unresolved_comments=""
    local inline_comments
    inline_comments=$(gh api "repos/${repo}/pulls/${pr_number}/comments" \
        --jq '[.[] | select(.in_reply_to_id == null)] | .[-5:][] | "- **\(.path):\(.line // .original_line // "?")**: \(.body | split("\n")[0])"' 2>/dev/null || echo "")
    if [[ -n "$inline_comments" ]]; then
        unresolved_comments="$inline_comments"
    fi

    # --- Rework cycle history ---
    local rework_cycles=""
    local cycles_count
    cycles_count=$(get_rework_cycles "$repo" "rework" "$pr_number" "$project" 2>/dev/null || echo "0")
    if [[ "$cycles_count" -gt 0 ]]; then
        rework_cycles="Rework cycles completed: ${cycles_count}/${MAX_REWORK_CYCLES:-3}"
    fi

    # --- Session log excerpt ---
    local log_excerpt=""
    if [[ "${HANDOFF_INCLUDE_LOGS:-true}" == "true" ]]; then
        local max_lines="${HANDOFF_MAX_LOG_LINES:-200}"
        local log_file=""
        # Find the most recent relevant log
        local repo_slug="${repo##*/}"
        log_file=$(find "${AUTOMATION_DIR}/logs" -name "*${repo_slug}*pr*${pr_number}*" -type f 2>/dev/null | sort -t/ -k2 | tail -1)
        if [[ -n "$log_file" && -f "$log_file" ]]; then
            log_excerpt=$(tail -n "$max_lines" "$log_file" 2>/dev/null || echo "")
        fi
    fi

    # --- Build reason-specific section ---
    local reason_title reason_detail suggested_actions
    case "$reason" in
        max_rework)
            reason_title="Rework Cycle Limit Reached"
            reason_detail="This PR has gone through ${cycles_count}/${MAX_REWORK_CYCLES:-3} rework cycles without converging on an approved state. The agent was unable to fully resolve all review feedback within the allowed iterations."
            suggested_actions="1. Review the unresolved comments below — some may require human judgment
2. Check if the review feedback is contradictory or ambiguous
3. Make targeted fixes and push directly, or re-label with \`agent-work\` for a fresh attempt
4. Consider splitting the PR if scope has grown"
            ;;
        rebase_conflict)
            reason_title="Rebase Conflict"
            reason_detail="Auto-rebase onto the base branch failed due to merge conflicts. The agent cannot resolve these automatically."
            suggested_actions="1. Review the conflict details below
2. Resolve conflicts manually: \`git checkout ${pr_branch} && git rebase origin/main\`
3. Push the resolved branch
4. Remove the \`needs-rebase\` label to resume the pipeline"
            ;;
        high_risk)
            reason_title="High-Risk PR — Human Review Required"
            reason_detail="This PR was classified as **high risk** by the automated risk scorer. High-risk PRs require human judgment before merging."
            suggested_actions="1. Review the risk factors listed below
2. Verify security-sensitive changes are correct
3. Merge manually when satisfied: \`gh pr merge ${pr_number} --repo ${repo} --squash\`"
            ;;
        ci_fix_exhausted)
            reason_title="CI Auto-Fix Attempts Exhausted"
            reason_detail="The automated CI fix system was unable to resolve test/lint failures after the maximum number of attempts. The failures may require deeper investigation."
            suggested_actions="1. Review the specific failures listed below
2. Check if the failures indicate a logic error (not just lint/format)
3. Fix manually and push, or re-label with \`zapat-rework\` for full agent rework"
            ;;
        *)
            reason_title="Pipeline Escalation"
            reason_detail="The pipeline encountered a situation requiring human intervention."
            suggested_actions="1. Review the context below
2. Take appropriate action based on the details"
            ;;
    esac

    # --- Generate desktop deep link ---
    local deep_link_section=""
    if [[ "${HANDOFF_DEEP_LINK_ENABLED:-false}" == "true" ]]; then
        deep_link_section="
### Quick Resume
Open in Claude Code Desktop: \`claude \"Review PR #${pr_number} in ${repo}\"\`"
    fi

    # --- Assemble the comment ---
    local comment
    comment="<!-- zapat-handoff: ${reason} -->
## Pipeline Handoff: ${reason_title}

**PR:** #${pr_number} — ${pr_title}
**Branch:** \`${pr_branch}\`
**Changes:** ${files_changed} files, +${additions}/-${deletions}
${rework_cycles:+**${rework_cycles}**}
${reviews_summary:+**${reviews_summary}**}

### Why This Needs Human Attention

${reason_detail}

${extra_context:+### Details

${extra_context}
}
### Suggested Next Steps

${suggested_actions}
${deep_link_section}
${unresolved_comments:+
### Unresolved Review Comments (last 5)

${unresolved_comments}
}
${log_excerpt:+
<details>
<summary>Session Log Excerpt (last ${HANDOFF_MAX_LOG_LINES:-200} lines)</summary>

\`\`\`
${log_excerpt}
\`\`\`

</details>
}
---
_Escalated by [Zapat](https://github.com/zapat-ai/zapat) | Reason: \`${reason}\`_"

    echo "$comment"
}

# Post a handoff comment on a PR and update item state.
# Usage: post_handoff_comment "repo" "pr_number" "reason" ["extra_context"]
post_handoff_comment() {
    local repo="$1" pr_number="$2" reason="$3" extra_context="${4:-}"
    local project="${CURRENT_PROJECT:-default}"

    local comment
    comment=$(generate_handoff_context "$reason" "$repo" "$pr_number" "$extra_context")

    # Post the comment
    gh pr comment "$pr_number" --repo "$repo" --body "$comment" 2>/dev/null || {
        log_warn "Failed to post handoff comment on PR #${pr_number}"
        return 1
    }

    # Update item state with handoff metadata
    local state_file
    local key="${project}--${repo//\//-}_rework_${pr_number}"
    state_file="$ITEM_STATE_DIR/${key}.json"
    if [[ -f "$state_file" ]]; then
        local now
        now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
        local tmp_file="${state_file}.tmp"
        jq --arg reason "$reason" --arg now "$now" \
            '.handoff_reason = $reason | .handoff_at = $now' \
            "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
    fi

    log_info "Handoff comment posted on PR #${pr_number} (reason: ${reason})"
}
