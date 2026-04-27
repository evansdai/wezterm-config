---
name: wezterm-session-tracker
description: |
  Understand and maintain the WezTerm agent session tracker in events/session_tracker_poc.lua and its tab-title.lua integration.
  ALWAYS invoke this skill when modifying session tracking, agent state detection, tab session icons, debounce logic,
  OpenCode/Claude process detection, stale icon cleanup, redraw behavior, or OSC user-variable handling for agent state.
  Do NOT edit session_tracker_poc.lua or session-related code in tab-title.lua without reading this skill first.
  Keywords: session tracker, agent state, pane state, debounce, OSC signal, tab icon, claude detection, opencode detection, stale waiting icon, session_state, user-var-changed, tab refresh
---

# WezTerm Agent Session Tracker

Detects Claude Code and OpenCode sessions in WezTerm panes and displays status icons in tab titles.

## Visual Contract

| Tab Icon | Meaning |
|----------|---------|
| Running glyph (play) | Agent is actively working |
| Waiting glyph (badge) | Agent is paused, waiting for user input |
| No icon | No agent session detected in this tab |

When multiple panes in a tab have active sessions, a count is appended (e.g. "play-icon 3").

## Files

| File | Role |
|------|------|
| `events/session_tracker_poc.lua` | Core tracker: process detection, state machine, OSC handling, public API |
| `events/tab-title.lua` | Consumer: calls `get_tab_session_state()`, renders session segment in tab bar |
| `SESSION_TRACKER_SIGNALING_PLAN.md` | Design doc for the signaling contract |

## Recent Reliability Updates

- Expanded shell detection to cover Windows shells: `pwsh`, `pwsh-preview`, `powershell`, `cmd`, `nu`, and `wsl` in addition to `zsh`, `bash`, and `fish`.
- Expanded OpenCode detection beyond bare process name matching to include packaged/native binary path patterns on Windows, Linux, and macOS.
- Added stale OSC cleanup for shell-only idle states so a missed `session_state=''` signal does not leave a waiting icon stuck after OpenCode exits.
- Added a tab-bar refresh step when tab session state actually changes so icon removal is reflected immediately instead of waiting for a later redraw.

## Pane State Storage

```lua
pane_state[pane_id] = {
   state              = 'idle' | 'running' | 'debounce' | 'completed',
   process            = 'claude' | 'opencode' | 'bash' | ...,
   completed_from     = 'claude' | nil,        -- remembers which agent completed
   agent_state        = 'running' | 'waiting' | nil,  -- from OSC user-var signals
   agent_state_from_osc = true | false | nil,  -- whether agent_state was set by OSC
   shell_polls        = number,                -- consecutive shell polls while idle/debounce
}
```

### Critical field: `agent_state_from_osc`

This boolean flag tracks whether `agent_state` was set explicitly via an OSC escape sequence (user-var-changed event) rather than inferred. It controls two behaviors:

1. **Preservation across `set_state()` calls**: Both `agent_state` and `agent_state_from_osc` are copied from the previous state when `set_state()` is called. Without this, every poll cycle that calls `set_state()` would wipe the OSC signal.

2. **Selective clearing on idle**: When a pane transitions to idle (shell detected, no prior running/debounce), `agent_state` is only cleared if `agent_state_from_osc` is false. This prevents polling from overriding an explicit OSC signal.

3. **Unconditional clearing on completion**: When a session completes (debounce -> shell persists), both `agent_state` and `agent_state_from_osc` are cleared unconditionally -- the session is over.

### Supporting field: `shell_polls`

This counter tracks consecutive polls where a shell is foregrounded.

1. It confirms the normal `running -> debounce -> completed` exit path.
2. It provides a fallback cleanup path for OSC-only states that would otherwise linger at the shell.
3. It must be reset when a tracked process or subprocess is seen again.

## Pane State Machine

```
                    +-----------+
     tracked        |           |    shell detected
     process   +--->|  running  |-------------------+
     detected  |    |           |                   |
               |    +-----+-----+                   |
               |          |                         v
               |          | non-shell,        +-----------+
               |          | non-tracked       |           |
               |          | process      +--->| debounce  |<--- stays here if
               |          +------------->|   |           |     non-shell non-tracked
               |                         |   +-----+-----+     process detected
               |                         |         |
               |                         +---------+
               |                               |
               |                               | shell still there (2nd poll)
               |                               v
               |                         +-----------+
               |                         |           |
               |                         | completed | agent_state = nil (cleared)
               |                         |           | agent_state_from_osc = false
               |                         +-----+-----+
               |                               |
               |                               | next poll -> shell still there
               |                               v
               |                         +-----------+
               |                         |           |
               +-------------------------|   idle    |
                 (on next agent launch)  |           |
                                         +-----------+
```

