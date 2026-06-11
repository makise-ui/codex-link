#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/update-host.sh [options]

Updates the Codex Link host from the current git remote, reinstalls workspace
dependencies, rebuilds the host package, and optionally restarts the running
host service.

Options:
  --allow-dirty              Continue even when the git working tree is dirty.
  --dry-run                  Print commands without changing files.
  --skip-pull                Do not fetch or pull from git.
  --skip-install             Do not run pnpm install.
  --skip-build               Do not rebuild the host package.
  --with-tests               Run the host test suite after building.
  --restart-command <cmd>    Command to run after a successful update.
  -h, --help                 Show this help.

Environment:
  CODEX_LINK_RESTART_COMMAND Optional restart command used when
                             --restart-command is not provided.

Examples:
  scripts/update-host.sh
  scripts/update-host.sh --with-tests
  scripts/update-host.sh --restart-command "systemctl --user restart codex-link"
EOF
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

allow_dirty=0
dry_run=0
skip_pull=0
skip_install=0
skip_build=0
with_tests=0
restart_command="${CODEX_LINK_RESTART_COMMAND:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-dirty)
      allow_dirty=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --skip-pull)
      skip_pull=1
      shift
      ;;
    --skip-install)
      skip_install=1
      shift
      ;;
    --skip-build)
      skip_build=1
      shift
      ;;
    --with-tests)
      with_tests=1
      shift
      ;;
    --restart-command)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --restart-command requires a command string" >&2
        exit 2
      fi
      restart_command="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  if [[ "$dry_run" -eq 0 ]]; then
    "$@"
  fi
}

run_shell() {
  echo "+ $1"
  if [[ "$dry_run" -eq 0 ]]; then
    bash -lc "$1"
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

require_command git
require_command pnpm

cd "$repo_root"

if [[ ! -f package.json || ! -f pnpm-workspace.yaml || ! -d host ]]; then
  echo "error: script must run from the Codex Link repository layout" >&2
  exit 1
fi

dirty_status="$(git status --porcelain)"
if [[ "$allow_dirty" -eq 0 && -n "$dirty_status" && "$dry_run" -eq 0 ]]; then
  echo "error: working tree is dirty; commit/stash changes or pass --allow-dirty" >&2
  git status --short >&2
  exit 1
fi
if [[ "$allow_dirty" -eq 0 && -n "$dirty_status" && "$dry_run" -eq 1 ]]; then
  echo "warning: working tree is dirty; a real update would stop here unless --allow-dirty is passed" >&2
  git status --short >&2
fi

current_revision="$(git rev-parse --short HEAD)"
echo "Codex Link host updater"
echo "Repository: $repo_root"
echo "Current revision: $current_revision"

if [[ "$skip_pull" -eq 0 ]]; then
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [[ -z "$upstream" ]]; then
    echo "error: current branch has no upstream; pass --skip-pull for local rebuilds" >&2
    exit 1
  fi
  run git fetch --tags --prune
  run git pull --ff-only
fi

if [[ "$skip_install" -eq 0 ]]; then
  run pnpm install --frozen-lockfile
fi

if [[ "$skip_build" -eq 0 ]]; then
  run pnpm --dir host build
fi

if [[ "$with_tests" -eq 1 ]]; then
  run pnpm --dir host test
fi

updated_revision="$(git rev-parse --short HEAD)"
echo "Updated revision: $updated_revision"

if [[ -n "$restart_command" ]]; then
  run_shell "$restart_command"
else
  echo "No restart command configured; restart the host process manually if it is already running."
fi

echo "Host update complete."
