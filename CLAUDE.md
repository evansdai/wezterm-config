# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a modular WezTerm terminal emulator configuration written in Lua. The configuration features a custom class-based architecture with object-oriented patterns for managing settings, events, and utilities.

## Architecture

### Core Configuration Pattern

The configuration uses a builder pattern implemented in `config/init.lua`:

- `Config` class provides `:init()` and `:append()` methods to build configuration incrementally
- `wezterm.lua` is the main entry point that chains configuration modules together
- Configuration modules return tables that are merged via `Config:append()`
- Duplicate keys trigger warnings but don't break the configuration

### Directory Structure

```
config/        - Configuration modules (appearance, bindings, domains, fonts, general, launch)
events/        - Event handlers for WezTerm lifecycle events
utils/         - Utility modules (backdrops, GPU adapter, platform detection, etc.)
colors/        - Custom color scheme definitions
backdrops/     - Background images for the terminal
```

### Key Components

**BackDrops System (`utils/backdrops.lua`)**
- Object-oriented singleton managing background images
- Must call `:set_images()` in `wezterm.lua` (not in sub-modules) due to WezTerm's coroutine restrictions
- Supports cycling, random selection, fuzzy search, and focus mode
- Chain methods: `:set_images_dir()` -> `:set_focus()` -> `:set_images()` -> `:random()`

**GPU Adapter Selection (`utils/gpu-adapter.lua`)**
- Only works when `front_end = 'WebGpu'` in `config/appearance.lua`
- Automatically selects best GPU and graphics API combo
- Platform-aware: Dx12/Vulkan/OpenGL on Windows, Vulkan/OpenGL on Linux, Metal on macOS

**Key Bindings (`config/bindings.lua`)**
- Platform-aware modifier keys defined in `mod` table
- macOS: `SUPER` = Super, `SUPER_REV` = Super+Ctrl
- Windows/Linux: `SUPER` = Alt, `SUPER_REV` = Alt+Ctrl
- Custom events prefixed with namespace (e.g., `tabs.toggle-tab-bar`, `tabs.manual-update-tab-title`)

**Event System (`events/`)**
- Each event handler exports a `setup()` function called from `wezterm.lua`
- Handlers use `wezterm.on()` to register event listeners
- Configuration passed to `setup()` (e.g., `{ date_format = '%a %H:%M:%S' }`)

## Development Commands

### Linting and Formatting

```bash
# Format Lua code (excludes config/init.lua)
stylua -g '!/config/init.lua' --check wezterm.lua colors/ config/ events/ utils/

# Lint Lua code
luacheck wezterm.lua colors/* config/* events/* utils/*
```

### Style Configuration

- **StyLua**: 3 spaces, LuaJIT syntax, Unix line endings, single quotes preferred
- **Luacheck**: LuaJIT standard, max line length 150, ignores warning 241 (unused variables)
- Special case: `utils/backdrops.lua` ignores warning 212 (unused argument)

## Important Patterns

### Adding New Configuration Options

1. Create a new file in `config/` that returns a table of options
2. Require and append it in `wezterm.lua` using `Config:append()`
3. Ensure no duplicate keys with existing configuration

### Adding Event Handlers

1. Create a new file in `events/` with a `setup()` function
2. Register event listeners inside `setup()` using `wezterm.on()`
3. Call `require('events.your-event').setup()` in `wezterm.lua`

### Platform-Specific Code

Use `require('utils.platform')` which provides:
- `platform.is_win`, `platform.is_linux`, `platform.is_mac`
- Consistent platform detection across the configuration

### Customization Points

Users typically modify:
- `config/domains.lua` - SSH/WSL domain configuration
- `config/launch.lua` - Shell preferences and paths
- `backdrops/` - Add/remove background images
- `config/bindings.lua` - Custom key bindings

## Testing Changes

WezTerm automatically reloads configuration when files change (`automatically_reload_config = true`). Check for errors in the WezTerm debug overlay (F12).
