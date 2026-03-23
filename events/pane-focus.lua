local wezterm = require('wezterm')

local M = {}

local last_pane_id = nil

---Check if pane is the only pane in its tab
---@param pane any The pane object
---@return boolean True if pane is the only one in the tab
local function is_only_pane_in_tab(pane)
   local tab = pane:tab()
   if not tab then
      return true
   end
   local panes = tab:panes()
   return #panes <= 1
end

---Check if the active pane in the tab is zoomed
---@param pane any The pane object
---@return boolean True if the active pane is zoomed
local function is_zoomed_pane(pane)
   local tab = pane:tab()
   if not tab then
      return false
   end
   local panes_info = tab:panes_with_info()
   for _, p in ipairs(panes_info) do
      if p.is_zoomed then
         return true
      end
   end
   return false
end

---Setup pane focus event handler
M.setup = function()
   wezterm.on('update-status', function(window, pane)
      if not pane then
         return
      end

      local current_pane_id = pane:pane_id()

      -- Trigger bell when active pane changes (unless zoomed or single pane)
      if last_pane_id ~= current_pane_id then
         local should_bell = true

         -- Skip bell if this is the only pane in the tab
         if is_only_pane_in_tab(pane) then
            should_bell = false
         end

         -- Skip bell if the pane is zoomed
         if is_zoomed_pane(pane) then
            should_bell = false
         end

         if should_bell then
            pane:inject_output('\x07')
         end

         last_pane_id = current_pane_id
      end
   end)
end

return M
