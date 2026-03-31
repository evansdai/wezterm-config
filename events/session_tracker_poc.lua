local wezterm = require('wezterm')
wezterm.log_info('[Tracker] module loading...')

local nf = wezterm.nerdfonts

local TRACKED_PROCESSES = {
   claude = true,
   ['claude-code'] = true,
   opencode = true,
}

local GLYPH_CLAUDE = nf.cod_account or 'C'

local SHELL_PROCESSES = {
   zsh = true,
   bash = true,
   fish = true,
}

local pane_state = {}
local tab_state = {}

local function basename(proc)
   proc = proc or ''
   local name = proc:match('([^/\\]+)$') or proc
   name = name:gsub('%.exe$', '')
   return string.lower(name)
end

local function identify_process(proc)
   local raw = string.lower(proc or '')
   local name = basename(raw)

   if TRACKED_PROCESSES[name] then
      return name
   end

   if raw:find('claude%-code') or raw:find('claude/versions/', 1, true) or raw:find('/claude/', 1, true) then
      return 'claude'
   end

   return nil
end

local function pane_id_of(pane)
   if not pane then
      return nil
   end

   local pane_id = nil

   if type(pane.pane_id) == 'function' then
      local ok, id = pcall(function() return pane:pane_id() end)
      if ok then
         pane_id = id
      end
   else
      pane_id = pane.pane_id
   end

   -- Normalize to number if possible, to handle string/number mismatches
   return tonumber(pane_id) or pane_id
end

local function tab_id_of(tab)
   if not tab then
      return nil
   end

   local tab_id = nil

   if type(tab.tab_id) == 'function' then
      local ok, id = pcall(function() return tab:tab_id() end)
      if ok then
         tab_id = id
      end
   else
      tab_id = tab.tab_id
   end

   return tonumber(tab_id) or tab_id
end

local function pane_process_name(pane)
   if not pane then
      return ''
   end

   if type(pane.get_foreground_process_name) == 'function' then
      local ok, proc = pcall(function() return pane:get_foreground_process_name() end)
      if ok and proc then
         return proc
      end
   end

   -- Fallback for event-provided pane objects (e.g., from format-tab-title)
   -- which have the property but not the method
   if pane.foreground_process_name then
      return pane.foreground_process_name
   end

   return ''
end

local function get_state(pane_id)
   local state = pane_state[pane_id]
   if not state then
      state = { state = 'idle', process = '' }
      pane_state[pane_id] = state
   end
   return state
end

local function log(msg)
   wezterm.log_info('[Tracker] ' .. msg)
end

local function is_tracked_process(proc)
   return identify_process(proc) ~= nil
end

local function set_state(pane_id, state, process, completed_from)
   local current = pane_state[pane_id] or {}
   pane_state[pane_id] = {
      state = state,
      process = process or '',
      completed_from = completed_from,
      agent_state = current.agent_state,
   }
end

local function set_agent_state(pane, value)
   local pane_id = pane_id_of(pane)
   if not pane_id then
      return
   end

   local current = get_state(pane_id)
   local normalized = string.lower(value or '')

   if normalized == 'waiting' or normalized == 'idle' or normalized == 'needs_input' or normalized == 'completed' then
      current.agent_state = 'waiting'
      current.agent_state_from_osc = true
   elseif normalized == 'running' or normalized == 'busy' or normalized == 'working' then
      current.agent_state = 'running'
      current.agent_state_from_osc = true
   elseif normalized == '' or normalized == 'clear' then
      current.agent_state = nil
      current.agent_state_from_osc = false
   else
      log(string.format('pane %d: ignoring unknown session_state=%s', pane_id, normalized))
      return
   end

   pane_state[pane_id] = current
   log(string.format('pane %d: session_state=%s (OSC)', pane_id, current.agent_state or 'cleared'))
end

local function update_pane(pane)
   local pane_id = pane_id_of(pane)
   if not pane_id then
      return
   end

   local current = get_state(pane_id)
    local raw_proc = pane_process_name(pane)
   local proc = identify_process(raw_proc) or basename(raw_proc)

     if TRACKED_PROCESSES[proc] then
       if current.state == 'debounce' then
          log(string.format('pane %d: debounce -> running (false alarm, %s)', pane_id, proc))
       elseif current.state ~= 'running' then
          log(string.format('pane %d: %s -> running (%s)', pane_id, current.state, proc))
       end
       set_state(pane_id, 'running', proc)
       -- Don't set agent_state from poller - let OSC signals be authoritative
       -- Fallback only: if no agent_state yet, assume running for tracked processes
       if not pane_state[pane_id].agent_state and current.agent_state == nil then
          pane_state[pane_id].agent_state = 'running'
       end
       return
    end

   if SHELL_PROCESSES[proc] then
      if current.state == 'running' then
         log(string.format('pane %d: running -> debounce (%s)', pane_id, proc))
         set_state(pane_id, 'debounce', proc, current.process)
         return
      end

        if current.state == 'debounce' then
           log(string.format('pane %d: COMPLETED (%s)', pane_id, current.completed_from or current.process or '?'))
           set_state(pane_id, 'completed', proc, current.completed_from or current.process)
           -- Only clear agent_state if it wasn't set by OSC (avoid fighting signals)
           if not current.agent_state_from_osc then
              pane_state[pane_id].agent_state = nil
           end
           return
        end

       if current.state ~= 'idle' then
          log(string.format('pane %d: %s -> idle (%s)', pane_id, current.state, proc))
        end
        set_state(pane_id, 'idle', proc)
       -- Only clear agent_state if it wasn't set by OSC
       if not current.agent_state_from_osc then
          pane_state[pane_id].agent_state = nil
       end
       return
     end

    if current.state ~= 'idle' then
       log(string.format('pane %d: %s -> idle (%s)', pane_id, current.state, proc))
     end
     set_state(pane_id, 'idle', proc)
    -- Only clear agent_state if it wasn't set by OSC
    if not current.agent_state_from_osc then
       pane_state[pane_id].agent_state = nil
    end
 end

