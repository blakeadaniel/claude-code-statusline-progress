# claude-code-statusline-progress

**claude-code-statusline-progress** is a terminal status line for the [Claude Code](https://claude.ai/code) CLI that gives you real-time monitoring of token usage, context-window consumption, and Anthropic rate limits without leaving your shell. It renders a single compact bar showing the active model, reasoning effort, working directory, git branch, session context usage, 5-hour and 7-day rolling rate-limit gauges, and session cost — installed with one `npx` command and driven by a dependency-free `bash` + `python3` script.

[![npm version](https://img.shields.io/npm/v/claude-code-statusline-progress.svg)](https://www.npmjs.com/package/claude-code-statusline-progress)
[![npm downloads](https://img.shields.io/npm/dm/claude-code-statusline-progress.svg)](https://www.npmjs.com/package/claude-code-statusline-progress)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Node.js >= 18](https://img.shields.io/badge/node-%3E%3D18-brightgreen.svg)](package.json)

<!-- Absolute raw URL so the demo also renders on npmjs.com, which does not resolve relative paths. -->
<img src="https://raw.githubusercontent.com/blakeadaniel/claude-code-statusline-progress/main/assets/statusline-demo.gif" alt="Animated demo: the status line as a session fills up, with the context bar shifting green to yellow to red, and segments dropping off as the terminal narrows" width="100%">

```
Opus 5 [high] ~/code/project (main*) [████░░░░░░░░░░░░░░░░] 18% 177k / 1000k tokens  │  5h: [████░░] 66% 4h46m  │  7d: [██░░░░] 30% 1d12h  │  $3.42 · 1h15m
```

The bars shift green → yellow → red as you approach configurable warning and danger thresholds. Everything is rendered by a single `bash` + `python3` script with no dependencies beyond the standard library — no network calls, no background daemons, no state files.

## Table of Contents

- [What it shows](#what-it-shows)
- [Why use a Claude Code status line?](#why-use-a-claude-code-status-line)
- [Responsive sizing](#responsive-sizing)
- [Installation](#installation)
- [Configuration](#configuration)
- [How it works](#how-it-works)
- [Development](#development)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Related tools](#related-tools)
- [License](#license)

## What it shows

| Segment | Example | Description |
|---|---|---|
| Model | `Opus 5` | Active model display name |
| Effort | `[high]` | Reasoning effort, from `$CLAUDE_EFFORT` |
| Directory | `~/code/project` | Current working directory, home shortened to `~` |
| Git | `(main*)` | Branch name; `*` marks a dirty working tree |
| Context bar | `[███░░░░░░░] 18% 177k / 1000k tokens` | Session context window usage |
| 5-hour gauge | `5h: [████░░] 66% 4h46m` | 5-hour rolling usage and time until reset |
| 7-day gauge | `7d: [██░░░░] 30% 1d12h` | 7-day rolling usage and time until reset |
| Cost | `$3.42 · 1h15m` | Session cost so far and wall-clock duration |

Every segment is optional in the sense that it disappears when Claude Code doesn't supply the underlying data — outside a git repo there's no branch, and before the first API response there are no rate-limit gauges.

## Why use a Claude Code status line?

Claude Code sessions burn through a context window and a rolling usage allowance at the same time, and neither is visible while you work. This status line answers the three questions that interrupt a session:

- **How much context is left?** A live token bar (`177k / 1000k tokens`) instead of waiting for a compaction warning.
- **How close am I to a rate limit?** 5-hour and 7-day usage gauges with the exact time until each window resets.
- **What has this session cost?** Running USD cost and wall-clock duration.

It is a single shell script — no daemon, no network calls, no state files, no telemetry — so nothing runs between refreshes and nothing leaves your machine.

## Responsive sizing

The status line adapts to your terminal width. The context bar grows and shrinks to fill the available space (between 3 and 20 cells), and lower-priority segments drop off as the window narrows:

| Terminal width | What's shown |
|---|---|
| Widest | Full bar + `5h` + `7d` gauges + cost |
| Narrower | cost drops |
| Narrower still | `7d` gauge drops |
| Narrower again | both gauges drop, token detail stays |
| Narrowest | token detail drops — model, cwd, bar, and `%` remain |

Priority order is: context token detail → `5h` gauge → `7d` gauge → cost. Cost never renders while a higher-priority segment that *has* data was hidden for width.

Width comes from `$COLUMNS`, which Claude Code sets before invoking the command (v2.1.153+), falling back to `stty size`, then `tput cols`, then `80`. Claude Code re-runs the status line on activity and on a periodic idle refresh — not on terminal resize events — so after resizing, the new width is picked up on the next refresh rather than instantly.

## Installation

### Prerequisites

- Claude Code
- `bash`
- Python 3 (standard library only)
- Node.js ≥ 18 — for the installer only; the status line itself never runs Node

### Using npx (recommended)

```sh
npx claude-code-statusline-progress
```

The installer will:

1. Print the default color thresholds
2. Ask whether you want to customize them (`Customize thresholds? [y/N]`)
3. Write the script to `~/.claude/statusline-command.sh` (mode `0755`), baking in your thresholds
4. Merge a `statusLine` entry into `~/.claude/settings.json`, preserving your other settings

Restart Claude Code afterwards.

If `~/.claude/settings.json` exists but isn't valid JSON, the installer stops and tells you to fix it rather than overwriting it.

### From source

```sh
git clone https://github.com/blakeadaniel/claude-code-statusline-progress.git
cd claude-code-statusline-progress
node bin/install.js
```

### Manual setup

Copy `statusline-command.sh` anywhere and point Claude Code at it in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /path/to/statusline-command.sh"
  }
}
```

A ready-to-paste version of that block is in [settings-snippet.json](settings-snippet.json).

### Let Claude install it

[setup-prompt.md](setup-prompt.md) contains a prompt you can paste into Claude Code to have it do the copy, the threshold edits, and the settings merge for you.

## Configuration

### Color thresholds

Each bar transitions green → yellow over the range `[0, warn]`, yellow → red over `[warn, danger]`, and stays solid red above `danger`.

| Meter | Warn constant | Default | Danger constant | Default |
|---|---|---|---|---|
| Session context window | `CONTEXT_WARN` | `0.20` | `CONTEXT_DANGER` | `0.50` |
| 5-hour usage | `USAGE_5H_WARN` | `0.50` | `USAGE_5H_DANGER` | `0.90` |
| 7-day usage | `USAGE_7D_WARN` | `0.50` | `USAGE_7D_DANGER` | `0.90` |

There are three ways to change them:

**1. Re-run the installer** and answer `y` at the customize prompt. It asks for percentages (`20`, not `0.20`) and rejects a danger value that isn't above its warning.

**2. Set environment variables** before Claude Code launches. Values are fractions:

```sh
export CONTEXT_WARN=0.10
export CONTEXT_DANGER=0.35
claude
```

Invalid or unparseable values silently fall back to the defaults. If `danger <= warn`, danger is nudged to `warn + 0.01` so the gradient math stays well-defined.

**3. Edit the constants** directly near the top of the Python block in `~/.claude/statusline-command.sh`:

```python
CONTEXT_WARN    = _envf("CONTEXT_WARN", 0.20)
CONTEXT_DANGER  = _envf("CONTEXT_DANGER", 0.50)
USAGE_5H_WARN   = _envf("USAGE_5H_WARN", 0.50)
USAGE_5H_DANGER = _envf("USAGE_5H_DANGER", 0.90)
USAGE_7D_WARN   = _envf("USAGE_7D_WARN", 0.50)
USAGE_7D_DANGER = _envf("USAGE_7D_DANGER", 0.90)
```

### Environment variables

| Variable | Description | Default |
|---|---|---|
| `CLAUDE_EFFORT` | Effort label shown in brackets | `?` |
| `COLUMNS` | Terminal width; set by Claude Code | `stty` → `tput` → `80` |
| `CONTEXT_WARN` / `CONTEXT_DANGER` | Context bar thresholds (0–1) | `0.20` / `0.50` |
| `USAGE_5H_WARN` / `USAGE_5H_DANGER` | 5-hour gauge thresholds (0–1) | `0.50` / `0.90` |
| `USAGE_7D_WARN` / `USAGE_7D_DANGER` | 7-day gauge thresholds (0–1) | `0.50` / `0.90` |

### Bar sizing

Two constants at the top of the Python block control the context bar's range:

```python
MIN_BAR = 3     # narrowest the context bar ever shrinks to
MAX_BAR = 20    # widest it grows on roomy terminals
```

## How it works

Claude Code invokes the command on each refresh and pipes a JSON status object to it on stdin. The script reads that object and renders one line to stdout — that's the whole contract. The fields it consumes:

| JSON path | Used for |
|---|---|
| `model.display_name` | Model name |
| `workspace.current_dir` (or `cwd`) | Directory segment, and the `git -C` target |
| `workspace.repo` | Gate for the git block — absent means no `git` subprocess runs at all |
| `context_window.context_window_size` | Bar denominator (falls back to 1,000,000) |
| `context_window.total_input_tokens` | Bar numerator |
| `context_window.current_usage.*` | Numerator fallback: input + cache-creation + cache-read tokens |
| `rate_limits.five_hour.used_percentage` / `.resets_at` | 5-hour gauge and countdown |
| `rate_limits.seven_day.used_percentage` / `.resets_at` | 7-day gauge and countdown |
| `cost.total_cost_usd` / `.total_duration_ms` | Cost segment |

Two design notes worth knowing:

- **No network calls.** The 5h/7d numbers come from the `rate_limits` fields in the status JSON. Earlier versions probed the API for rate-limit response headers and cached the result; that's gone as of v1.3.0.
- **Git is nearly free.** The branch lookup only runs when `workspace.repo` is present, and both `git` calls carry a 300 ms timeout. Outside a repo the script makes zero subprocesses.

Every field is defensively parsed: wrong types, non-finite numbers, negative costs, and malformed JSON all degrade to a sensible placeholder instead of a traceback in your status bar.

## Development

### Project structure

```
claude-code-statusline-progress/
├── statusline-command.sh   # The whole status line: bash wrapper + inline Python
├── bin/
│   └── install.js          # npx installer — prompts, patches, wires up settings.json
├── settings-snippet.json   # Copy-paste settings.json fragment
├── setup-prompt.md         # Prompt for having Claude Code install it
├── package.json
└── LICENSE
```

### Running it by hand

The script is a pure stdin → stdout filter, so you can exercise any state without launching Claude Code:

```sh
echo '{
  "model": {"display_name": "Opus 5"},
  "workspace": {"current_dir": "'"$PWD"'", "repo": {"root": "'"$PWD"'"}},
  "context_window": {"context_window_size": 1000000, "total_input_tokens": 177000},
  "rate_limits": {
    "five_hour": {"used_percentage": 66, "resets_at": '"$(( $(date +%s) + 17160 ))"'},
    "seven_day": {"used_percentage": 30, "resets_at": '"$(( $(date +%s) + 129600 ))"'}
  },
  "cost": {"total_cost_usd": 3.42, "total_duration_ms": 4500000}
}' | COLUMNS=200 CLAUDE_EFFORT=high bash statusline-command.sh
```

Change `COLUMNS` to watch segments drop out:

```sh
for w in 200 160 120 90 60; do
  printf '%3d: ' "$w"
  echo '{"model":{"display_name":"Opus 5"},"workspace":{"current_dir":"'"$PWD"'"},"context_window":{"total_input_tokens":177000},"rate_limits":{"five_hour":{"used_percentage":66},"seven_day":{"used_percentage":30}}}' \
    | COLUMNS=$w CLAUDE_EFFORT=high bash statusline-command.sh
  echo
done
```

Pipe through `sed 's/\x1b\[[0-9;]*m//g'` to see the plain text and check the visible width.

### Testing

There is no automated test suite. Changes are verified by hand with the stdin snippets above — in particular against empty input (`echo '{}'`), malformed input, missing `rate_limits`, and a range of `COLUMNS` values.

### Releasing

Bump `version` in [package.json](package.json), commit, tag, and `npm publish`. The published tarball contains only `bin/` and `statusline-command.sh` (see the `files` field).

## Troubleshooting

**The status line doesn't appear.** Confirm the `statusLine` key is in `~/.claude/settings.json` and restart Claude Code. Then run the script by hand with the snippet above to check it renders.

**Effort shows `?`.** The label comes from `$CLAUDE_EFFORT` in the environment Claude Code runs the command in. If it isn't set, `?` is the honest answer.

**No `5h` / `7d` gauges.** Those need `rate_limits` in the status JSON, which isn't populated until Claude Code has seen an API response — and they're also the first things dropped when the terminal is narrow. Widen the window and send a message.

**No git branch.** The block only runs when `workspace.repo` is present in the JSON, i.e. when the cwd is inside a repo. A detached HEAD produces an empty branch name and is therefore skipped.

**Colors look wrong.** The script emits 24-bit truecolor escapes (`\033[38;2;r;g;bm`). A terminal without truecolor support will approximate or mangle them.

## FAQ

**Does it work with any terminal?** Any terminal that supports 24-bit truecolor ANSI escapes renders the gradient correctly. Others will approximate the colors.

**Does it send data anywhere?** No. Every number comes from the JSON that Claude Code pipes to the command on stdin. The script makes no network calls.

**Does it need Node.js at runtime?** No. Node ≥ 18 is used only by the `npx` installer; the status line itself is `bash` + `python3`.

**Does it slow down Claude Code?** The script is a stdin → stdout filter with no subprocesses outside a git repo, and two `git` calls with a 300 ms timeout inside one.

**Where is the architecture documented?** In [docs/architecture/](docs/architecture/), including Mermaid [diagrams](docs/architecture/diagrams.md) of the render pipeline.

## Related tools

- [claude-discord-notify](https://github.com/blakeadaniel/claude-discord-notify) — send Claude Code notifications to a Discord channel via webhook.

## License

MIT — see [LICENSE](LICENSE).

## Author

**Blake Daniel** — [@blakeadaniel](https://github.com/blakeadaniel)

Issues and pull requests: [github.com/blakeadaniel/claude-code-statusline-progress](https://github.com/blakeadaniel/claude-code-statusline-progress/issues)
