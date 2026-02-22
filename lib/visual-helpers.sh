#!/usr/bin/env bash
# Zapat - Visual Verification Helpers
# Dev server management and screenshot capture for UI-eligible repos.
# Source this file: source "$SCRIPT_DIR/lib/visual-helpers.sh"

# Check if a repo is eligible for visual verification.
# Three conditions must ALL be met:
#   1. VISUAL_VERIFY_ENABLED=true in .env
#   2. Repo type is UI-capable (web, extension)
#   3. PR contains UI-relevant file changes
# Usage: should_visual_verify "repo" "pr_number" "repo_type"
# Returns: 0 (yes) or 1 (no)
should_visual_verify() {
    local repo="$1" pr_number="$2" repo_type="$3"

    # Condition 1: Feature enabled
    if [[ "${VISUAL_VERIFY_ENABLED:-false}" != "true" ]]; then
        return 1
    fi

    # Condition 2: Repo type is UI-capable
    case "$repo_type" in
        web|extension)
            ;;
        *)
            log_info "Visual verify skipped: repo type '$repo_type' is not UI-capable"
            return 1
            ;;
    esac

    # Condition 3: PR contains UI-relevant changes
    if ! has_ui_changes "$repo" "$pr_number"; then
        log_info "Visual verify skipped: PR #${pr_number} has no UI-relevant file changes"
        return 1
    fi

    return 0
}

# Check if a PR contains UI-relevant file changes.
# Usage: has_ui_changes "repo" "pr_number"
# Returns: 0 if UI changes present, 1 if not
has_ui_changes() {
    local repo="$1" pr_number="$2"

    local files
    files=$(gh pr view "$pr_number" --repo "$repo" --json files --jq '.files[].path' 2>/dev/null || echo "")

    if [[ -z "$files" ]]; then
        return 1
    fi

    # UI file patterns (trigger visual verification)
    local ui_patterns=(
        '\.tsx$'
        '\.jsx$'
        '\.css$'
        '\.scss$'
        '\.html$'
        '\.svg$'
        '/pages/'
        '/app/'
        '/components/'
        '/views/'
        '/layouts/'
        '/styles/'
        '/public/'
    )

    # Non-UI file patterns (skip these even if they match extensions)
    local skip_patterns=(
        '\.test\.'
        '\.spec\.'
        '\.config\.'
    )

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Skip test/config files
        local is_skip=false
        for pattern in "${skip_patterns[@]}"; do
            if echo "$file" | grep -qE "$pattern"; then
                is_skip=true
                break
            fi
        done
        [[ "$is_skip" == "true" ]] && continue

        # Check if it's a UI file
        for pattern in "${ui_patterns[@]}"; do
            if echo "$file" | grep -qE "$pattern"; then
                return 0
            fi
        done
    done <<< "$files"

    return 1
}

# Start the dev server in a worktree.
# Usage: start_dev_server "worktree_dir" "dev_cmd" "port"
# Sets: DEV_SERVER_PID
# Returns: 0 on success, 1 on failure
start_dev_server() {
    local worktree_dir="$1"
    local dev_cmd="${2:-npm run dev}"
    local port="${3:-3000}"

    cd "$worktree_dir" || return 1

    # Install dependencies if needed
    if [[ -f "package.json" ]] && [[ ! -d "node_modules" ]]; then
        log_info "Installing dependencies..."
        npm install --silent 2>/dev/null || {
            log_warn "npm install failed, trying with legacy-peer-deps"
            npm install --legacy-peer-deps --silent 2>/dev/null || {
                log_error "Failed to install dependencies"
                return 1
            }
        }
    fi

    # Start the dev server in the background
    log_info "Starting dev server: $dev_cmd (port: $port)"
    eval "$dev_cmd" > /tmp/zapat-dev-server-$$.log 2>&1 &
    DEV_SERVER_PID=$!

    # Wait for server to be ready
    if ! wait_for_server "$port" 120; then
        log_error "Dev server failed to start within 120s"
        stop_dev_server
        return 1
    fi

    log_info "Dev server running on port $port (PID: $DEV_SERVER_PID)"
    return 0
}

# Wait for a server to respond on a given port.
# Usage: wait_for_server "port" "timeout_seconds"
# Returns: 0 when server responds, 1 on timeout
wait_for_server() {
    local port="$1" timeout="${2:-120}"
    local elapsed=0
    local interval=3

    while [[ $elapsed -lt $timeout ]]; do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${port}" 2>/dev/null | grep -qE "^[23]"; then
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    return 1
}

# Stop the dev server.
# Usage: stop_dev_server
stop_dev_server() {
    if [[ -n "${DEV_SERVER_PID:-}" ]]; then
        kill "$DEV_SERVER_PID" 2>/dev/null || true
        # Also kill any child processes (Next.js spawns children)
        pkill -P "$DEV_SERVER_PID" 2>/dev/null || true
        wait "$DEV_SERVER_PID" 2>/dev/null || true
        DEV_SERVER_PID=""
        log_info "Dev server stopped"
    fi
}

