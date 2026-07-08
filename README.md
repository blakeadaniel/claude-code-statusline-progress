# claude-code-statusline-progress

A terminal status line for [Claude Code](https://claude.ai/code) that shows your current model, effort level, working directory, session context usage, and rolling rate-limit consumption — all in one compact bar.

```
Opus 4.8 [high] ~/code/project [██████░░░░░░░░░░░░░░] 18% 177k / 1000k tokens  │  5h: ████░░ 66% 4h46m  │  7d: ██░░░░ 30% 1d12h
```

The bar colors shift green → yellow → red as you approach configurable warning and danger thresholds.

## What it shows

| Segment | Description |
|---|---|
| `Opus 4.8 [high]` | Active model and effort level |
| `~/code/project` | Current working directory (home directory shortened to `~`) |
| `[██████░░░░░░░░░░░░░░] 18% 177k / 1000k tokens` | Session context window usage |
| `5h: ████░░ 66% 4h46m` | 5-hour rolling usage — percentage used, time until reset |
| `7d: ██░░░░ 30% 1d12h` | 7-day rolling usage — percentage used, time until reset |

The 5h and 7d gauges are fetched from Anthropic's rate-limit response headers and cached for 60 seconds in the background so they don't slow down the status line render.

## Responsive sizing

The status line adapts to your terminal width. The context bar grows and shrinks to fill the available space, and lower-priority segments drop off as the window narrows:

| Terminal width | What's shown |
|---|---|
| Wide | Full bar + `5h` + `7d` gauges |
| Narrower | `7d` gauge drops |
| Narrower still | both gauges drop, token detail stays |
| Narrow | token detail drops — model, bar, and `%` remain |

Width is read from the controlling terminal at render time (`stty size`, falling back to `$COLUMNS`, `tput cols`, then `80`). Note that Claude Code re-runs the status line on activity and on a periodic idle refresh — not on terminal resize events — so after resizing, the new width is picked up on the next refresh rather than instantly.

## Install

```sh
npx claude-code-statusline-progress
```

The installer will:

1. Show the default color thresholds
2. Ask if you want to customize them
3. Copy the script to `~/.claude/statusline-command.sh`
4. Add the `statusLine` entry to `~/.claude/settings.json`

Restart Claude Code after installing.

## Thresholds

Color thresholds control when each bar transitions from green → yellow → red. The defaults are:

| Meter | Warning | Danger |
|---|---|---|
| Session context window | 20% | 50% |
| 5-hour usage | 50% | 90% |
| 7-day usage | 50% | 90% |

To change them, re-run `npx claude-code-statusline-progress` and answer `y` at the customize prompt, or edit the constants directly in `~/.claude/statusline-command.sh`:

```python
CONTEXT_WARN   = 0.20
CONTEXT_DANGER = 0.50
USAGE_5H_WARN   = 0.50
USAGE_5H_DANGER = 0.90
USAGE_7D_WARN   = 0.50
USAGE_7D_DANGER = 0.90
```

## Manual setup

If you prefer not to use `npx`, copy `statusline-command.sh` anywhere and add this to `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "bash /path/to/statusline-command.sh"
}
```

## Requirements

- Claude Code
- bash
- Python 3 (standard library only)
- Node.js ≥ 18 (installer only)
