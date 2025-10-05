#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.doxavore.scheduled-rsync"
APP_NAME="scheduled-rsync"
BIN_INSTALL="/usr/local/bin/${APP_NAME}"
LAUNCHAGENT="$HOME/Library/LaunchAgents/${APP_ID}.plist"
LOG_DIR="$HOME/Library/Logs/${APP_ID}"
STATE_DIR="$HOME/Library/Application Support/${APP_ID}"
STATE_LOG_FILE="$STATE_DIR/run.log"

SCHEDULE_HOUR="${SCHEDULE_HOUR:-2}"
SCHEDULE_MINUTE="${SCHEDULE_MINUTE:-30}"

EMAIL_ARG=""
MAIL_FROM_ARG=""

if [[ "${1:-}" == "--email" ]]; then
  EMAIL_ARG="$2"
  shift 2
fi

if [[ "${1:-}" == "--mail-from" ]]; then
  MAIL_FROM_ARG="$2"
  shift 2
fi

if [[ $# -lt 2 ]]; then
  echo "Usage: ./install.sh [--email you@example.com] [--mail-from 'Name <from@example.com>'] DESTINATION[:] DIR [DIR ...]" >&2
  echo "Example: ./install.sh --email you@example.com --mail-from 'Doug Mayer <doug@mayer.me>' user@nas.example.com: Desktop Documents" >&2
  exit 2
fi

DEST="$1"
shift
if [[ "$DEST" != *: ]]; then DEST="${DEST}:"; fi
DIRS=("$@")

MAIL_TO="${EMAIL_ARG}"
if [[ -z "$MAIL_TO" ]]; then
  read -r -p "Failure email recipient address (required): " MAIL_TO
fi
if [[ -z "$MAIL_TO" ]]; then
  echo "An email address is required for failure notifications." >&2
  exit 2
fi

echo "Plan:"
echo "  Install binary: $BIN_INSTALL"
echo "  LaunchAgent:    $LAUNCHAGENT"
echo "  Schedule:       daily at ${SCHEDULE_HOUR}:${SCHEDULE_MINUTE} (local)"
echo "  Destination:    $DEST"
echo "  Dirs:           ${DIRS[*]}"
echo "  Failure email:  $MAIL_TO"
if [[ -n "$MAIL_FROM_ARG" ]]; then
  echo "  Mail sender:    $MAIL_FROM_ARG"
fi
read -r -p "Proceed? [y/N] " yn
case "$yn" in
  [Yy]*) ;;
  *) echo "Aborted."; exit 1 ;;
esac

# Ensure /usr/local/bin exists and is writable
SUDO=""
if [[ ! -d "/usr/local/bin" ]]; then
  echo "Creating /usr/local/bin..."
  if ! mkdir -p "/usr/local/bin" 2>/dev/null; then
    echo "Need sudo to create /usr/local/bin"
    sudo mkdir -p "/usr/local/bin"
  fi
fi
if [[ ! -w "/usr/local/bin" ]]; then
  SUDO="sudo"
fi

# --------- Preflight checks -----------
echo "Running preflight checks..."

# PATH the LaunchAgent will use
LAUNCH_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

have_cmd() { PATH="$LAUNCH_PATH" command -v "$1" >/dev/null 2>&1; }

missing=0
for c in rsync ssh osascript; do
  if ! have_cmd "$c"; then
    echo "ERROR: '$c' not found in LaunchAgent PATH ($LAUNCH_PATH)" >&2
    missing=1
  fi
done
if [[ $missing -eq 1 ]]; then
  echo "Please install the missing tools (e.g., 'brew install rsync') and re-run." >&2
  exit 2
fi

RSYNC_BIN="$(PATH="$LAUNCH_PATH" command -v rsync)"
RSYNC_VERSION_LINE="$("$RSYNC_BIN" --version 2>/dev/null | head -n1 || true)"
RSYNC_VER="$(awk '{print $3}' <<<"$RSYNC_VERSION_LINE")"
if [[ -z "$RSYNC_VER" ]]; then RSYNC_VER="unknown"; fi
echo "Detected rsync: $RSYNC_BIN (version $RSYNC_VER)"

# Writable logs/state
mkdir -p "$LOG_DIR" "$STATE_DIR"
touch "$LOG_DIR/.w" "$STATE_DIR/.w" 2>/dev/null || {
  echo "ERROR: Cannot write to $LOG_DIR or $STATE_DIR" >&2
  exit 2
}
rm -f "$LOG_DIR/.w" "$STATE_DIR/.w"

