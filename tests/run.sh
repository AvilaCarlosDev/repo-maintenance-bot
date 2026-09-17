#!/usr/bin/env bash
# shellcheck disable=SC2317 # Test cases are invoked indirectly by run_test.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOT="$PROJECT_ROOT/auto-commit.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/repo-maintenance-tests.XXXXXX")"
ORIGINAL_PATH="$PATH"
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
    case "$TEST_ROOT" in
        "${TMPDIR:-/tmp}"/repo-maintenance-tests.*) rm -rf -- "$TEST_ROOT" ;;
        *) printf 'Refusing to remove unexpected test path: %s\n' "$TEST_ROOT" >&2 ;;
    esac
}
trap cleanup EXIT INT TERM

mkdir -p "$TEST_ROOT/bin"

cat >"$TEST_ROOT/bin/npm" <<'FAKE_NPM'
#!/usr/bin/env bash
set -u

command_name="${1:-}"
if [[ -n "${FAKE_NPM_CALL_LOG:-}" ]]; then
    printf '%s\n' "$*" >>"$FAKE_NPM_CALL_LOG"
fi
case "$command_name" in
    update)
        case "${FAKE_NPM_UPDATE:-change}" in
            change)
                lockfile="package-lock.json"
                [[ -f npm-shrinkwrap.json ]] && lockfile="npm-shrinkwrap.json"
                printf '{"name":"fixture","lockfileVersion":3,"updated":true}\n' >"$lockfile"
                ;;
            none) ;;
            unexpected)
                printf '{"name":"fixture","lockfileVersion":3,"updated":true}\n' >package-lock.json
                printf '{"name":"unexpected"}\n' >package.json
                ;;
            untracked)
                printf '{"name":"fixture","lockfileVersion":3,"updated":true}\n' >package-lock.json
                printf 'unexpected\n' >untracked.txt
                ;;
            fail) exit 9 ;;
        esac
        ;;
    ci)
        mkdir -p node_modules
        if [[ -n "${FAKE_SOURCE_REPO:-}" ]]; then
            printf 'concurrent user change\n' >"$FAKE_SOURCE_REPO/concurrent.txt"
        fi
        exit "${FAKE_NPM_CI_EXIT:-0}"
        ;;
    test)
        if [[ "${FAKE_NPM_MUTATE_LOCK:-0}" == "1" ]]; then
            printf '{"name":"fixture","lockfileVersion":3,"mutatedByTest":true}\n' >package-lock.json
        fi
        exit "${FAKE_NPM_TEST_EXIT:-0}"
        ;;
    run)
        if [[ "${2:-}" == "build" ]]; then
            if [[ "${FAKE_NPM_BUILD_OUTPUT:-0}" == "1" ]]; then
                printf 'generated\n' >build-output.txt
            fi
            exit "${FAKE_NPM_BUILD_EXIT:-0}"
        fi
        ;;
esac
FAKE_NPM
chmod +x "$TEST_ROOT/bin/npm"

create_fixture() {
    local name="$1"
    local repo="$TEST_ROOT/$name"

    mkdir -p "$repo"
    git -C "$repo" init -q -b main
    git -C "$repo" config user.name "Test User"
    git -C "$repo" config user.email "test@example.invalid"

    cat >"$repo/package.json" <<'JSON'
{
  "name": "fixture",
  "version": "1.0.0",
  "scripts": {
    "test": "fixture-test",
    "build": "fixture-build"
  }
}
JSON
    printf '{"name":"fixture","lockfileVersion":3,"updated":false}\n' >"$repo/package-lock.json"
    printf '# fixture\n' >"$repo/README.md"
    git -C "$repo" add .
    git -C "$repo" commit -q -m "initial"
    printf '%s\n' "$repo"
}

run_bot() {
    local case_name="$1"
    local repo="$2"
    local -a environment
    shift 2

    environment=(
        "PATH=$TEST_ROOT/bin:$ORIGINAL_PATH"
        "CHECKPOINT_DIR=$TEST_ROOT/checkpoints-$case_name"
        "LOG_FILE=$TEST_ROOT/$case_name.log"
    )
    env "${environment[@]}" "$@" "$BOT" "$repo" >"$TEST_ROOT/$case_name.output" 2>&1
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    if [[ "$expected" != "$actual" ]]; then
        printf '  expected: %q\n  actual:   %q\n  %s\n' "$expected" "$actual" "$message" >&2
        return 1
    fi
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    if ! grep -Fq -- "$pattern" "$file"; then
        printf '  missing %q in %s\n' "$pattern" "$file" >&2
        return 1
    fi
}

test_dry_run_is_non_mutating() {
    local repo head_before lock_before
    repo="$(create_fixture dry-run)"
    head_before="$(git -C "$repo" rev-parse HEAD)"
    lock_before="$(cat "$repo/package-lock.json")"

    run_bot dry-run "$repo" REPO_MAINTENANCE_DRY_RUN=1 || return 1
    assert_eq "$head_before" "$(git -C "$repo" rev-parse HEAD)" "dry-run created a commit" || return 1
    assert_eq "$lock_before" "$(cat "$repo/package-lock.json")" "dry-run changed the lockfile" || return 1
    assert_eq "" "$(git -C "$repo" status --porcelain)" "dry-run left worktree changes" || return 1
    assert_contains "$TEST_ROOT/dry-run.output" "source repository remains unchanged"
}