### Transition Table

| From | To | Trigger | Notes |
|------|----|---------|-------|
| idle | running | Tracked process detected as foreground | No default `agent_state` is set; relies on OSC or tab-level fallback |
| running | debounce | Shell (zsh/bash/fish) becomes foreground | `completed_from` preserves which agent was running |
| running | debounce | Non-tracked, non-shell process (e.g. node, go) | Agent subprocess -- stays sticky in debounce |
| debounce | running | Tracked process detected again | False alarm; agent returned |
| debounce | debounce | Non-tracked, non-shell process still running | Subprocess still active; stays in debounce |
| debounce | completed | Shell detected on consecutive poll | Agent truly exited; clears `agent_state` and `agent_state_from_osc` |
| completed | idle | Next poll cycle | Transient state; clears on next update |
| any non-running/debounce | idle | Shell or unknown process | Default fallback for unrecognized states |

### Important: No Default `agent_state` on Detection

When a tracked process is first detected (idle -> running), the tracker does **not** set `agent_state = 'waiting'` or any default. This was a deliberate fix. The tab-level fallback in `update_tab_state()` handles this: if `state == 'running'` or `state == 'debounce'` but `agent_state` is nil, the pane counts as running for tab display purposes.

## Process Detection

### Tracked Processes

Defined in `TRACKED_PROCESSES` table:
- `claude`
- `claude-code`
- `opencode`

The `identify_process()` function also matches:
- Full paths containing `claude-code` pattern
- Paths containing `claude/versions/` (npm-installed Claude)
- Paths containing `/claude/`
- OpenCode packaged binary paths such as `opencode-windows-*`, `opencode-linux-*`, `opencode-darwin-*`
- Standalone OpenCode install paths such as `.opencode/bin/opencode` and `.opencode\\bin\\opencode`
- Binary-like tails such as `/bin/opencode`, `\\bin\\opencode.exe`, or `/opencode`

### Shell Processes

Defined in `SHELL_PROCESSES` table: `zsh`, `bash`, `fish`, `pwsh`, `pwsh-preview`, `powershell`, `cmd`, `nu`, `wsl`

Shell detection triggers debounce/completion logic.

### Everything Else

Non-tracked, non-shell processes (e.g. `node`, `go`, `python`) are treated as potential agent subprocesses when the pane was previously running or in debounce. They keep the pane in debounce (sticky behavior) to avoid premature completion.

## Debounce Mechanism

The debounce exists because agents frequently spawn subprocesses or briefly yield to shell during operation. Without debounce, the tab icon would flicker.

**Two-poll confirmation**: A pane only transitions from debounce to completed when shell is detected on two consecutive polls. The first shell detection enters debounce; the second confirms exit.

**Subprocess stickiness**: If a non-tracked, non-shell process is running while in debounce, the pane stays in debounce. This handles cases like `claude` spawning `node` or `go` subprocesses.

**Debounce -> running recovery**: If the tracked process reappears during debounce, the pane returns to running (false alarm).

**Idle shell stale-state cleanup**: If the pane remains at a known shell for consecutive polls while an OSC-derived state still exists, the tracker clears that stale OSC state. This prevents the OpenCode waiting icon from sticking after exit when the clear signal is missed.

## OSC User Variable Integration

Agents can signal their internal state via WezTerm user variables (OSC 1337 SetUserVar):

```bash
# Signal waiting for input
printf '\033]1337;SetUserVar=%s=%s\007' session_state $(echo -n waiting | base64)

# Signal actively working
printf '\033]1337;SetUserVar=%s=%s\007' session_state $(echo -n running | base64)

# Clear state on exit
printf '\033]1337;SetUserVar=%s=%s\007' session_state $(echo -n "" | base64)
```

Both `session_state` and `agent_state` user var names are accepted.

### Value Mapping