# Capture screenshots of specified pages using Playwright.
# Usage: capture_screenshots "port" "pages" "viewports" "output_dir"
# pages: comma-separated paths (e.g., "/,/login,/dashboard")
# viewports: comma-separated sizes (e.g., "1920x1080,375x812")
# output_dir: directory to save screenshots
# Returns: 0 on success, 1 on failure
capture_screenshots() {
    local port="$1"
    local pages="${2:-/}"
    local viewports="${3:-1920x1080}"
    local output_dir="$4"

    mkdir -p "$output_dir"

    # Check if Playwright is available
    if ! command -v npx &>/dev/null; then
        log_error "npx not found, cannot run Playwright"
        return 1
    fi

    # Generate a temporary Playwright script
    local script_file
    script_file=$(mktemp /tmp/zapat-screenshot-XXXXXX.mjs)

    cat > "$script_file" << 'PLAYWRIGHT_EOF'
import { chromium } from 'playwright';

const port = process.argv[2];
const pages = process.argv[3].split(',');
const viewports = process.argv[4].split(',');
const outputDir = process.argv[5];

const browser = await chromium.launch({ headless: true });

for (const viewport of viewports) {
    const [width, height] = viewport.split('x').map(Number);
    const context = await browser.newContext({
        viewport: { width, height },
        deviceScaleFactor: 1,
    });

    for (const page of pages) {
        const p = await context.newPage();
        const url = `http://localhost:${port}${page}`;
        try {
            await p.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
            // Wait a bit for any animations to settle
            await p.waitForTimeout(1000);
            const filename = `${page.replace(/\//g, '_').replace(/^_/, '') || 'index'}_${viewport}.png`;
            await p.screenshot({ path: `${outputDir}/${filename}`, fullPage: true });
            console.log(`Captured: ${filename}`);
        } catch (e) {
            console.error(`Failed to capture ${url}: ${e.message}`);
        }
        await p.close();
    }

    await context.close();
}

await browser.close();
PLAYWRIGHT_EOF

    # Run the screenshot script
    log_info "Capturing screenshots: pages=${pages}, viewports=${viewports}"
    if npx playwright test --config=/dev/null 2>/dev/null; then
        true  # playwright installed
    fi

    if node "$script_file" "$port" "$pages" "$viewports" "$output_dir" 2>&1; then
        local count
        count=$(find "$output_dir" -name "*.png" -type f 2>/dev/null | wc -l | tr -d ' ')
        log_info "Captured $count screenshots in $output_dir"
        rm -f "$script_file"
        return 0
    else
        log_error "Screenshot capture failed"
        rm -f "$script_file"
        return 1
    fi
}

# Get the dev server command for a repo.
# Checks repos.conf for per-repo overrides, falls back to defaults.
# Usage: get_dev_server_cmd "repo" "worktree_dir"
# Sets: VISUAL_DEV_CMD, VISUAL_DEV_PORT, VISUAL_PAGES
# shellcheck disable=SC2034  # VISUAL_* vars are used by callers
get_dev_server_config() {
    local repo="$1" worktree_dir="$2"

    # Defaults
    VISUAL_DEV_CMD="npm run dev"
    VISUAL_DEV_PORT="3000"
    VISUAL_PAGES="${VISUAL_VERIFY_PAGES:-/}"

    # Check for per-repo visual.conf
    local project="${CURRENT_PROJECT:-default}"
    local repo_slug="${repo//\//-}"
    local visual_conf="${AUTOMATION_DIR}/config/${project}/visual-${repo_slug}.conf"

    if [[ -f "$visual_conf" ]]; then
        # Source per-repo config
        while IFS='=' read -r key value; do
            [[ -z "$key" || "$key" == \#* ]] && continue
            case "$key" in
                DEV_SERVER_CMD)  VISUAL_DEV_CMD="$value" ;;
                DEV_SERVER_PORT) VISUAL_DEV_PORT="$value" ;;
                SCREENSHOT_PAGES) VISUAL_PAGES="$value" ;;
            esac
        done < "$visual_conf"
    else
        # Auto-detect from package.json
        if [[ -f "$worktree_dir/package.json" ]]; then
            local has_dev
            has_dev=$(jq -r '.scripts.dev // empty' "$worktree_dir/package.json" 2>/dev/null)
            if [[ -n "$has_dev" ]]; then
                VISUAL_DEV_CMD="npm run dev"
            fi

            # Detect port from common frameworks
            local dev_script
            dev_script=$(jq -r '.scripts.dev // ""' "$worktree_dir/package.json" 2>/dev/null)
            if echo "$dev_script" | grep -q "3001"; then
                VISUAL_DEV_PORT="3001"
            elif echo "$dev_script" | grep -q "5173"; then
                VISUAL_DEV_PORT="5173"
            fi
        fi
    fi
}
