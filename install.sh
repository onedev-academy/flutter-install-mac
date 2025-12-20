#!/bin/bash
set -euo pipefail

# NOTE:
# This script intentionally avoids running `flutter doctor`
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
  [ -z "$REQUIRED_SHELL_RC" ] && return 0
  grep -qs "export PATH=.*$p" "$REQUIRED_SHELL_RC" && return 0
  {
    echo "export PATH=\"$p:\$PATH\""
  } | cat - "$REQUIRED_SHELL_RC" > "$REQUIRED_SHELL_RC.tmp" && mv "$REQUIRED_SHELL_RC.tmp" "$REQUIRED_SHELL_RC"
}

# -------- Detect shell rc --------
USER_SHELL="$(basename "${SHELL:-/bin/zsh}")"
case "$USER_SHELL" in
  zsh) REQUIRED_SHELL_RC="$HOME/.zshrc" ;;
  bash) REQUIRED_SHELL_RC="$HOME/.bash_profile" ;;
  *)
    SHELL_RC=""
    warn "Unknown shell: $USER_SHELL; PATH persistence skipped"
    ;;
esac

# --- 1) Install Homebrew ---
if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  log "Homebrew already installed."
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

FLUTTER_PATH="$FLUTTER_HOME/bin"
add_path_to_rc_top "$FLUTTER_PATH"
export PATH="$FLUTTER_PATH:$PATH"

# --- 5) Install CocoaPods via gem ---
# Step 1: Install CocoaPods system-wide
if command -v pod >/dev/null 2>&1; then
  log "CocoaPods already installed at: $(command -v pod)"
else
  log "Installing CocoaPods..."
  sudo gem install cocoapods --no-document
fi

# Step 2: Detect gem bin path
GEM_BIN_PATH=$(sudo ruby -e 'require "rubygems"; puts Gem.bindir' 2>/dev/null || echo "/usr/local/bin")
add_path_to_rc_top "$GEM_BIN_PATH"
export PATH="$GEM_BIN_PATH:$PATH"
command -v pod >/dev/null 2>&1 && echo "pod installed at $(command -v pod)"

# --- 6) Install Android Studio ---
# -------- Config --------
ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
ANDROID_HOME="$ANDROID_SDK_ROOT"
CMDLINE_TOOLS="$ANDROID_SDK_ROOT/cmdline-tools/latest"
REQUIRED_SHELL_RC=""

if brew list --cask android-studio >/dev/null 2>&1; then
  log "Android Studio already installed"
else
  if [ -f /usr/local/bin/studio ]; then
    log "Removing existing Android Studio launcher"
    sudo rm -f /usr/local/bin/studio
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
