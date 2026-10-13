#!/usr/bin/env bash
#
# setup.sh - turn every project folder of the session 1 repository into its own git repository and
# install what the rounds need, on macOS, Linux or Git Bash. Runs unattended.
#
#   1. Checks that git works and that this folder is not inside another git repository
#   2. Removes the .git of this folder when it holds no work that exists nowhere else
#   3. git init and a first commit in 1-vibecoding/, 2-vibecoding/ and 3-vibecoding/
#   4. The Spec Kit CLI for round 3, through 3-vibecoding/setup.sh
#
# One repository per project keeps the agent away from your other rounds: Copilot CLI and worktree sessions
# work from the git root. Safe to run again: a project that already has its first commit is left alone.
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
SPEC_KIT_SETUP_SCRIPT="3-vibecoding/setup.sh"
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

# Prints why removing the .git of this folder would lose work, or nothing when it is safe. Any git
# error counts as unsafe, so a repository git cannot read is never removed blindly.
describe_work_only_in_this_clone() {
  local git_output
  if ! git_output="$(git status --porcelain 2>&1)"; then
    printf 'git cannot read this repository:\n%s\n' "$git_output"; return
  fi
  if [ -n "$git_output" ]; then echo "It has changed or new files."; return; fi
  if [ -n "$(git stash list 2>/dev/null)" ]; then echo "It has stashed changes."; return; fi
  if git rev-parse --verify --quiet HEAD >/dev/null &&
     [ -n "$(git rev-list HEAD --not --remotes 2>/dev/null | head -n 1)" ]; then
    echo "It has commits that are on no remote."
  fi
}

bold "Setting up the session 1 repository: one repository per project, and Spec Kit for round 3"

# --- 1. Checks ---------------------------------------------------------------
step "1/4 Checks"
# On a Mac without the developer tools, /usr/bin/git exists but only offers to install them.
if ! command -v git >/dev/null 2>&1 || ! git_version="$(git --version 2>/dev/null)"; then
  error_message "git does not work yet. Install it from https://git-scm.com (on a Mac: xcode-select --install) and run ./setup.sh again."
  exit 1
fi
ok "$git_version works."

for project_folder in "${PROJECT_FOLDERS[@]}"; do
  if [ ! -d "$project_folder" ]; then
    error_message "The folder $project_folder is missing. Run this script from the session 1 repository folder."
    exit 1
  fi
done

# Nested repositories inside someone else's repository would turn up there as embedded repositories.
# Any answer but "not a git repository" counts as inside one, so an unreadable parent never passes.
if enclosing_output="$(LC_ALL=C git -C "$SCRIPT_DIRECTORY/.." rev-parse --show-toplevel 2>&1)" ||
   ! printf '%s' "$enclosing_output" | grep -qi "not a git repository"; then
  error_message "This folder is inside another git repository, or git cannot tell:"
  printf '%s\n' "$enclosing_output" >&2
  info "Copy the folder somewhere outside that repository and run ./setup.sh there."
  exit 1
fi
ok "This folder is not inside another git repository."

# --- 2. Remove the repository of this folder -----------------------------------
step "2/4 Remove the repository of this folder"
if [ -e ".git" ]; then
  work_only_in_this_clone="$(describe_work_only_in_this_clone)"
  if [ -n "$work_only_in_this_clone" ]; then
    error_message "This folder's repository holds work that exists nowhere else, so setup leaves it alone."
    printf '%s\n' "$work_only_in_this_clone" >&2
    info "Push or remove that work, or clone the repository again in a new folder, and run ./setup.sh there."
    exit 1
  fi
  info "Every project gets its own repository, so the agent stays inside its project folder."
  if ! rm -rf ".git"; then
    error_message "Could not remove $SCRIPT_DIRECTORY/.git. Close programs that use this folder and run ./setup.sh again."
    exit 1
  fi
  ok "Removed $SCRIPT_DIRECTORY/.git: the history of this clone is gone, every file stays."
else
  ok "This folder is no repository any more."
fi

# --- 3. One repository per project --------------------------------------------------
step "3/4 One repository per project"
uses_fallback_identity=0
if [ -z "$(git config --get user.name || true)" ] || [ -z "$(git config --get user.email || true)" ]; then
  uses_fallback_identity=1
  info "git has no name and email set up, so the project repositories use \"$FALLBACK_AUTHOR_NAME\"."
  info "Set your own with:  git config --global user.name \"Your Name\""
fi

for project_folder in "${PROJECT_FOLDERS[@]}"; do
  if git -C "$project_folder" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    ok "$project_folder is already its own repository."
    continue
  fi
  # A .git without a commit is what an interrupted run leaves behind; init again finishes it.
  # symbolic-ref instead of init --initial-branch, which git before 2.28 does not know.
  # The first commit skips the user's signing and hooks: a gpg or hook setup must not block it.
  if git -C "$project_folder" init --quiet &&
     git -C "$project_folder" symbolic-ref HEAD refs/heads/main &&
     { [ "$uses_fallback_identity" = 0 ] ||
       { git -C "$project_folder" config user.name "$FALLBACK_AUTHOR_NAME" &&
         git -C "$project_folder" config user.email "$FALLBACK_AUTHOR_EMAIL"; }; } &&
     git -C "$project_folder" add --all &&
     git -C "$project_folder" -c commit.gpgsign=false commit --quiet --no-verify --message "$FIRST_COMMIT_MESSAGE"; then
    ok "$project_folder is its own repository, with a first commit on main."
  else
    error_message "Making $project_folder a repository failed. Read the messages above and run ./setup.sh again."
    exit 1
  fi
done

# --- 4. Spec Kit for round 3 ----------------------------------------------------------
step "4/4 Spec Kit for round 3"
if ! bash "$SPEC_KIT_SETUP_SCRIPT"; then
  error_message "Installing Spec Kit did not finish. Rounds 1 and 2 are ready; run ./setup.sh in 3-vibecoding/ before round 3."
  exit 1
fi

echo
info "Next: open the folder of your round in VS Code, never this root folder."
