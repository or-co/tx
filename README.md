# tx

**Restart your Mac, type `tx`, and your tmux is back exactly as you left it.**

- Claude Code chats continue where they stopped
- nvim reopens your files, splits and tabs
- shells are back in the same folders
- every window, pane and name is in its place

## Install

You need tmux 3.2 or newer and `jq` (`brew install tmux jq`).

```sh
git clone <this repo> tx
cd tx
./install.sh
tmux source-file ~/.tmux.conf    # only if tmux is already running
```

That's it. It saves on its own while you work.

## Use

| | |
|---|---|
| `tx` | open tmux, restoring your workspace if tmux isn't running |
| `prefix S` | save now |
| `prefix Q` | save and quit (before a reboot) |
| `tx status` | see what's saved |

A few extras, for when you need them:

- `tx restore --pick` brings back an older save.
- `tx ignore` makes a pane come back as a plain shell.
- `tx reset` throws away the saved workspace.

## Good to know

- Programs other than Claude and nvim (a dev server, for example) come back typed on the prompt. Press Enter to run them.
- A program's memory can't come back (a Python REPL's variables, for example), but the command to restart it does.
- After a sudden power loss you may lose the last ~30 seconds of changes.

Curious how it works? See [docs/how-it-works.md](docs/how-it-works.md).

## Uninstall

```sh
cd tx
./uninstall.sh
```

This removes everything the installer added and keeps backups of every file it changed. Restart tmux afterwards. To also delete your saved workspaces, use `./uninstall.sh --purge`.

## License

MIT
