---
name: wezterm-visual-bell
description: Configure WezTerm visual bell (screen flash on terminal bell). Use when user wants to change bell color, disable the pink/red flash, or adjust bell behavior in WezTerm.
---

# WezTerm Visual Bell Configuration

Controls the screen flash when the terminal receives a bell character (e.g., pressing backspace on an empty prompt over SSH).

## Key Settings

**Color** (`colors/custom.lua`):
```lua
visual_bell = mocha.sapphire,  -- Default was mocha.red
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

**Audible bell** (`config/general.lua`):
```lua
audible_bell = 'Disabled',  -- Set to 'SystemBeep' to enable sound
```

## Available Colors

| Variable | Hex | Color |
|----------|-----|-------|
| mocha.red | #f38ba8 | Pinkish-red (default) |
| mocha.sapphire | #74c7ec | Light cyan-blue |
| mocha.surface1 | #45475a | Subtle gray |
| mocha.overlay0 | #6c7086 | Muted |
| rgba(0,0,0,0) | transparent | No flash |

## Quick Changes

- **Disable entirely**: Comment out `visual_bell` block in `config/appearance.lua`
- **Make subtle**: Set `visual_bell = mocha.surface1` in colors file
- **Silent only**: Keep `audible_bell = 'Disabled'`
