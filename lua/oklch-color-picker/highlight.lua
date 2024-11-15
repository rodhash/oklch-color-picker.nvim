local utils = require 'oklch-color-picker.utils'
local downloader = require 'oklch-color-picker.downloader'
local color_to_hex

local find, sub, format = string.find, string.sub, string.format
local nvim_buf_clear_namespace, nvim_buf_add_highlight, nvim_set_hl = vim.api.nvim_buf_clear_namespace, vim.api.nvim_buf_add_highlight, vim.api.nvim_set_hl
local pow, sqrt, min, max = math.pow, math.sqrt, math.min, math.max
local rshift, band = bit.rshift, bit.band

local M = {}

--- @class oklch.HightlightConfig
--- @field enabled boolean
--- @field edit_delay number async delay in ms
--- @field scroll_delay number async delay in ms

M.patterns = nil

---@type oklch.HightlightConfig
M.config = nil

local ns

--- @param config oklch.HightlightConfig
--- @param patterns oklch.FinalPatternList[]
--- @param auto_download boolean
function M.setup(config, patterns, auto_download)
  M.config = config
  M.patterns = patterns

  if not M.config.enabled then
    return
  end

  local on_downloaded = function(err)
    if err then
      utils.log(err, vim.log.levels.ERROR)
      return
    end
    local parser = require('oklch-color-picker.parser').get_parser()
    if parser == nil then
      utils.log("Couldn't load parser library", vim.log.levels.ERROR)
      return
    end
    color_to_hex = parser.color_to_hex

    ns = vim.api.nvim_create_namespace 'OklchColorPickerNamespace'
    M.gr = vim.api.nvim_create_augroup('OklchColorPicker', {})

    -- set to false for enable to work
    M.config.enabled = false
    M.enable()
  end

  if auto_download then
    downloader.ensure_parser_downloaded(vim.schedule_wrap(on_downloaded))
  else
    on_downloaded(nil)
  end
end

function M.disable()
  if not M.config or not M.config.enabled then
    return
  end
  M.config.enabled = false

  M.bufs = {}
  vim.api.nvim_clear_autocmds { group = M.gr }
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
    end
  end
end

function M.enable()
  if not color_to_hex or not M.config or M.config.enabled then
    return
  end
  M.config.enabled = true

  vim.api.nvim_create_autocmd('BufEnter', {
    group = M.gr,
    callback = function(data)
      M.on_buf_enter(data.buf, false)
    end,
  })

  vim.schedule(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        M.on_buf_enter(bufnr, true)
      end
    end
  end)
end

function M.toggle()
  if M.config.enabled then
    M.disable()
  else
    M.enable()
  end
end

---@class BufData
---@field pending_updates { from_line: integer, to_line: integer }|nil
---@field prev_win_pos table<integer>

--- @type { [integer]: BufData }
M.bufs = {}
--- @type integer
M.gr = nil

--- Unattaching is very annoying, so just make sure we never attach twice
--- @type { [integer]: boolean}
M.buf_attached = {}

--- @param bufnr number
--- @param force_update boolean
function M.on_buf_enter(bufnr, force_update)
  local buftype = vim.api.nvim_get_option_value('buftype', { buf = bufnr })
  if buftype ~= '' then
    return
  end

  if M.bufs[bufnr] then
    if force_update or M.bufs[bufnr].pending_updates then
      M.update(bufnr)
    end
    return
  end

  M.bufs[bufnr] = {
    prev_win_pos = { 0, 0 },
  }

  M.update(bufnr)

  if M.buf_attached[bufnr] == nil then
    vim.api.nvim_buf_attach(bufnr, false, {
      on_bytes = function(_, _, _, start_row, _, _, old_end_row, _, _, new_end_row, _, _)
        if new_end_row < old_end_row then
          -- We deleted some lines.
          -- It's possible that we uncovered new unhighlighted colors from the bottom
          -- of the view, so update the rest of the view.
          M.update_lines(bufnr, start_row, 100000000, false)
        else
          M.update_lines(bufnr, start_row, start_row + new_end_row + 1, false)
        end
      end,
      on_reload = function()
        M.update(bufnr)
      end,
      on_detach = function()
        M.bufs[bufnr] = nil
        M.buf_attached[bufnr] = nil
        vim.api.nvim_clear_autocmds { buffer = bufnr, group = M.gr }
      end,
    })
    M.buf_attached[bufnr] = true
  end

  vim.api.nvim_create_autocmd('WinScrolled', {
    group = M.gr,
    buffer = bufnr,
    callback = function(data)
      local buf_data = M.bufs[bufnr]
      if buf_data == nil then
        return
      end

      local top, bottom = M.get_view(bufnr)
      if bottom > buf_data.prev_win_pos[2] then
        -- scrolled down
        M.update_lines(data.buf, buf_data.prev_win_pos[2], 1e9)
      elseif bottom <= buf_data.prev_win_pos[1] then
        -- large jump up
        M.update_lines(data.buf, 0, 1e9)
      else
        -- scrolled up
        M.update_lines(data.buf, 0, buf_data.prev_win_pos[1] + 1)
      end
      buf_data.prev_win_pos[1] = top
      buf_data.prev_win_pos[2] = bottom
    end,
  })
end

--- @param bufnr integer
function M.update(bufnr)
  M.update_lines(bufnr, 0, 1e9, true)
end