| OSC Value | Maps To | Group |
|-----------|---------|-------|
| `waiting`, `idle`, `needs_input` | `agent_state = 'waiting'`, `agent_state_from_osc = true` | Waiting |
| `running`, `busy`, `working` | `agent_state = 'running'`, `agent_state_from_osc = true` | Running |
| `''` (empty), `clear`, `completed` | `agent_state = nil`, `agent_state_from_osc = false` | Clear |

Note: `completed` maps to **clear**, not waiting. This is intentional -- an OSC `completed` signal means the session ended.

## Tab State Aggregation

`update_tab_state(tab, panes)` aggregates all pane states into a single tab-level state stored in `tab_state[tab_id]`.

State changes are compared against the previous tab snapshot. The tracker only triggers a redraw when the aggregate tab state actually changed.

### Priority Logic

For each pane, state is determined by:

1. **OSC `agent_state` takes priority** -- if `agent_state == 'waiting'`, count as waiting; if `agent_state == 'running'`, count as running
2. **Fallback to polled state** -- if no `agent_state`, but `state == 'running'` or `state == 'debounce'`, count as running

### Tab State Resolution

```lua
tab_state[tab_id] = {
   state   = 'running' | 'waiting',  -- tab-level summary
   running = number,                  -- count of running panes
   waiting = number,                  -- count of waiting panes
}
-- or nil if no active sessions
```

- If `running_count > 0` -> tab state is `'running'` (running takes priority)
- Else if `waiting_count > 0` -> tab state is `'waiting'`
- Else -> `tab_state[tab_id] = nil` (no icon shown)

There is no `completed` tab state. Completed panes have their `agent_state` cleared, so they don't contribute to any count, and the icon disappears naturally.

## Public API

### `M.get_tab_session_state(tab_or_tab_id)`

Returns the session state for a tab.

**Parameters:**
- `tab_or_tab_id` -- WezTerm tab object (with `:tab_id()` method) or numeric tab ID

**Returns (two values):**
1. `state: string|nil` -- `'running'`, `'waiting'`, or `nil`
2. `counts: table|nil` -- `{ running = number, waiting = number }` or `nil`

**Usage:**
```lua
local state, counts = session_tracker.get_tab_session_state(tab.tab_id)
if state then
   -- state is 'running' or 'waiting'
   -- counts.running and counts.waiting are available
end
```

### `M.has_claude_in_tab(tab)`

Debug helper. Checks if any pane in the tab has a tracked process. Logs detection details.

### `M.GLYPH_CLAUDE`

Exported glyph constant for Claude icon (`nf.cod_account`).

## Tab-Title Integration

`events/tab-title.lua` is the consumer. Key integration points:

### `Tab:set_info()` (line ~238)

```lua
local session_tracker = require('events.session_tracker_poc')

local ok1, session_state, session_counts = pcall(function()
   return session_tracker.get_tab_session_state(tab.tab_id)
end)
self.session_state = ok1 and session_state or nil
self.session_counts = ok1 and session_counts or nil
```

Note: `pcall` wrapping returns all values from the inner function.

### Inset Calculation

When `session_state` is non-nil, `inset` increases by 2 (icon space). If `counts.running + counts.waiting > 1`, inset increases by 3 more (for the count digits).

### `Tab:update_cells()` (line ~311)

Builds the session segment text:
- No session: `' '` (empty space)
- Single active pane: `' ' .. glyph` (icon only)
- Multiple active panes: `string.format(' %s%d', glyph, total_active)` (icon + count)

Glyph selection: `GLYPH_SESSION_RUNNING` for `'running'`, `GLYPH_SESSION_WAITING` for `'waiting'`.

### Color Mapping

Session segment colors are resolved via:
```lua
colors['session_' .. (self.session_state or 'running') .. '_' .. tab_state]
```

