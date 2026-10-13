#!/usr/bin/env bash
#
# setup.sh - install the Spec Kit CLI (specify) for the spec driven workshop on macOS, Linux or
# Git Bash.
#
#   1. uv: checks that it works, offers the official installer when it is missing
#   2. the Spec Kit CLI from GitHub at the pinned tag: uv tool install specify-cli --from git+...@v<version>
#   3. prints the next step: specify init my-app --integration copilot
#
# Safe to run again: an installed CLI at the pinned version is left alone, another version is
# replaced by the pinned one. On Git Bash it hands off to setup.ps1, so Windows has one installer.
#
# Usage: ./setup.sh

# This script relies on bashisms ([[ ]], local, pipefail). Refuse a plain POSIX sh with a friendly
# line instead of an opaque syntax error.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run this script with bash:  bash setup.sh" >&2
  exit 1
fi

set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIRECTORY"

# Every participant and trainer uses this one version: the one session 2's setup installs its Spec Kit skills
# with. setup.ps1, setup.cmd and README.md repeat it.
SPEC_KIT_VERSION="1.1.3"
SPEC_KIT_SOURCE="git+https://github.com/github/spec-kit.git@v$SPEC_KIT_VERSION"

USAGE="Usage: ./setup.sh"
for argument in "$@"; do
  case "$argument" in
    -h|--help) echo "$USAGE"; exit 0 ;;
    *)         printf 'Unknown option: %s\n%s\n' "$argument" "$USAGE" >&2; exit 1 ;;
  esac
done

# --- Output helpers --------------------------------------------------------
bold() { printf '\033[1m%s\033[0m\n' "$1"; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
info() { printf '\033[36m•\033[0m %s\n' "$1"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[33m!\033[0m %s\n' "$1"; }
error_message() { printf '\033[31m✗\033[0m %s\n' "$1" >&2; }

# offer "question" -> 0 when the answer is yes. No terminal to answer from counts as no.
offer() {
  local answer=""
  read -r -p "  $1 [y/N] " answer || true
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

# True when directory $1 is one of the entries of $2, a PATH-style list.
path_list_contains() {
  case ":$2:" in
    *":$1:"*) return 0 ;;
    *)        return 1 ;;
  esac
}

# --- Detect the platform -----------------------------------------------------
case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin*)                       PLATFORM="macos" ;;
  Linux*)                        PLATFORM="linux" ;;
  MINGW*|MSYS*|CYGWIN*|Windows*) PLATFORM="windows" ;;
  *)                             PLATFORM="unknown" ;;
esac

bold "Setting up the Spec Kit CLI $SPEC_KIT_VERSION ($PLATFORM)"

# On Git Bash hand everything to setup.ps1: it knows where Windows installers put uv.
# WSL reports Linux and stays here.
if [ "$PLATFORM" = "windows" ] && command -v powershell.exe >/dev/null 2>&1; then
  info "Windows detected, handing off to setup.ps1..."
  POWERSHELL_SCRIPT="$SCRIPT_DIRECTORY/setup.ps1"
  if command -v cygpath >/dev/null 2>&1; then POWERSHELL_SCRIPT="$(cygpath -w "$POWERSHELL_SCRIPT")"; fi
  exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$POWERSHELL_SCRIPT"
fi

print_uv_install_help() {
  echo
  info "Install uv yourself, then run ./setup.sh again in a new terminal:"
  echo "    curl -LsSf https://astral.sh/uv/install.sh | sh"
  info "More information: https://docs.astral.sh/uv/getting-started/installation/"
}

print_manual_install_help() {
  echo
  info "Install the Spec Kit CLI yourself with:"
  echo "    uv tool install specify-cli --from $SPEC_KIT_SOURCE --force"
}

# The PATH this terminal started with, to tell whether a new terminal finds the tools too.
ORIGINAL_PATH="$PATH"
UV_WAS_INSTALLED=0

# --- 1. uv -------------------------------------------------------------------
step "1/3 uv"
# Where the official installer puts uv. A uv installed in another terminal is only on this
# terminal's PATH after a restart.
UV_INSTALL_DIRECTORY="${UV_INSTALL_DIR:-${XDG_BIN_HOME:-$HOME/.local/bin}}"
if [ -d "$UV_INSTALL_DIRECTORY" ]; then export PATH="$UV_INSTALL_DIRECTORY:$PATH"; fi

if ! command -v uv >/dev/null 2>&1; then
  error_message "uv was not found."
  if offer "Install uv now with the official installer (curl -LsSf https://astral.sh/uv/install.sh | sh)?"; then
    if ! command -v curl >/dev/null 2>&1; then
      error_message "curl is needed to download uv and was not found."
      print_uv_install_help
      exit 1
    fi
    if ! curl -LsSf https://astral.sh/uv/install.sh | sh; then
      error_message "The uv installer did not finish."
      print_uv_install_help
      exit 1
    fi
    export PATH="$UV_INSTALL_DIRECTORY:$PATH"
    UV_WAS_INSTALLED=1
    if ! command -v uv >/dev/null 2>&1; then
      error_message "uv was installed but this terminal cannot find it. Open a new terminal and run ./setup.sh again."
      exit 1
    fi
  else
    error_message "uv is required."
    print_uv_install_help
    exit 1
  fi
fi

