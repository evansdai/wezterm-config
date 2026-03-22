---
name: wezterm-tab-icons
description: Maintain and update WezTerm tab icons in events/tab-title.lua, including icon glyphs, zoom and unseen-output behavior, render variants, and color mapping. Use when changing tab title icons, adding new tab indicators, or debugging tab icon regressions.
allowed-tools: Read, Grep, Glob, Edit, Bash
---

# WezTerm Tab Icons

This skill defines the safe process for updating tab icons in this repository.

## Scope

- File of truth: `events/tab-title.lua`
- Entry point: `wezterm.on('format-tab-title', ...)`
- Main class: `Tab`

## Critical Implementation Anchors

- Icon constants: `GLYPH_*` values near top of file
- Segment order matrix: `RENDER_VARIANTS`
- Color map: `local colors = { ... }`
- Data capture: `Tab:set_info(...)`
- Segment creation: `Tab:create_cells()`
- Segment updates: `Tab:update_cells(...)`
- Final layout selection: `Tab:render()`

## Non-Negotiable Rules

1. Keep zoom state tab-local.
   - Use `tab.active_pane.is_zoomed` for zoom indicator state.
   - Do not compute zoom from shared pane snapshots that can bleed across tabs.

2. Keep unseen-output count sourced from tab panes.
   - Use `check_unseen_output(tab.panes)`.

3. Keep render matrix and index arithmetic in sync.
   - Any change to `RENDER_VARIANTS` requires matching updates in `Tab:render()`.

4. Keep segment names consistent across all paths.
   - If you add/rename a segment, update both `create_cells()` and `update_cells()`.

5. Keep icon positioning intentional.
   - This repo places status icons at the beginning of the tab title.

6. Keep Cells iteration ordered.
   - Always use `ipairs()` when iterating segment items in `utils/cells.lua`.
   - `pairs()` causes non-deterministic order after table insert/remove operations, breaking format command sequences.

7. Keep render paths consistent.
   - Both new-tab and cached-tab paths must call `update_cells()` before `render()`.
   - Missing color/state updates on first render causes visual corruption (e.g., lost rounded edges).

## Common Tasks

### Change zoom icon glyph

1. Update `GLYPH_ZOOM`.
2. Reload WezTerm and verify icon renders with your Nerd Font.
3. If glyph support is uncertain, temporarily use ASCII (`[Z]`) to validate logic.

### Change icon color

1. Update `Tab:update_cells(...)` color mapping for the target segment.
2. If zoom should match unseen-output style, map `zoom` to `colors['unseen_output_' .. tab_state]`.

### Add a new status icon

1. Add `GLYPH_*` constant.
2. Add new segment in `create_cells()`.
3. Add color update in `update_cells()`.
4. Extend `RENDER_VARIANTS` for all required combinations.
5. Update variant index math in `render()`.
6. Update title inset logic in `set_info()` so truncation remains correct.

## Regression Checklist

- Zoom icon appears only on the zoomed tab.
- Other tabs do not show zoom icon when one tab is zoomed.
- Unseen-output icon still appears when applicable.
- Icon order is correct (status icon before title).
- Active/hover/default states colorize as intended.

## Quick Validation

1. Open two tabs.
2. In tab A, create split panes and zoom one pane.
3. Confirm zoom icon appears in tab A only.
4. Switch to tab B and ensure no zoom icon appears there.
5. Trigger unseen output and verify unseen icon behavior is unchanged.

## Recovery Strategy

If icons disappear unexpectedly:

1. Temporarily set problematic icon to ASCII text.
2. Verify segment is present in the selected `RENDER_VARIANTS` row.
3. Verify segment color mapping is not using an invisible fg/bg combination.
4. Re-check `Tab:render()` index arithmetic against the matrix.
5. Check `utils/cells.lua` uses `ipairs()` not `pairs()` for segment item iteration (order matters for format commands).
