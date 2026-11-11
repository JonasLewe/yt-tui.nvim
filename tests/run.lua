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

test("commands and repeated setup", function()
  configure()
  configure()
  check(vim.fn.exists(":YtTui") == 2, "YtTui command missing")
  check(vim.fn.exists(":YtTuiClose") == 2, "YtTuiClose command missing")
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
  check(closes.q and closes["<Esc>"], "normal-mode close mappings missing")
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

test("nonzero exit keeps output and allows a fresh launch", function()
  configure("failure")
  plugin.open()
  local failed = current_session()
  assert_stopped(failed)
  check(api.nvim_buf_is_valid(failed.buf) and api.nvim_win_is_valid(failed.win), "error output was discarded")
  local output = table.concat(api.nvim_buf_get_lines(failed.buf, 0, -1, false), "\n")
  check(output:find("YT_FIXTURE_FAILED", 1, true), "failure output is missing")
  local replacement = start()
  check(replacement.buf ~= failed.buf, "open did not replace the exited terminal")
  assert_disposed(failed)
end)

test("external window close stops the process", function()
  local session = start()
  api.nvim_win_close(session.win, true)
  assert_disposed(session)
end)

test("external buffer deletion stops the process", function()
  local session = start()
  api.nvim_buf_delete(session.buf, { force = true })
  assert_disposed(session)
end)

test("replacing the terminal buffer stops the process and preserves the new buffer", function()
  local session = start()
  vim.cmd("enew")
  local replacement = api.nvim_get_current_buf()
  eventually(function()
    return not api.nvim_buf_is_valid(session.buf)
  end, "hidden terminal buffer leaked")
  assert_stopped(session)
  check(api.nvim_win_is_valid(session.win), "plugin closed a repurposed window")
  check(api.nvim_win_get_buf(session.win) == replacement, "plugin removed the replacement buffer")
  api.nvim_win_close(session.win, true)
  api.nvim_buf_delete(replacement, { force = true })
end)

test("normal-mode q closes the terminal", function()
  local session = start()
  vim.cmd("stopinsert")
  vim.cmd("normal q")
  assert_disposed(session)
end)

test("normal-mode Escape closes the terminal", function()
  local session = start()
  vim.cmd("stopinsert")
  local escape = api.nvim_replace_termcodes("<Esc>", true, false, true)
  api.nvim_feedkeys(escape, "mx", false)
  assert_disposed(session)
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

local failures = 0
for _, case in ipairs(tests) do
  local ok, err = xpcall(case.run, debug.traceback)
  if ok then
    print("PASS " .. case.name)
  else
    failures = failures + 1
    print("FAIL " .. case.name .. "\n" .. err)
  end
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
