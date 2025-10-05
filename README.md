# scheduled-rsync

Daily rsync of selected `$HOME` subdirectories to a remote SSH destination.
On success, writes a timestamp to a file. On failure, sends an email via Mail.app and provides a persistent alert (AppleScript).

This small utility is intended for macOS users who want a simple way to back up important files to a remote server. It uses `rsync` for file transfer and provides notifications in case of errors, assume you have Mail.app configured.

I make no warranties about this code. Use at your own risk.

## Install

```bash
git clone https://github.com/doxavore/scheduled-rsync
cd scheduled-rsync

./install.sh --email you@example.com --mail-from alerts@example.com user@nas.example.com: Desktop Documents
```

- Destination must be reachable over SSH and may omit the trailing :; the installer adds it.
- Directories are $HOME-relative (e.g., Desktop, Documents).
- `--email` specifies where failure notifications are sent.
- `--mail-from` (optional) sets the sender account Mail.app should use when sending messages. It must match one of your configured accounts in Mail.app.

Default schedule: 02:30 local time. Override by environment:

```bash
SCHEDULE_HOUR=3 SCHEDULE_MINUTE=5 ./install.sh --email ops@example.com user@nas: Desktop
```

## Uninstall

An uninstall script is included:

```bash
./uninstall.sh
```

## Runtime behavior

- Logs: ~/Library/Logs/com.doxavore.scheduled-rsync/
- State / timestamp: ~/Library/Application Support/com.doxavore.scheduled-rsync/last_success.txt

Rsync flags defaults are in `RSYNC_FLAGS_DEFAULT`. Override per-run via RSYNC_FLAGS, eg.:

```bash
RSYNC_FLAGS="-aEHAX --delete" scheduled-rsync user@nas: Desktop Documents
```
