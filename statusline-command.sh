#!/usr/bin/env bash
# Claude Code statusLine — model, effort, cwd, context-window bar, 5h/7d usage from native rate_limits fields.
# Renders e.g.:  Opus 4.8 [high] ~/code/project [██████░░░░░░░░░░░░░░] 18% 177k / 1000k tokens  │  5h: ████░░ 66% 4h46m  │  7d: ██░░░░ 30% 1d12h
input=$(cat)

# ── Terminal width detection ─────────────────────────────────────────────────
# Claude Code sets $COLUMNS before invoking the statusLine command (v2.1.153+
# per the official docs), so prefer it first. The script's stdout is captured
# rather than connected to a real terminal, so tty-based detection (stty/tput)
# is unreliable here — those are kept only as fallbacks for manual testing
# outside Claude Code. Guard against $COLUMNS being present but invalid
# (non-numeric, or 0 — a zero-width terminal makes no sense) by falling
# through to the next source rather than accepting it.
COLS="${COLUMNS:-}"
[[ "$COLS" =~ ^[0-9]+$ ]] && [[ "$COLS" -gt 0 ]] || COLS=$(stty size </dev/tty 2>/dev/null | awk '{print $2}')
[[ "$COLS" =~ ^[0-9]+$ ]] && [[ "$COLS" -gt 0 ]] || COLS=$(tput cols 2>/dev/null)
[[ "$COLS" =~ ^[0-9]+$ ]] && [[ "$COLS" -gt 0 ]] || COLS=80

# ── Render ────────────────────────────────────────────────────────────────────
EFFORT="${CLAUDE_EFFORT:-?}" \
COLS="$COLS" \
python3 - "$input" <<'PY'
import json, math, os, re, sys, datetime

MIN_BAR      = 3     # narrowest the context bar ever shrinks to
MAX_BAR      = 20    # widest it grows on roomy terminals
COLS         = int(os.environ.get("COLS") or 80)

_ANSI = re.compile(r"\033\[[0-9;]*m")
def vis(s):
    """Visible length of a string, ignoring ANSI color escapes."""
    return len(_ANSI.sub("", s))

# Thresholds: fraction at which the bar transitions green→yellow (warn) and yellow→red (danger)
CONTEXT_WARN   = 0.20
CONTEXT_DANGER = 0.50
USAGE_5H_WARN   = 0.50
USAGE_5H_DANGER = 0.90
USAGE_7D_WARN   = 0.50
USAGE_7D_DANGER = 0.90

try:
    data = json.loads(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].strip() else {}
except Exception:
    data = {}

cw = data.get("context_window")
if not isinstance(cw, dict):
    cw = {}
CONTEXT_MAX = cw.get("context_window_size") or 1_000_000
if (
    isinstance(CONTEXT_MAX, bool)
    or not isinstance(CONTEXT_MAX, (int, float))
    or not math.isfinite(CONTEXT_MAX)
    or CONTEXT_MAX <= 0
):
    CONTEXT_MAX = 1_000_000

model      = (data.get("model") or {}).get("display_name") or "Claude"
effort     = os.environ.get("EFFORT", "?")

cwd = (data.get("workspace") or {}).get("current_dir") or data.get("cwd") or ""
home = os.path.expanduser("~")
if cwd == home:
    cwd = "~"
elif cwd.startswith(home + os.sep):
    cwd = "~" + cwd[len(home):]

# ── Current context usage ────────────────────────────────────────────────────
def _num(v):
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) else None

current_usage = cw.get("current_usage")
if not isinstance(current_usage, dict):
    current_usage = {}

used = _num(cw.get("total_input_tokens"))
if used is None and current_usage:
    input_tok = _num(current_usage.get("input_tokens", 0))
    cache_create_tok = _num(current_usage.get("cache_creation_input_tokens", 0))
    cache_read_tok = _num(current_usage.get("cache_read_input_tokens", 0))
    if None in (input_tok, cache_create_tok, cache_read_tok):
        used = None
    else:
        used = input_tok + cache_create_tok + cache_read_tok

