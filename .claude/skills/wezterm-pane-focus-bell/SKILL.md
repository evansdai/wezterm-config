---
name: wezterm-pane-focus-bell
description: Trigger WezTerm visual bell when switching focus to a new pane. Use when the user wants to flash the screen on pane activation, bell on focus change, or visual feedback when switching panels/tabs.
---

# WezTerm Pane Focus Bell

Trigger the visual bell effect whenever you switch focus to a different pane, providing visual feedback for pane activation.

## How It Works

The solution uses WezTerm's `update-status` event to track pane ID changes. When the active pane changes, it injects a BEL character (`\x07`) to trigger the configured visual bell.

## Installation

### 1. Create the Event Handler

Create `events/pane-focus.lua`:

```lua
local wezterm = require('wezterm')

local M = {}

local last_pane_id = nil

M.setup = function()
   wezterm.on('update-status', function(window, pane)
      if not pane then
         return
      end

      local current_pane_id = pane:pane_id()

      -- Trigger bell when active pane changes
      if last_pane_id ~= current_pane_id then
         pane:inject_output('\x07')
         last_pane_id = current_pane_id
      end
   end)
end

return M
```

### 2. Register in wezterm.lua

Add to your `wezterm.lua`:

```lua
require('events.pane-focus').setup()
```

### 3. Ensure status_update_interval is Set

In `config/general.lua` (or your config):

```lua
status_update_interval = 1000,  -- Check every 1000ms
```

## Configuration

The visual bell appearance is controlled by existing settings:

**Color** (`colors/custom.lua`):
```lua
visual_bell = mocha.sapphire,  -- Or any color
```

**Animation** (`config/appearance.lua`):
```lua
visual_bell = {
   fade_in_function = 'EaseIn',
   fade_in_duration_ms = 150,
   fade_out_function = 'EaseOut',
   fade_out_duration_ms = 300,
   target = 'BackgroundColor',
}
```

**Audible Bell** (`config/general.lua`):
```lua
audible_bell = 'Disabled',  -- Keep disabled to avoid sound
```

## Common Issues

| Issue | Solution |
|-------|----------|
| Bell not triggering | Verify `status_update_interval` is set |
| No visual flash | Check `visual_bell` animation durations are > 0 |
| Flash too slow | Reduce `fade_in_duration_ms` and `fade_out_duration_ms` |

## Why This Approach

- **`pane-focus-changed` doesn't exist** — WezTerm has no built-in pane focus event
- **`update-status` fires regularly** — Uses existing polling mechanism
- **`pane:inject_output('\x07')`** — Standard way to trigger bell programmatically
- **Simple state tracking** — Compare pane IDs to detect changes

## See Also

- [wezterm-visual-bell](wezterm-visual-bell) — Configure bell color and animation
- WezTerm docs: https://wezfurlong.org/wezterm/config/lua/pane/inject_output.html
