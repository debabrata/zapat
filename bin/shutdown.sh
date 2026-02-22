#!/usr/bin/env bash
# Zapat - Graceful Shutdown
# Stops the Zapat pipeline: kills agent sessions, removes cron entries,
# stops the dashboard, and cleans up runtime state.
# Usage: bin/shutdown.sh [OPTIONS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# --- Flag Parsing ---
FORCE=false
KEEP_CRON=false
KEEP_WORKTREES=false
QUIET=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f)
            FORCE=true
            shift
            ;;
        --keep-cron)
            KEEP_CRON=true
            shift
            ;;
        --keep-worktrees)
            KEEP_WORKTREES=true
            shift
            ;;
        --quiet|-q)
            QUIET=true
            shift
            ;;
        --help|-h)
            echo "Usage: bin/shutdown.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force, -f       Skip confirmation prompt"
            echo "  --keep-cron       Don't remove crontab entries"
            echo "  --keep-worktrees  Don't clean up worktrees"
            echo "  --quiet, -q       Minimal output"
            echo "  --help, -h        Show this help message"
            echo ""
            echo "Stops the Zapat pipeline: kills agent sessions, removes cron"
            echo "entries, stops the dashboard, and cleans up runtime state."
            exit 0
            ;;
        *)
            log_error "Unknown option: $1 (use --help for usage)"
            exit 1
            ;;
    esac
done

# Load env for SLACK_WEBHOOK_URL, DASHBOARD_PORT, etc.
load_env 2>/dev/null || true

if [[ "$QUIET" != "true" ]]; then
    echo "============================================"
    echo "  Zapat — Shutdown"
    echo "============================================"
    echo ""
fi

# --- Confirmation ---
if [[ "$FORCE" != "true" ]]; then
    echo "This will:"
    echo "  - Kill all agent sessions in the 'zapat' tmux session"
    echo "  - Stop the dashboard server"
    [[ "$KEEP_CRON" != "true" ]] && echo "  - Remove Zapat crontab entries"
    [[ "$KEEP_WORKTREES" != "true" ]] && echo "  - Clean up active worktrees"
    echo "  - Release concurrency slots"
    echo ""
    read -r -p "Proceed? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    echo ""
fi

STEPS_DONE=0
STEPS_SKIPPED=0
SESSIONS_KILLED=0

# --- Step 1: Kill tmux agent sessions ---
[[ "$QUIET" != "true" ]] && echo "[1/5] Stopping agent sessions..."
if tmux has-session -t zapat 2>/dev/null; then
    # List all windows in the zapat session and kill them
    WINDOWS=$(tmux list-windows -t zapat -F '#{window_name}' 2>/dev/null || true)
    if [[ -n "$WINDOWS" ]]; then
        while IFS= read -r win; do
            [[ -z "$win" ]] && continue
            tmux kill-window -t "zapat:${win}" 2>/dev/null || true
            SESSIONS_KILLED=$((SESSIONS_KILLED + 1))
        done <<< "$WINDOWS"
    fi
    # Kill the entire tmux session
    tmux kill-session -t zapat 2>/dev/null || true
    log_info "Killed tmux session 'zapat' ($SESSIONS_KILLED windows)"
    STEPS_DONE=$((STEPS_DONE + 1))
else
    log_info "No tmux session 'zapat' found"
    STEPS_SKIPPED=$((STEPS_SKIPPED + 1))
fi

# --- Step 2: Stop dashboard server ---
[[ "$QUIET" != "true" ]] && echo "[2/5] Stopping dashboard server..."
DASHBOARD_PORT=${DASHBOARD_PORT:-8080}
DASHBOARD_PID_FILE="${SCRIPT_DIR}/state/dashboard.pid"
DASHBOARD_STOPPED=false

if [[ -f "$DASHBOARD_PID_FILE" ]]; then
    OLD_PID=$(cat "$DASHBOARD_PID_FILE" 2>/dev/null)
    if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null || true
        sleep 1
        # Force kill if still running
        if kill -0 "$OLD_PID" 2>/dev/null; then
            kill -9 "$OLD_PID" 2>/dev/null || true
        fi
        DASHBOARD_STOPPED=true
        log_info "Dashboard server stopped (PID: $OLD_PID)"
    fi
    rm -f "$DASHBOARD_PID_FILE"
fi

# Also kill anything lingering on the dashboard port
if lsof -ti:"${DASHBOARD_PORT}" &>/dev/null; then
    kill "$(lsof -ti:"${DASHBOARD_PORT}")" 2>/dev/null || true
    DASHBOARD_STOPPED=true
    log_info "Killed process on port ${DASHBOARD_PORT}"
fi

if [[ "$DASHBOARD_STOPPED" == "true" ]]; then
    STEPS_DONE=$((STEPS_DONE + 1))
else
    log_info "No dashboard server running"
    STEPS_SKIPPED=$((STEPS_SKIPPED + 1))
fi

