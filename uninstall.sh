#!/usr/bin/env bash
# Uninstall tx. Removes everything install.sh added; your saved workspaces stay in
# ~/.local/state/tx unless you pass --purge.
#
# Usage: ./uninstall.sh [--bin-dir DIR] [--purge]
set -euo pipefail

BIN_DIR="$HOME/.local/bin" PURGE=0
while [ $# -gt 0 ]; do
  case $1 in
    --bin-dir) BIN_DIR=$2; shift 2;;
    --purge) PURGE=1; shift;;
    -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown option: $1" >&2; exit 1;;
  esac
done

STATE=${TX_STATE:-$HOME/.local/state/tx}
BACKUP="$STATE/backup-uninstall-$(date +%Y%m%d-%H%M%S)"
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
skip() { printf '  - %s\n' "$*"; }
backup() { [ -e "$1" ] || return 0; mkdir -p "$BACKUP"; cp "$1" "$BACKUP/$(echo "${1#$HOME/}" | tr / _)"; }
strip_block() {
  [ -f "$1" ] && grep -q '^# >>> tx >>>' "$1" || return 1
  backup "$1"
  local tmp; tmp=$(mktemp)
  awk '/^# >>> tx >>>/{skip=1; nb=0} !skip{ if ($0 == "") { nb++; next } while (nb > 0) { print ""; nb-- } print } /^# <<< tx <<</{skip=0} END{ while (nb > 0) { print ""; nb-- } }' "$1" > "$tmp"
  cat "$tmp" > "$1"; rm -f "$tmp"
}

echo "tx uninstaller"

# stop the background save loop(s) first, so nothing writes while we remove things
pkill -f 'tx _loop' 2>/dev/null && ok "stopped the background save loop" || true

# tmux
for f in "$HOME/.tmux.conf" "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"; do
  strip_block "$f" && ok "tmux: removed tx block from $f" || true
done

# shell rc
for f in "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.bashrc"; do
  strip_block "$f" && ok "shell: removed tx block from $f" || true
done

# Claude Code hook
CS="$HOME/.claude/settings.json"
if [ -f "$CS" ] && grep -q '_claude-hook' "$CS"; then
  backup "$CS"
  tmp=$(mktemp)
  jq 'if .hooks.SessionStart then
        .hooks.SessionStart |= map(select(any(.hooks[]?; (.command // "") | contains(" _claude-hook")) | not))
        | (if .hooks.SessionStart == [] then del(.hooks.SessionStart) else . end)
        | (if .hooks == {} then del(.hooks) else . end)
      else . end' "$CS" > "$tmp"
  jq . "$tmp" >/dev/null && cat "$tmp" > "$CS"; rm -f "$tmp"
  ok "claude: removed SessionStart hook from $CS"
else
  skip "claude: no tx hook found"
fi

# nvim (only files that are ours)
NC="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
for f in "$NC/lua/plugins/tx.lua" "$NC/plugin/tx.lua" "$NC/lua/tx_session.lua"; do
  if [ -f "$f" ] && grep -q 'tx_session' "$f"; then rm -f "$f"; ok "nvim: removed $f"; fi
done

# the script
if [ -f "$BIN_DIR/tx" ] && grep -q 'tmux workspace persistence' "$BIN_DIR/tx"; then
  rm -f "$BIN_DIR/tx"; ok "removed $BIN_DIR/tx"
else
  skip "no tx script in $BIN_DIR"
fi

if [ $PURGE = 1 ]; then
  rm -rf "$STATE"; ok "purged saved workspaces ($STATE)"
else
  skip "kept saved workspaces and backups in $STATE (use --purge to delete)"
  [ -d "$BACKUP" ] && skip "backups of changed files: $BACKUP"
fi

echo
echo "Done. A running tmux still has the tx key bindings and hooks loaded;"
echo "restart tmux (or the Mac) to clear them completely."
