#!/usr/bin/env bash

# Repo Maintenance Bot
# Safely updates npm lockfiles, validates the resulting dependency tree in an
# isolated clone, and commits only the validated lockfile.

set -euo pipefail
umask 077

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/repo-maintenance-bot"
CHECKPOINT_DIR="${CHECKPOINT_DIR:-$STATE_DIR/checkpoints}"
LOG_FILE="${LOG_FILE:-$STATE_DIR/repo-maintenance.log}"
DRY_RUN="${REPO_MAINTENANCE_DRY_RUN:-${STREAK_KEEPER_DRY_RUN:-0}}"
PUSH_CHANGES="${REPO_MAINTENANCE_PUSH:-${STREAK_KEEPER_PUSH:-0}}"
SKIP_TESTS="${REPO_MAINTENANCE_SKIP_TESTS:-${STREAK_KEEPER_SKIP_TESTS:-0}}"
ALLOW_INSTALL_SCRIPTS="${REPO_MAINTENANCE_ALLOW_INSTALL_SCRIPTS:-0}"
TEMP_ROOT="${TMPDIR:-/tmp}"
ACTIVE_SANDBOX=""
SANDBOX_REPO=""

log() {
    local message="$1"

    message="${message//$'\r'/ }"
    message="${message//$'\n'/ }"
    message="${message//$'\e'/}"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" | tee -a "$LOG_FILE"
}

validate_flag() {
    local name="$1"
    local value="$2"

    if [[ "$value" != "0" && "$value" != "1" ]]; then
        printf 'Error: %s must be 0 or 1 (received %q).\n' "$name" "$value" >&2
        return 1
    fi
}

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        log "❌ Required command not found: $command_name"
        return 1
    fi
}

cleanup_active_sandbox() {
    if [[ -z "$ACTIVE_SANDBOX" || ! -d "$ACTIVE_SANDBOX" ]]; then
        return 0
    fi

    case "$ACTIVE_SANDBOX" in
        "${TEMP_ROOT%/}"/repo-maintenance-bot.*)
            if ! rm -rf -- "$ACTIVE_SANDBOX"; then
                printf 'Could not remove sandbox path: %s\n' "$ACTIVE_SANDBOX" >&2
                return 1
            fi
            ACTIVE_SANDBOX=""
            ;;
        *)
            printf 'Refusing to remove unexpected sandbox path: %s\n' "$ACTIVE_SANDBOX" >&2
            return 1
            ;;
    esac
}

trap cleanup_active_sandbox EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

repo_checkpoint_file() {
    local repo_path="$1"
    local repo_name
    local repo_id

    repo_name="$(basename "$repo_path")"
    repo_name="${repo_name//[^a-zA-Z0-9._-]/_}"
    repo_id="$(printf '%s' "$repo_path" | cksum | awk '{print $1}')"
    printf '%s/.checkpoint-%s-%s-%s\n' "$CHECKPOINT_DIR" "$repo_name" "$repo_id" "$(date '+%Y-%m-%d')"
}

check_checkpoint() {
    local repo_path="$1"
    local checkpoint_file

    checkpoint_file="$(repo_checkpoint_file "$repo_path")"
    if [[ -f "$checkpoint_file" ]]; then
        log "⏭️  Skip: $(basename "$repo_path") was already processed today"
        return 1
    fi
}

create_checkpoint() {
    local repo_path="$1"
    local checkpoint_file

    checkpoint_file="$(repo_checkpoint_file "$repo_path")"
    if ! touch "$checkpoint_file"; then
        log "❌ Could not create checkpoint: $checkpoint_file"
        return 1
    fi
    log "✅ Checkpoint created: $checkpoint_file"
}

repo_is_clean() {
    local repo_path="$1"
    local status

    if ! status="$(git -C "$repo_path" status --porcelain --untracked-files=all)"; then
        return 1
    fi
    [[ -z "$status" ]]
}

has_npm_script() {
    local repo_path="$1"
    local script_name="$2"

    node - "$repo_path/package.json" "$script_name" <<'NODE' >/dev/null 2>&1
const fs = require('node:fs');
const [packagePath, scriptName] = process.argv.slice(2);
const pkg = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
process.exit(pkg.scripts && pkg.scripts[scriptName] ? 0 : 1);
NODE
}

detect_npm_lockfile() {
    local repo_path="$1"

    if [[ -f "$repo_path/package-lock.json" ]]; then
        printf 'package-lock.json\n'
        return 0
    fi

    if [[ -f "$repo_path/npm-shrinkwrap.json" ]]; then
        printf 'npm-shrinkwrap.json\n'
        return 0
    fi

    return 1
}