# --- Step 3: Remove crontab entries ---
[[ "$QUIET" != "true" ]] && echo "[3/5] Removing crontab entries..."
if [[ "$KEEP_CRON" != "true" ]]; then
    EXISTING_CRON=$(crontab -l 2>/dev/null || true)
    if echo "$EXISTING_CRON" | grep -q '# --- Zapat'; then
        CLEANED_CRON=$(echo "$EXISTING_CRON" | sed '/^# --- Zapat/,/^# --- End Zapat/d')
        # Remove trailing blank lines (awk works on both macOS and Linux)
        CLEANED_CRON=$(printf '%s\n' "$CLEANED_CRON" | awk '/[^[:space:]]/{p=NR} {lines[NR]=$0} END{for(i=1;i<=p;i++) print lines[i]}')
        if [[ -z "$CLEANED_CRON" ]]; then
            crontab -r 2>/dev/null || true
        else
            echo "$CLEANED_CRON" | crontab -
        fi
        log_info "Zapat crontab entries removed"
        STEPS_DONE=$((STEPS_DONE + 1))
    else
        log_info "No Zapat crontab entries found"
        STEPS_SKIPPED=$((STEPS_SKIPPED + 1))
    fi
else
    log_info "Keeping crontab entries (--keep-cron)"
    STEPS_SKIPPED=$((STEPS_SKIPPED + 1))
fi

# --- Step 4: Clean up worktrees ---
[[ "$QUIET" != "true" ]] && echo "[4/5] Cleaning up worktrees..."
WORKTREE_CLEANED=0
if [[ "$KEEP_WORKTREES" != "true" ]]; then
    WORKTREE_BASE="${ZAPAT_HOME:-$HOME/.zapat}/worktrees"
    if [[ -d "$WORKTREE_BASE" ]]; then
        for wt in "$WORKTREE_BASE"/*/; do
            [[ -d "$wt" ]] || continue
            rm -rf "$wt"
            WORKTREE_CLEANED=$((WORKTREE_CLEANED + 1))
        done
    fi

    # Prune worktrees in all repos
    while IFS= read -r proj; do
        [[ -z "$proj" ]] && continue
        while IFS=$'\t' read -r repo local_path repo_type; do
            [[ -z "$repo" ]] && continue
            if [[ -d "$local_path" ]]; then
                git -C "$local_path" worktree prune 2>/dev/null || true
            fi
        done < <(read_repos "$proj")
    done < <(read_projects)

    log_info "Cleaned $WORKTREE_CLEANED worktrees"
    STEPS_DONE=$((STEPS_DONE + 1))
else
    log_info "Keeping worktrees (--keep-worktrees)"
    STEPS_SKIPPED=$((STEPS_SKIPPED + 1))
fi

# --- Step 5: Release concurrency slots ---
[[ "$QUIET" != "true" ]] && echo "[5/5] Releasing concurrency slots..."
SLOTS_RELEASED=0
for slot_dir in "$SCRIPT_DIR/state/agent-work-slots" "$SCRIPT_DIR/state/triage-slots"; do
    if [[ -d "$slot_dir" ]]; then
        for slot_file in "$slot_dir"/*; do
            [[ -f "$slot_file" ]] || continue
            rm -f "$slot_file"
            SLOTS_RELEASED=$((SLOTS_RELEASED + 1))
        done
    fi
done
if [[ $SLOTS_RELEASED -gt 0 ]]; then
    log_info "Released $SLOTS_RELEASED concurrency slots"
fi
STEPS_DONE=$((STEPS_DONE + 1))

# --- Notify ---
if [[ -n "${SLACK_WEBHOOK_URL:-}" && "$SLACK_WEBHOOK_URL" != *"YOUR"* ]]; then
    "$SCRIPT_DIR/bin/notify.sh" \
        --slack \
        --message "Zapat pipeline stopped on $(hostname) at $(date '+%Y-%m-%d %H:%M:%S'). Sessions killed: ${SESSIONS_KILLED}, Worktrees cleaned: ${WORKTREE_CLEANED}." \
        --job-name "shutdown" \
        --status success 2>/dev/null || true
fi

# --- Summary ---
if [[ "$QUIET" != "true" ]]; then
    echo ""
    echo "============================================"
    echo "  Shutdown Complete"
    echo "============================================"
    echo ""
    echo "  Sessions killed:  $SESSIONS_KILLED"
    echo "  Dashboard:        $(if [[ "$DASHBOARD_STOPPED" == "true" ]]; then echo "stopped"; else echo "was not running"; fi)"
    echo "  Crontab:          $(if [[ "$KEEP_CRON" == "true" ]]; then echo "kept"; else echo "cleaned"; fi)"
    echo "  Worktrees:        $WORKTREE_CLEANED cleaned"
    echo "  Slots released:   $SLOTS_RELEASED"
    echo ""
    echo "  To restart: ${SCRIPT_DIR}/bin/startup.sh"
    echo ""
fi