# Validate Mail availability & accounts
MAIL_ACCOUNTS="$(/usr/bin/osascript -e 'tell application "Mail" to get name of every account' 2>/dev/null || true)"
if [[ -z "$MAIL_ACCOUNTS" ]]; then
  echo "WARN: Mail.app reports no configured accounts or is not accessible. Failure emails may not send."
fi

# If MAIL_FROM specified, verify it maps to an account email address
if [[ -n "$MAIL_FROM_ARG" ]]; then
  if ! /usr/bin/osascript - "$MAIL_FROM_ARG" <<'OSA' >/dev/null 2>&1
on run argv
  set targetAddr to item 1 of argv
  tell application "Mail"
    set ok to false
    repeat with a in accounts
      if (email addresses of a) contains targetAddr then
        set ok to true
        exit repeat
      end if
    end repeat
  end tell
  if ok is false then error "No Mail account with address: " & targetAddr
end run
OSA
  then
    echo "ERROR: Could not query Mail accounts for sender validation." >&2
    exit 2
  fi
fi

# Optional: proactively trigger Automation prompts (Mail + alert)
read -r -p "Trigger macOS Automation consent prompts for Mail/alerts now? [y/N] " grant
if [[ "$grant" =~ ^[Yy]$ ]]; then
  echo "Asking Mail for accounts (may prompt for permission)..."
  /usr/bin/osascript -e 'tell application "Mail" to get name of every account' || true
  echo "Showing a test alert (may prompt for permission)..."
  /usr/bin/osascript -e 'display alert "scheduled-rsync preflight" message "Permission check succeeded."' || true
fi

# SSH non-interactive check (warn-only)
SSH_DEST="${DEST%:}"  # strip trailing colon for ssh
echo "Checking SSH naccess to ${SSH_DEST} ..."
if ! PATH="$LAUNCH_PATH" ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$SSH_DEST" true 2>/dev/null; then
  echo "WARN: SSH check failed. Ensure key-based auth works for the LaunchAgent context."
else
  echo "SSH check succeeded."
fi

# --------- End preflight checks -----------

mkdir -p "$(dirname "$BIN_INSTALL")" "$(dirname "$LAUNCHAGENT")"

# Install binary, bake MAIL_TO default
bin_src="bin/${APP_NAME}"
tmp_bin="$(mktemp)"
sed "s/__MAIL_TO_PLACEHOLDER__/${MAIL_TO//\//\\/}/g" "$bin_src" >"$tmp_bin"
if [[ -n "$SUDO" ]]; then echo "May need sudo to install to ${BIN_INSTALL}"; fi
$SUDO install -m 0755 "$tmp_bin" "$BIN_INSTALL"
rm -f "$tmp_bin"

PROGRAM_ARGS=()
PROGRAM_ARGS+=("$BIN_INSTALL")
PROGRAM_ARGS+=("$DEST")
for d in "${DIRS[@]}"; do PROGRAM_ARGS+=("$d"); done

# XML escaping helper
xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"
  printf '%s' "$s"
}

MAIL_TO_XML="$(xml_escape "$MAIL_TO")"
MAIL_FROM_XML=""
if [[ -n "$MAIL_FROM_ARG" ]]; then
  MAIL_FROM_XML="$(xml_escape "$MAIL_FROM_ARG")"
fi

# Write LaunchAgent plist (unchanged except env additions)
cat >"$LAUNCHAGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${APP_ID}</string>

  <key>ProgramArguments</key>
  <array>
PLIST

for arg in "${PROGRAM_ARGS[@]}"; do
  esc="$(xml_escape "$arg")"
  echo "    <string>${esc}</string>" >>"$LAUNCHAGENT"
done

cat >>"$LAUNCHAGENT" <<PLIST
  </array>

  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>${SCHEDULE_HOUR}</integer>
    <key>Minute</key><integer>${SCHEDULE_MINUTE}</integer>
  </dict>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>$LOG_DIR/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/launchd.err.log</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${LAUNCH_PATH}</string>
    <key>MAIL_TO</key>
    <string>${MAIL_TO_XML}</string>
PLIST

if [[ -n "$MAIL_FROM_ARG" ]]; then
  cat >>"$LAUNCHAGENT" <<PLIST
    <key>MAIL_FROM</key>
    <string>${MAIL_FROM_XML}</string>
PLIST
fi

cat >>"$LAUNCHAGENT" <<'PLIST'
  </dict>
</dict>
</plist>
PLIST

launchctl unload "$LAUNCHAGENT" >/dev/null 2>&1 || true
launchctl load "$LAUNCHAGENT"

echo "Installed. Test a run now:"
echo "  launchctl start ${APP_ID}"
echo "Logs:"
echo "  tail -f \"$STATE_LOG_FILE\""