local function update_tab_state(tab, panes)
   local tab_id = tab_id_of(tab)
   if not tab_id then
      return
   end

   if not panes then
      local ok, resolved_panes = pcall(function() return tab:panes() end)
      if not ok or not resolved_panes then
         tab_state[tab_id] = nil
         return
      end
      panes = resolved_panes
   end

   local running_count = 0
   local waiting_count = 0
   local completed_count = 0

    for _, pane in ipairs(panes) do
       local state = pane_state[pane_id_of(pane)]
       if state then
          -- Prioritize agent_state (from OSC signals) over polled state
          if state.agent_state == 'waiting' then
             waiting_count = waiting_count + 1
          elseif state.agent_state == 'running' then
             running_count = running_count + 1
          -- Fallback to polled state when no agent_state
          elseif state.state == 'running' then
             running_count = running_count + 1
          elseif state.state == 'completed' then
             completed_count = completed_count + 1
          end
       end
    end

   if running_count > 0 then
      tab_state[tab_id] = {
         state = 'running',
         running = running_count,
         waiting = waiting_count,
         completed = completed_count,
      }
   elseif waiting_count > 0 then
      tab_state[tab_id] = {
         state = 'waiting',
         running = 0,
         waiting = waiting_count,
         completed = completed_count,
      }
   elseif completed_count > 0 then
      tab_state[tab_id] = {
         state = 'completed',
         running = 0,
         waiting = 0,
         completed = completed_count,
      }
   else
      tab_state[tab_id] = nil
   end
end

local function tab_has_running(tab)
   for _, pane in ipairs(tab.panes or {}) do
      local state = pane_state[pane_id_of(pane)]
      if state and state.state == 'running' then
         return true
      end
   end
   return false
end

local function tab_has_completed(tab)
   for _, pane in ipairs(tab.panes or {}) do
      local state = pane_state[pane_id_of(pane)]
      if state and state.state == 'completed' then
         return true
      end
   end
   return false
end

local function tab_has_claude(tab)
   for _, pane in ipairs(tab.panes or {}) do
      local raw_proc = pane_process_name(pane)
      local proc = basename(raw_proc)
      local pane_id = pane_id_of(pane) or -1
      local tracked_proc = identify_process(raw_proc)
      log(string.format('tab %s pane %d: checking process "%s" (basename: "%s")', tab.tab_id, pane_id, raw_proc, proc))
      if tracked_proc then
         log(string.format('tab %s: detected tracked process in pane %d (%s)', tab.tab_id, pane_id, tracked_proc))
         return true
      end
   end
   return false
end

local first_update = true
local function poll_all_panes(window)
   if first_update then
      log('first poll executed')
      first_update = false
   end

   local ok, mux_window = pcall(function() return window:mux_window() end)
   if not ok or not mux_window then
      return
   end

   local ok2, tabs = pcall(function() return mux_window:tabs() end)
   if not ok2 or not tabs then
      return
   end

   local live_tab_ids = {}

   for _, tab in ipairs(tabs) do
      local tab_id = tab_id_of(tab)
      if tab_id then
         live_tab_ids[tab_id] = true
      end

      local ok3, panes = pcall(function() return tab:panes() end)
      if ok3 and panes then
         for _, pane in ipairs(panes) do
            update_pane(pane)
         end
         update_tab_state(tab, panes)
      elseif tab_id then
         tab_state[tab_id] = nil
      end
   end

   -- Clean up state for closed tabs
   for tab_id in pairs(tab_state) do
      if not live_tab_ids[tab_id] then
         tab_state[tab_id] = nil
      end
   end
end

wezterm.on('update-status', poll_all_panes)
wezterm.on('user-var-changed', function(_window, pane, name, value)
   if name == 'session_state' or name == 'agent_state' then
      set_agent_state(pane, value)

      local ok, tab = pcall(function() return pane:tab() end)
      if ok and tab then
         update_tab_state(tab)
      end
   end
end)

local M = {}

---Get tab session state with counts
---Returns state string and counts table, or nil if no tracked sessions
---@param tab_or_tab_id table|number
---@return string|nil state 'running', 'waiting', or 'completed'
---@return table|nil counts {running: number, waiting: number, completed: number}
function M.get_tab_session_state(tab_or_tab_id)
   local tab_id = tab_or_tab_id
   if type(tab_or_tab_id) == 'table' then
      tab_id = tab_id_of(tab_or_tab_id)
   end

   local state = tab_state[tab_id]
   if not state then
      return nil, nil
   end

   return state.state, {
      running = state.running or 0,
      waiting = state.waiting or 0,
      completed = state.completed or 0,
   }
end

function M.has_claude_in_tab(tab)
   return tab_has_claude(tab)
end

M.GLYPH_CLAUDE = GLYPH_CLAUDE

wezterm.log_info('[Tracker] module loaded, handlers registered')

return M