Color keys defined:
- `session_running_default/hover/active` -- green foreground (#A6E3A1)
- `session_waiting_default/hover/active` -- orange foreground (#FAB387)

### Render Variants

Every render variant includes the `'session'` segment (it renders as a space when inactive). The session segment sits between `scircle_left` and the next icon (zoom/admin/wsl/title).

## Event Registration

The tracker self-registers two event handlers on module load (no `.setup()` call needed):

1. **`update-status`** -- Polls all panes in all tabs every status update cycle via `poll_all_panes(window)`
2. **`user-var-changed`** -- Listens for `session_state` or `agent_state` user var changes, calls `set_agent_state()`, then immediately updates the affected tab state

## Refresh Behavior

The tracker uses a small `refresh_tab_bar(window)` helper that re-applies the current config overrides via `window:set_config_overrides(overrides or {})`.

- This is used only when the aggregate tab session state changes.
- The goal is to force `format-tab-title` to run promptly so stale icons disappear immediately.
- Keep this path narrow because `set_config_overrides()` causes a window config reload event.

## Lifecycle

1. Module loads -> registers event handlers
2. WezTerm fires `update-status` -> `poll_all_panes()` iterates all tabs/panes
3. For each pane: `update_pane()` updates `pane_state[pane_id]`
4. For each tab: `update_tab_state()` aggregates pane states into `tab_state[tab_id]`
5. Stale tab state is cleaned up for closed tabs
6. `format-tab-title` fires -> `tab-title.lua` calls `get_tab_session_state(tab_id)` -> renders icon

OSC signals (step 2b): When `user-var-changed` fires, `set_agent_state()` updates `agent_state`/`agent_state_from_osc` on the pane, then immediately recalculates the tab state for instant UI feedback.
When either polling or OSC handling changes the aggregate tab state, the tracker forces a redraw so the icon state is refreshed immediately.

## Key Invariants and Gotchas

1. **`set_state()` must preserve `agent_state` and `agent_state_from_osc`**: The function rebuilds the state table from scratch. If it doesn't copy these fields from the previous state, OSC signals get wiped every poll cycle. This was the primary bug that caused the running icon to disappear.

2. **`set_state()` must also preserve/reset `shell_polls` intentionally**: The counter is part of stale-state cleanup. Forgetting it breaks completion confirmation or causes premature stale clearing.

3. **`completed` OSC value maps to clear, not waiting**: An agent sending `completed` means "session over". It must not result in a waiting icon.

4. **No default `agent_state` on agent detection**: When transitioning idle -> running, do NOT set `agent_state = 'waiting'`. The tab-level fallback handles display. Setting a default caused incorrect waiting icons when the agent was actually running.

5. **Debounce counts as running at tab level**: In `update_tab_state()`, `state == 'debounce'` contributes to `running_count` (when no OSC signal overrides it). This prevents the icon from disappearing during subprocess execution.

6. **Completion clears unconditionally**: When debounce -> completed, both `agent_state` and `agent_state_from_osc` are set to nil/false regardless of their previous values. The session is over.

7. **Idle shell fallback must clear stale OSC state after consecutive shell polls**: This is the fix for the stuck OpenCode waiting icon when exit signaling is missed.

8. **`tab-title.lua` must not reference `counts.completed`**: There is no `completed` count. Only `counts.running` and `counts.waiting` exist. Referencing `counts.completed` causes nil arithmetic errors.

9. **Pane ID normalization**: Always use `tonumber(pane_id) or pane_id` because mux pane objects (with methods) and event-provided pane objects (with properties) may return different types.

10. **`pane_process_name()` dual access**: Must handle both `:get_foreground_process_name()` method (mux panes) and `.foreground_process_name` property (event panes).

11. **Subprocess stickiness**: Non-tracked, non-shell processes keep the pane in debounce if it was previously running or in debounce. This prevents agent subprocesses from triggering premature idle.

12. **Windows shell coverage matters**: If `SHELL_PROCESSES` misses the shell in `config/launch.lua`, completion and stale waiting-icon cleanup can fail on that platform.

13. **OpenCode often needs path-based detection**: Do not rely only on basename `opencode`; packaged installs may surface distinctive path fragments instead.

14. **Refresh only on real tab-state changes**: The redraw helper is intentionally gated to avoid unnecessary `window-config-reloaded` churn.

## Adding a New Tracked Process

1. Add the process name to `TRACKED_PROCESSES` table
2. If the process has unusual path patterns, add detection logic to `identify_process()`
3. No changes needed in tab-title.lua (it's agent-agnostic)

## Adding New OSC Signal Values

1. Add the value string to the appropriate group in `set_agent_state()`:
   - Waiting group: `normalized == 'your_value'`
   - Running group: `normalized == 'your_value'`
   - Clear group: `normalized == 'your_value'`
2. No changes needed elsewhere

## Debugging

- All state transitions are logged with `[Tracker]` prefix
- View logs: run WezTerm with `WEZTERM_LOG=lua=info wezterm`
- Check WezTerm debug overlay: F12
- WezTerm auto-reloads config on file save (`automatically_reload_config = true`)