test_failed_test_cannot_be_hidden_by_build() {
    local repo head_before
    repo="$(create_fixture test-failure)"
    head_before="$(git -C "$repo" rev-parse HEAD)"

    if run_bot test-failure "$repo" FAKE_NPM_TEST_EXIT=7 FAKE_NPM_BUILD_EXIT=0; then
        printf '  bot succeeded despite a failed test\n' >&2
        return 1
    fi
    assert_eq "$head_before" "$(git -C "$repo" rev-parse HEAD)" "failed test created a commit" || return 1
    assert_eq "" "$(git -C "$repo" status --porcelain)" "failed test changed source repo" || return 1
    assert_contains "$TEST_ROOT/test-failure.output" "npm test failed"
}

test_failed_build_is_rejected() {
    local repo head_before
    repo="$(create_fixture build-failure)"
    head_before="$(git -C "$repo" rev-parse HEAD)"

    if run_bot build-failure "$repo" FAKE_NPM_BUILD_EXIT=8; then
        printf '  bot succeeded despite a failed build\n' >&2
        return 1
    fi
    assert_eq "$head_before" "$(git -C "$repo" rev-parse HEAD)" "failed build created a commit" || return 1
    assert_eq "" "$(git -C "$repo" status --porcelain)" "failed build changed source repo" || return 1
    assert_contains "$TEST_ROOT/build-failure.output" "npm run build failed"
}

test_success_commits_only_lockfile() {
    local repo changed_files
    repo="$(create_fixture success)"

    run_bot success "$repo" FAKE_NPM_BUILD_OUTPUT=1 || return 1
    changed_files="$(git -C "$repo" show --pretty='' --name-only HEAD)"
    assert_eq "package-lock.json" "$changed_files" "commit included files beyond the lockfile" || return 1
    [[ ! -e "$repo/build-output.txt" ]] || return 1
    assert_contains "$TEST_ROOT/success.output" "Created a validated maintenance commit"
}

test_dirty_repo_is_skipped() {
    local repo head_before
    repo="$(create_fixture dirty)"
    head_before="$(git -C "$repo" rev-parse HEAD)"
    printf 'local work\n' >>"$repo/README.md"

    run_bot dirty "$repo" || return 1
    assert_eq "$head_before" "$(git -C "$repo" rev-parse HEAD)" "dirty repo received a commit" || return 1
    assert_contains "$TEST_ROOT/dirty.output" "has unreviewed local changes"
}

test_no_diff_creates_no_commit() {
    local repo head_before
    repo="$(create_fixture no-diff)"
    head_before="$(git -C "$repo" rev-parse HEAD)"

    run_bot no-diff "$repo" FAKE_NPM_UPDATE=none || return 1
    assert_eq "$head_before" "$(git -C "$repo" rev-parse HEAD)" "no-diff run created a commit" || return 1
    assert_eq "" "$(git -C "$repo" status --porcelain)" "no-diff run changed source repo" || return 1
    assert_contains "$TEST_ROOT/no-diff.output" "No lockfile updates needed"
}

test_unexpected_maintenance_files_are_rejected() {
    local repo head_before
    repo="$(create_fixture unexpected)"
    head_before="$(git -C "$repo" rev-parse HEAD)"

    if run_bot unexpected "$repo" FAKE_NPM_UPDATE=unexpected; then
        printf '  bot accepted an unexpected package.json change\n' >&2
        return 1
    fi
    assert_eq "$head_before" "$(git -C "$repo" rev-parse HEAD)" "unexpected files created a commit" || return 1
    assert_eq "" "$(git -C "$repo" status --porcelain)" "unexpected files changed source repo" || return 1
    assert_contains "$TEST_ROOT/unexpected.output" "unexpectedly changed package.json"
}

test_checkpoint_prevents_second_run() {
    local repo head_after_first
    repo="$(create_fixture checkpoint)"

    run_bot checkpoint "$repo" || return 1
    head_after_first="$(git -C "$repo" rev-parse HEAD)"
    run_bot checkpoint "$repo" || return 1
    assert_eq "$head_after_first" "$(git -C "$repo" rev-parse HEAD)" "checkpoint allowed a second commit" || return 1
    assert_contains "$TEST_ROOT/checkpoint.output" "was already processed today"
}