local function get_view()
  return { vim.fn.line 'w0' - 1, vim.fn.line 'w$' }
end

--- @param bufnr integer
--- @return integer, integer
function M.get_view(bufnr)
  local v = vim.api.nvim_buf_call(bufnr, get_view)
  return v[1], v[2]
end

M.pending_timer = vim.uv.new_timer()

M.perf_logging = false

--- @param bufnr integer
--- @param from_line integer
--- @param to_line integer
--- @param scroll boolean
M.update_lines = vim.schedule_wrap(function(bufnr, from_line, to_line, scroll)
  local buf_data = M.bufs[bufnr]
  if buf_data == nil then
    return
  end

  local top, bottom = M.get_view(bufnr)
  if buf_data.pending_updates == nil then
    buf_data.pending_updates = {
      from_line = max(from_line, top),
      to_line = min(to_line, bottom),
    }
  else
    buf_data.pending_updates.from_line = max(min(buf_data.pending_updates.from_line, from_line), top)
    buf_data.pending_updates.to_line = min(max(buf_data.pending_updates.to_line, to_line), bottom)
  end

  local process_update = function()
    local buf_data = M.bufs[bufnr]
    if buf_data == nil or buf_data.pending_updates == nil then
      return
    end

    local t = vim.uv.hrtime()

    local from_line = buf_data.pending_updates.from_line --[[@as integer]]
    local to_line = buf_data.pending_updates.to_line --[[@as integer]]
    buf_data.pending_updates = nil

    local lines = vim.api.nvim_buf_get_lines(bufnr, from_line, to_line, false)

    local ft = vim.api.nvim_get_option_value('filetype', { buf = bufnr })

    -- ignore very long lines
    for i, line in ipairs(lines) do
      if string.len(line) > 4000 then
        lines[i] = ''
      end
    end

    M.highlight_lines(bufnr, lines, from_line, ft)

    if M.perf_logging then
      local ms = (vim.uv.hrtime() - t) / 1000000
      print(format('color highlighting took: %.3f ms, lines %d to %d', ms, from_line, to_line))
    end
  end

  local delay = scroll and M.config.scroll_delay or M.config.edit_delay
  M.pending_timer:stop()
  if delay > 0 then
    M.pending_timer:start(delay, 0, vim.schedule_wrap(process_update))
  else
    process_update()
  end
end)

local function to_linear(c)
  if c <= 0.04045 then
    return c / 12.92
  else
    return pow((c + 0.055) / 1.055, 2.4)
  end
end

--- Follows W3C guidelines in choosing the better contrast foreground.
--- https://stackoverflow.com/questions/3942878/how-to-decide-font-color-in-white-or-black-depending-on-background-color
--- @param hex string
--- @return boolean
local function is_light(hex)
  local number = tonumber(hex, 16)
  local r = rshift(number, 16) / 255
  local g = band(rshift(number, 8), 0xff) / 255
  local b = band(number, 0xff) / 255
  local lr = to_linear(r)
  local lg = to_linear(g)
  local lb = to_linear(b)
  return 0.2126 * lr + 0.7152 * lg + 0.0722 * lb > 0.179
end

local hex_color_groups = {}

--- @param hex_color string
--- @return string
local function compute_hex_color_group(hex_color)
  local cached_group_name = hex_color_groups[hex_color]
  if cached_group_name ~= nil then
    return cached_group_name
  end

  local hex = sub(hex_color, 2)
  local group_name = format('OklchColorPickerHexColor_%s', hex)

  local fg = is_light(hex) and 'Black' or 'White'
  nvim_set_hl(0, group_name, { fg = fg, bg = hex_color })

  hex_color_groups[hex_color] = group_name

  return group_name
end

local line_matches = {}

---@param bufnr integer
---@param lines string[]
---@param from_line integer
---@param ft string
function M.highlight_lines(bufnr, lines, from_line, ft)
  local patterns = M.patterns

  nvim_buf_clear_namespace(bufnr, ns, from_line, from_line + #lines)

  for i, line in ipairs(lines) do
    for j = 1, #line_matches do
      line_matches[j] = nil
    end
    local match_idx = 1

    for _, pattern_list in ipairs(patterns) do
      if pattern_list.ft(ft) then
        for _, pattern in ipairs(pattern_list) do
          local start = 1
          local match_start, match_end = find(line, pattern.cheap, start)

          while match_start ~= nil do
            local replace_start, replace_end
            if pattern.simple_groups then
              replace_start, replace_end = match_start, match_end
            else
              _, _, replace_start, replace_end = find(line, pattern.grouped, match_start)
              replace_end = replace_end - 1
            end

            local has_space = true
            for _, match in ipairs(line_matches) do
              if not (match[1] > match_end or match[2] < match_start) then
                has_space = false
                break
              end
            end

            if has_space then
              local color = sub(line, replace_start --[[@as number]], replace_end)
              local hex = color_to_hex(color, pattern_list.format)

              if hex then
                local group = compute_hex_color_group(hex)
                local line_n = from_line + i - 1 -- zero based index
                nvim_buf_add_highlight(bufnr, ns, group, line_n, match_start - 1, match_end --[[@as number]])
              end
              line_matches[match_idx] = { match_start, match_end }
              match_idx = match_idx + 1
            end

            start = match_end + 1
            match_start, match_end = find(line, pattern.cheap, start)
          end
        end
      end
    end
  end
end

return M
