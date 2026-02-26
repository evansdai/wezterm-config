local wezterm = require('wezterm')
local platform = require('utils.platform')

local M = {}

---@class SystemStats.Cache
---@field value string
---@field last_update number

---@type table<string, SystemStats.Cache>
local cache = {
   cpu = { value = 'N/A', last_update = 0 },
   memory = { value = 'N/A', last_update = 0 },
}

local CACHE_DURATION = 2 -- seconds

---Execute a command and return stdout
---@param cmd table Command and arguments as array
---@return string|nil
local function run_command(cmd)
   local success, stdout, stderr = wezterm.run_child_process(cmd)
   if success then
      return stdout
   end
   return nil
end

---Get CPU usage percentage
---@return string
local function get_cpu_usage_internal()
   if platform.is_mac then
      -- macOS: use top command
      local output = run_command({ 'top', '-l', '1', '-n', '0' })
      if output then
         local cpu_idle = output:match('CPU usage: [%d%.]+%% user, [%d%.]+%% sys, ([%d%.]+)%% idle')
         if cpu_idle then
            local usage = 100 - tonumber(cpu_idle)
            return string.format('%.1f%%', usage)
         end
      end
   elseif platform.is_linux then
      -- Linux: use top command
      local output = run_command({ 'top', '-bn1' })
      if output then
         local cpu_idle = output:match('%%Cpu%(s%):[^,]+,[^,]+,[^,]+, ([%d%.]+) id')
         if cpu_idle then
            local usage = 100 - tonumber(cpu_idle)
            return string.format('%.1f%%', usage)
         end
      end
   elseif platform.is_win then
      -- Windows: use wmic
      local output = run_command({ 'wmic', 'cpu', 'get', 'loadpercentage', '/value' })
      if output then
         local cpu = output:match('LoadPercentage=(%d+)')
         if cpu then
            return string.format('%s%%', cpu)
         end
      end
   end
   return 'N/A'
end

---Get memory usage
---@return string
local function get_memory_usage_internal()
   if platform.is_mac then
      -- macOS: use vm_stat and sysctl
      local vm_output = run_command({ 'vm_stat' })
      if vm_output then
         local page_size = 4096 -- default page size
         local pages_active = vm_output:match('Pages active:%s+(%d+)')
         local pages_wired = vm_output:match('Pages wired down:%s+(%d+)')

         if pages_active and pages_wired then
            local used = (tonumber(pages_active) + tonumber(pages_wired)) * page_size / (1024 ^ 3)
            local total_cmd = run_command({ 'sysctl', '-n', 'hw.memsize' })
            if total_cmd then
               local total = tonumber(total_cmd) / (1024 ^ 3)
               return string.format('%.1f/%.0fGB', used, total)
            end
         end
      end
   elseif platform.is_linux then
      -- Linux: use free command
      local output = run_command({ 'free', '-m' })
      if output then
         local total, used = output:match('Mem:%s+(%d+)%s+(%d+)')
         if total and used then
            return string.format('%.1f/%.0fGB', tonumber(used) / 1024, tonumber(total) / 1024)
         end
      end
   elseif platform.is_win then
      -- Windows: use wmic
      local output = run_command({ 'wmic', 'OS', 'get', 'FreePhysicalMemory,TotalVisibleMemorySize', '/value' })
      if output then
         local free = output:match('FreePhysicalMemory=(%d+)')
         local total = output:match('TotalVisibleMemorySize=(%d+)')
         if free and total then
            local used = (tonumber(total) - tonumber(free)) / (1024 ^ 2)
            local total_gb = tonumber(total) / (1024 ^ 2)
            return string.format('%.1f/%.0fGB', used, total_gb)
         end
      end
   end
   return 'N/A'
end

---Get cached system stat
---@param stat_type string 'cpu' or 'memory'
---@param getter_func function Function to get the stat
---@return string
local function get_cached_stat(stat_type, getter_func)
   local now = os.time()
   local stat = cache[stat_type]

   if now - stat.last_update >= CACHE_DURATION then
      stat.value = getter_func()
      stat.last_update = now
   end

   return stat.value
end

---Get CPU usage with caching
---@return string
function M.get_cpu_usage()
   return get_cached_stat('cpu', get_cpu_usage_internal)
end

---Get memory usage with caching
---@return string
function M.get_memory_usage()
   return get_cached_stat('memory', get_memory_usage_internal)
end

return M