test_install_scripts_require_opt_in() {
    local default_repo opt_in_repo
    default_repo="$(create_fixture scripts-default)"
    opt_in_repo="$(create_fixture scripts-opt-in)"

    run_bot scripts-default "$default_repo" \
        REPO_MAINTENANCE_DRY_RUN=1 \
        FAKE_NPM_CALL_LOG="$TEST_ROOT/scripts-default.calls" || return 1
    assert_contains "$TEST_ROOT/scripts-default.calls" "ci --ignore-scripts" || return 1

    run_bot scripts-opt-in "$opt_in_repo" \
        REPO_MAINTENANCE_DRY_RUN=1 \
        REPO_MAINTENANCE_ALLOW_INSTALL_SCRIPTS=1 \
        FAKE_NPM_CALL_LOG="$TEST_ROOT/scripts-opt-in.calls" || return 1
    if ! grep -Fxq 'ci' "$TEST_ROOT/scripts-opt-in.calls"; then
        printf '  opt-in run did not call plain npm ci\n' >&2
        return 1
    fi
}

test_concurrent_source_change_is_preserved_and_rejected() {
    local repo head_before lock_before
    repo="$(create_fixture concurrent)"
    head_before="$(git -C "$repo" rev-parse HEAD)"
    lock_before="$(cat "$repo/package-lock.json")"

    if run_bot concurrent "$repo" FAKE_SOURCE_REPO="$repo"; then
        printf '  bot accepted a repository changed during validation\n' >&2
        return 1
    fi
    assert_eq "$head_before" "$(git -C "$repo" rev-parse HEAD)" "concurrent change created a commit" || return 1
    assert_eq "$lock_before" "$(cat "$repo/package-lock.json")" "concurrent change overwrote the lockfile" || return 1
    assert_eq "concurrent user change" "$(cat "$repo/concurrent.txt")" "concurrent user file was lost" || return 1
    assert_contains "$TEST_ROOT/concurrent.output" "source repository changed during validation"
}

test_push_is_explicit_and_functional() {
    local repo remote source_head remote_head
    repo="$(create_fixture push)"
    remote="$TEST_ROOT/push-remote.git"
    git init -q --bare "$remote"
    git -C "$repo" remote add origin "$remote"
    git -C "$repo" push -q -u origin main

    run_bot push "$repo" REPO_MAINTENANCE_PUSH=1 || return 1
    source_head="$(git -C "$repo" rev-parse HEAD)"
    remote_head="$(git --git-dir="$remote" rev-parse refs/heads/main)"
    assert_eq "$source_head" "$remote_head" "explicit push did not update the remote" || return 1
    assert_contains "$TEST_ROOT/push.output" "Pushed the validated commit"
}

test_validation_cannot_replace_tested_lockfile() {
    local repo head_before lock_before
    repo="$(create_fixture lock-mutation)"
    head_before="$(git -C "$repo" rev-parse HEAD)"
    lock_before="$(cat "$repo/package-lock.json")"

    if run_bot lock-mutation "$repo" FAKE_NPM_MUTATE_LOCK=1; then
        printf '  bot accepted a lockfile changed during validation\n' >&2
        return 1
    fi
    assert_eq "$head_before" "$(git -C "$repo" rev-parse HEAD)" "mutated lockfile created a commit" || return 1
    assert_eq "$lock_before" "$(cat "$repo/package-lock.json")" "mutated lockfile reached source repo" || return 1
    assert_contains "$TEST_ROOT/lock-mutation.output" "Validation changed the lockfile"
}

test_untracked_maintenance_files_are_rejected() {
    local repo head_before
    repo="$(create_fixture untracked)"
    head_before="$(git -C "$repo" rev-parse HEAD)"

    if run_bot untracked "$repo" FAKE_NPM_UPDATE=untracked; then
        printf '  bot accepted an unexpected untracked file\n' >&2
        return 1
    fi
    assert_eq "$head_before" "$(git -C "$repo" rev-parse HEAD)" "untracked file created a commit" || return 1
    assert_eq "" "$(git -C "$repo" status --porcelain)" "untracked file reached source repo" || return 1
    assert_contains "$TEST_ROOT/untracked.output" "unexpectedly changed untracked.txt"
}

run_test() {
    local name="$1"
    local function_name="$2"
    if "$function_name"; then
        printf 'ok - %s\n' "$name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        printf 'not ok - %s\n' "$name"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

run_test "dry-run never mutates the source repository" test_dry_run_is_non_mutating
run_test "failed test cannot be hidden by a successful build" test_failed_test_cannot_be_hidden_by_build
run_test "failed build is rejected" test_failed_build_is_rejected
run_test "successful maintenance commits only the lockfile" test_success_commits_only_lockfile
run_test "dirty repositories are skipped" test_dirty_repo_is_skipped
run_test "no diff creates no commit" test_no_diff_creates_no_commit
run_test "unexpected maintenance files are rejected" test_unexpected_maintenance_files_are_rejected
run_test "daily checkpoint prevents a second run" test_checkpoint_prevents_second_run
run_test "install scripts require explicit opt-in" test_install_scripts_require_opt_in
run_test "concurrent source changes are preserved and rejected" test_concurrent_source_change_is_preserved_and_rejected
run_test "push is explicit and functional" test_push_is_explicit_and_functional
run_test "validation cannot replace the installed lockfile" test_validation_cannot_replace_tested_lockfile
run_test "untracked maintenance files are rejected" test_untracked_maintenance_files_are_rejected

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
