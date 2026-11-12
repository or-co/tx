#!/usr/bin/env bash
# Install tx — tmux workspace persistence (Claude Code sessions, nvim, shells) across reboots.
# Safe to re-run: every change lives between "# >>> tx >>>" markers or is matched by name,
# and every file it touches is backed up first.
#
# Usage: ./install.sh [--bin-dir DIR] [--no-claude] [--no-nvim] [--no-shellrc]
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
BIN_DIR="$HOME/.local/bin"
DO_CLAUDE=1 DO_NVIM=1 DO_SHELLRC=1
while [ $# -gt 0 ]; do
  case $1 in
    --bin-dir) BIN_DIR=$2; shift 2;;
    --no-claude) DO_CLAUDE=0; shift;;
    --no-nvim) DO_NVIM=0; shift;;
    --no-shellrc) DO_SHELLRC=0; shift;;
    -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown option: $1" >&2; exit 1;;
  esac
done

STATE=${TX_STATE:-$HOME/.local/state/tx}
BACKUP="$STATE/backup-$(date +%Y%m%d-%H%M%S)"
TX="$BIN_DIR/tx"
say()  { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }
backup() { [ -e "$1" ] || return 0; mkdir -p "$BACKUP"; cp "$1" "$BACKUP/$(echo "${1#$HOME/}" | tr / _)"; }
strip_block() {  # remove an existing "# >>> tx >>>" … "# <<< tx <<<" block (in place, keeps symlinks)
  [ -f "$1" ] || return 0
  local tmp; tmp=$(mktemp)
  awk '/^# >>> tx >>>/{skip=1; nb=0} !skip{ if ($0 == "") { nb++; next } while (nb > 0) { print ""; nb-- } print } /^# <<< tx <<</{skip=0} END{ while (nb > 0) { print ""; nb-- } }' "$1" > "$tmp"
  cat "$tmp" > "$1"; rm -f "$tmp"
}

echo "tx installer"

# ── requirements ──
for c in tmux zsh jq perl uuidgen; do command -v $c >/dev/null || die "missing requirement: $c"; done
tv=$(tmux -V | sed 's/[^0-9.]//g'); tmaj=${tv%%.*}; tmin=${tv#*.}; tmin=${tmin%%.*}
{ [ "$tmaj" -gt 3 ] || { [ "$tmaj" -eq 3 ] && [ "${tmin:-0}" -ge 2 ]; }; } || die "tmux >= 3.2 required (found $(tmux -V))"
ok "requirements: tmux $tv, zsh, jq, perl, uuidgen"

# ── the tx script ──
mkdir -p "$BIN_DIR"
install -m 755 "$HERE/bin/tx" "$TX"
ok "installed $TX"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "$BIN_DIR is not on your PATH — add it to your shell rc";; esac

# ── tmux config ──
if   [ -f "$HOME/.tmux.conf" ]; then TCONF="$HOME/.tmux.conf"
elif [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf" ]; then TCONF="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
else TCONF="$HOME/.tmux.conf"; touch "$TCONF"; fi
backup "$TCONF"; strip_block "$TCONF"
{ echo; sed "s|@TX@|$TX|g" "$HERE/tmux/tx.conf"; } >> "$TCONF"
ok "tmux: added tx block to $TCONF"

# ── Claude Code SessionStart hook ──
if [ $DO_CLAUDE = 1 ]; then
  CS="$HOME/.claude/settings.json"
  if [ -d "$HOME/.claude" ]; then
    [ -f "$CS" ] || echo '{}' > "$CS"
    backup "$CS"
    tmp=$(mktemp)
    jq --arg cmd "$TX _claude-hook" '
      .hooks.SessionStart = (((.hooks.SessionStart // [])
          | map(select(any(.hooks[]?; (.command // "") | contains(" _claude-hook")) | not)))
        + [{"hooks": [{"type": "command", "command": $cmd, "timeout": 5}]}])' "$CS" > "$tmp"
    jq . "$tmp" >/dev/null && cat "$tmp" > "$CS"; rm -f "$tmp"
    ok "claude: SessionStart hook in $CS"
  else
    warn "claude: ~/.claude not found — skipped (re-run install after installing Claude Code)"
  fi
fi

# ── nvim plugin ──
if [ $DO_NVIM = 1 ]; then
  NC="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
  if [ -d "$NC" ]; then
    mkdir -p "$NC/lua"
    install -m 644 "$HERE/nvim/tx_session.lua" "$NC/lua/tx_session.lua"
    if [ -d "$NC/lua/plugins" ]; then          # lazy.nvim / LazyVim: spec files are loaded at startup
      LOADER="$NC/lua/plugins/tx.lua"; LOADER_BODY='require("tx_session").setup()
return {}'
    else                                       # plain config: plugin/ is sourced at startup
      mkdir -p "$NC/plugin"; LOADER="$NC/plugin/tx.lua"; LOADER_BODY='require("tx_session").setup()'
    fi
    printf -- '-- tx: per-tmux-pane session persistence (installed by tx; see lua/tx_session.lua)\n%s\n' "$LOADER_BODY" > "$LOADER"
    ok "nvim: $NC/lua/tx_session.lua + $LOADER"
  else
    warn "nvim: $NC not found — skipped (nvim panes will still be saved over RPC, just less often)"
  fi
fi

# ── keep restore commands out of shell history ──
if [ $DO_SHELLRC = 1 ]; then
  case $(basename "${SHELL:-}") in
    zsh)  RC="${ZDOTDIR:-$HOME}/.zshrc"; LINE='setopt HIST_IGNORE_SPACE';;
    bash) RC="$HOME/.bashrc"; LINE='export HISTCONTROL="ignorespace${HISTCONTROL:+:$HISTCONTROL}"';;
    *)    RC=;;
  esac
  if [ -n "$RC" ]; then
    touch "$RC"; backup "$RC"; strip_block "$RC"
    printf '\n# >>> tx >>>  (restore commands are typed with a leading space; keep them out of history)\n%s\n# <<< tx <<<\n' "$LINE" >> "$RC"
    ok "shell: history setting in $RC"
  fi
fi

[ -d "$BACKUP" ] && say "backups of changed files: $BACKUP"
echo
echo "Done. To start using it now:"
if tmux list-sessions >/dev/null 2>&1; then
  echo "  tmux source-file $TCONF     # turn it on in your running tmux"
fi
echo "  tx status                     # see what would be restored"
echo "After a reboot, just run: tx"
