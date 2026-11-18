local api = vim.api
local root = assert(vim.env.YT_TUI_TEST_ROOT, "run tests/run.sh")
local fixture = root .. "/tests/fixture.py"
local python = vim.fn.exepath("python3")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
vim.opt.runtimepath:prepend(root)
vim.o.columns = 120
vim.o.lines = 40
vim.cmd("runtime plugin/yt-tui.lua")
local plugin = require("yt-tui")
local notices = {}
local default_select = vim.ui.select
vim.notify = function(message, level)
  notices[#notices + 1] = { message = message, level = level }
end

local function check(condition, message)
  if not condition then
    error(message, 2)
  end
end

local function eventually(predicate, message)
  check(vim.wait(3000, predicate, 10), message)
end

local function buffers()
  local result = {}
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "yt-tui" then
      result[#result + 1] = buf
    end
  end
  return result
end

local jobs = {}
local captures = 0
local function configure(mode, extra)
  captures = captures + 1
  local capture = temp .. "/arguments-" .. captures .. ".json"
  local opts = {
    executable = python,
    args = { fixture, mode or "hold", capture },
  }
  plugin.setup(vim.tbl_extend("force", opts, extra or {}))
  return capture
end

local function current_session()
  local candidates = buffers()
  check(#candidates == 1, "expected one yt-tui terminal, got " .. #candidates)
  local buf = candidates[1]
  local win = vim.fn.bufwinid(buf)
  check(win ~= -1, "terminal buffer has no window")
  local job = vim.b[buf].terminal_job_id
  check(type(job) == "number", "terminal has no job")
  local session = { buf = buf, win = win, job = job, pid = vim.fn.jobpid(job) }
  jobs[#jobs + 1] = session
  return session
end

local function start(extra, args)
  local capture = configure("hold", extra)
  plugin.open(args)
  local session = current_session()
  eventually(function()
    return vim.fn.filereadable(capture) == 1
  end, "fixture did not start")
  return session, capture
end

local function assert_stopped(session)
  eventually(function()
    return vim.fn.jobwait({ session.job }, 0)[1] ~= -1
  end, "terminal job survived closure")
  eventually(function()
    return vim.uv.kill(session.pid, 0) == nil
  end, "terminal process survived closure")
end

local function assert_running(session)
  check(api.nvim_buf_is_valid(session.buf), "terminal buffer was discarded")
  check(vim.b[session.buf].terminal_job_id == session.job, "terminal job changed")
  check(vim.fn.jobwait({ session.job }, 0)[1] == -1, "terminal job unexpectedly stopped")
  check(vim.fn.jobpid(session.job) == session.pid, "terminal process changed")
end

local function assert_hidden(session)
  check(#vim.fn.win_findbuf(session.buf) == 0, "terminal still has a visible window")
  assert_running(session)
end

local function assert_same_session(session)
  assert_running(session)
  check(api.nvim_get_current_buf() == session.buf, "resume did not focus the existing terminal")
  check(#buffers() == 1, "resume created another terminal buffer")
end

local function output(session)
  return table.concat(api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")
end

local function read_capture(capture)
  eventually(function()
    return vim.fn.filereadable(capture) == 1
  end, "fixture did not capture arguments")
  return vim.json.decode(table.concat(vim.fn.readfile(capture), "\n"))
end

local function capture_prompt()
  local prompt
  vim.ui.select = function(items, opts, callback)
    check(prompt == nil, "unexpected duplicate confirmation")
    prompt = { items = items, opts = opts, answer = callback }
  end
  return function()
    check(prompt ~= nil, "restart did not request confirmation")
    check(#prompt.items == 2 and prompt.items[1]:lower():find("cancel", 1, true), "confirmation must default to cancel")
    return prompt
  end
end

local function assert_disposed(session)
  eventually(function()
    return not api.nvim_win_is_valid(session.win) and not api.nvim_buf_is_valid(session.buf)
  end, "terminal window or buffer leaked")
  assert_stopped(session)
end

local function close()
  plugin.close()
  eventually(function()
    return #buffers() == 0
  end, "plugin close left a terminal buffer")
end

local tests = {}
local function test(name, run)
  tests[#tests + 1] = { name = name, run = run }
end

-- A separate editor runs its actual input loop while this suite drives it over
-- built-in RPC. This exercises terminal-mode mappings, not their Lua callbacks.
local function with_input_editor(run)
  local editor = vim.fn.jobstart({
    vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE",
  }, { rpc = true })
  check(editor > 0, "could not start input-test editor")
  local function remote(code, args)
    return vim.fn.rpcrequest(editor, "nvim_exec_lua", code, args or {})
  end
  local function input(keys)
    return vim.fn.rpcrequest(editor, "nvim_input", keys)
  end
  local function mode(expected)
    eventually(function()
      return vim.fn.rpcrequest(editor, "nvim_get_mode").mode == expected
    end, "input-test editor did not enter " .. expected .. " mode")
  end
  local ok, err = xpcall(function()
    remote("vim.opt.runtimepath:prepend(...)", { root })
    run(remote, input, mode)
  end, debug.traceback)
  pcall(remote, "require('yt-tui').close()")
  pcall(vim.fn.jobstop, editor)
  vim.fn.jobwait({ editor }, 3000)
  check(ok, err)
end

local function captured_input(capture)
  local file = io.open(capture .. ".input", "rb")
  if not file then return "" end
  local content = file:read("*a")
  file:close()
  return content
end

local function start_input_fixture(remote, mode, capture, hide_key, fixture_mode)
  remote([[
    local fixture, capture, hide_key, fixture_mode = ...
    require('yt-tui').setup({
      executable = vim.fn.exepath('python3'),
      args = { fixture, fixture_mode, capture },
      hide_key = hide_key,
    })
    assert(require('yt-tui').open())
  ]], { fixture, capture, hide_key, fixture_mode or "raw" })
  eventually(function()
    return vim.fn.filereadable(capture .. ".raw-ready") == 1
  end, "raw fixture did not start")
  mode("t")
  return remote([[
    local buf = vim.api.nvim_get_current_buf()
    local job = vim.b[buf].terminal_job_id
    return { buf = buf, job = job, pid = vim.fn.jobpid(job) }
  ]])
end

test("configured hide chord works through terminal input without consuming ordinary keys", function()
  with_input_editor(function(remote, input, mode)
    local capture = temp .. "/hide-input.json"
    local original = start_input_fixture(remote, mode, capture, "<C-w>q")
    input("kj yt<Esc>")
    eventually(function()
      return captured_input(capture) == "kj yt\27"
    end, "kj, leader text, or Escape was intercepted")
    input("<C-w>q")
    mode("n")
    check(remote("return #vim.fn.win_findbuf(...) == 0", { original.buf }), "hide chord left the float visible")
    check(remote("return vim.fn.jobwait({...}, 0)[1]", { original.job }) == -1, "hide chord stopped the process")
    check(captured_input(capture) == "kj yt\27", "hide chord leaked into the application")
    remote("assert(require('yt-tui').open())")
    mode("t")
    local resumed = remote([[
      local buf = vim.api.nvim_get_current_buf()
      local job = vim.b[buf].terminal_job_id
      return { buf = buf, job = job, pid = vim.fn.jobpid(job) }
    ]])
    check(vim.deep_equal(original, resumed), "hide chord replaced the terminal session")
    input("<C-\\><C-n>")
    mode("nt")
    input("<C-w>q")
    eventually(function()
      return remote("return #vim.fn.win_findbuf(...) == 0", { original.buf })
    end, "normal-mode hide chord left the float visible")
    check(remote("return vim.fn.jobwait({...}, 0)[1]", { original.job }) == -1, "normal-mode hide stopped the process")
  end)
end)

test("hide chord can be changed or disabled without global terminal mappings", function()
  with_input_editor(function(remote, input, mode)
    local capture = temp .. "/custom-hide-input.json"
    local original = start_input_fixture(remote, mode, capture, "<C-x>h")
    input("<C-w>q")
    eventually(function() return captured_input(capture) == "\23q" end, "unconfigured chord was intercepted")
    input("<C-x>h")
    mode("n")
    check(remote("return #vim.fn.win_findbuf(...) == 0", { original.buf }), "custom hide chord did not hide")
    check(remote("return #vim.api.nvim_get_keymap('t')") == 0, "hide chord created a global terminal mapping")
    remote("require('yt-tui').close()")
    capture = temp .. "/disabled-hide-input.json"
    original = start_input_fixture(remote, mode, capture, false)
    input("<C-w>q<C-x>h")
    eventually(function() return captured_input(capture) == "\23q\24h" end, "disabled mapping still intercepted input")
    check(remote("return #vim.fn.win_findbuf(...) == 1", { original.buf }), "disabled chord hid the float")
  end)
end)

test("invalid hide chord settings preserve the previous configuration", function()
  configure("hold", { hide_key = "<C-w>q" })
  for _, value in ipairs({ true, 42, {}, "", "bad\0key" }) do
    check(not pcall(plugin.setup, { hide_key = value }), "invalid hide_key was accepted")
  end
  check(plugin.open(), "invalid setup replaced the usable configuration")
  local session = current_session()
  vim.cmd.stopinsert()
  local keys = api.nvim_replace_termcodes("<C-w>q", true, false, true)
  api.nvim_feedkeys(keys, "mx", false)
  assert_hidden(session)
end)

test("application q hides while Q quits and editing keeps both letters", function()
  with_input_editor(function(remote, input, mode)
    remote("vim.env.YT_TUI_NVIM_HIDE = 'outside-plugin'")
    local capture = temp .. "/application-quit-controls.json"
    local original = start_input_fixture(remote, mode, capture, false, "quit-controls")
    check(vim.fn.readfile(capture .. ".host-env")[1] == "1", "child did not receive host capability")
    check(remote("return vim.env.YT_TUI_NVIM_HIDE") == "outside-plugin", "plugin changed global environment")
    check(remote("return #vim.api.nvim_buf_get_keymap(0, 't')") == 0, "plugin mapped printable terminal keys")
    input("eqQkj yy")
    eventually(function() return captured_input(capture) == "eqQkj yy" end, "editing lost q/Q or ordinary input")
    mode("t")
    check(remote("return #vim.fn.win_findbuf(...) == 1", { original.buf }), "editing q/Q hid the application")
    input("<Esc>q")
    mode("n")
    check(remote("return #vim.fn.win_findbuf(...) == 0", { original.buf }), "application q did not hide")
    check(remote("return vim.fn.jobwait({...}, 0)[1]", { original.job }) == -1, "application q stopped process")
    remote("assert(require('yt-tui').open())")
    mode("t")
    local resumed = remote([[
      local buf = vim.api.nvim_get_current_buf()
      local job = vim.b[buf].terminal_job_id
      return { buf = buf, job = job, pid = vim.fn.jobpid(job) }
    ]])
    check(vim.deep_equal(original, resumed), "application hide discarded session state")
    check(captured_input(capture) == "eqQkj yy\27q", "resume changed captured application state")
    input("Q")
    eventually(function()
      return remote("return not vim.api.nvim_buf_is_valid(...)", { original.buf })
    end, "application Q did not clean up the terminal")
    check(remote("return vim.fn.jobwait({...}, 0)[1]", { original.job }) ~= -1, "application Q left process running")
  end)
end)

test("raw q/Q and unrelated terminal requests remain untouched", function()
  with_input_editor(function(remote, input, mode)
    local capture = temp .. "/raw-quit-controls.json"
    local original = start_input_fixture(remote, mode, capture, false)
    input("qQ")
    eventually(function() return captured_input(capture) == "qQ" end, "raw q/Q were intercepted")
    mode("t")
    remote("require('yt-tui').close()")
    capture = temp .. "/unrelated-terminal-requests.json"
    original = start_input_fixture(remote, mode, capture, false, "quit-controls")
    remote([[
      _G.request_count = 0
      vim.api.nvim_create_autocmd('TermRequest', {
        callback = function() _G.request_count = _G.request_count + 1 end,
      })
    ]])
    input("b")
    eventually(function() return remote("return _G.request_count") == 3 end, "probe OSC sequences were not delivered")
    check(remote("return #vim.fn.win_findbuf(...) == 1", { original.buf }), "unrelated OSC hid the terminal")
    remote([[
      _G.other_terminal = vim.api.nvim_create_buf(false, true)
      local channel = vim.api.nvim_open_term(_G.other_terminal, {})
      vim.api.nvim_chan_send(channel, '\27]777;yt-tui;hide\7')
    ]])
    eventually(function() return remote("return _G.request_count") == 4 end, "other buffer's request was not delivered")
    check(remote("return #vim.fn.win_findbuf(...) == 1", { original.buf }), "another terminal hid yt-tui")
    check(remote("return vim.fn.jobwait({...}, 0)[1]", { original.job }) == -1, "unrelated request stopped process")
    remote("vim.api.nvim_buf_delete(_G.other_terminal, { force = true })")
  end)
end)

test("queued terminal requests cannot hide a resumed window or replacement session", function()
  local function queued_hide(session)
    local callbacks = {}
    local schedule = vim.schedule
    vim.schedule = function(callback) callbacks[#callbacks + 1] = callback end
    local ok, err = pcall(api.nvim_exec_autocmds, "TermRequest", {
      buffer = session.buf,
      data = { sequence = "\27]777;yt-tui;hide", terminator = "\7" },
    })
    vim.schedule = schedule
    check(ok, err)
    check(#callbacks == 1, "request did not queue exactly one hide")
    return callbacks[1]
  end
  local first = start()
  local stale_window = queued_hide(first)
  plugin.hide()
  plugin.open()
  stale_window()
  assert_same_session(first)
  local stale_session = queued_hide(first)
  close()
  local replacement = start()
  stale_session()
  assert_same_session(replacement)
  assert_disposed(first)
end)

test("normal-mode Escape preserves retained failure output until Q closes it", function()
  configure("failure")
  plugin.open()
  local failed = current_session()
  assert_stopped(failed)
  check(api.nvim_buf_is_valid(failed.buf), "failed output was not retained")
  vim.cmd.stopinsert()
  api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "mx", false)
  check(api.nvim_get_current_win() == failed.win, "Escape hid the failed terminal")
  check(output(failed):find("YT_FIXTURE_FAILED", 1, true), "Escape discarded the failure output")
  vim.cmd("normal Q")
  assert_disposed(failed)
end)

test("commands and repeated setup", function()
  configure()
  configure()
  for _, command in ipairs({ "YtTui", "YtTuiClose", "YtTuiHide", "YtTuiToggle", "YtTuiRestart" }) do
    check(vim.fn.exists(":" .. command) == 2, command .. " command missing")
  end
  vim.cmd("YtTui")
  local session = current_session()
  vim.cmd("YtTuiClose")
  assert_disposed(session)
end)

test("floating window and terminal key passthrough", function()
  local observed
  local autocmd = api.nvim_create_autocmd("TermOpen", {
    once = true,
    callback = function(event)
      observed = vim.b[event.buf].terminal_passthrough
    end,
  })
  local session = start()
  pcall(api.nvim_del_autocmd, autocmd)
  local config = api.nvim_win_get_config(session.win)
  check(config.relative == "editor", "terminal is not an editor-relative float")
  check(config.width > 90 and config.height > 25, "default float is unexpectedly small")
  check(observed == true, "terminal_passthrough was not set before TermOpen")
  check(#api.nvim_buf_get_keymap(session.buf, "t") == 0, "plugin intercepted terminal keys")
  local normal_maps = api.nvim_buf_get_keymap(session.buf, "n")
  local closes = {}
  for _, mapping in ipairs(normal_maps) do
    closes[mapping.lhs] = true
  end
  check(closes.q, "normal-mode hide mapping missing")
  vim.fn.chansend(session.job, "hello from terminal\n")
  eventually(function()
    local content = table.concat(api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")
    return content:find("YT_FIXTURE_INPUT: hello from terminal", 1, true) ~= nil
  end, "terminal input did not reach the process")
  close()
  assert_disposed(session)
end)

test("arguments are passed literally", function()
  local marker = temp .. "/shell-must-not-run"
  local args = {
    "https://example.invalid/issue/DEMO-1?x=one&y=two",
    "literal spaces",
    "$(touch " .. marker .. ")",
    "; touch " .. marker,
  }
  local _, capture = start(nil, args)
  local received = vim.json.decode(table.concat(vim.fn.readfile(capture), "\n"))
  check(vim.deep_equal(received, args), "arguments changed: " .. vim.inspect(received))
  check(vim.fn.filereadable(marker) == 0, "arguments were evaluated by a shell")
end)

test("command forwards an issue URL", function()
  local capture = configure()
  local url = "https://example.invalid/issue/DEMO-42"
  vim.cmd("YtTui " .. url)
  eventually(function()
    return vim.fn.filereadable(capture) == 1
  end, "command did not launch the fixture")
  local received = vim.json.decode(table.concat(vim.fn.readfile(capture), "\n"))
  check(vim.deep_equal(received, { url }), "command lost its issue URL")
end)

test("repeated invocation focuses one running session", function()
  local original = api.nvim_get_current_win()
  local session = start()
  api.nvim_set_current_win(original)
  plugin.open()
  check(api.nvim_get_current_win() == session.win, "repeated open did not focus the float")
  check(#buffers() == 1 and vim.b[session.buf].terminal_job_id == session.job, "repeated open replaced the job")
  local before = #notices
  plugin.open({ "https://example.invalid/issue/OTHER-1" })
  check(#notices > before, "new arguments were silently discarded while running")
  check(vim.b[session.buf].terminal_job_id == session.job, "new arguments replaced a running session")
end)

test("resize updates and bounds the floating window", function()
  local session = start({ width = 0.6, height = 0.5 })
  local before = api.nvim_win_get_config(session.win)
  vim.o.columns = 160
  vim.o.lines = 50
  api.nvim_exec_autocmds("VimResized", {})
  local after = api.nvim_win_get_config(session.win)
  check(after.width > before.width and after.height > before.height, "float did not resize")
  vim.o.columns = 12
  vim.o.lines = 5
  api.nvim_exec_autocmds("VimResized", {})
  local small = api.nvim_win_get_config(session.win)
  check(small.width >= 1 and small.height >= 1, "small terminal produced an empty float")
  check(small.width <= vim.o.columns and small.height <= vim.o.lines, "small float exceeds the screen")
  close()
  vim.o.columns = 120
  vim.o.lines = 40
end)

test("missing executable leaves no window or buffer", function()
  local windows = #api.nvim_list_wins()
  local before = #notices
  plugin.setup({ executable = temp .. "/does-not-exist" })
  plugin.open()
  check(#buffers() == 0 and #api.nvim_list_wins() == windows, "failed launch leaked UI")
  check(#notices > before, "missing executable produced no diagnostic")
end)

test("unlaunchable executable reports failure and remains closable", function()
  local executable = temp .. "/broken-executable"
  vim.fn.writefile({ "#!/definitely/missing/yt-tui-test-interpreter" }, executable)
  vim.fn.setfperm(executable, "rwx------")
  local windows = #api.nvim_list_wins()
  local before = #notices
  plugin.setup({ executable = executable })
  local opened = plugin.open()
  if opened then
    -- PTY jobs can report an exec failure asynchronously as a nonzero exit.
    local session = current_session()
    assert_stopped(session)
    eventually(function()
      return #notices > before
    end, "spawn failure produced no diagnostic")
    close()
    assert_disposed(session)
  else
    check(#buffers() == 0 and #api.nvim_list_wins() == windows, "spawn failure leaked UI")
    check(#notices > before, "spawn failure produced no diagnostic")
  end
end)

test("successful exit closes the window", function()
  configure("success")
  plugin.open()
  local session = current_session()
  assert_disposed(session)
end)

test("nonzero exit keeps output until explicit restart", function()
  local failed = start()
  vim.fn.chansend(failed.job, "fail\n")
  assert_stopped(failed)
  check(api.nvim_buf_is_valid(failed.buf) and api.nvim_win_is_valid(failed.win), "error output was discarded")
  check(output(failed):find("YT_FIXTURE_FAILED", 1, true), "failure output is missing")
  plugin.open()
  check(api.nvim_get_current_buf() == failed.buf, "open silently discarded failure output")
  local capture = configure()
  plugin.restart()
  local replacement = current_session()
  read_capture(capture)
  check(replacement.buf ~= failed.buf, "restart did not replace the exited terminal")
  assert_disposed(failed)
end)

test("external window close hides the process and immediate reopen is safe", function()
  local session = start()
  api.nvim_win_close(session.win, true)
  assert_hidden(session)
  plugin.open()
  local resumed = api.nvim_get_current_win()
  vim.wait(50, function() return false end, 10)
  assert_same_session(session)
  check(api.nvim_win_is_valid(resumed), "old window callback closed the resumed float")
end)

test("external buffer deletion stops the process", function()
  local session = start()
  api.nvim_buf_delete(session.buf, { force = true })
  assert_disposed(session)
end)

test("replacing the terminal buffer hides it and preserves the repurposed window", function()
  local session = start()
  vim.cmd("enew")
  local replacement = api.nvim_get_current_buf()
  assert_hidden(session)
  check(api.nvim_win_is_valid(session.win), "plugin closed a repurposed window")
  check(api.nvim_win_get_buf(session.win) == replacement, "plugin removed the replacement buffer")
  plugin.open()
  assert_same_session(session)
  check(api.nvim_get_current_win() ~= session.win, "plugin took over a repurposed window")
  close()
  assert_stopped(session)
  check(api.nvim_win_is_valid(session.win), "cleanup closed a repurposed window")
  check(api.nvim_win_get_buf(session.win) == replacement, "cleanup removed the replacement buffer")
  api.nvim_win_close(session.win, true)
  api.nvim_buf_delete(replacement, { force = true })
end)

test("normal-mode q hides the terminal", function()
  local session = start()
  vim.cmd("stopinsert")
  vim.cmd("normal q")
  assert_hidden(session)
  plugin.open()
  assert_same_session(session)
end)

test("terminal-normal Escape reaches the live application once and resumes terminal input", function()
  with_input_editor(function(remote, input, mode)
    local capture = temp .. "/normal-escape.json"
    local original = start_input_fixture(remote, mode, capture, false)
    local win = remote("return vim.api.nvim_get_current_win()")
    input("<C-\\><C-n>")
    mode("nt")
    input("<Esc>")
    mode("t")
    input("x")
    eventually(function() return captured_input(capture) == "\27x" end, "expected a single Escape followed by x")
    check(remote("return vim.api.nvim_get_current_win()") == win, "Escape changed the focused window")
    check(remote("return vim.api.nvim_get_current_buf()") == original.buf, "Escape changed the terminal buffer")
    check(remote("return vim.fn.jobpid(...)", { original.job }) == original.pid, "Escape replaced the process")
  end)
end)

test("old exit callbacks do not close a replacement session", function()
  local first = start()
  plugin.close()
  configure()
  plugin.open()
  local second = current_session()
  assert_stopped(first)
  vim.wait(150, function()
    return not api.nvim_buf_is_valid(second.buf)
  end, 10)
  check(api.nvim_buf_is_valid(second.buf) and api.nvim_win_is_valid(second.win), "old callbacks closed the new session")
  check(vim.fn.jobwait({ second.job }, 0)[1] == -1, "replacement process stopped")
  close()
  close()
  assert_disposed(second)
end)

test("repeated hide and resume retain process, output, and event handlers", function()
  local original = api.nvim_get_current_win()
  local baseline = #api.nvim_get_autocmds({})
  local session = start()
  local active = #api.nvim_get_autocmds({})
  vim.fn.chansend(session.job, "draft still here\n")
  eventually(function()
    return output(session):find("YT_FIXTURE_INPUT: draft still here", 1, true) ~= nil
  end, "fixture did not retain draft text")
  for _ = 1, 8 do
    vim.cmd("YtTuiHide")
    assert_hidden(session)
    check(api.nvim_get_current_win() == original, "hide did not return to original window")
    plugin.hide()
    vim.cmd("YtTui")
    assert_same_session(session)
    check(output(session):find("YT_FIXTURE_INPUT: draft still here", 1, true), "resume lost terminal content")
    check(#api.nvim_get_autocmds({}) == active, "hide/resume leaked event handlers")
  end
  close()
  assert_disposed(session)
  check(#api.nvim_get_autocmds({}) == baseline, "close leaked event handlers")
end)

test("toggle hides visible session without stealing focus and resumes it", function()
  local original = api.nvim_get_current_win()
  local session = start()
  api.nvim_set_current_win(original)
  vim.cmd("YtTuiToggle")
  assert_hidden(session)
  check(api.nvim_get_current_win() == original, "toggle stole focus while hiding")
  vim.cmd("YtTuiToggle")
  assert_same_session(session)
  close()
  vim.cmd("YtTuiToggle")
  local fresh = current_session()
  check(fresh.job ~= session.job, "toggle did not start after a closed session")
end)

test("resume uses current dimensions after resize while hidden", function()
  local session = start({ width = 0.6, height = 0.5 })
  local before = api.nvim_win_get_config(session.win)
  plugin.hide()
  vim.o.columns = 160
  vim.o.lines = 50
  api.nvim_exec_autocmds("VimResized", {})
  assert_hidden(session)
  plugin.open()
  assert_same_session(session)
  local after = api.nvim_win_get_config(api.nvim_get_current_win())
  check(after.width > before.width and after.height > before.height, "resumed float used stale dimensions")
end)

test("resume moves the same session into the current tab", function()
  local first_tab = api.nvim_get_current_tabpage()
  local original = api.nvim_get_current_win()
  local session = start()
  vim.cmd("tabnew")
  local second_tab = api.nvim_get_current_tabpage()
  local second_code = api.nvim_get_current_win()
  plugin.toggle()
  assert_same_session(session)
  check(api.nvim_get_current_tabpage() == second_tab, "resume jumped to the old tab")
  check(not api.nvim_win_is_valid(session.win), "old tab retained another float")
  plugin.hide()
  check(api.nvim_get_current_win() == second_code, "hide did not return to this tab's code window")
  api.nvim_set_current_tabpage(first_tab)
  check(api.nvim_win_is_valid(original), "moving float closed original code window")
  vim.cmd("tabclose")
  check(api.nvim_get_current_tabpage() == second_tab, "closing old tab changed target tab")
  plugin.open()
  assert_same_session(session)
end)

test("hidden terminal buffer deletion stops the process", function()
  local session = start()
  plugin.hide()
  api.nvim_buf_delete(session.buf, { force = true })
  assert_disposed(session)
end)

test("hidden successful exit cleans up without changing code focus", function()
  local original = api.nvim_get_current_win()
  local session = start()
  plugin.hide()
  vim.fn.chansend(session.job, "exit\n")
  assert_disposed(session)
  check(api.nvim_get_current_win() == original, "hidden exit stole focus")
end)

test("hidden failure retains inspectable output without reopening itself", function()
  local original = api.nvim_get_current_win()
  local session = start()
  plugin.hide()
  local count = #notices
  vim.fn.chansend(session.job, "fail\n")
  assert_stopped(session)
  eventually(function() return #notices > count end, "hidden failure was not reported")
  check(api.nvim_get_current_win() == original, "hidden failure stole focus")
  check(#vim.fn.win_findbuf(session.buf) == 0, "hidden failure opened a window")
  check(output(session):find("YT_FIXTURE_FAILED", 1, true), "hidden failure output lost")
  vim.cmd("stopinsert")
  plugin.open()
  check(api.nvim_get_current_buf() == session.buf, "resume discarded failed session")
  check(api.nvim_get_mode().mode ~= "t", "failed terminal reopened in terminal mode")
  plugin.hide()
  close()
  assert_disposed(session)
end)

test("restart cancellation keeps live hidden session and draft", function()
  local session = start(nil, { "https://example.invalid/issue/DEMO-1" })
  plugin.hide()
  local prompt = capture_prompt()
  vim.cmd("YtTuiRestart")
  local pending = prompt()
  assert_hidden(session)
  pending.answer(pending.items[1], 1)
  assert_hidden(session)
  plugin.open()
  assert_same_session(session)
end)

test("confirmed restart starts fresh without reusing invocation URL", function()
  local session = start(nil, { "https://example.invalid/issue/DEMO-1" })
  plugin.hide()
  local capture = configure()
  local prompt = capture_prompt()
  vim.cmd("YtTuiRestart")
  local pending = prompt()
  pending.answer(pending.items[2], 2)
  local fresh = current_session()
  check(fresh.job ~= session.job and fresh.buf ~= session.buf, "restart reused old session")
  check(vim.deep_equal(read_capture(capture), {}), "restart reused the previous issue URL")
  assert_disposed(session)
end)

test("restart command bang bypasses confirmation and forwards new URL", function()
  local session = start()
  local capture = configure()
  vim.ui.select = function() error("forced restart unexpectedly prompted") end
  local url = "https://example.invalid/issue/DEMO-2"
  vim.cmd("YtTuiRestart! " .. url)
  local fresh = current_session()
  check(fresh.job ~= session.job, "bang restart kept old job")
  check(vim.deep_equal(read_capture(capture), { url }), "bang restart lost explicit URL")
  assert_disposed(session)
end)

test("restart preserves configured defaults and literal argument boundaries", function()
  local session = start()
  local capture = temp .. "/restart-literal.json"
  local marker = temp .. "/restart-shell-must-not-run"
  plugin.setup({ executable = python, args = { fixture, "hold", capture, "configured default" } })
  local args = { "literal spaces", "$(touch " .. marker .. ")", "; touch " .. marker }
  plugin.restart(args, { force = true })
  local expected = { "configured default" }
  vim.list_extend(expected, args)
  check(vim.deep_equal(read_capture(capture), expected), "restart changed configured or literal arguments")
  check(vim.fn.filereadable(marker) == 0, "restart evaluated shell arguments")
  assert_disposed(session)
end)

test("invalid restart preflight preserves existing session", function()
  local session = start()
  vim.ui.select = function() error("invalid restart unexpectedly prompted") end
  check(plugin.restart({ 123 }, { force = true }) == false, "invalid args were accepted")
  assert_same_session(session)
  plugin.setup({ executable = temp .. "/does-not-exist" })
  check(plugin.restart() == false, "missing executable was accepted")
  assert_same_session(session)
end)

test("restart revalidates configuration after confirmation", function()
  local session = start()
  local prompt = capture_prompt()
  plugin.restart()
  local pending = prompt()
  plugin.setup({ executable = temp .. "/no-longer-exists" })
  pending.answer(pending.items[2], 2)
  assert_same_session(session)
end)

test("pending restart cannot replace a newer session", function()
  local first = start()
  local prompt = capture_prompt()
  plugin.restart()
  local pending = prompt()
  plugin.close()
  local replacement = start()
  pending.answer(pending.items[2], 2)
  assert_same_session(replacement)
  assert_disposed(first)
end)

test("a newer restart prompt invalidates an older prompt", function()
  local session = start()
  local first_prompt = capture_prompt()
  plugin.restart()
  local first = first_prompt()
  local second_prompt = capture_prompt()
  plugin.restart()
  local second = second_prompt()
  first.answer(first.items[2], 2)
  assert_same_session(session)
  second.answer(second.items[1], 1)
  assert_same_session(session)
end)

test("explicit stop terminates a hidden nested editor process", function()
  local capture = configure("nested")
  plugin.open({ vim.v.progpath })
  local session = current_session()
  eventually(function() return vim.fn.filereadable(capture .. ".child-pid") == 1 end, "nested editor did not start")
  local child_pid = tonumber(vim.fn.readfile(capture .. ".child-pid")[1])
  plugin.hide()
  assert_hidden(session)
  check(vim.uv.kill(child_pid, 0) == 0, "hide stopped nested editor")
  plugin.open()
  assert_same_session(session)
  close()
  assert_disposed(session)
  local stopped = vim.wait(3000, function() return vim.uv.kill(child_pid, 0) == nil end, 10)
  if not stopped then vim.uv.kill(child_pid, 15) end
  check(stopped, "explicit stop left nested editor running")
end)

test("quitting parent Neovim cleans up hidden session and nested editor", function()
  local capture = temp .. "/shutdown.json"
  local result = vim.system({
    vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE",
    "-c", 'lua dofile(vim.env.YT_TUI_TEST_ROOT .. "/tests/shutdown.lua")',
  }, { env = { YT_TUI_TEST_ROOT = root, YT_TUI_SHUTDOWN_CAPTURE = capture }, text = true }):wait(10000)
  check(result.code == 0, "parent shutdown probe failed: " .. (result.stderr or ""))
  for _, suffix in ipairs({ ".pid", ".child-pid" }) do
    check(vim.fn.filereadable(capture .. suffix) == 1, "shutdown probe did not launch process " .. suffix)
    local pid = tonumber(vim.fn.readfile(capture .. suffix)[1])
    local stopped = vim.wait(3000, function() return vim.uv.kill(pid, 0) == nil end, 10)
    if not stopped then vim.uv.kill(pid, 15) end
    check(stopped, "quitting parent left a process running: " .. suffix)
  end
end)

test("TermOpen closure stops the job returned after its callback", function()
  local baseline = #api.nvim_get_autocmds({})
  local observed
  configure()
  api.nvim_create_autocmd("TermOpen", {
    once = true,
    callback = function(event)
      local job = vim.b[event.buf].terminal_job_id
      observed = { buf = event.buf, win = api.nvim_get_current_win(), job = job, pid = vim.fn.jobpid(job) }
      jobs[#jobs + 1] = observed
      plugin.close()
    end,
  })
  check(plugin.open() == false, "open reported success after TermOpen closed it")
  check(observed ~= nil, "TermOpen callback did not run")
  assert_disposed(observed)
  check(#api.nvim_get_autocmds({}) == baseline, "TermOpen closure leaked handlers")
end)

test("TermOpen restart leaves only the replacement process", function()
  local original
  local replacement_capture
  configure()
  api.nvim_create_autocmd("TermOpen", {
    once = true,
    callback = function(event)
      local job = vim.b[event.buf].terminal_job_id
      original = { buf = event.buf, win = api.nvim_get_current_win(), job = job, pid = vim.fn.jobpid(job) }
      jobs[#jobs + 1] = original
      replacement_capture = configure()
      plugin.restart({}, { force = true })
    end,
  })
  check(plugin.open() == false, "superseded open reported success")
  check(original ~= nil, "TermOpen callback did not run")
  local replacement = current_session()
  read_capture(replacement_capture)
  check(replacement.job ~= original.job, "TermOpen restart retained original job")
  assert_disposed(original)
  assert_same_session(replacement)
end)

test("FileType closure stops the initialized process without leaked handlers", function()
  local baseline = #api.nvim_get_autocmds({})
  local observed
  configure()
  api.nvim_create_autocmd("FileType", {
    pattern = "yt-tui",
    once = true,
    callback = function()
      observed = current_session()
      plugin.close()
    end,
  })
  check(plugin.open() == false, "open reported success after FileType closed it")
  check(observed ~= nil, "FileType callback did not run")
  assert_disposed(observed)
  check(#api.nvim_get_autocmds({}) == baseline, "FileType closure leaked handlers")
end)

test("BufEnter replacement on resume keeps the repurposed float untouched", function()
  local session = start()
  plugin.hide()
  local replacement = api.nvim_create_buf(false, true)
  local repurposed
  api.nvim_create_autocmd("BufEnter", {
    buffer = session.buf,
    once = true,
    callback = function()
      repurposed = api.nvim_get_current_win()
      api.nvim_win_set_buf(repurposed, replacement)
      api.nvim_win_set_config(repurposed, { width = 17 })
    end,
  })
  check(plugin.open() == false, "resume reported success after window was repurposed")
  check(repurposed ~= nil and api.nvim_win_is_valid(repurposed), "repurposed window was lost")
  check(api.nvim_win_get_buf(repurposed) == replacement, "resume replaced user buffer")
  check(api.nvim_win_get_config(repurposed).width == 17, "resume resized a repurposed window")
  assert_hidden(session)
  plugin.open()
  assert_same_session(session)
  close()
  check(api.nvim_win_is_valid(repurposed), "cleanup closed a repurposed window")
  api.nvim_win_close(repurposed, true)
  api.nvim_buf_delete(replacement, { force = true })
end)

test("BufEnter closure on resume stops the session without leaking a float", function()
  local session = start()
  plugin.hide()
  local windows = #api.nvim_list_wins()
  api.nvim_create_autocmd("BufEnter", {
    buffer = session.buf,
    once = true,
    callback = function()
      plugin.close()
    end,
  })
  check(plugin.open() == false, "resume reported success after BufEnter closed it")
  assert_disposed(session)
  check(#api.nvim_list_wins() == windows, "BufEnter closure leaked a float")
end)

test("opening cannot turn the editing buffer into a terminal when WinEnter redirects focus", function()
  local path = temp .. "/working-file"
  vim.fn.writefile({ "work in progress" }, path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  local editor = api.nvim_get_current_win()
  local file = api.nvim_get_current_buf()
  local windows = #api.nvim_list_wins()
  configure()
  api.nvim_create_autocmd("WinEnter", {
    once = true,
    callback = function()
      api.nvim_set_current_win(editor)
    end,
  })
  vim.cmd("YtTui")
  check(vim.bo[file].buftype == "" and api.nvim_buf_get_name(file) == path, "editing buffer became a terminal")
  check(api.nvim_buf_get_lines(file, 0, 1, false)[1] == "work in progress", "editing buffer content changed")
  check(api.nvim_get_current_win() == editor and #api.nvim_list_wins() == windows, "failed open left a float")
  check(plugin.open(), "retry after focus returned failed")
  close()
end)

local failures = 0
for _, case in ipairs(tests) do
  local ok, err = xpcall(case.run, debug.traceback)
  if ok then
    print("PASS " .. case.name)
  else
    failures = failures + 1
    print("FAIL " .. case.name .. "\n" .. err)
  end
  vim.ui.select = default_select
  pcall(close)
  for _, buf in ipairs(buffers()) do
    pcall(api.nvim_buf_delete, buf, { force = true })
  end
  vim.o.columns = 120
  vim.o.lines = 40
end

for _, session in ipairs(jobs) do
  if vim.fn.jobwait({ session.job }, 0)[1] == -1 then
    failures = failures + 1
    print("FAIL job leaked after the suite: " .. session.job)
    vim.fn.jobstop(session.job)
  end
end
vim.fn.delete(temp, "rf")
print(string.format("%d tests, %d failures", #tests, failures))
vim.cmd(failures == 0 and "qa!" or "cquit 1")
