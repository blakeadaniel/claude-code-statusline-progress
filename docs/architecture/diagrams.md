# Architecture Diagrams

All diagrams below are generated from the actual source in this repo:
[`statusline-command.sh`](../../statusline-command.sh) and
[`bin/install.js`](../../bin/install.js). Component names match identifiers in the code.

Preview any block by pasting it into <https://mermaid.live>, or view inline with a
Mermaid-capable Markdown renderer.

---

## 1. System Architecture

Two independent paths: a one-time **install** path (Node) and a per-refresh **render**
path (bash + embedded Python). They meet only at two files under `~/.claude/`.

```mermaid
graph TB
    subgraph install["Install Path — runs once"]
        NPM["npm registry<br/>claude-code-statusline-progress"]
        INSTALLER["bin/install.js<br/>Node ESM, npx entrypoint"]
        PROMPT["readline prompts<br/>6 threshold values"]
    end

    subgraph repo["Package Contents"]
        SRC["statusline-command.sh<br/>bash + python3 heredoc"]
    end

    subgraph home["User Home — ~/.claude/"]
        DEST["statusline-command.sh<br/>mode 0755"]
        SETTINGS["settings.json<br/>statusLine key"]
    end

    subgraph host["Claude Code Host Process"]
        CC["Claude Code<br/>status line runner"]
        ENVV["Environment<br/>COLUMNS, CLAUDE_EFFORT"]
        JSON["Status JSON<br/>on stdin"]
    end

    subgraph render["Render Path — runs every refresh"]
        BASH["bash prologue<br/>width detection"]
        PY["python3 renderer<br/>parse → color → assemble"]
        GIT["git subprocess<br/>branch + porcelain"]
    end

    TERM["Terminal<br/>one ANSI line on stdout"]

    NPM --> INSTALLER
    INSTALLER --> PROMPT
    PROMPT -->|"threshold values"| INSTALLER
    SRC -->|"read + regex patch"| INSTALLER
    INSTALLER -->|"write 0755"| DEST
    INSTALLER -->|"merge statusLine"| SETTINGS

    SETTINGS -.->|"command: bash ~/.claude/statusline-command.sh"| CC
    CC --> ENVV
    CC --> JSON
    ENVV --> BASH
    JSON --> BASH
    BASH -->|"COLS, EFFORT, argv[1]"| PY
    DEST -.->|"is"| BASH
    PY -->|"only inside a git repo"| GIT
    GIT -->|"branch name, dirty flag"| PY
    PY --> TERM

    classDef host fill:#bcd9f5,stroke:#3b6ea5,color:#0b1c2c
    classDef external fill:#f6d9ae,stroke:#b5792a,color:#2e1d05
    classDef artifact fill:#c3e3ad,stroke:#5a8c3f,color:#12240a
    classDef output fill:#a9ddc1,stroke:#3f8c63,color:#082418
    class CC host
    class NPM,GIT external
    class DEST,SETTINGS artifact
    class TERM output
```

---

## 2. Data Flow — Status Line Render

One refresh, end to end. The script is a pure `stdin → stdout` filter; the only side
effect is the optional `git` subprocess pair.

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant SH as statusline-command.sh
    participant PY as python3 renderer
    participant GIT as git
    participant OUT as stdout

    CC->>SH: spawn with COLUMNS, CLAUDE_EFFORT set
    CC->>SH: pipe status JSON on stdin
    SH->>SH: input=$(cat)
    SH->>SH: COLS ← $COLUMNS → stty size → tput cols → 80
    SH->>PY: exec python3 with $input as argv[1]

    PY->>PY: json.loads(argv[1]) — any failure ⇒ {}
    PY->>PY: read thresholds from env (_envf), clamp danger > warn
    PY->>PY: normalize context_window, current_usage, cost, rate_limits

    alt workspace.repo present and current_dir is a directory
        PY->>GIT: git -C <dir> branch --show-current (timeout 0.3s)
        GIT-->>PY: branch name
        PY->>GIT: git -C <dir> status --porcelain (timeout 0.3s)
        GIT-->>PY: dirty or empty
    else outside a git repo
        Note over PY,GIT: zero subprocess calls
    end

    PY->>PY: build header, context bar, 5h, 7d, cost fragments
    PY->>PY: greedy fit against budget = COLS - 1
    PY->>PY: grow bar width into leftover columns (MIN_BAR..MAX_BAR)
    PY->>OUT: write one line, no trailing newline
    OUT-->>CC: rendered status line

    Note over CC,OUT: Re-runs on activity and on idle refresh — not on SIGWINCH,<br/>so a resize is picked up on the next refresh.
