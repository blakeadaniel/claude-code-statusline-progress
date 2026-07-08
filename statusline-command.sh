#!/usr/bin/env bash
# Claude Code statusLine — model, effort, cwd, context-window bar, 5h/7d usage from Anthropic headers.
# Renders e.g.:  Opus 4.8 [high] ~/code/project [██████░░░░░░░░░░░░░░] 18% 177k / 1000k tokens  │  5h: ████░░ 66% 4h46m  │  7d: ██░░░░ 30% 1d12h
input=$(cat)

# ── Unified rate-limit headers (cached 60 s, async background refresh) ───────
LIMITS_CACHE="/tmp/claude-unified-limits-cache.json"
CREDS_FILE="${HOME}/.claude/.credentials.json"
CACHE_TTL=60

now_s=$(date +%s)
cache_age=9999
if [[ -f "$LIMITS_CACHE" ]]; then
    cache_mtime=$(stat -c %Y "$LIMITS_CACHE" 2>/dev/null || echo 0)
    cache_age=$(( now_s - cache_mtime ))
fi

if [[ $cache_age -gt $CACHE_TTL && -f "$CREDS_FILE" ]]; then
    (
        python3 - "$CREDS_FILE" <<'PY' > "${LIMITS_CACHE}.tmp" 2>/dev/null \
            && mv "${LIMITS_CACHE}.tmp" "$LIMITS_CACHE"
import json, urllib.request, sys
with open(sys.argv[1]) as f:
    token = json.load(f)["claudeAiOauth"]["accessToken"]
req = urllib.request.Request(
    "https://api.anthropic.com/v1/messages",
    data=json.dumps({
        "model": "claude-haiku-4-5-20251001",
        "max_tokens": 1,
        "messages": [{"role": "user", "content": "x"}],
    }).encode(),
    headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "anthropic-version": "2023-06-01",
        "anthropic-beta": "claude-code-20250219",
    },
    method="POST",
)
try:
    resp = urllib.request.urlopen(req, timeout=8)
    hdrs = dict(resp.headers)
except urllib.error.HTTPError as e:
    hdrs = dict(e.headers)
result = {k: v for k, v in hdrs.items() if "ratelimit-unified" in k.lower()}
if result:
    print(json.dumps(result))
PY
    ) &
    disown $!
fi

LIMITS_JSON=""
[[ -f "$LIMITS_CACHE" ]] && LIMITS_JSON=$(cat "$LIMITS_CACHE")

# ── Terminal width detection ─────────────────────────────────────────────────
# The statusLine command is spawned with stdout piped, so query the controlling
# terminal directly. Fall back through $COLUMNS, tput, then a sane default.
COLS=$(stty size </dev/tty 2>/dev/null | awk '{print $2}')
[[ "$COLS" =~ ^[0-9]+$ ]] || COLS="${COLUMNS:-}"
[[ "$COLS" =~ ^[0-9]+$ ]] || COLS=$(tput cols 2>/dev/null)
[[ "$COLS" =~ ^[0-9]+$ ]] || COLS=80

# ── Render ────────────────────────────────────────────────────────────────────
EFFORT="${CLAUDE_EFFORT:-?}" \
LIMITS_JSON="$LIMITS_JSON" \
COLS="$COLS" \
python3 - "$input" <<'PY'
import json, os, re, sys, datetime

CONTEXT_MAX = 1_000_000
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

model      = (data.get("model") or {}).get("display_name") or "Claude"
effort     = os.environ.get("EFFORT", "?")
transcript = data.get("transcript_path") or ""

cwd = (data.get("workspace") or {}).get("current_dir") or data.get("cwd") or ""
home = os.path.expanduser("~")
if cwd == home:
    cwd = "~"
elif cwd.startswith(home + os.sep):
    cwd = "~" + cwd[len(home):]

# ── Current context usage ────────────────────────────────────────────────────
used = None
if transcript and os.path.exists(transcript):
    try:
        last = None
        with open(transcript) as fh:
            for line in fh:
                if '"usage"' not in line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                u = (rec.get("message") or {}).get("usage") or rec.get("usage")
                if isinstance(u, dict) and ("input_tokens" in u or "cache_read_input_tokens" in u):
                    last = u
        if last:
            used = (last.get("input_tokens", 0)
                    + last.get("cache_creation_input_tokens", 0)
                    + last.get("cache_read_input_tokens", 0))
    except Exception:
        used = None

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

# ── 5h / 7d from Anthropic unified rate-limit headers ────────────────────────
SEP = f"  {GREY}│{RESET}  "
limits_raw = os.environ.get("LIMITS_JSON", "")
h = {}
if limits_raw:
    try:
        h = json.loads(limits_raw)
    except Exception:
        pass

def usage_section(label, util, warn, danger, reset):
    if util is None:
        return None
    frac_u = float(util)
    clr    = usage_color(frac_u, warn, danger)
    pct    = f"{clr}{frac_u * 100:.0f}%{RESET}"
    bar    = usage_bar(frac_u, warn, danger)
    cd     = f" {GREY}{fmt_countdown(reset)}{RESET}" if reset else ""
    return f"{SEP}{GREY}{label}:{RESET} {bar} {pct}{cd}"

sec5 = usage_section("5h", h.get("anthropic-ratelimit-unified-5h-utilization"),
                     USAGE_5H_WARN, USAGE_5H_DANGER,
                     h.get("anthropic-ratelimit-unified-5h-reset"))
sec7 = usage_section("7d", h.get("anthropic-ratelimit-unified-7d-utilization"),
                     USAGE_7D_WARN, USAGE_7D_DANGER,
                     h.get("anthropic-ratelimit-unified-7d-reset"))

# ── Responsive assembly ──────────────────────────────────────────────────────
def assemble(bar_w, with_tokens, with5, with7):
    s = f"{header} [{context_bar(bar_w)}]"
    if pct_txt:
        s += f" {pct_txt}"
    if with_tokens:
        s += f" {tokens_txt}"
    if with5 and sec5:
        s += sec5
    if with7 and sec7:
        s += sec7
    return s

# Leave a 1-column margin; never demand less than header + a minimum bar fits.
budget = max(vis(header) + MIN_BAR + 4, COLS - 1)

def fits(bw, t, a, b):
    return vis(assemble(bw, t, a, b)) <= budget

# Greedily enable optional segments at the minimum bar width, in priority order:
# context token detail → 5h gauge → 7d gauge. When usage is unknown the token
# label is the only context detail, so it is always shown.
with_tokens = used is None
with5 = with7 = False
if used is not None and fits(MIN_BAR, True, with5, with7):
    with_tokens = True
if sec5 and fits(MIN_BAR, with_tokens, True, with7):
    with5 = True
if sec7 and fits(MIN_BAR, with_tokens, with5, True):
    with7 = True

# Grow the context bar to soak up whatever horizontal room is left.
used_cols = vis(assemble(MIN_BAR, with_tokens, with5, with7))
bar_w     = max(MIN_BAR, min(MAX_BAR, MIN_BAR + (budget - used_cols)))

sys.stdout.write(assemble(bar_w, with_tokens, with5, with7))
PY
