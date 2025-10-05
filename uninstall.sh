#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.doxavore.scheduled-rsync"
APP_NAME="scheduled-rsync"
BIN_PATH="/usr/local/bin/${APP_NAME}"
LAUNCHAGENT="$HOME/Library/LaunchAgents/${APP_ID}.plist"
LOG_DIR="$HOME/Library/Logs/${APP_ID}"
STATE_DIR="$HOME/Library/Application Support/${APP_ID}"

confirm() {
  read -r -p "$1 [y/N] " yn
  case $yn in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

echo "Preparing to uninstall ${APP_NAME}..."
echo "This will remove:"
echo "  LaunchAgent: $LAUNCHAGENT"
echo "  Binary:      $BIN_PATH"
echo "  Logs:        $LOG_DIR"
echo "  State:       $STATE_DIR"

if ! confirm "Continue with uninstall?"; then
  echo "Aborted."
  exit 1
fi

# Stop and unload the launch agent if loaded
if launchctl list | grep -q "$APP_ID"; then
  echo "Unloading launch agent..."
  launchctl unload "$LAUNCHAGENT" >/dev/null 2>&1 || true
fi

# Remove files (use sudo if /usr/local/bin not writable)
SUDO=""
if [[ ! -w "/usr/local/bin" ]]; then
  SUDO="sudo"
fi

$SUDO rm -f "$BIN_PATH"
rm -f "$LAUNCHAGENT"

# Clean up logs and state directories
echo "Removing logs and state directories..."
rm -rf "$LOG_DIR" "$STATE_DIR"

echo "${APP_NAME} has been uninstalled"
