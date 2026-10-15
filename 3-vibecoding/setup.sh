#!/usr/bin/env bash
#
# setup.sh - install the Spec Kit CLI (specify) for the spec driven workshop on macOS, Linux or
# Git Bash. Runs unattended.
#
#   1. uv: checks that it works, installs it with the official installer when it is missing
#   2. Python 3.13 through uv, as the python and python3 of new terminals
#   3. the Spec Kit CLI from GitHub at the pinned tag, on Python 3.13:
#      uv tool install specify-cli --python 3.13 --from <tag archive>
#   4. puts specify on the PATH of new terminals and sets up Spec Kit in this folder:
#      specify init . --integration copilot --script py
#
# Safe to run again: a working CLI at the pinned version on Python 3.13 is left alone; anything
# else, another version, another Python or a broken install, is replaced by the pinned one. A folder that already has .specify is
# left alone too. On Git Bash it hands off to setup.ps1,
# so Windows has one installer.
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
# The tag archive instead of git+https: uv downloads it itself, so neither git nor git's proxy and
# certificate settings are needed.
SPEC_KIT_SOURCE="https://github.com/github/spec-kit/archive/refs/tags/v$SPEC_KIT_VERSION.zip"
# specify-cli runs on this Python, not on whatever uv finds first: its dependencies, PyYAML among
# them, have wheels for it, so nothing has to be built from source. Spec Kit's --script py scripts
# run on it too. Session 2's setup pins the same version.
PYTHON_VERSION="3.13"

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
  echo "    uv python install $PYTHON_VERSION --default"
  echo "    uv tool install --force specify-cli --python $PYTHON_VERSION --from $SPEC_KIT_SOURCE"
  info "Behind a proxy, set HTTPS_PROXY first, for example:  export HTTPS_PROXY=http://proxy.example:8080"
}

# True when the specify-cli tool environment runs on the pinned Python.
specify_uses_pinned_python() {
  local tool_directory tool_python_version
  tool_directory="$(uv tool dir 2>/dev/null)" || return 1
  tool_python_version="$("$tool_directory/specify-cli/bin/python" --version 2>/dev/null)" || return 1
  case "$tool_python_version" in
    "Python $PYTHON_VERSION".*) return 0 ;;
    *)                          return 1 ;;
  esac
}

# Downloads the official uv installer and runs it, with curl or else wget.
run_uv_installer() {
  if command -v curl >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://astral.sh/uv/install.sh | sh
  else
    error_message "Neither curl nor wget was found, so uv cannot be downloaded."
    return 1
  fi
}

# True when the specify on PATH runs and reports the pinned version; its output lands in SPECIFY_VERSION_OUTPUT.
specify_works_at_pinned_version() {
  SPECIFY_VERSION_OUTPUT="$(specify --version 2>/dev/null)" || return 1
  case "$SPECIFY_VERSION_OUTPUT" in
    *"$SPEC_KIT_VERSION"*) return 0 ;;
    *)                     return 1 ;;
  esac
}

# The PATH this terminal started with, to tell whether a new terminal finds the tools too.
ORIGINAL_PATH="$PATH"
UV_WAS_INSTALLED=0
SPECIFY_VERSION_OUTPUT=""

# --- 1. uv -------------------------------------------------------------------
step "1/4 uv"
# Where the official installer puts uv. A uv installed in another terminal is only on this
# terminal's PATH after a restart.
UV_INSTALL_DIRECTORY="${UV_INSTALL_DIR:-${XDG_BIN_HOME:-$HOME/.local/bin}}"
if [ -d "$UV_INSTALL_DIRECTORY" ]; then export PATH="$UV_INSTALL_DIRECTORY:$PATH"; fi

if ! command -v uv >/dev/null 2>&1; then
  info "uv was not found. Installing it with the official installer (https://astral.sh/uv/install.sh)..."
  if ! run_uv_installer; then
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
fi

# A broken or half-finished install is found on PATH but fails here.
if ! UV_VERSION="$(uv --version 2>/dev/null)"; then
  error_message "Found uv at $(command -v uv), but it does not run. The install looks broken."
  print_uv_install_help
  exit 1
fi
if ! uv tool --help >/dev/null 2>&1; then
  error_message "$UV_VERSION is too old for uv tool. Update it with:  uv self update"
  exit 1
fi
ok "$UV_VERSION works ($(command -v uv))."

# A TLS-inspecting proxy re-signs traffic with a company certificate that only the system store
# trusts; uv's own certificate bundle would reject it.
if [ -z "${UV_SYSTEM_CERTS:-}${UV_NATIVE_TLS:-}" ]; then
  if uv tool install --help 2>/dev/null | grep -q -- '--system-certs'; then
    export UV_SYSTEM_CERTS=1
  else
    export UV_NATIVE_TLS=1
  fi
fi

# --- 2. Python -----------------------------------------------------------------
# python lands in the same folder as specify, unless UV_PYTHON_BIN_DIR says otherwise, so step 3
# puts both on the PATH of new terminals.
step "2/4 Python $PYTHON_VERSION"
# Older uv releases only know --default as a preview feature.
info "Installing Python $PYTHON_VERSION as the default python. The first time this can take a few minutes..."
if ! uv python install "$PYTHON_VERSION" --default && ! uv python install "$PYTHON_VERSION" --default --preview; then
  error_message "Installing Python $PYTHON_VERSION failed. Check your internet connection (or HTTPS_PROXY behind a proxy)."
  print_manual_install_help
  exit 1
fi
ok "Python $PYTHON_VERSION is installed."

