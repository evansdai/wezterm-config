local wezterm = require('wezterm')
local platform = require('utils.platform')

local M = {}

---@class SystemStats.Cache
---@field value any
---@field last_update number

---@type table<string, SystemStats.Cache>
local cache = {
   cpu = { value = 'N/A', last_update = 0 },
   memory = { value = 'N/A', last_update = 0 },
   swap = { value = nil, last_update = 0 },
}

local CACHE_DURATION = 2

---Execute a command and return stdout
---@param cmd table Command and arguments as array
---@return string|nil
local function run_command(cmd)
   local success, stdout, _ = wezterm.run_child_process(cmd)
   if success then
      return stdout
   end
   return nil
end

---Parse vm_stat output to extract page size and page counts
---@param output string vm_stat output
---@return table|nil Page counts and page size
local function parse_vm_stat(output)
   if not output then
      return nil
   end

   -- Parse page size from header (e.g., "Mach Virtual Memory Statistics: (page size of 16384 bytes)")
   local page_size = output:match('page size of (%d+) bytes')
   page_size = page_size and tonumber(page_size) or 16384 -- fallback to 16KB

   -- Helper to parse page count (handles trailing dots)
   local function get_pages(pattern)
      local val = output:match(pattern)
      if val then
         -- Remove trailing dot if present
         val = val:gsub('%.$', '')
         return tonumber(val) or 0
      end
      return 0
   end

   return {
      page_size = page_size,
      active = get_pages('Pages active:%s+([%d%.]+)'),
      inactive = get_pages('Pages inactive:%s+([%d%.]+)'),
      speculative = get_pages('Pages speculative:%s+([%d%.]+)'),
      wired = get_pages('Pages wired down:%s+([%d%.]+)'),
      free = get_pages('Pages free:%s+([%d%.]+)'),
      occupied = get_pages('Pages occupied by compressor:%s+([%d%.]+)'),
      anonymous = get_pages('Anonymous pages:%s+([%d%.]+)'),
      file_backed = get_pages('File%-backed pages:%s+([%d%.]+)'),
   }
end

local function parse_size_with_unit(str)
   local num, unit = str:match('([%d%.]+)([BKMGT]?)')
   num = tonumber(num) or 0

   local multipliers = {
      B = 1,
      K = 1024,
      M = 1024 ^ 2,
      G = 1024 ^ 3,
      T = 1024 ^ 4,
   }

   local normalized = unit ~= '' and unit or 'M'
   return num * (multipliers[normalized] or multipliers.M)
end

---Get CPU usage percentage
---@return string
local function get_cpu_usage_internal()
   if platform.is_mac then
      local output = run_command({ 'iostat', '-c', '2' })
      if output then
         local sample = nil
         for line in output:gmatch('[^\r\n]+') do
            local us, sy, id =
               line:match('%s([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+[%d%.]+%s+[%d%.]+%s+[%d%.]+$')
            if us and sy and id then
               sample = {
                  user = tonumber(us),
                  sys = tonumber(sy),
                  idle = tonumber(id),
               }
            end
         end

         if sample then
            local usage = sample.user + sample.sys
            usage = math.max(0, math.min(100, usage))
            return string.format('%.0f%%', usage)
         end
      end

      local top_output = run_command({ 'top', '-l', '1', '-n', '0' })
      if top_output then
         local cpu_idle =
            top_output:match('CPU usage: [%d%.]+%% user, [%d%.]+%% sys, ([%d%.]+)%% idle')
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
       -- Windows: use PowerShell (wmic is deprecated)
       local output = run_command({
          'powershell.exe',
          '-Command',
          'Get-CimInstance Win32_Processor | Select-Object -ExpandProperty LoadPercentage',
       })
       if output then
          local cpu = output:match('(%d+)')
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
      local total_cmd = run_command({ 'sysctl', '-n', 'hw.memsize' })
      if total_cmd then
         local total_bytes = tonumber(total_cmd)
         local total_gb = total_bytes / (1024 ^ 3)

         local vm_output = run_command({ 'vm_stat' })
         local stats = vm_output and parse_vm_stat(vm_output) or nil
         if stats then
            local anonymous_bytes = stats.anonymous * stats.page_size
            local wired_bytes = stats.wired * stats.page_size
            local compressed_bytes = stats.occupied * stats.page_size
            local used_bytes = math.max(0, anonymous_bytes + wired_bytes + compressed_bytes)
            local used_gb = used_bytes / (1024 ^ 3)
            return string.format('%.1f/%.0fGB', used_gb, total_gb)
         end

         local top_output = run_command({ 'top', '-l', '1', '-n', '0' })
         if top_output then
            local used_str = top_output:match('PhysMem:%s+([%d%.]+[BKMGT]?)%s+used')
            if used_str then
               local used_bytes = parse_size_with_unit(used_str)
               local used_gb = used_bytes / (1024 ^ 3)
               return string.format('%.1f/%.0fGB', used_gb, total_gb)
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
       -- Windows: use PowerShell (wmic is deprecated)
       local output = run_command({
          'powershell.exe',
          '-Command',
          'Get-CimInstance Win32_OperatingSystem | ForEach-Object { "FreePhysicalMemory=" + $_.FreePhysicalMemory + ";TotalVisibleMemorySize=" + $_.TotalVisibleMemorySize }',
       })
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

