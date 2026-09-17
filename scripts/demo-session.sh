#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/repo-maintenance-demo.XXXXXX")"
DEMO_REPO="$SESSION_ROOT/demo-project"

cleanup() {
  case "$SESSION_ROOT" in
    "${TMPDIR:-/tmp}"/repo-maintenance-demo.*)
      rm -rf -- "$SESSION_ROOT"
      ;;
  esac
}

trap cleanup EXIT

mkdir -p "$DEMO_REPO"
cd "$DEMO_REPO"

npm init --yes >/dev/null
npm install --package-lock-only --ignore-scripts --save-exact ansi-regex@5.0.0 >/dev/null
npm pkg set 'dependencies.ansi-regex=^5.0.0' >/dev/null
npm pkg set 'scripts.test=node -e "console.log(\"tests: ok\")"' >/dev/null
npm pkg set 'scripts.build=node -e "console.log(\"build: ok\")"' >/dev/null

git init --quiet
git config user.name "Demo User"
git config user.email "demo@example.invalid"
git add package.json package-lock.json
git commit --quiet -m "chore: initial demo lockfile"

INITIAL_HEAD="$(git rev-parse --short HEAD)"
INITIAL_LOCK_VERSION="$(node -p "require('./package-lock.json').packages['node_modules/ansi-regex'].version")"

printf 'Demo project: ansi-regex %s, clean working tree\n\n' "$INITIAL_LOCK_VERSION"

REPO_MAINTENANCE_DRY_RUN=1 \
LOG_FILE="$SESSION_ROOT/repo-maintenance.log" \
CHECKPOINT_DIR="$SESSION_ROOT/checkpoints" \
  "$PROJECT_ROOT/auto-commit.sh" "$DEMO_REPO"

FINAL_HEAD="$(git rev-parse --short HEAD)"
FINAL_LOCK_VERSION="$(node -p "require('./package-lock.json').packages['node_modules/ansi-regex'].version")"
WORKTREE_STATE="dirty"

if [[ -z "$(git status --porcelain)" ]]; then
  WORKTREE_STATE="clean"
fi

printf '\nSource verification\n'
printf '  HEAD unchanged: %s\n' "$([[ "$INITIAL_HEAD" == "$FINAL_HEAD" ]] && echo yes || echo no)"
printf '  Working tree:   %s\n' "$WORKTREE_STATE"
printf '  Source lock:    %s (unchanged)\n' "$FINAL_LOCK_VERSION"