# ── Colors ────────────────────────────────────────────────────────────────────
RESET  = "\033[0m"
GREY   = "\033[90m"
BLUE   = "\033[38;2;97;175;239m"
BOLD   = "\033[1m"
GREEN  = (40, 200, 40)
YELLOW = (230, 210, 0)
RED    = (220, 40, 40)

def _lerp(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

def color_for(frac, warn=0.20, danger=0.50):
    if frac <= warn:
        r, g, b = _lerp(GREEN, YELLOW, frac / warn)
    elif frac <= danger:
        r, g, b = _lerp(YELLOW, RED, (frac - warn) / (danger - warn))
    else:
        r, g, b = RED
    return f"\033[38;2;{r};{g};{b}m"

def usage_color(frac, warn, danger):
    return color_for(frac, warn=warn, danger=danger)

def kfmt(n):
    return f"{round(n / 1000)}k"

def usage_bar(frac, warn, danger, width=6):
    filled = max(0, min(width, round(frac * width)))
    cells = []
    for j in range(width):
        if j < filled:
            cells.append(f"{usage_color((j + 1) / width, warn, danger)}█")
        else:
            cells.append(f"{GREY}░")
    return "[" + "".join(cells) + RESET + "]"

def fmt_countdown(ts):
    """Unix timestamp → compact countdown string."""
    secs = max(0, int(ts) - int(datetime.datetime.now(datetime.timezone.utc).timestamp()))
    if secs < 3600:
        return f"{secs // 60}m"
    if secs < 86400:
        h, m = divmod(secs, 3600)
        return f"{h}h{m // 60:02d}m" if m >= 60 else f"{h}h"
    d, rem = divmod(secs, 86400)
    return f"{d}d{rem // 3600}h"

# ── Build the context bar at an arbitrary width ──────────────────────────────
def context_bar(width):
    if used is None:
        return f"{GREY}{'░' * width}{RESET}"
    filled = max(0, min(width, round(frac * width)))
    cells  = []
    for j in range(width):
        if j < filled:
            cells.append(f"{color_for((j + 1) / width, warn=CONTEXT_WARN, danger=CONTEXT_DANGER)}█")
        else:
            cells.append(f"{GREY}░")
    return "".join(cells) + RESET

# Pre-build the fixed text fragments (these don't change with terminal width).
header = f"{BOLD}{model}{RESET} {GREY}[{effort}]{RESET}"
if cwd:
    header += f" {BLUE}{cwd}{RESET}"

if used is not None:
    frac       = used / CONTEXT_MAX
    pct_txt    = f"{color_for(frac, warn=CONTEXT_WARN, danger=CONTEXT_DANGER)}{frac * 100:.0f}%{RESET}"
    tokens_txt = f"{GREY}{kfmt(used)} / {kfmt(CONTEXT_MAX)} tokens{RESET}"
else:
    frac       = 0.0
    pct_txt    = ""
    tokens_txt = f"{GREY}-- / {kfmt(CONTEXT_MAX)} tokens{RESET}"

# ── Session cost / duration ──────────────────────────────────────────────────
cost_data = data.get("cost")
if not isinstance(cost_data, dict):
    cost_data = {}
total_cost = _num(cost_data.get("total_cost_usd"))
total_duration_ms = _num(cost_data.get("total_duration_ms"))
# Negative values are nonsensical (and would render mathematically wrong
# strings via divmod()'s floor-toward-negative-infinity behavior) — treat
# them the same as "no data yet", same as 0.
if total_cost is not None and total_cost < 0:
    total_cost = None
if total_duration_ms is not None and total_duration_ms < 0:
    total_duration_ms = None

# ── 5h / 7d from native rate_limits fields ───────────────────────────────────
SEP = f"  {GREY}│{RESET}  "
rl = data.get("rate_limits")
if not isinstance(rl, dict):
    rl = {}
five_hour = rl.get("five_hour")
if not isinstance(five_hour, dict):
    five_hour = {}
seven_day = rl.get("seven_day")
if not isinstance(seven_day, dict):
    seven_day = {}

def usage_section(label, util, warn, danger, reset):
    if util is None:
        return None
    frac_u = float(util)
    clr    = usage_color(frac_u, warn, danger)
    pct    = f"{clr}{frac_u * 100:.0f}%{RESET}"
    bar    = usage_bar(frac_u, warn, danger)
    cd     = f" {GREY}{fmt_countdown(reset)}{RESET}" if reset is not None else ""
    return f"{SEP}{GREY}{label}:{RESET} {bar} {pct}{cd}"

def _pct_frac(v):
    """used_percentage is 0-100; usage_section expects a 0-1 fraction."""
    v = _num(v)
    return None if v is None else v / 100

sec5 = usage_section("5h", _pct_frac(five_hour.get("used_percentage")),
                     USAGE_5H_WARN, USAGE_5H_DANGER,
                     _num(five_hour.get("resets_at")))
sec7 = usage_section("7d", _pct_frac(seven_day.get("used_percentage")),
                     USAGE_7D_WARN, USAGE_7D_DANGER,
                     _num(seven_day.get("resets_at")))

def cost_section():
    if not total_cost and not total_duration_ms:
        return None
    parts = []
    if total_cost:
        parts.append(f"${total_cost:.2f}")
    if total_duration_ms:
        secs = int(total_duration_ms / 1000)
        h, rem = divmod(secs, 3600)
        m, s = divmod(rem, 60)
        parts.append(f"{h}h{m:02d}m" if h else f"{m}m{s:02d}s")
    return f"{SEP}{GREY}{' · '.join(parts)}{RESET}"

sec_cost = cost_section()

# ── Responsive assembly ──────────────────────────────────────────────────────
def assemble(bar_w, with_tokens, with5, with7, with_cost):
    s = f"{header} [{context_bar(bar_w)}]"
    if pct_txt:
        s += f" {pct_txt}"
    if with_tokens:
        s += f" {tokens_txt}"
    if with5 and sec5:
        s += sec5
    if with7 and sec7:
        s += sec7
    if with_cost and sec_cost:
        s += sec_cost
    return s

# Leave a 1-column margin; never demand less than header + a minimum bar fits.
budget = max(vis(header) + MIN_BAR + 4, COLS - 1)

def fits(bw, t, a, b, c):
    return vis(assemble(bw, t, a, b, c)) <= budget

# Greedily enable optional segments at the minimum bar width, in priority order:
# context token detail → 5h gauge → 7d gauge → cost/duration. When usage is
# unknown the token label is the only context detail, so it is always shown.
with_tokens = used is None
with5 = with7 = with_cost = False
if used is not None and fits(MIN_BAR, True, with5, with7, with_cost):
    with_tokens = True
if sec5 and fits(MIN_BAR, with_tokens, True, with7, with_cost):
    with5 = True
if sec7 and fits(MIN_BAR, with_tokens, with5, True, with_cost):
    with7 = True
# Cost is strictly lowest priority: never let it render while a
# higher-priority segment that HAS data was hidden by the width check.
# (If 7d has no data at all — sec7 is None — there's nothing to defer to.)
if sec_cost and (not sec7 or with7) and fits(MIN_BAR, with_tokens, with5, with7, True):
    with_cost = True

# Grow the context bar to soak up whatever horizontal room is left.
used_cols = vis(assemble(MIN_BAR, with_tokens, with5, with7, with_cost))
bar_w     = max(MIN_BAR, min(MAX_BAR, MIN_BAR + (budget - used_cols)))

sys.stdout.write(assemble(bar_w, with_tokens, with5, with7, with_cost))
PY
