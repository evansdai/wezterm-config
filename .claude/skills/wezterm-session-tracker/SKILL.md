# WezTerm Agent Session Tracker

Detect Claude Code and OpenCode sessions in panes and display status icons in tab titles.

## Purpose

Tracks when AI agent sessions (Claude Code, OpenCode) are running in WezTerm panes and shows visual indicators in the tab bar:

- **Running icon** (▶) — Agent is actively working
- **Waiting icon** (⏸) — Agent is paused waiting for user input
- **No icon** — No agent session detected

## Architecture

### Core Components

| Component | File | Responsibility |
|-----------|------|----------------|
| Session Tracker | `events/session_tracker_poc.lua` | Detects processes, manages state, provides API |
| Tab Title | `events/tab-title.lua` | Renders icons via `get_tab_session_state()` |

### State Storage

Pane state is stored in a dictionary keyed by pane ID:

```lua
pane_state[pane_id] = {
   state = 'idle' | 'running' | 'debounce' | 'completed',
   process = 'claude' | 'opencode' | '',
   completed_from = 'claude' | nil,  -- what completed when in debounce
   agent_state = 'running' | 'waiting' | nil,  -- from user-var-changed
}
```

## State Machine

```
                    +----------+
     tracked        |          |   shell detected
     process   +--->|  running |------------------+
     detected  |    |          |                  |
               |    +----------+                  |
               |           |                      v
               |           |               +-----------+
               |           | debounce      |           |
               +-----------+ timeout       | debounce  |
                                           |           |
                                           +-----+-----+
                                                 |
                                                 | shell still there
                                                 v
                                           +-----------+
                                           |           |
                                           | completed |--+  agent_state cleared
                                           |           |  |
                                           +-----------+  |
                                                  |       |
                                                  v       v
                                           +-----------+  |
                                           |           |  |
                                           |   idle    |<--+
                                           |           |
                                           +-----------+
```

### State Transitions

| From | To | Trigger |
|------|-----|---------|
| idle | running | Tracked process detected (claude/opencode) |
| running | debounce | Shell process detected (zsh/bash/fish) |
| debounce | completed | Still shell on next poll |
| completed | idle | Final cleanup state |
| * | idle | Unknown/untracked process |

## Process Detection

### Tracked Processes

- `claude` / `claude-code`
- `opencode`

Detection handles:
- Direct executable names
- Full paths (e.g., `~/.claude/versions/...`)

### Debounce Mechanism

When a tracked process exits and shell appears, the tracker enters `debounce` state for one poll cycle. This prevents flickering when the agent:
- Spawns subprocesses
- Briefly yields to shell during operation

Only after shell persists does state become `completed`.

## User Variable Integration

Agents can signal their internal state via WezTerm user variables:

```bash
# Signal waiting for input
printf '\e]1337;SetUserVar=session_state=waiting\a'

# Signal actively working
printf '\e]1337;SetUserVar=session_state=running\a'

# Clear state on exit
printf '\e]1337;SetUserVar=session_state=\a'
```

### Recognized Values

| Value | Maps to |
|-------|---------|
| `waiting`, `idle`, `needs_input`, `completed` | `agent_state = 'waiting'` |
| `running`, `busy`, `working` | `agent_state = 'running'` |
| `''`, `clear` | `agent_state = nil` |

## API

### `get_tab_session_state(tab)`

Returns the session state for a tab's panes.

**Parameters:**
- `tab` — WezTerm tab object with `tab.panes` array

**Returns:**
- `'waiting'` — Agent present and waiting for input
- `'running'` — Agent present and running
- `nil` — No agent session

**Priority:** If any pane in the tab has `waiting` state, returns `waiting`. Otherwise returns `running` if any pane is running.

### `has_claude_in_tab(tab)`

Debug helper that logs process detection info.

## Integration with Tab Titles

In `events/tab-title.lua`:

```lua
local session_tracker = require('events.session_tracker_poc')

function Tab:set_info(event_opts, tab, max_width)
    -- ...
    local ok1, session_state = pcall(function()
        return session_tracker.get_tab_session_state(tab)
    end)
    self.session_state = ok1 and session_state or nil
    -- ...
end

function Tab:update_cells(event_opts, is_active, hover)
    if self.session_state == 'running' then
        self.cells:update_segment_text('session', ' ' .. GLYPH_SESSION_RUNNING)
    elseif self.session_state == 'waiting' then
        self.cells:update_segment_text('session', ' ' .. GLYPH_SESSION_WAITING)
    else
        self.cells:update_segment_text('session', ' ')
    end
    -- ...
end
```

## Key Implementation Details

### Pane ID Normalization

Pane IDs are normalized with `tonumber()` to handle potential string/number mismatches between mux pane objects (methods) and event-provided pane objects (properties).

### Process Name Handling

The `pane_process_name()` function handles both:
- **Mux pane objects**: Has `get_foreground_process_name()` method
- **Event pane objects**: Has `foreground_process_name` property only

### State Retrieval Priority

When determining tab icon:
1. Check `agent_state` (from user-vars) — most authoritative
2. Fall back to `state` (from process polling)
3. Return `nil` if neither indicates activity

## Future Todos

- [ ] **Agent-side signaling**: Create wrapper scripts or hooks for Claude Code and OpenCode that emit `session_state` user variables at appropriate lifecycle points
- [ ] **Per-pane status bar**: Extend to show agent state in right-status or a custom status overlay
- [ ] **Session history**: Track session duration and show summary when completed
- [ ] **Multi-pane tabs**: Better handling when one pane has running agent and another is idle
- [ ] **Visual polish**: Configurable icons/colors via setup options
- [ ] **Cleanup on exit**: Ensure `agent_state` is cleared when tracked process exits (currently relies on shell debounce)
- [ ] **Error handling**: Add pcall error logging in tab-title.lua for easier debugging

## Usage

### 1. Load the tracker

In `wezterm.lua`:

```lua
require('events.session_tracker_poc')  -- Auto-registers handlers
require('events.tab-title').setup()     -- Renders icons
```

### 2. Agent-side integration (optional but recommended)

For OpenCode wrapper example:

```bash
#!/bin/bash
# opencode-wrapper

# Signal running on start
printf '\e]1337;SetUserVar=session_state=running\a'

# Run actual opencode
opencode "$@"

# Clear on exit
printf '\e]1337;SetUserVar=session_state=\a'
```

### 3. Verify working

Open a new tab with Claude Code or OpenCode. The tab should show:
- ▶ when running
- ⏸ when waiting (if agent sends waiting signal)

Check logs with `WEZTERM_LOG=lua=info wezterm` to see state transitions.