create_sandbox_clone() {
    local repo_path="$1"

    if ! ACTIVE_SANDBOX="$(mktemp -d "${TEMP_ROOT%/}/repo-maintenance-bot.XXXXXX")"; then
        log "❌ Could not create an isolated temporary directory"
        return 1
    fi
    if ! git clone --quiet --no-local "$repo_path" "$ACTIVE_SANDBOX/repo"; then
        log "❌ Could not create isolated clone for $(basename "$repo_path")"
        cleanup_active_sandbox
        return 1
    fi

    if ! git -C "$ACTIVE_SANDBOX/repo" remote remove origin; then
        log "❌ Could not disconnect the isolated clone from its source"
        cleanup_active_sandbox
        return 1
    fi

    SANDBOX_REPO="$ACTIVE_SANDBOX/repo"
}

apply_npm_maintenance() {
    local sandbox_repo="$1"
    local lockfile="$2"

    log "📦 Checking safe npm lockfile updates"
    if ! (cd "$sandbox_repo" && npm update --package-lock-only --ignore-scripts); then
        log "❌ npm could not update $lockfile"
        return 1
    fi

    if git -C "$sandbox_repo" diff --quiet -- "$lockfile"; then
        return 2
    fi

    local changed_file
    while IFS= read -r -d '' changed_file; do
        if [[ "$changed_file" != "$lockfile" ]]; then
            log "❌ Maintenance unexpectedly changed $changed_file; refusing the update"
            return 1
        fi
    done < <(
        git -C "$sandbox_repo" diff --name-only -z
        git -C "$sandbox_repo" ls-files --others --exclude-standard -z
    )
}

install_updated_dependencies() {
    local sandbox_repo="$1"
    local -a npm_ci_args=(ci)

    if [[ "$ALLOW_INSTALL_SCRIPTS" != "1" ]]; then
        npm_ci_args+=(--ignore-scripts)
    fi

    log "📥 Installing the updated dependency tree in the isolated clone"
    if ! (cd "$sandbox_repo" && npm "${npm_ci_args[@]}"); then
        log "❌ npm ci failed for the updated lockfile"
        return 1
    fi
}

run_validation() {
    local sandbox_repo="$1"

    if [[ "$SKIP_TESTS" == "1" ]]; then
        log "⏭️  Validation skipped by REPO_MAINTENANCE_SKIP_TESTS=1"
        return 0
    fi

    if has_npm_script "$sandbox_repo" test; then
        log "🧪 Running npm test"
        if ! (cd "$sandbox_repo" && npm test); then
            log "❌ npm test failed"
            return 1
        fi
    fi

    if has_npm_script "$sandbox_repo" build; then
        log "🏗️  Running npm run build"
        if ! (cd "$sandbox_repo" && npm run build); then
            log "❌ npm run build failed"
            return 1
        fi
    fi
}

show_candidate_diff() {
    local sandbox_repo="$1"
    local lockfile="$2"
    git -C "$sandbox_repo" diff --stat -- "$lockfile" | tee -a "$LOG_FILE"
}

apply_validated_lockfile() {
    local repo_path="$1"
    local sandbox_repo="$2"
    local lockfile="$3"
    local initial_head="$4"

    if [[ "$(git -C "$repo_path" rev-parse HEAD)" != "$initial_head" ]] || ! repo_is_clean "$repo_path"; then
        log "❌ The source repository changed during validation; refusing to apply the result"
        return 1
    fi

    if ! cp -- "$sandbox_repo/$lockfile" "$repo_path/$lockfile"; then
        log "❌ Could not copy the validated $lockfile"
        return 1
    fi

    if ! git -C "$repo_path" add -- "$lockfile"; then
        git -C "$repo_path" restore --worktree -- "$lockfile" || true
        log "❌ Could not stage $lockfile"
        return 1
    fi
}

restore_lockfile() {
    local repo_path="$1"
    local lockfile="$2"
    git -C "$repo_path" restore --staged --worktree -- "$lockfile" >/dev/null 2>&1 || true
}

