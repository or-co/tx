# How tx works

## When it saves

A reboot gives tmux no warning, so `tx` can't save at the last moment. It keeps the saved state current all the time instead:

- every 30 seconds (it only writes when something changed)
- when you create, split or rename a window, or detach
- when a Claude Code session starts, `/clear`s or `/resume`s (through a Claude hook)
- when you press `prefix S` or `prefix Q`

## How it knows what runs in each pane

It looks at the foreground process of each pane.

- **Claude Code:** a `SessionStart` hook stores the conversation id on the pane. Claude Code's own process record (`~/.claude/sessions/<pid>.json`) is used as a backup.
- **nvim:** a small plugin writes a session file for each pane as you work (`~/.local/state/tx/nvim/<pane-id>.vim`). Every pane has a permanent ID that is given back to it on restore, so two nvims in the same folder never overwrite each other.
- **Shells:** tmux already knows each pane's current directory.

## How it restores

Each pane gets a normal shell first, and then the right command is typed into it. Quitting a restored Claude or nvim therefore leaves you in a normal shell.

- Claude panes resume one after another, starting with the window you were on.
- Other programs (a dev server, `ssh`, …) are typed but not run. You press Enter.
- Risky commands (`rm`, `sudo`, `git push`, …) are never typed.
- The restore commands start with a space, and the installer configures your shell so those commands stay out of history.

## Reboot safety

During shutdown, programs die in random order. A save at that moment could record "nvim is gone" or "this pane is gone" and overwrite your good snapshot. To prevent this:

- a pane that disappears is dropped from the save only after 5 seconds, and only if tmux is still running
- a Claude or nvim pane that turns into a plain shell counts as closed only after 25 seconds
- saves you trigger yourself (`prefix S`, `prefix Q`, `tx save` in a terminal) skip these delays, because tmux is healthy at that point
- the last 20 snapshots are kept, and `tx restore --pick` brings back any of them

## Files

| Path | What |
|---|---|
| `~/.local/state/tx/current.json` | the snapshot that `tx` restores |
| `~/.local/state/tx/history/` | the last 20 snapshots |
| `~/.local/state/tx/nvim/` | nvim session files |
| `~/.local/state/tx/log` | what it did and when |

## What the installer changes

Every file it changes is backed up to `~/.local/state/tx/backup-<time>/`. Every addition sits between `# >>> tx >>>` markers, so reinstalling updates the setup instead of duplicating it.

| File | Change |
|---|---|
| `~/.local/bin/tx` | the script |
| `~/.tmux.conf` | the save loop, hooks, `prefix S` / `prefix Q`, a status-line warning |
| `~/.claude/settings.json` | one `SessionStart` hook (your other settings are kept) |
| your nvim config | `lua/tx_session.lua`, plus `lua/plugins/tx.lua` (LazyVim) or `plugin/tx.lua` |
| `~/.zshrc` or `~/.bashrc` | keeps restore commands out of history |

Installer options: `--bin-dir DIR`, `--no-claude`, `--no-nvim`, `--no-shellrc`.

## Testing on a separate tmux server

```sh
TX_L=txtest TX_STATE=/tmp/tx-test TX_CONF=/path/to/test.tmux.conf tx
```

`TX_INTERVAL` sets the save interval in seconds.
