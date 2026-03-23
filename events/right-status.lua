local wezterm = require('wezterm')
local umath = require('utils.math')
local Cells = require('utils.cells')
local OptsValidator = require('utils.opts-validator')
local system_stats = require('utils.system-stats')

---@alias Event.RightStatusOptions { date_format?: string }

---Setup options for the right status bar
local EVENT_OPTS = {}

---@type OptsSchema
EVENT_OPTS.schema = {
   {
      name = 'date_format',
      type = 'string',
      default = '%a %d %b %H:%M',
   },
}
EVENT_OPTS.validator = OptsValidator:new(EVENT_OPTS.schema)

local nf = wezterm.nerdfonts
local attr = Cells.attr

local M = {}

local ICON_DATE = nf.fa_calendar
local ICON_CPU = nf.md_chip
local ICON_MEMORY = nf.md_memory
local ICON_SWAP = nf.md_swap_horizontal

---@type string[]
local discharging_icons = {
   nf.md_battery_10,
   nf.md_battery_20,
   nf.md_battery_30,
   nf.md_battery_40,
   nf.md_battery_50,
   nf.md_battery_60,
   nf.md_battery_70,
   nf.md_battery_80,
   nf.md_battery_90,
   nf.md_battery,
}
---@type string[]
local charging_icons = {
   nf.md_battery_charging_10,
   nf.md_battery_charging_20,
   nf.md_battery_charging_30,
   nf.md_battery_charging_40,
   nf.md_battery_charging_50,
   nf.md_battery_charging_60,
   nf.md_battery_charging_70,
   nf.md_battery_charging_80,
   nf.md_battery_charging_90,
   nf.md_battery_charging,
}

---@type table<string, Cells.SegmentColors>
-- stylua: ignore
local colors = {
   date       = { fg = '#fab387', bg = 'rgba(0, 0, 0, 0.4)' },
   cpu        = { fg = '#a6e3a1', bg = 'rgba(0, 0, 0, 0.4)' },
   memory     = { fg = '#89b4fa', bg = 'rgba(0, 0, 0, 0.4)' },
   memory_warn = { fg = '#f9e2af', bg = 'rgba(0, 0, 0, 0.4)' },
   memory_crit = { fg = '#f38ba8', bg = 'rgba(0, 0, 0, 0.4)' },
   battery    = { fg = '#f9e2af', bg = 'rgba(0, 0, 0, 0.4)' },
   separator  = { fg = '#74c7ec', bg = 'rgba(0, 0, 0, 0.4)' }
}

local cells = Cells:new()

cells
   :add_segment('date_icon', ICON_DATE .. '  ', colors.date, attr(attr.intensity('Bold')))
   :add_segment('date_text', '', colors.date, attr(attr.intensity('Bold')))
   :add_segment('cpu_icon', '  ' .. ICON_CPU .. ' ', colors.cpu)
   :add_segment('cpu_text', '', colors.cpu, attr(attr.intensity('Bold')))
   :add_segment('memory_icon', '  ' .. ICON_MEMORY .. ' ', colors.memory)
   :add_segment('memory_text', '', colors.memory, attr(attr.intensity('Bold')))
   :add_segment('swap_icon', ' ' .. ICON_SWAP .. ' ', colors.memory)
   :add_segment('swap_text', '', colors.memory, attr(attr.intensity('Bold')))
   :add_segment('spacer', '  ', colors.memory)
   :add_segment('battery_icon', '', colors.battery)
   :add_segment('battery_text', '', colors.battery, attr(attr.intensity('Bold')))

---@return string, string
local function battery_info()
   -- ref: https://wezfurlong.org/wezterm/config/lua/wezterm/battery_info.html

   local charge = ''
   local icon = ''

   for _, b in ipairs(wezterm.battery_info()) do
      local idx = umath.clamp(umath.round(b.state_of_charge * 10), 1, 10)
      charge = string.format('%.0f%%', b.state_of_charge * 100)

      if b.state == 'Charging' then
         icon = charging_icons[idx]
      else
         icon = discharging_icons[idx]
      end
   end

   return charge, icon .. ' '
end

---@param opts? Event.RightStatusOptions Default: {date_format = '%a %H:%M:%S'}
M.setup = function(opts)
   local valid_opts, err = EVENT_OPTS.validator:validate(opts or {})

   if err then
      wezterm.log_error(err)
   end

   wezterm.on('update-right-status', function(window, _)
      local success, result = pcall(function()
         local battery_text, battery_icon = battery_info()
         local cpu_usage = system_stats.get_cpu_usage()
         local memory_usage = system_stats.get_memory_usage()
         -- Just do not show swap
         -- local swap_info = system_stats.get_swap_usage()

         local memory_color = colors.memory
         local swap_color = colors.memory
         local show_swap = false
         local swap_info = nil

         -- Uncomment to enable swap display
         -- swap_info = system_stats.get_swap_usage()
         -- if swap_info then
         --    show_swap = true
         --    if swap_info.status == 'critical' then
         --       memory_color = colors.memory_crit
         --       swap_color = colors.memory_crit
         --    elseif swap_info.status == 'warning' then
         --       memory_color = colors.memory_warn
         --       swap_color = colors.memory_warn
         --    end
         -- end

         cells
            :update_segment_text('date_text', wezterm.strftime(valid_opts.date_format))
            :update_segment_text('cpu_text', cpu_usage)
            :update_segment_text('memory_text', memory_usage)
            :update_segment_colors('memory_icon', memory_color)
            :update_segment_colors('memory_text', memory_color)

         if show_swap and swap_info then
            cells
               :update_segment_text('swap_text', swap_info.text)
               :update_segment_colors('swap_icon', swap_color)
               :update_segment_colors('swap_text', swap_color)
         else
            cells:update_segment_text('swap_text', '')
         end

         cells
            :update_segment_text('battery_icon', battery_icon)
            :update_segment_text('battery_text', battery_text)

         local segments = {
            'date_icon',
            'date_text',
            'cpu_icon',
            'cpu_text',
            'memory_icon',
            'memory_text',
         }

         if show_swap then
            table.insert(segments, 'swap_icon')
            table.insert(segments, 'swap_text')
         end

         table.insert(segments, 'spacer')
         table.insert(segments, 'battery_icon')
         table.insert(segments, 'battery_text')

         window:set_right_status(wezterm.format(cells:render(segments)))
      end)

      if not success then
         wezterm.log_error('right-status error: ' .. tostring(result))
      end
   end)
end

return M
