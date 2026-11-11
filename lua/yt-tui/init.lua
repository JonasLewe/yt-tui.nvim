local M = {}
local api = vim.api

local defaults = {
  executable = "yt-tui",
  args = {},
  width = 0.9,
  height = 0.9,
  border = "rounded",
  title = " yt-tui ",
}
local config = vim.deepcopy(defaults)
local session

local function notify(message, level)
  vim.notify("yt-tui.nvim: " .. message, level or vim.log.levels.ERROR)
end

local function valid_args(args)
  if type(args) ~= "table" or not vim.islist(args) then
    return false
  end
  for _, arg in ipairs(args) do
    if type(arg) ~= "string" or arg:find("\0", 1, true) then
      return false
    end
  end
  return true
end

---Configure subsequent terminal sessions. No global key mappings are installed.
---@param opts? table
function M.setup(opts)
  if opts ~= nil and type(opts) ~= "table" then
    error("yt-tui.nvim: setup expects a table", 2)
  end
  local next_config = vim.tbl_extend("force", vim.deepcopy(defaults), opts or {})
  if type(next_config.executable) ~= "string"
    or next_config.executable == ""
    or next_config.executable:find("\0", 1, true)
  then
    error("yt-tui.nvim: executable must be a nonempty string", 2)
  end
  if not valid_args(next_config.args) then
    error("yt-tui.nvim: args must be a list of strings", 2)
  end
  for _, key in ipairs({ "width", "height" }) do
    local value = next_config[key]
    if type(value) ~= "number" or value ~= value or value <= 0 or value > 1 then
      error("yt-tui.nvim: " .. key .. " must be a fraction greater than 0 and at most 1", 2)
    end
  end
  local borders = { none = true, single = true, double = true, rounded = true, solid = true, shadow = true }
  if type(next_config.border) ~= "string" or not borders[next_config.border] then
    error("yt-tui.nvim: border must be a built-in Neovim border style", 2)
  end
  if type(next_config.title) ~= "string" then
    error("yt-tui.nvim: title must be a string", 2)
  end
  config = vim.deepcopy(next_config)
end

local function window_config(opts)
  local columns = math.max(1, vim.o.columns)
  local lines = math.max(1, vim.o.lines - vim.o.cmdheight)
  local border = opts.border
  if columns < 3 or lines < 3 then
    border = "none"
  end
  local padding = border == "none" and 0 or 2
  local width = math.max(1, math.floor(columns * opts.width) - padding)
  local height = math.max(1, math.floor(lines * opts.height) - padding)
  local result = {
    relative = "editor",
    style = "minimal",
    border = border,
    width = width,
    height = height,
    row = math.max(0, math.floor((lines - height - padding) / 2)),
    col = math.max(0, math.floor((columns - width - padding) / 2)),
  }
  if border ~= "none" and opts.title ~= "" then
    result.title = opts.title
    result.title_pos = "center"
  end
  return result
end

local function dispose(current)
  if current.closed then
    return
  end
  current.closed = true
  if session == current then
    session = nil
  end
  if current.group then
    pcall(api.nvim_del_augroup_by_id, current.group)
  end
  if current.running and current.job and current.job > 0 then
    pcall(vim.fn.jobstop, current.job)
  end
  if api.nvim_get_current_buf() == current.buf then
    vim.cmd.stopinsert()
  end
  if current.win and api.nvim_win_is_valid(current.win)
    and api.nvim_win_get_buf(current.win) == current.buf
  then
    pcall(api.nvim_win_close, current.win, true)
  end
  if api.nvim_buf_is_valid(current.buf) then
    pcall(api.nvim_buf_delete, current.buf, { force = true })
  end
end

-- WinClosed and BufWipeout run while their window/buffer is being removed.
-- Defer API mutations, and detach this session immediately so a new one is safe.
local function schedule_dispose(current)
  if current.closed or current.closing then
    return
  end
  current.closing = true
  if session == current then
    session = nil
  end
  vim.schedule(function()
    dispose(current)
  end)
end

---Close the floating terminal and stop its process.
function M.close()
  if session then
    dispose(session)
  end
end

---Open yt-tui, or focus the current running session when no arguments are given.
---@param args? string[] Arguments appended to the configured defaults.
---@return boolean
function M.open(args)
  args = args or {}
  if not valid_args(args) then
    notify("arguments must be a list of strings")
    return false
  end
  if vim.fn.has("nvim-0.11") ~= 1 then
    notify("Neovim 0.11 or newer is required")
    return false
  end

  if session then
    if session.running
      and api.nvim_win_is_valid(session.win)
      and api.nvim_buf_is_valid(session.buf)
      and api.nvim_win_get_buf(session.win) == session.buf
    then
      if #args > 0 then
        notify("a session is already running; use :YtTuiClose before opening with new arguments", vim.log.levels.WARN)
        return false
      end
      api.nvim_set_current_win(session.win)
      vim.cmd.startinsert()
      return true
    end
    dispose(session)
  end

  if vim.fn.executable(config.executable) ~= 1 then
    notify("executable not found: " .. config.executable .. ". Install yt-tui or set setup({ executable = ... }).")
    return false
  end

  local current = { buf = api.nvim_create_buf(false, true), opts = vim.deepcopy(config), running = true }
  session = current
  vim.b[current.buf].terminal_passthrough = true
  local opened, win = pcall(api.nvim_open_win, current.buf, true, window_config(current.opts))
  if not opened then
    dispose(current)
    notify("could not open floating window: " .. tostring(win))
    return false
  end
  current.win = win
  local command = { current.opts.executable }
  vim.list_extend(command, current.opts.args)
  vim.list_extend(command, args)
  local started, job = pcall(vim.fn.jobstart, command, {
    term = true,
    on_exit = function(_, code)
      current.running = false
      vim.schedule(function()
        if session ~= current or current.closed or current.closing then
          return
        end
        if code == 0 then
          dispose(current)
        else
          if api.nvim_get_current_buf() == current.buf then
            vim.cmd.stopinsert()
          end
          notify(
            "process exited with code " .. code
              .. "; output kept open. Use :YtTui to retry or :YtTuiClose to close.",
            vim.log.levels.WARN
          )
        end
      end)
    end,
  })
  if not started or job <= 0 then
    current.running = false
    dispose(current)
    notify("could not start " .. config.executable .. ": " .. tostring(job))
    return false
  end
  current.job = job
  if not api.nvim_buf_is_valid(current.buf) or not api.nvim_win_is_valid(current.win) then
    dispose(current)
    return false
  end

  -- Register after jobstart: creating a terminal initially renames its buffer.
  current.group = api.nvim_create_augroup("YtTuiTerminal" .. current.buf, { clear = true })
  api.nvim_create_autocmd("VimResized", {
    group = current.group,
    callback = function()
      if api.nvim_win_is_valid(current.win) then
        api.nvim_win_set_config(current.win, window_config(current.opts))
      end
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = current.group,
    pattern = tostring(current.win),
    callback = function()
      schedule_dispose(current)
    end,
  })
  api.nvim_create_autocmd({ "BufHidden", "BufWipeout" }, {
    group = current.group,
    buffer = current.buf,
    callback = function()
      schedule_dispose(current)
    end,
  })
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, M.close, { buffer = current.buf, silent = true, desc = "Close yt-tui window" })
  end
  vim.bo[current.buf].filetype = "yt-tui"
  vim.cmd.startinsert()
  return true
end

return M
