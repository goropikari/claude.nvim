#!/usr/bin/env bash
# Claude Code lifecycle hook script
# Receives JSON payload on stdin, updates session state file atomically.
#
# Tracked events:
#   Notification (permission_prompt) -> status: waiting
#   PreToolUse                       -> status: working
#   Stop                             -> status: idle
#   SessionEnd                       -> (deletes session file)

set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
HOOK_EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty')

[ -z "$SESSION_ID" ] && exit 0

# Use $NVIM (Neovim server socket path) to isolate sessions per Neovim instance.
# terminals.nvim terminals inherit $NVIM automatically from Neovim.
if [ -n "${NVIM:-}" ]; then
  NVIM_KEY=$(printf '%s' "$NVIM" | tr '/.' '_' | sed 's/^_*//')
  STATE_DIR="/tmp/claude-sessions/${NVIM_KEY}"
else
  STATE_DIR="/tmp/claude-sessions/unknown"
fi

case "$HOOK_EVENT" in
  Notification)
    NOTIF_TYPE=$(printf '%s' "$INPUT" | jq -r '.notification_type // empty')
    [ "$NOTIF_TYPE" = "permission_prompt" ] && STATUS="waiting" || exit 0
    ;;
  PreToolUse)
    STATUS="working"
    ;;
  Stop)
    STATUS="idle"
    ;;
  SessionEnd)
    rm -f "$STATE_DIR/session-${SESSION_ID}.json"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac

mkdir -p "$STATE_DIR"

# Walk up the process tree NOW (while all ancestors are alive) and collect pids.
# This is more reliable than storing $PPID alone, which may exit before Neovim reads it.
ancestor_pids() {
  local pid=$PPID
  local list=""
  for _ in $(seq 1 30); do
    [ -z "$pid" ] || [ "$pid" -le 1 ] && break
    list="${list:+$list,}$pid"
    pid=$(awk '/^PPid/{print $2}' "/proc/$pid/status" 2>/dev/null) || break
  done
  printf '%s' "$list"
}
ANCESTORS=$(ancestor_pids)

# Atomic write: write to tmp then mv to avoid partial reads from Neovim
TMPFILE=$(mktemp "$STATE_DIR/.tmp.XXXXXX")
printf '{"session_id":"%s","status":"%s","cwd":"%s","ancestor_pids":[%s],"updated_at":%d}\n' \
  "$SESSION_ID" "$STATUS" "$CWD" "$ANCESTORS" "$(date +%s)" > "$TMPFILE"
mv "$TMPFILE" "$STATE_DIR/session-${SESSION_ID}.json"
