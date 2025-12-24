#!/bin/bash
set -euo pipefail

# NOTE:
# This script intentionally avoids running `flutter doctor` and install Xcode: Go to: https://developer.apple.com/download/all/
# to prevent blocking behavior on macOS.

echo "======================================"
echo " Auto Flutter + Android Install Script"
echo "======================================"

# -------- Helpers --------
log() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
err() { echo "[ERR ] $*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || err "Missing command: $1"
}

add_path_to_rc_top() {
  local p="$1"
  [ -z "$SHELL_RC" ] && return 0
  grep -qs "$p" "$SHELL_RC" && return 0
  {
    echo "export PATH=\"$p:\$PATH\""
  } | cat - "$SHELL_RC" > "$SHELL_RC.tmp" && mv "$SHELL_RC.tmp" "$SHELL_RC"
}

# ---------- Detect shell ----------
USER_SHELL="$(basename "${SHELL:-/bin/zsh}")"
case "$USER_SHELL" in
  zsh)  SHELL_RC="$HOME/.zshrc" ;;
  bash) SHELL_RC="$HOME/.bash_profile" ;;
  *)    SHELL_RC=""; warn "Unknown shell, PATH persistence skipped" ;;
esac

# ---------- Detect architecture ----------
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  BREW_PREFIX="/opt/homebrew"
else
  BREW_PREFIX="/usr/local"
fi

BREW_BIN="$BREW_PREFIX/bin"
export PATH="$BREW_BIN:$PATH"
add_path_to_rc_top "$BREW_BIN"

# --- 1) Install Homebrew ---
if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  log "Homebrew already installed."
fi

# ---------- Xcode Command Line Tools ----------
if xcode-select -p &>/dev/null; then
  log "Xcode Command Line Tools already installed"
else
  log "Triggering Xcode Command Line Tools install"
  sudo rm -rf /Library/Developer/CommandLineTools || true
  xcode-select --install >/dev/null 2>&1 || true
  log "⚠️ Complete Xcode tools installation if prompted"
fi

# --- 2) Remove Homebrew Dart/flutter if present ---
brew list --formula 2>/dev/null | grep -q '^dart$' && brew uninstall dart --force || true
brew list --cask 2>/dev/null | grep -q '^flutter$' && brew uninstall --cask flutter --force || true

# --- 3) Ensure Git is installed ---
if ! command -v git >/dev/null 2>&1; then
    log "Git not found. Installing Git..."
    brew install git
else
    log "Git already installed."
fi

# --- 4) Install Flutter SDK to home directory ---
FLUTTER_HOME="$HOME/flutter"
if [ ! -d "$FLUTTER_HOME/bin" ]; then
    log "Installing Flutter SDK..."
    git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_HOME"
else
    log "Flutter already installed at $FLUTTER_HOME"
fi

add_path_to_rc_top "$FLUTTER_HOME/bin"
export PATH="$FLUTTER_HOME/bin:$PATH"

# --- 5) Install CocoaPods via gem ---
if [[ "$ARCH" == "arm64" ]]; then
   if command -v ruby >/dev/null 2>&1; then
      RUBY_VER="$(ruby -e 'print RUBY_VERSION')"
   else
      RUBY_VER="0"
  fi

  if ! command -v ruby >/dev/null 2>&1 || \
   [[ "$(printf '%s\n' "$RUBY_VER" "3.1" | sort -V | head -n1)" == "$RUBY_VER" ]]; then
    log "Installing Homebrew Ruby..."
    brew list ruby >/dev/null 2>&1 || brew install ruby
  fi

   # Add Homebrew Ruby to PATH
   HOMEBREW_RUBY_BIN="$(brew --prefix ruby)/bin"
   export PATH="$HOMEBREW_RUBY_BIN:$PATH"
   add_path_to_rc_top "$HOMEBREW_RUBY_BIN"
fi

# Install CocoaPods
if command -v pod >/dev/null 2>&1; then
   log "CocoaPods already installed at: $(command -v pod)"
else
   log "Installing CocoaPods..."
   gem install cocoapods --no-document
fi

# Verify installation
command -v pod >/dev/null 2>&1 && echo "pod installed at $(command -v pod)"

GEM_BIN_PATH="$(ruby -e 'require "rubygems"; puts Gem.bindir')"
add_path_to_rc_top "$GEM_BIN_PATH"
export PATH="$GEM_BIN_PATH:$PATH"

require_cmd pod

# --- 6) Install Android Studio ---
# -------- Config --------
ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
ANDROID_HOME="$ANDROID_SDK_ROOT"
CMDLINE_TOOLS="$ANDROID_SDK_ROOT/cmdline-tools/latest"
REQUIRED_SHELL_RC=""

if brew list --cask android-studio >/dev/null 2>&1; then
  log "Android Studio already installed"
else
  if [ -f "$BREW_PREFIX/bin/studio" ]; then
     sudo rm -f "$BREW_PREFIX/bin/studio"
  fi
  log "Installing Android Studio"
  brew install --cask android-studio
fi

# -------- Android SDK + cmdline-tools --------
log "Configuring Android SDK"
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"

if [ ! -d "$CMDLINE_TOOLS" ]; then
  log "Installing Android command-line tools"
  TMP_ZIP="/tmp/cmdline-tools.zip"
  curl -fsSL -o "$TMP_ZIP" https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip
  unzip -q "$TMP_ZIP" -d "$ANDROID_SDK_ROOT/cmdline-tools"
  mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$CMDLINE_TOOLS"
fi

export ANDROID_SDK_ROOT ANDROID_HOME
export PATH="$CMDLINE_TOOLS/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

add_path_to_rc_top "$CMDLINE_TOOLS/bin"
add_path_to_rc_top "$ANDROID_SDK_ROOT/platform-tools"

require_cmd sdkmanager

# -------- Install latest platform/build-tools --------
log "Resolving latest Android SDK packages"
LATEST_PLATFORM=$(sdkmanager --list | grep -o 'platforms;android-[0-9]\+' | sort -V | tail -1)
LATEST_BUILD_TOOLS=$(sdkmanager --list | grep -o 'build-tools;[0-9.]\+' | sort -V | tail -1)

log "Installing: platform-tools, $LATEST_PLATFORM, $LATEST_BUILD_TOOLS"
sdkmanager "platform-tools" \
"$LATEST_PLATFORM" \
"$LATEST_BUILD_TOOLS" || true

# -------- Accept all licenses reliably --------
log "Accepting all Android licenses"
yes | sdkmanager --licenses

# --- 8) Flutter config ---
flutter config --android-sdk "$ANDROID_SDK_ROOT"

log  "Run: flutter doctor"

echo "============================"
echo " Installation Completed!"
echo "============================"
