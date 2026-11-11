local M = {}
local api = vim.api

local defaults = {
  executable = "yt-tui",
  args = {},
  width = 0.9,
  height = 0.9,
  border = "rounded",
  title = " yt-tui ",
  hide_key = false,
}
local config = vim.deepcopy(defaults)
local session
local restart_request = 0

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
  if next_config.hide_key ~= false
    and (type(next_config.hide_key) ~= "string"
      or next_config.hide_key == ""
      or next_config.hide_key:find("\0", 1, true))
  then
    error("yt-tui.nvim: hide_key must be a nonempty key sequence or false", 2)
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

local function owned_window(current)
  local win = current.win
  if win and api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == current.buf then
    return win
  end
end

-- The window is disposable; the terminal buffer owns the live process.
local function hide_window(current)
  local win = owned_window(current)
  local return_win = current.return_win
  if not win then
    current.win = nil
    current.return_win = nil
    return true
  end
  local focused = api.nvim_get_current_win() == win
  if focused then
    vim.cmd.stopinsert()
  end
  local hidden, err = pcall(api.nvim_win_close, win, true)
  if not hidden then
    notify("could not hide floating window: " .. tostring(err))
    return false
  end
  -- WinClosed/BufHidden may already have detached this exact window.
  if current.win == win then
    current.win = nil
    current.return_win = nil
  end
  if focused and return_win and api.nvim_win_is_valid(return_win)
    and api.nvim_win_get_tabpage(return_win) == api.nvim_get_current_tabpage()
  then
    api.nvim_set_current_win(return_win)
  end
  return true
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
  hide_window(current)
  if api.nvim_buf_is_valid(current.buf) then
    pcall(api.nvim_buf_delete, current.buf, { force = true })
  end
end

-- Buffer removal can run under textlock. Detach immediately so a replacement
-- session is safe, then release the old job and callbacks outside the event.
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

local function show(current)
  local win = owned_window(current)
  if win and api.nvim_win_get_tabpage(win) ~= api.nvim_get_current_tabpage() then
    if not hide_window(current) then
      return false
    end
    win = nil
  end
  local previous = api.nvim_get_current_win()
  if not win then
    local opened, result = pcall(api.nvim_open_win, current.buf, true, window_config(current.opts))
    if not opened then
      notify("could not open floating window: " .. tostring(result))
      return false
    end
    win = result
    current.win = win
  else
    local focused, err = pcall(api.nvim_set_current_win, win)
    if not focused then
      notify("could not focus floating window: " .. tostring(err))
      return false
    end
  end
  -- Entering a buffer can run user autocmds that close or repurpose its window.
  if current.closed or current.closing or owned_window(current) ~= win then
    return false
  end
  api.nvim_win_set_config(win, window_config(current.opts))
  if previous ~= win then
    current.return_win = previous
  end
  if current.running then
    vim.cmd.startinsert()
  else
    vim.cmd.stopinsert()
  end
  return true
end

local function validate_args(args)
  if not valid_args(args) then
    notify("arguments must be a list of strings")
    return false
  end
  if vim.fn.has("nvim-0.11") ~= 1 then
    notify("Neovim 0.11 or newer is required")
    return false
  end
  return true
end

local function preflight(args)
  if not validate_args(args) then
    return false
  end
  if vim.fn.executable(config.executable) ~= 1 then
    notify("executable not found: " .. config.executable .. ". Install yt-tui or set setup({ executable = ... }).")
    return false
  end
  return true
end

