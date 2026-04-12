# claude.nvim

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/goropikari/claude.nvim)

A Neovim plugin that monitors [Claude Code](https://claude.ai/code) session states — waiting for approval, working, or idle — across multiple terminal buffers.

Sessions are matched to [terminals.nvim](https://github.com/goropikari/terminals.nvim) terminal buffers via process ancestry, and listed in a [snacks.nvim](https://github.com/folke/snacks.nvim) picker. A statusline API lets you surface session state anywhere in your UI.

## How it looks

**Picker (`:ClaudeStatus`)**

```
⏳  ~/projects/api    a1b2c3d4  buf:5      ← waiting for approval
⚙   ~/projects/web    e5f6g7h8  buf:8      ← working
✓   ~/projects/infra  i9j0k1l2  (no terminal)
```

Press `<CR>` to jump to the matching terminal in terminals.nvim.

**Statusline**

```
⏳1 ⚙ 2        ← summary: counts per status
⏳⚙ ✓          ← detail: one icon per session
```

## Requirements

- [folke/snacks.nvim](https://github.com/folke/snacks.nvim)
- `jq` (available on `$PATH`)
- [goropikari/terminals.nvim](https://github.com/goropikari/terminals.nvim) _(optional)_

## Installation

### lazy.nvim

```lua
{
  "goropikari/claude.nvim",
  build = "make",  -- ensures hook.sh is executable
  dependencies = {
    "folke/snacks.nvim",
    -- "goropikari/terminals.nvim",  -- optional
  },
  opts = {},
}
```

> `build = "make"` can be omitted — the plugin sets the executable bit on load automatically.

## Setup

After installing, run this **once** to register the Claude Code hooks:

```
:ClaudeInstallHooks
```

This copies `hook.sh` to `stdpath("data")/claude-nvim/hook.sh` and merges the following into `~/.claude/settings.json` (existing settings are preserved; a `.bak` backup is written first):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/share/nvim/claude-nvim/hook.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/share/nvim/claude-nvim/hook.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/share/nvim/claude-nvim/hook.sh"
          }
        ]
      }
    ]
  }
}
```

## Commands and Lua API

| Command               | Lua API                             | Description                                          |
| --------------------- | ----------------------------------- | ---------------------------------------------------- |
| `:ClaudeStatus`       | `require("claude").pick()`          | Open the session picker                              |
| `:ClaudeInstallHooks` | `require("claude").install_hooks()` | Write Claude Code hooks to `~/.claude/settings.json` |

**Picker keymaps:**

| Key           | Action                                      |
| ------------- | ------------------------------------------- |
| `<CR>`        | Open the matched terminal in terminals.nvim |
| `<Esc>` / `q` | Close the picker                            |

### Statusline

| Lua API                                  | Returns                            | Description                                    |
| ---------------------------------------- | ---------------------------------- | ---------------------------------------------- |
| `require("claude").statusline_summary()` | `"⏳1 ⚙ 2"`                        | Counts per status; zero-count statuses omitted |
| `require("claude").statusline_detail()`  | `"⏳⚙ ✓ "`                         | One icon per session                           |
| `require("claude").statusline_counts()`  | `{ waiting=1, working=2, idle=0 }` | Raw counts table                               |

Results are cached for `cache_ttl` seconds (default: 2) to keep statusline rendering fast.

### Lower-level submodules

```lua
-- Raw session table for this Neovim instance
-- { [session_id] = { session_id, status, cwd, ancestor_pids, updated_at } }
require("claude.session").load()

-- All terminal buffers (buftype == "terminal") with job PID and terminals.nvim metadata
require("claude.terminal").get_all()

-- Match terminals to a session via ancestor PID lookup (falls back to cwd)
require("claude.terminal").find_by_session(terminals_map, session)

-- Statusline submodule
require("claude.statusline").setup(opts)
require("claude.statusline").counts()
require("claude.statusline").summary()
require("claude.statusline").detail()
```

## Statusline integration

```lua
-- raw statusline
vim.o.statusline = "%{%v:lua.require('claude').statusline_summary()%}"
```

## Configuration

```lua
require("claude").setup({
  -- "all" (default): show every terminal buffer (buftype == "terminal")
  -- "terminals.nvim": restrict to terminals managed by goropikari/terminals.nvim;
  --                   <CR> uses terminals.nvim's window management to open them
  terminals = "all",

  statusline = {
    icons = {
      waiting = "󰚡 ",   -- default: "⏳"
      working = "󰒋 ",   -- default: "⚙ "
      idle    = "󰄴 ",   -- default: "✓ "
    },
    cache_ttl = 3,       -- seconds between state-file reads (default: 2)
  },
})
```

## How it works

```
Claude Code session
  │
  │  lifecycle hooks (Notification / PreToolUse / Stop)
  ▼
scripts/hook.sh
  │  writes /tmp/claude-sessions/<nvim-instance>/session-<id>.json
  │  stores ancestor PIDs at hook execution time
  ▼
:ClaudeStatus / statusline
  │  reads state files for this Neovim instance only
  │  matches sessions to terminal buffers via ancestor PID lookup
  ▼
snacks.nvim picker  ──<CR>──►  terminals.nvim window
```

### Session states

| State     | Icon | Trigger                                      |
| --------- | ---- | -------------------------------------------- |
| `waiting` | ⏳   | `Notification` hook with `permission_prompt` |
| `working` | ⚙    | `PreToolUse` hook                            |
| `idle`    | ✓    | `Stop` hook                                  |

### Terminal matching

When a hook fires, `hook.sh` walks the process tree from its own PID up to the root and records the full ancestor PID list in the session JSON. At query time, each terminal buffer's job PID is checked against that list — no `/proc` traversal needed after the fact. Falls back to `cwd` matching when ancestor data is unavailable.

### Per-instance isolation

Session state files are stored under `/tmp/claude-sessions/<key>/` where `<key>` is derived from the Neovim server socket path (`$NVIM` / `vim.v.servername`). Each Neovim instance only sees its own sessions. Files are cleaned up automatically on `VimLeavePre`.

Sessions older than 1 hour are silently ignored.
