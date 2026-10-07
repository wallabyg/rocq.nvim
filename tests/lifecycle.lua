-- Run from rocq.nvim with COQ_LSP_BIN pointing to the server.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local function text(ft)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].filetype == ft then
      return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    end
  end
  return ""
end
local function wait_for(predicate, message)
  assert(vim.wait(15000, predicate, 20), message .. "\n" .. text("rocqinfo"))
end
local ok, err = xpcall(function()
  vim.cmd.edit("examples/Basic.v")
  vim.bo.filetype = "coq"
  local source, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local rocq = require("rocq")
  rocq.setup({ cmd = { vim.env.COQ_LSP_BIN or "coq-lsp" }, update_delay = 30 })
  local function client(buf) return vim.lsp.get_clients({ bufnr = buf or source, name = "coq_lsp" })[1] end
  wait_for(function() return client() and client().initialized end, "Initialization failed")
  vim.api.nvim_win_set_cursor(win, { 3, 10 })
  rocq.pin()
  wait_for(function() return text("rocqinfo"):find("H : P", 1, true) end, "Initial goals failed")
  local old = client()
  local canceled, foreign = {}, {}
  local original_cancel = old.cancel_request
  old.cancel_request = function(self, id)
    canceled[id] = true
    return original_cancel(self, id)
  end
  -- Keep another proof on the same server; interrupt must not cancel its request.
  local other = vim.fn.bufadd(vim.fn.getcwd() .. "/examples/Navigation.v")
  vim.fn.bufload(other)
  vim.bo[other].filetype = "coq"
  vim.lsp.buf_attach_client(other, old.id)
  wait_for(function() return old.attached_buffers[other] end, "Second proof failed to attach")
  old:request("proof/goals", { textDocument = { uri = vim.uri_from_bufnr(other) },
    position = { line = 0, character = 0 }, pp_format = "Str" }, function() end, other)
  for id, req in pairs(old.requests) do if req.bufnr == other then foreign[id] = true end end
  rocq.goals()
  rocq.query("Check", "H")
  vim.cmd("RocqInterrupt")
  assert(next(canceled), "Interrupt did not send cancellation")
  for id in pairs(foreign) do assert(not canceled[id], "Interrupt canceled another proof's request") end
  assert(text("rocqinfo"):find("Interrupted", 1, true), "Interrupted goals were not labeled")
  assert(text("rocqquery"):find("Interrupted", 1, true), "Pending query was not canceled")
  vim.api.nvim_win_set_cursor(win, { 4, 10 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = source })
  vim.wait(200, function() return false end, 20)
  assert(text("rocqinfo"):find("Interrupted", 1, true), "Automatic updates or late replies resumed interrupted goals")
  vim.cmd("RocqGoals")
  wait_for(function() return not text("rocqinfo"):find("Interrupted", 1, true)
    and not text("rocqinfo"):find("Loading", 1, true) end, "Manual resume failed")

  vim.api.nvim_buf_set_text(source, 0, 0, 0, 0, { "(* unsaved *) " })
  local lines = vim.api.nvim_buf_get_lines(source, 0, -1, false)
  local marks = vim.api.nvim_buf_get_extmarks(source, vim.api.nvim_create_namespace("rocq.pins"), 0, -1, {})
  local root, cmd = old.config.root_dir, vim.deepcopy(old.config.cmd)
  vim.cmd("RocqToggle")
  local windows = #vim.api.nvim_tabpage_list_wins(0)
  vim.cmd("RocqRestart")
  vim.cmd("RocqRestart") -- A repeated command must join the existing restart.
  wait_for(function() return client() and client().id ~= old.id and client().initialized end, "Restart failed")
  local replacement = client()
  wait_for(function() return replacement.attached_buffers[other] end, "Restart lost another proof")
  wait_for(function() return not vim.lsp.get_client_by_id(old.id) end, "Old server survived restart")
  vim.wait(200, function() return false end, 20)
  assert(#vim.api.nvim_tabpage_list_wins(0) == windows, "Restart reopened hidden or new panels")
  assert(vim.api.nvim_get_current_win() == win, "Restart stole focus")
  assert(vim.deep_equal(lines, vim.api.nvim_buf_get_lines(source, 0, -1, false)), "Restart changed unsaved proof")
  assert(vim.deep_equal(marks, vim.api.nvim_buf_get_extmarks(source, vim.api.nvim_create_namespace("rocq.pins"), 0, -1, {})), "Restart lost pins")
  assert(replacement.config.root_dir == root and vim.deep_equal(replacement.config.cmd, cmd), "Restart lost server configuration")
  assert(#vim.lsp.get_clients({ name = "coq_lsp" }) == 1, "Restart duplicated server")
  vim.api.nvim_win_set_cursor(win, { 3, 10 })
  vim.cmd("RocqToggle")
  wait_for(function() return text("rocqinfo"):find("H : P", 1, true)
    and not text("rocqinfo"):find("Loading", 1, true) end, "Restarted server lost live or pinned goals")
  -- Recovery from the goal panel also preserves focus.
  rocq.focus()
  local panel_win = vim.api.nvim_get_current_win()
  vim.cmd("RocqRestart!")
  wait_for(function() return client() and client().id ~= replacement.id and client().initialized end, "Forced restart failed")
  vim.wait(100, function() return false end, 20)
  assert(vim.api.nvim_get_current_win() == panel_win, "Panel restart stole focus")
  wait_for(function() return not text("rocqinfo"):find("Loading", 1, true)
    and text("rocqinfo"):find("H : P", 1, true) end, "Goal panel restart did not refresh goals")
  rocq.focus()
  rocq.query("Check", "H")
  wait_for(function() return text("rocqquery"):match("H\n%s*: P") end, "Query after restart failed")
  local query_win
  for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(candidate)].filetype == "rocqquery" then query_win = candidate end
  end
  vim.api.nvim_set_current_win(query_win)
  local before_query_restart = client()
  vim.cmd("RocqRestart")
  wait_for(function() return client() and client().id ~= before_query_restart.id and client().initialized end,
    "Restart from query panel failed")
  wait_for(function() return not text("rocqinfo"):find("Loading", 1, true)
    and text("rocqinfo"):find("H : P", 1, true) end, "Query panel restart did not refresh goals")
  assert(vim.api.nvim_get_current_win() == query_win, "Query panel restart stole focus")
  vim.api.nvim_set_current_win(win)
  local crashed = client()
  crashed:stop(true)
  wait_for(function() return not vim.lsp.get_client_by_id(crashed.id) end, "Crash simulation failed")
  vim.cmd("RocqRestart")
  wait_for(function() return client() and client().initialized end, "Recovery without a client failed")
  print("PASS: cancellation isolation, pause/resume, graceful/forced restart, shared buffers, hidden panels, unsaved edits, pins, configuration, and crash recovery")
end, debug.traceback)
for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") else vim.cmd("qa!") end