```

---

## 3. Data Flow — Install

```mermaid
sequenceDiagram
    participant User
    participant NPX as npx
    participant INS as bin/install.js
    participant FS as filesystem
    participant CFG as ~/.claude/settings.json

    User->>NPX: npx claude-code-statusline-progress
    NPX->>INS: run bin entrypoint
    INS->>User: showDefaults() — 3 sections, warn/danger
    INS->>User: "Customize thresholds? [y/N]"

    alt user answers y
        loop each of 3 sections
            INS->>User: "Warning at [n%]"
            User-->>INS: value
            INS->>INS: pct() — reject NaN or outside 0..100
            INS->>User: "Danger at [n%]"
            User-->>INS: value
            INS->>INS: reject danger <= warn, re-ask
        end
    else default path
        INS->>INS: defaultThresholds()
    end

    INS->>FS: read ../statusline-command.sh
    INS->>INS: patch() — regex-replace each CONSTANT = <float> with pct/100
    INS->>FS: mkdir -p ~/.claude
    INS->>FS: write ~/.claude/statusline-command.sh (mode 0o755)

    INS->>CFG: read existing settings if present
    alt settings.json is unparseable
        INS->>User: error and exit 1
    else
        INS->>INS: settings.statusLine = {type: command, command: bash <dest>}
        INS->>CFG: write merged JSON
    end

    INS->>User: "Restart Claude Code to see your statusline."
```

---

## 4. Component Relationships — Render Pipeline

Functions and the data they exchange, as defined in the Python block.

```mermaid
graph LR
    subgraph input["Input"]
        STDIN["status JSON<br/>stdin"]
        ENV["env<br/>COLS, EFFORT, thresholds"]
    end

    subgraph parse["Parse & Normalize"]
        LOAD["json.loads<br/>fallback {}"]
        ENVF["_envf<br/>threshold parsing"]
        CLAMP["danger = max(danger, warn+0.01)"]
        NUM["_num<br/>reject bool/NaN/inf"]
        CWIN["context_window guard<br/>fallback 1_000_000"]
    end

    subgraph derive["Derive"]
        USED["used tokens<br/>total_input_tokens or<br/>sum of current_usage"]
        CWD["cwd → ~ collapse"]
        BRANCH["branch_txt<br/>git subprocess"]
        PCTF["_pct_frac<br/>0-100 → 0-1"]
    end

    subgraph paint["Paint"]
        LERP["_lerp"]
        COLOR["color_for<br/>green→yellow→red"]
        CBAR["context_bar(width)"]
        UBAR["usage_bar(frac,w=6)"]
        CD["fmt_countdown"]
        KFMT["kfmt"]
    end

    subgraph frag["Fragments"]
        HDR["header<br/>model + effort + cwd + branch"]
        PCT["pct_txt / tokens_txt"]
        S5["sec5 — usage_section('5h')"]
        S7["sec7 — usage_section('7d')"]
        SC["sec_cost — cost_section"]
    end

    subgraph fit["Responsive Assembly"]
        VIS["vis()<br/>ANSI-stripped length"]
        ASM["assemble(bar_w, flags)"]
        FITS["fits() vs budget"]
        GROW["grow bar MIN_BAR..MAX_BAR"]
    end

    OUT["stdout — one line"]

    STDIN --> LOAD
    ENV --> ENVF --> CLAMP
    LOAD --> CWIN
    LOAD --> NUM
    CWIN --> USED
    NUM --> USED
    LOAD --> CWD
    LOAD --> BRANCH
    LOAD --> PCTF

    CLAMP --> COLOR
    LERP --> COLOR
    COLOR --> CBAR
    COLOR --> UBAR

    USED --> CBAR
    USED --> KFMT --> PCT
    COLOR --> PCT
    CWD --> HDR
    BRANCH --> HDR
    ENV --> HDR

    PCTF --> S5
    PCTF --> S7
    UBAR --> S5
    UBAR --> S7
    CD --> S5
    CD --> S7
    NUM --> SC

    HDR --> ASM
    PCT --> ASM
    S5 --> ASM
    S7 --> ASM
    SC --> ASM
    CBAR --> ASM

    ASM --> VIS --> FITS --> GROW --> OUT

    classDef host fill:#bcd9f5,stroke:#3b6ea5,color:#0b1c2c
    classDef external fill:#f6d9ae,stroke:#b5792a,color:#2e1d05
    classDef output fill:#a9ddc1,stroke:#3f8c63,color:#082418
    class STDIN,ENV host
    class BRANCH external
    class OUT output
```

---

## 5. Input Contract — Status JSON

The stdin object as the renderer consumes it. Every field is optional; each has an
explicit fallback. Types are what the code accepts after `_num` / `isinstance` guards.

```mermaid
classDiagram
    class StatusInput {
        +ModelInfo model
        +Workspace workspace
        +string cwd
        +ContextWindow context_window
        +Cost cost
        +RateLimits rate_limits
    }

    class ModelInfo {
        +string display_name
    }

    class Workspace {
        +string current_dir
        +object repo
    }

    class ContextWindow {
        +number context_window_size
        +number total_input_tokens
        +CurrentUsage current_usage
    }

    class CurrentUsage {
        +number input_tokens
        +number cache_creation_input_tokens
        +number cache_read_input_tokens
    }

    class Cost {
        +number total_cost_usd
        +number total_duration_ms
    }

    class RateLimits {
        +Window five_hour
        +Window seven_day
    }

    class Window {
        +number used_percentage
        +number resets_at
    }

    StatusInput --> ModelInfo : model
    StatusInput --> Workspace : workspace
    StatusInput --> ContextWindow : context_window
    StatusInput --> Cost : cost
    StatusInput --> RateLimits : rate_limits
    ContextWindow --> CurrentUsage : current_usage
    RateLimits --> Window : five_hour
    RateLimits --> Window : seven_day

    note for ModelInfo "missing ⇒ 'Claude'"
    note for Workspace "repo present ⇒ git lookup enabled"
    note for ContextWindow "size missing/invalid ⇒ 1_000_000"
    note for CurrentUsage "summed only when total_input_tokens is absent"
    note for Cost "negative values treated as absent"
    note for Window "used_percentage is 0-100; resets_at is a unix timestamp"