local function launch(args)
  if not preflight(args) then
    return false
  end
  local current = { buf = api.nvim_create_buf(false, true), opts = vim.deepcopy(config), running = false }
  session = current
  vim.bo[current.buf].bufhidden = "hide"
  vim.b[current.buf].terminal_passthrough = true
  if not show(current) then
    dispose(current)
    return false
  end
  local command = { current.opts.executable }
  vim.list_extend(command, current.opts.args)
  vim.list_extend(command, args)
  current.running = true
  local started, job = pcall(vim.fn.jobstart, command, {
    term = true,
    env = { YT_TUI_NVIM_HIDE = "1" },
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
              .. "; output retained. Use :YtTui to inspect, :YtTuiRestart to retry, or :YtTuiClose to discard.",
            vim.log.levels.WARN
          )
        end
      end)
    end,
  })
  if not started or job <= 0 then
    current.running = false
    dispose(current)
    notify("could not start " .. current.opts.executable .. ": " .. tostring(job))
    return false
  end
  current.job = job
  -- TermOpen may synchronously close/restart the session before jobstart returns
  -- its job ID. dispose() could not stop that job yet, so finish cleanup here.
  if current.closed or current.closing or session ~= current or not api.nvim_buf_is_valid(current.buf) then
    pcall(vim.fn.jobstop, job)
    dispose(current)
    return false
  end

  -- Register after jobstart: creating a terminal initially renames its buffer.
  current.group = api.nvim_create_augroup("YtTuiTerminal" .. current.buf, { clear = true })
  api.nvim_create_autocmd("TermRequest", {
    group = current.group,
    buffer = current.buf,
    callback = function(event)
      if not event.data or event.data.sequence ~= "\27]777;yt-tui;hide" then
        return
      end
      local win = owned_window(current)
      if not win then
        return
      end
      -- The application knows when q means hide instead of typed text. Defer
      -- window changes outside the terminal event, rejecting stale requests.
      vim.schedule(function()
        if session == current and not current.closed and not current.closing
          and current.running and owned_window(current) == win
        then
          hide_window(current)
        end
      end)
    end,
  })
  api.nvim_create_autocmd("VimResized", {
    group = current.group,
    callback = function()
      local win = owned_window(current)
      if win then
        api.nvim_win_set_config(win, window_config(current.opts))
      end
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = current.group,
    callback = function(event)
      if current.win == tonumber(event.match) then
        current.win = nil
        current.return_win = nil
      end
    end,
  })
  api.nvim_create_autocmd("BufHidden", {
    group = current.group,
    buffer = current.buf,
    callback = function()
      current.win = nil
      current.return_win = nil
    end,
  })
  api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
    group = current.group,
    buffer = current.buf,
    callback = function()
      schedule_dispose(current)
    end,
  })
  api.nvim_create_autocmd("VimLeavePre", {
    group = current.group,
    callback = function()
      dispose(current)
    end,
  })
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      if session == current then
        M.hide()
      end
    end, { buffer = current.buf, silent = true, desc = "Hide yt-tui window" })
  end
  vim.keymap.set("n", "Q", function()
    if session == current then
      M.close()
    end
  end, { buffer = current.buf, silent = true, desc = "Quit yt-tui" })
  if current.opts.hide_key then
    -- Opt in to one outer-window gesture without consuming editor escape keys
    -- or printable leader sequences inside yt-tui and its nested editor.
    vim.keymap.set({ "n", "t" }, current.opts.hide_key, function()
      if session == current then
        M.hide()
      end
    end, { buffer = current.buf, silent = true, desc = "Hide yt-tui window" })
  end
  vim.bo[current.buf].filetype = "yt-tui"
  if current.closed or current.closing or not api.nvim_buf_is_valid(current.buf) then
    dispose(current)
    return false
  end
  if owned_window(current) and api.nvim_get_current_buf() == current.buf and current.running then
    vim.cmd.startinsert()
  end
  return true
end

---Hide the floating terminal without stopping its process.
---@return boolean
function M.hide()
  return not session or hide_window(session)
end

---Close the floating terminal and stop its process.
function M.close()
  if session then
    dispose(session)
  end
end

---Open, resume, or focus the existing terminal, including retained error output.
---@param args? string[] Arguments appended to the configured defaults.
---@return boolean
function M.open(args)
  args = args or {}
  if not validate_args(args) then
    return false
  end
  if session and not api.nvim_buf_is_valid(session.buf) then
    dispose(session)
  end
  if session then
    if #args > 0 then
      notify("a session already exists; use :YtTuiRestart with new arguments", vim.log.levels.WARN)
      return false
    end
    return show(session)
  end
  return launch(args)
end

---Hide a float visible in this tab, otherwise show the same session here.
---@return boolean
function M.toggle()
  local win = session and owned_window(session)
  if win and api.nvim_win_get_tabpage(win) == api.nvim_get_current_tabpage() then
    return M.hide()
  end
  return M.open()
end

---Start fresh. A live session asks before discarding unsaved work.
---True means launched or confirmation requested; the prompt completes later.
---@param args? string[] Fresh invocation arguments, not the previous issue URL.
---@param opts? {force?: boolean}
---@return boolean
function M.restart(args, opts)
  args = args or {}
  opts = opts or {}
  if type(opts) ~= "table" or (opts.force ~= nil and type(opts.force) ~= "boolean") then
    notify("restart options must be a table with an optional boolean force")
    return false
  end
  if not preflight(args) then
    return false
  end
  args = vim.deepcopy(args)
  restart_request = restart_request + 1
  local request = restart_request
  local expected = session
  local function replace()
    -- Both the prompt and session must still be current. Recheck configuration
    -- because setup() or the executable may have changed while the prompt waited.
    if request ~= restart_request or session ~= expected or not preflight(args) then
      return false
    end
    M.close()
    return launch(args)
  end
  if expected and expected.running and not opts.force then
    vim.ui.select({ "Cancel", "Restart" }, {
      prompt = "Restart yt-tui? Unsaved work will be discarded.",
    }, function(choice)
      if choice == "Restart" then
        replace()
      end
    end)
    return true
  end
  return replace()
end

return M