# A broken or half-finished install is found on PATH but fails here.
if ! UV_VERSION="$(uv --version 2>/dev/null)"; then
  error_message "Found uv at $(command -v uv), but it does not run. The install looks broken."
  print_uv_install_help
  exit 1
fi
ok "$UV_VERSION works ($(command -v uv))."

# --- 2. The Spec Kit CLI -------------------------------------------------------
step "2/3 The Spec Kit CLI (specify-cli $SPEC_KIT_VERSION)"
INSTALLED_SPEC_KIT_VERSION="$(uv tool list 2>/dev/null | sed -n 's/^specify-cli v\([^ ]*\).*/\1/p' | head -n 1 || true)"
OTHER_SPECIFY_COMMAND="$(command -v specify 2>/dev/null || true)"

if [ "$INSTALLED_SPEC_KIT_VERSION" = "$SPEC_KIT_VERSION" ]; then
  ok "specify-cli $SPEC_KIT_VERSION is already installed."
else
  # --force replaces another version, including one installed from PyPI, and a specify command
  # another installer left in uv's bin directory.
  INSTALL_ARGUMENTS=(tool install specify-cli --from "$SPEC_KIT_SOURCE")
  if [ -n "$INSTALLED_SPEC_KIT_VERSION" ]; then
    warn "specify-cli $INSTALLED_SPEC_KIT_VERSION is installed. Replacing it with $SPEC_KIT_VERSION, the version the workshop uses."
    INSTALL_ARGUMENTS+=(--force)
  elif [ -n "$OTHER_SPECIFY_COMMAND" ]; then
    warn "Another specify command is on your PATH ($OTHER_SPECIFY_COMMAND). Installing $SPEC_KIT_VERSION with uv."
    INSTALL_ARGUMENTS+=(--force)
  fi
  info "Running uv ${INSTALL_ARGUMENTS[*]}..."
  if ! uv "${INSTALL_ARGUMENTS[@]}"; then
    error_message "Installing the Spec Kit CLI failed. Check your internet connection (or HTTPS_PROXY behind a proxy)."
    print_manual_install_help
    exit 1
  fi
  ok "specify-cli $SPEC_KIT_VERSION installed."
fi

TOOL_BIN_DIRECTORY="$(uv tool dir --bin 2>/dev/null || true)"
if [ -n "$TOOL_BIN_DIRECTORY" ]; then export PATH="$TOOL_BIN_DIRECTORY:$PATH"; fi

if ! SPECIFY_VERSION_OUTPUT="$(specify --version 2>/dev/null)"; then
  error_message "specify does not run after the install (uv tool bin directory: ${TOOL_BIN_DIRECTORY:-unknown})."
  print_manual_install_help
  exit 1
fi
SPECIFY_COMMAND="$(command -v specify)"
case "$SPECIFY_VERSION_OUTPUT" in
  *"$SPEC_KIT_VERSION"*) ok "$SPECIFY_VERSION_OUTPUT works ($SPECIFY_COMMAND)." ;;
  *)
    error_message "specify reports '$SPECIFY_VERSION_OUTPUT' instead of $SPEC_KIT_VERSION ($SPECIFY_COMMAND)."
    print_manual_install_help
    exit 1 ;;
esac

# How the participant reaches specify after this script ends: plainly, in a new terminal, or by its
# full path when its folder stays off PATH.
SPECIFY_INVOCATION="specify"
NEEDS_NEW_TERMINAL=0
SPECIFY_DIRECTORY="$(dirname "$SPECIFY_COMMAND")"
if [ "$UV_WAS_INSTALLED" = "1" ] && [ "$SPECIFY_DIRECTORY" = "$UV_INSTALL_DIRECTORY" ]; then
  # The uv installer already added this folder to the shell's startup file.
  NEEDS_NEW_TERMINAL=1
elif ! path_list_contains "$SPECIFY_DIRECTORY" "$ORIGINAL_PATH"; then
  warn "$SPECIFY_DIRECTORY is not on your PATH yet, so your terminal does not find specify."
  if offer "Add it to your shell's startup file now (uv tool update-shell)?" && uv tool update-shell; then
    ok "Added. It takes effect in new terminals."
    NEEDS_NEW_TERMINAL=1
  else
    SPECIFY_INVOCATION="\"$SPECIFY_COMMAND\""
    info "Add it later with:  uv tool update-shell"
  fi
else
  SPECIFY_IN_YOUR_TERMINAL="$( (PATH="$ORIGINAL_PATH"; command -v specify) 2>/dev/null || true)"
  if [ -n "$SPECIFY_IN_YOUR_TERMINAL" ] && [ "$SPECIFY_IN_YOUR_TERMINAL" != "$SPECIFY_COMMAND" ]; then
    warn "Another specify comes first on your PATH ($SPECIFY_IN_YOUR_TERMINAL), so a plain specify runs that one."
    SPECIFY_INVOCATION="\"$SPECIFY_COMMAND\""
  fi
fi

# --- 3. Next step --------------------------------------------------------------
step "3/3 Next step"
ok "Spec Kit is ready."
if [ "$NEEDS_NEW_TERMINAL" = "1" ]; then
  info "Open a new terminal, go to the folder where your project should live and run:"
else
  info "Go to the folder where your project should live and run:"
fi
echo "    $SPECIFY_INVOCATION init my-app --integration copilot"
info "Then open the new my-app folder in VS Code and open Copilot Chat in agent mode."