```

---

## 6. State Machine — Bar Cell Color

`color_for(frac, warn, danger)` maps a fraction to an RGB escape. Cells are colored by
their own position `(j+1)/width`, not by the overall fill, so a bar gradients across
itself.

```mermaid
stateDiagram-v2
    [*] --> Empty: no usage data
    [*] --> Safe: frac computed

    Empty --> [*]: all cells GREY ░

    Safe --> Warn: frac > warn
    Warn --> Danger: frac > danger
    Danger --> Warn: frac <= danger
    Warn --> Safe: frac <= warn

    Danger --> [*]
    Safe --> [*]
    Warn --> [*]

    note right of Safe
        frac <= warn
        _lerp(GREEN, YELLOW, frac/warn)
    end note

    note right of Warn
        warn < frac <= danger
        _lerp(YELLOW, RED, (frac-warn)/(danger-warn))
    end note

    note right of Danger
        frac > danger
        solid RED (220,40,40)
    end note
```

Threshold pairs, each `_envf`-overridable and clamped so `danger > warn`:

| Gauge | Warn | Danger |
|---|---|---|
| Context window | `CONTEXT_WARN` 0.20 | `CONTEXT_DANGER` 0.50 |
| 5-hour usage | `USAGE_5H_WARN` 0.50 | `USAGE_5H_DANGER` 0.90 |
| 7-day usage | `USAGE_7D_WARN` 0.50 | `USAGE_7D_DANGER` 0.90 |

---

## 7. Responsive Degradation Ladder

Segments are enabled greedily at `MIN_BAR` width in strict priority order, then the bar
absorbs whatever columns remain.

```mermaid
graph TD
    START["budget = max(vis(header)+MIN_BAR+4, COLS-1)"]
    T{"used is None?"}
    TON["with_tokens = True<br/>(token label is the only detail)"]
    TFIT{"fits(MIN_BAR, tokens)?"}
    TYES["with_tokens = True"]
    TNO["tokens hidden"]

    F5{"sec5 exists and fits?"}
    F5Y["with5 = True"]
    F7{"sec7 exists and fits?"}
    F7Y["with7 = True"]

    FC{"sec_cost exists<br/>AND (sec7 absent OR with7)<br/>AND fits?"}
    FCY["with_cost = True"]
    FCN["cost deferred —<br/>never outranks a hidden 7d"]

    GROW["used_cols = vis(assemble(MIN_BAR, flags))<br/>bar_w = clamp(MIN_BAR + budget - used_cols, MIN_BAR, MAX_BAR)"]
    EMIT["assemble(bar_w, flags) → stdout"]

    START --> T
    T -->|yes| TON --> F5
    T -->|no| TFIT
    TFIT -->|yes| TYES --> F5
    TFIT -->|no| TNO --> F5

    F5 -->|yes| F5Y --> F7
    F5 -->|no| F7
    F7 -->|yes| F7Y --> FC
    F7 -->|no| FC
    FC -->|yes| FCY --> GROW
    FC -->|no| FCN --> GROW
    GROW --> EMIT

    classDef host fill:#bcd9f5,stroke:#3b6ea5,color:#0b1c2c
    classDef output fill:#a9ddc1,stroke:#3f8c63,color:#082418
    classDef caveat fill:#f2e6a0,stroke:#a89428,color:#2b2405
    class START host
    class EMIT output
    class FCN caveat
```

---

## 8. Directory Structure

```mermaid
graph TD
    ROOT["claude-code-statusline-progress/"]

    ROOT --> BIN["bin/"]
    ROOT --> SCRIPT["statusline-command.sh<br/>the whole renderer"]
    ROOT --> PKG["package.json<br/>bin entry, files allowlist"]
    ROOT --> SNIP["settings-snippet.json<br/>manual-install fragment"]
    ROOT --> SETUP["setup-prompt.md<br/>agent-driven install"]
    ROOT --> RM["README.md"]
    ROOT --> LIC["LICENSE — MIT"]
    ROOT --> DOCS["docs/architecture/"]

    BIN --> INSTALL["install.js<br/>npx installer"]
    DOCS --> DR["README.md"]
    DOCS --> DD["diagrams.md"]

    classDef host fill:#bcd9f5,stroke:#3b6ea5,color:#0b1c2c
    classDef artifact fill:#c3e3ad,stroke:#5a8c3f,color:#12240a
    classDef caveat fill:#f2e6a0,stroke:#a89428,color:#2b2405
    class ROOT host
    class SCRIPT,INSTALL artifact
    class DOCS caveat
```
