#!/usr/bin/env bash
#
# setup.sh - turn every project folder of the session 1 repository into its own git repository,
# on macOS, Linux or Git Bash.
#
#   1. Checks that git works and that this folder is not inside another git repository
#   2. Removes the .git of this folder, after asking: the clone's history goes, every file stays
#   3. git init and a first commit in 1-vibecoding/, 2-vibecoding/ and 3-vibecoding/
#
# One repository per project keeps the agent away from your other rounds: Copilot CLI and worktree sessions
# work from the git root. Safe to run again: a project that is already a repository is left alone.
#
# Usage: ./setup.sh

# This script relies on bashisms ([[ ]], local, arrays). Refuse a plain POSIX sh with a friendly
# line instead of an opaque syntax error.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run this script with bash:  bash setup.sh" >&2
  exit 1
fi

set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIRECTORY"

PROJECT_FOLDERS=("1-vibecoding" "2-vibecoding" "3-vibecoding")
FIRST_COMMIT_MESSAGE="Starter"
FALLBACK_AUTHOR_NAME="Duinzicht workshop"
FALLBACK_AUTHOR_EMAIL="workshop@duinzicht.example"

for argument in "$@"; do
  case "$argument" in
    -h|--help) echo "Usage: ./setup.sh"; exit 0 ;;
    *)         printf 'Unknown option: %s\nUsage: ./setup.sh\n' "$argument" >&2; exit 1 ;;
  esac
done

# --- Output helpers --------------------------------------------------------
bold() { printf '\033[1m%s\033[0m\n' "$1"; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
info() { printf '\033[36m•\033[0m %s\n' "$1"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
error_message() { printf '\033[31m✗\033[0m %s\n' "$1" >&2; }

# offer "question" -> 0 when the answer is yes. No terminal to answer from counts as no.
offer() {
  local answer=""
  read -r -p "  $1 [y/N] " answer || true
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

bold "Splitting the session 1 repository into one repository per project"

# --- 1. Checks ---------------------------------------------------------------
step "1/3 Checks"
if ! command -v git >/dev/null 2>&1; then
  error_message "git was not found. Install it from https://git-scm.com and run ./setup.sh again."
  exit 1
fi
ok "$(git --version) works."

for project_folder in "${PROJECT_FOLDERS[@]}"; do
  if [ ! -d "$project_folder" ]; then
    error_message "The folder $project_folder is missing. Run this script from the session 1 repository folder."
    exit 1
  fi
done

# Nested repositories inside someone else's repository would turn up there as embedded repositories.
if enclosing_repository="$(git -C "$SCRIPT_DIRECTORY/.." rev-parse --show-toplevel 2>/dev/null)"; then
  error_message "This folder is inside another git repository: $enclosing_repository"
  info "Copy the folder somewhere outside that repository and run ./setup.sh there."
  exit 1
fi
ok "This folder is not inside another git repository."

# --- 2. Remove the repository of this folder -----------------------------------
step "2/3 Remove the repository of this folder"
if [ -e ".git" ]; then
  info "Every project gets its own repository, so the agent stays inside its project folder."
  info "This removes $SCRIPT_DIRECTORY/.git: the history of this clone goes, every file stays."
  if ! offer "Remove it now?"; then
    error_message "Nothing changed. Run ./setup.sh again when you are ready."
    exit 1
  fi
  rm -rf ".git"
  ok "Removed."
else
  ok "This folder is no repository any more."
fi

# --- 3. One repository per project --------------------------------------------------
step "3/3 One repository per project"
commit_identity=()
if [ -z "$(git config --get user.name || true)" ] || [ -z "$(git config --get user.email || true)" ]; then
  info "git has no name and email set up, so the first commits use \"$FALLBACK_AUTHOR_NAME\"."
  info "Set your own for later commits:  git config --global user.name \"Your Name\""
  commit_identity=(-c "user.name=$FALLBACK_AUTHOR_NAME" -c "user.email=$FALLBACK_AUTHOR_EMAIL")
fi

for project_folder in "${PROJECT_FOLDERS[@]}"; do
  if [ -e "$project_folder/.git" ]; then
    ok "$project_folder is already its own repository."
    continue
  fi
  # symbolic-ref instead of init --initial-branch, which git before 2.28 does not know.
  if git -C "$project_folder" init --quiet &&
     git -C "$project_folder" symbolic-ref HEAD refs/heads/main &&
     git -C "$project_folder" add --all &&
     git -C "$project_folder" ${commit_identity[@]+"${commit_identity[@]}"} commit --quiet --message "$FIRST_COMMIT_MESSAGE"; then
    ok "$project_folder is its own repository, with a first commit on main."
  else
    error_message "Making $project_folder a repository failed. Read the messages above and run ./setup.sh again."
    exit 1
  fi
done

echo
info "Next: open the folder of your round in VS Code, never this root folder."