---Get swap usage percentage and status
---@return table|nil { percent: number, text: string, status: 'normal'|'warning'|'critical' }
local function get_swap_usage_internal()
   if platform.is_mac then
      local output = run_command({ 'sysctl', 'vm.swapusage' })
      if output then
         -- Parse: "vm.swapusage: total = 2048.00M  used = 1161.50M  free = 886.50M  (encrypted)"
         local total_str = output:match('total = ([%d%.]+[KMGT]?)')
         local used_str = output:match('used = ([%d%.]+[KMGT]?)')

         if total_str and used_str then
            local total = parse_size_with_unit(total_str)
            local used = parse_size_with_unit(used_str)

            if total <= 0 then
               return nil
            end

            local percent = (used / total) * 100
            local used_gb = used / (1024 ^ 3)

            local status = 'normal'
            if percent >= 90 then
               status = 'critical'
            elseif percent >= 70 then
               status = 'warning'
            end

            return {
               percent = percent,
               text = string.format('%.0f%%', percent),
               status = status,
            }
         end
      end
   elseif platform.is_linux then
      local output = run_command({ 'free', '-m' })
      if output then
         -- Parse: "Swap:        2048        1161         887"
         local total, used = output:match('Swap:%s+(%d+)%s+(%d+)')
         if total and used then
            local total_mb = tonumber(total)
            local used_mb = tonumber(used)

            if total_mb <= 0 then
               return nil
            end

            local percent = (used_mb / total_mb) * 100
            local used_gb = used_mb / 1024

            local status = 'normal'
            if percent >= 80 then
               status = 'critical'
            elseif percent >= 50 then
               status = 'warning'
            end

            return {
               percent = percent,
               text = string.format('%.2fG %.1f%%', used_gb, percent),
               status = status,
            }
         end
      end
    elseif platform.is_win then
       -- Windows: use PowerShell (wmic is deprecated)
       local output = run_command({
          'powershell.exe',
          '-Command',
          'Get-CimInstance Win32_PageFileUsage | ForEach-Object { "AllocatedBaseSize=" + $_.AllocatedBaseSize + ";CurrentUsage=" + $_.CurrentUsage }',
       })
       if output then
          local total = output:match('AllocatedBaseSize=(%d+)')
          local used = output:match('CurrentUsage=(%d+)')
          if total and used then
             local total_mb = tonumber(total)
             local used_mb = tonumber(used)

             if total_mb <= 0 then
                return nil
             end

             local percent = (used_mb / total_mb) * 100
             local used_gb = used_mb / 1024

             local status = 'normal'
             if percent >= 80 then
                status = 'critical'
             elseif percent >= 50 then
                status = 'warning'
             end

             return {
                percent = percent,
                text = string.format('%.2fG %.1f%%', used_gb, percent),
                status = status,
             }
          end
       end
    end
   return nil
end

---Get cached system stat
---@param stat_type string 'cpu', 'memory', or 'swap'
---@param getter_func function Function to get the stat
---@return any
local function get_cached_stat(stat_type, getter_func)
   local now = os.time()
   local stat = cache[stat_type]

   if now - stat.last_update >= CACHE_DURATION then
      local new_value = getter_func()
      if new_value then
         stat.value = new_value
         stat.last_update = now
      end
      -- If getter returns nil, keep cached value (don't overwrite with nil)
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

---Get swap usage info with caching
---@return table|nil { percent: number, text: string, status: 'normal'|'warning'|'critical' }
function M.get_swap_usage()
   return get_cached_stat('swap', get_swap_usage_internal)
end

return M