# --- 3. The Spec Kit CLI -------------------------------------------------------
step "3/4 The Spec Kit CLI (specify-cli $SPEC_KIT_VERSION)"
TOOL_BIN_DIRECTORY="$(uv tool dir --bin 2>/dev/null || true)"
if [ -n "$TOOL_BIN_DIRECTORY" ]; then export PATH="$TOOL_BIN_DIRECTORY:$PATH"; fi
INSTALLED_SPEC_KIT_VERSION="$(uv tool list 2>/dev/null | sed -n 's/^specify-cli v\([^ ]*\).*/\1/p' | head -n 1 || true)"

if [ "$INSTALLED_SPEC_KIT_VERSION" = "$SPEC_KIT_VERSION" ] && specify_uses_pinned_python && specify_works_at_pinned_version; then
  ok "specify-cli $SPEC_KIT_VERSION is already installed on Python $PYTHON_VERSION."
else
  if [ -n "$INSTALLED_SPEC_KIT_VERSION" ] && [ "$INSTALLED_SPEC_KIT_VERSION" != "$SPEC_KIT_VERSION" ]; then
    warn "specify-cli $INSTALLED_SPEC_KIT_VERSION is installed. Replacing it with $SPEC_KIT_VERSION, the version the workshop uses."
  elif [ -n "$INSTALLED_SPEC_KIT_VERSION" ] && ! specify_uses_pinned_python; then
    warn "specify-cli runs on another Python. Installing it again on Python $PYTHON_VERSION."
  fi
  # --force replaces another version, a broken tool environment, and a specify command another
  # installer left in uv's bin directory.
  info "Installing specify-cli $SPEC_KIT_VERSION from GitHub on Python $PYTHON_VERSION. The first time this can take a few minutes..."
  if ! uv tool install --force specify-cli --python "$PYTHON_VERSION" --from "$SPEC_KIT_SOURCE"; then
    error_message "Installing the Spec Kit CLI failed. Check your internet connection (or HTTPS_PROXY behind a proxy)."
    print_manual_install_help
    exit 1
  fi
  ok "specify-cli $SPEC_KIT_VERSION installed on Python $PYTHON_VERSION."
fi

if ! specify_works_at_pinned_version; then
  if [ -n "$SPECIFY_VERSION_OUTPUT" ]; then
    error_message "specify reports '$SPECIFY_VERSION_OUTPUT' instead of $SPEC_KIT_VERSION ($(command -v specify))."
  else
    error_message "specify does not run after the install (uv tool bin directory: ${TOOL_BIN_DIRECTORY:-unknown})."
  fi
  print_manual_install_help
  exit 1
fi
SPECIFY_COMMAND="$(command -v specify)"
ok "$SPECIFY_VERSION_OUTPUT works ($SPECIFY_COMMAND)."

# How the participant reaches specify after this script ends: plainly, in a new terminal, or by its
# full path when another specify comes first on PATH.
SPECIFY_INVOCATION="specify"
NEEDS_NEW_TERMINAL=0
SPECIFY_DIRECTORY="$(dirname "$SPECIFY_COMMAND")"
if [ "$UV_WAS_INSTALLED" = "1" ] && [ "$SPECIFY_DIRECTORY" = "$UV_INSTALL_DIRECTORY" ]; then
  # The uv installer already added this folder to the shell's startup file.
  NEEDS_NEW_TERMINAL=1
elif ! path_list_contains "$SPECIFY_DIRECTORY" "$ORIGINAL_PATH"; then
  info "$SPECIFY_DIRECTORY is not on your PATH yet. Adding it to your shell's startup file (uv tool update-shell)..."
  # With the PATH this terminal started with: uv skips a folder it already finds on the current PATH.
  if PATH="$ORIGINAL_PATH" "$(command -v uv)" tool update-shell; then
    ok "Added. It takes effect in new terminals."
    NEEDS_NEW_TERMINAL=1
  else
    warn "Could not add it. Add it later with:  uv tool update-shell"
    SPECIFY_INVOCATION="\"$SPECIFY_COMMAND\""
  fi
else
  SPECIFY_IN_YOUR_TERMINAL="$( (PATH="$ORIGINAL_PATH"; command -v specify) 2>/dev/null || true)"
  if [ -n "$SPECIFY_IN_YOUR_TERMINAL" ] && [ "$SPECIFY_IN_YOUR_TERMINAL" != "$SPECIFY_COMMAND" ]; then
    warn "Another specify comes first on your PATH ($SPECIFY_IN_YOUR_TERMINAL), so a plain specify runs that one."
    SPECIFY_INVOCATION="\"$SPECIFY_COMMAND\""
  fi
fi

# --- 4. Spec Kit in this folder ----------------------------------------------------
step "4/4 Spec Kit in this folder"
# A second run leaves .specify alone: init --force would overwrite a constitution the participant already wrote.
if [ -d ".specify" ]; then
  ok "This folder already has .specify, so specify init is skipped."
else
  info "Running specify init . --integration copilot --script py..."
  # --force: the folder already holds this README and the setup files, and init refuses a folder that
  # is not empty unless it can ask. It only adds .github/ and .specify/.
  if ! "$SPECIFY_COMMAND" init . --integration copilot --script py --force; then
    error_message "specify init did not finish."
    info "Run it yourself in this folder:"
    echo "    $SPECIFY_INVOCATION init . --integration copilot --script py --force"
    exit 1
  fi
fi
ok "Spec Kit is ready."
if [ "$NEEDS_NEW_TERMINAL" = "1" ]; then
  info "specify works in new terminals (in VS Code: quit VS Code and start it again)."
fi
info "Open this folder in VS Code and open Copilot Chat in agent mode."