process_repo() {
    local input_path="$1"
    local repo_path repo_name initial_head lockfile sandbox_repo
    local candidate_lock_checksum final_lock_checksum

    if [[ ! -d "$input_path" ]]; then
        log "❌ Directory does not exist: $input_path"
        return 1
    fi

    if ! repo_path="$(git -C "$input_path" rev-parse --show-toplevel 2>/dev/null)"; then
        log "❌ Not a Git repository: $input_path"
        return 1
    fi

    repo_name="$(basename "$repo_path")"
    log "🔍 Evaluating repository: $repo_name"

    if ! repo_is_clean "$repo_path"; then
        log "⚠️  Skip: $repo_name has unreviewed local changes"
        return 0
    fi

    if ! check_checkpoint "$repo_path"; then
        return 0
    fi

    if [[ ! -f "$repo_path/package.json" ]]; then
        log "ℹ️  No supported maintainer applies to $repo_name"
        return 0
    fi

    if ! lockfile="$(detect_npm_lockfile "$repo_path")"; then
        log "ℹ️  package.json found without an npm lockfile; nothing changed"
        return 0
    fi

    if ! initial_head="$(git -C "$repo_path" rev-parse HEAD)"; then
        log "❌ Repository has no commit to maintain: $repo_name"
        return 1
    fi
    if ! create_sandbox_clone "$repo_path"; then
        return 1
    fi
    sandbox_repo="$SANDBOX_REPO"

    local maintenance_status=0
    apply_npm_maintenance "$sandbox_repo" "$lockfile" || maintenance_status=$?
    if [[ "$maintenance_status" -eq 2 ]]; then
        log "✅ No lockfile updates needed for $repo_name"
        cleanup_active_sandbox
        return 0
    fi
    if [[ "$maintenance_status" -ne 0 ]]; then
        cleanup_active_sandbox
        return 1
    fi

    if ! candidate_lock_checksum="$(cksum <"$sandbox_repo/$lockfile")"; then
        log "❌ Could not fingerprint the candidate lockfile"
        cleanup_active_sandbox
        return 1
    fi

    if ! install_updated_dependencies "$sandbox_repo"; then
        cleanup_active_sandbox
        return 1
    fi

    if ! run_validation "$sandbox_repo"; then
        log "❌ Validation failed; the source repository was not modified"
        cleanup_active_sandbox
        return 1
    fi

    if ! final_lock_checksum="$(cksum <"$sandbox_repo/$lockfile")"; then
        log "❌ Could not verify the lockfile after validation"
        cleanup_active_sandbox
        return 1
    fi
    if [[ "$candidate_lock_checksum" != "$final_lock_checksum" ]]; then
        log "❌ Validation changed the lockfile after dependencies were installed; refusing the result"
        cleanup_active_sandbox
        return 1
    fi

    log "📝 Validated lockfile update:"
    if ! show_candidate_diff "$sandbox_repo" "$lockfile"; then
        log "❌ Could not summarize the validated lockfile"
        cleanup_active_sandbox
        return 1
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        log "🧪 DRY RUN: validation passed; the source repository remains unchanged"
        cleanup_active_sandbox
        return 0
    fi

    if ! apply_validated_lockfile "$repo_path" "$sandbox_repo" "$lockfile" "$initial_head"; then
        cleanup_active_sandbox
        return 1
    fi
    cleanup_active_sandbox

    if ! git -C "$repo_path" commit --only -m "build: update npm dependency lockfile" -- "$lockfile"; then
        restore_lockfile "$repo_path" "$lockfile"
        log "❌ Commit failed; restored $repo_name"
        return 1
    fi

    if ! create_checkpoint "$repo_path"; then
        log "❌ Commit exists, but the daily checkpoint could not be recorded"
        return 1
    fi
    log "✅ Created a validated maintenance commit in $repo_name"

    if [[ "$PUSH_CHANGES" == "1" ]]; then
        if ! git -C "$repo_path" push; then
            log "❌ Push failed; the validated commit remains local"
            return 1
        fi
        log "🚀 Pushed the validated commit for $repo_name"
    else
        log "ℹ️  Push disabled; set REPO_MAINTENANCE_PUSH=1 to enable it"
    fi
}

main() {
    validate_flag REPO_MAINTENANCE_DRY_RUN "$DRY_RUN"
    validate_flag REPO_MAINTENANCE_PUSH "$PUSH_CHANGES"
    validate_flag REPO_MAINTENANCE_SKIP_TESTS "$SKIP_TESTS"
    validate_flag REPO_MAINTENANCE_ALLOW_INSTALL_SCRIPTS "$ALLOW_INSTALL_SCRIPTS"

    mkdir -p "$CHECKPOINT_DIR" "$(dirname "$LOG_FILE")"

    require_command git
    require_command node
    require_command npm
    require_command mktemp
    require_command cksum

    if [[ "$#" -eq 0 ]]; then
        printf 'Usage: %s /path/to/repo1 [/path/to/repo2 ...]\n' "$0" >&2
        return 1
    fi

    log "🚀 Starting Repo Maintenance Bot"

    local success_count=0
    local fail_count=0
    local repo
    for repo in "$@"; do
        if process_repo "$repo"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done

    log "📊 Summary: $success_count processed, $fail_count failed"
    if [[ "$fail_count" -gt 0 ]]; then
        return 1
    fi
}

main "$@"
