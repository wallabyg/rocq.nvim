-- Run from rocq.nvim: nvim --headless -u NONE -i NONE -l tests/integration.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function panel_lines()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].filetype == "rocqinfo" then
      return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    end
  end
  return ""
end

local function wait_for(predicate, message)
  assert(vim.wait(15000, predicate, 20), message .. "\nPanel: " .. panel_lines())
end

local ok, err = xpcall(function()
  vim.cmd.edit("examples/Basic.v")
  vim.bo.filetype = "coq"
  local source = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local rocq = require("rocq")
  local cmd = { vim.env.COQ_LSP_BIN or "coq-lsp" }
  rocq.setup({ cmd = cmd, auto_update = false })
  wait_for(function()
    local clients = vim.lsp.get_clients({ bufnr = source, name = "coq_lsp" })
    return clients[1] and clients[1].initialized
  end, "LSP initialization failed")
  local progress_client = vim.lsp.get_clients({ bufnr = source, name = "coq_lsp" })[1]
  local progress_handler = progress_client.handlers["$/coq/fileProgress"]
  local real_progress = 0
  progress_client.handlers["$/coq/fileProgress"] = function(...)
    real_progress = real_progress + 1
    return progress_handler(...)
  end
  rocq.start()
  assert(#vim.lsp.get_clients({ bufnr = source, name = "coq_lsp" }) == 1,
    "Startup created a duplicate client")

  vim.api.nvim_win_set_cursor(source_win, { 3, 2 })
  rocq.goals()
  wait_for(function()
    local text = panel_lines()
    return text:find("H : P", 1, true) and text:find("Goals (1)", 1, true)
  end, "Expected identity goal after intros")
  assert(vim.api.nvim_get_current_win() == source_win, "Panel stole focus")
  assert(vim.api.nvim_get_current_buf() == source, "Panel replaced source buffer")

  vim.api.nvim_win_set_cursor(source_win, { 4, 2 })
  rocq.goals()
  wait_for(function() return panel_lines():find("No goals", 1, true) end,
    "Expected completed proof after exact")

  -- An unsaved edit must reach the server before the goal request.
  vim.api.nvim_buf_set_lines(source, 3, 4, false, { "  exact missing_term." })
  rocq.goals()
  wait_for(function() return panel_lines():find("missing_term", 1, true) end,
    "Expected server error for unsaved edit")
  vim.api.nvim_buf_set_lines(source, 3, 4, false, { "  exact H." })
  rocq.goals()
  wait_for(function() return panel_lines():find("No goals", 1, true) end,
    "Expected recovery after fixing unsaved edit")

  -- Moving the cursor before a reply must not display an old goal as current.
  vim.api.nvim_win_set_cursor(source_win, { 3, 2 })
  rocq.goals()
  vim.api.nvim_win_set_cursor(source_win, { 4, 2 })
  wait_for(function() return panel_lines():find("Position changed", 1, true) end,
    "Expected stale reply rejection")
  -- Enable automatic updates on the existing client. Headless tests explicitly
  -- dispatch editor events because API cursor/line changes do not reliably
  -- produce interactive CursorMoved/TextChanged events while vim.wait runs.
  rocq.setup({ cmd = cmd, update_delay = 120 })
  wait_for(function() return panel_lines():find("No goals", 1, true) end,
    "Expected automatic initial update")
  local function event(name)
    vim.api.nvim_exec_autocmds(name, { buffer = source })
  end
  vim.api.nvim_win_set_cursor(source_win, { 3, 2 })
  event("CursorMoved")
  wait_for(function() return panel_lines():find("H : P", 1, true) end,
    "Expected automatic cursor update")

  local client = vim.lsp.get_clients({ bufnr = source, name = "coq_lsp" })[1]
  local request = client.request
  local goal_requests = 0
  client.request = function(self, method, ...)
    if method == "proof/goals" then goal_requests = goal_requests + 1 end
    return request(self, method, ...)
  end
  for i = 1, 10 do
    vim.api.nvim_win_set_cursor(source_win, { i % 2 == 0 and 4 or 3, 2 })
    event(i % 2 == 0 and "CursorMovedI" or "CursorMoved")
  end
  assert(goal_requests == 0, "Cursor updates were not debounced")
  wait_for(function() return panel_lines():find("No goals", 1, true) end,
    "Expected goal at final cursor position")
  assert(goal_requests == 1, "Rapid cursor updates sent multiple goal requests")

  vim.api.nvim_buf_set_lines(source, 3, 4, false, { "  exact missing_term." })
  event("TextChangedI")
  wait_for(function() return panel_lines():find("missing_term", 1, true) end,
    "Expected automatic update after insert-mode edit")
  vim.api.nvim_buf_set_lines(source, 3, 4, false, { "  exact H." })
  event("TextChanged")
  wait_for(function() return panel_lines():find("No goals", 1, true) end,
    "Expected automatic recovery after normal-mode edit")

  -- A deferred update must not operate on another buffer after leaving.
  local before = goal_requests
  event("CursorMoved")
  local other = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(other)
  vim.wait(250, function() return false end, 20)
  assert(goal_requests == before, "Deferred update ran after leaving proof buffer")
  vim.api.nvim_set_current_buf(source)
  wait_for(function() return goal_requests > before end,
    "Expected refresh after returning to proof buffer")
  wait_for(function() return panel_lines():find("No goals", 1, true) end,
    "Expected goals after returning to proof buffer")
  assert(vim.api.nvim_get_current_win() == source_win, "Automatic update stole focus")
  client.request = request

  vim.api.nvim_win_set_cursor(source_win, { 3, 2 })
  vim.cmd("RocqPin")
  wait_for(function()
    local pin = panel_lines():match("Pin 1.*")
    return pin and pin:find("H : P", 1, true)
  end, "Expected pinned goal after intros")
  vim.cmd("RocqPin")
  local ns = vim.api.nvim_create_namespace("rocq.pins")
  assert(#vim.api.nvim_buf_get_extmarks(source, ns, 0, -1, {}) == 1,
    "Pinning the same position created a duplicate")
  vim.api.nvim_win_set_cursor(source_win, { 4, 2 })
  event("CursorMoved")
  wait_for(function()
    local text = panel_lines()
    return text:match("^No goals") and text:match("Pin 1.*H : P")
  end, "Expected live completed goal alongside pinned hypothesis")

  -- Insert a multibyte comment before the pin, then a line above it. The
  -- extmark must follow both edits and the LSP column must use UTF-16.
  vim.api.nvim_buf_set_text(source, 2, 0, 2, 0, { "  (* α *) " })
  vim.api.nvim_buf_set_lines(source, 0, 0, false, { "(* heading *)" })
  event("TextChanged")
  wait_for(function()
    local pin = panel_lines():match("Pin 1.*")
    return pin and pin:find("— 4:", 1, true) and pin:find("H : P", 1, true)
  end, "Expected pin to follow line and Unicode edits")
  local mark = vim.api.nvim_buf_get_extmarks(source, ns, 0, -1, {})[1]
  assert(mark[2] == 3 and mark[3] > 2, "Pin extmark did not track edits")

  vim.api.nvim_win_set_cursor(source_win, { 5, 2 })
  vim.cmd("RocqPin")
  wait_for(function()
    local pin = panel_lines():match("Pin 2.*")
    return pin and pin:find("No goals", 1, true)
  end, "Expected independent second pin")
  assert(#vim.api.nvim_buf_get_extmarks(source, ns, 0, -1, {}) == 2,
    "Expected two source markers")

  -- Change the actual proof state. Pins are positions in the current document,
  -- so the hypothesis must refresh rather than remain a snapshot of H.
  local prefix = "  (* α *) "
  vim.api.nvim_buf_set_text(source, 3, #prefix + 9, 3, #prefix + 10, { "K" })
  vim.api.nvim_buf_set_text(source, 4, 8, 4, 9, { "K" })
  event("TextChanged")
  wait_for(function()
    local pin = panel_lines():match("Pin 1.-Pin 2")
    return pin and pin:find("K : P", 1, true) and not pin:find("H : P", 1, true)
  end, "Expected pinned hypothesis to refresh after edit")

  vim.api.nvim_buf_set_lines(source, 3, 4, false, {})
  event("TextChanged")
  wait_for(function() return panel_lines():find("Pin 1 — position deleted", 1, true) end,
    "Deleted pinned text was treated as a valid proof position")
  vim.cmd("RocqClearPins")
  wait_for(function() return not panel_lines():find("Pin ", 1, true) end,
    "Clear pins left panel contents behind")
  assert(#vim.api.nvim_buf_get_extmarks(source, ns, 0, -1, {}) == 0,
    "Clear pins left source markers behind")

  -- Clear a new pin while its request is pending; late replies must not bring
  -- it back into the panel.
  vim.cmd("RocqPin")
  vim.cmd("RocqClearPins")
  vim.wait(300, function() return false end, 20)
  assert(not panel_lines():find("Pin ", 1, true), "Late reply resurrected cleared pin")
  assert(vim.api.nvim_get_current_win() == source_win, "Pin operation stole focus")
  assert(real_progress > 0, "No real server progress notifications received")
  wait_for(function() return not require("rocq.progress").status(source) end,
    "Checking status did not clear after real server completion")

  -- Exercise protocol edge cases deterministically through the installed LSP
  -- handler after verifying real notifications above.
  rocq.setup({ cmd = cmd, auto_update = false })
  vim.api.nvim_buf_set_text(source, 0, 3, 0, 3, { "α😀" })
  local progress = require("rocq.progress")
  local progress_ns = vim.api.nvim_create_namespace("rocq.progress")
  local version = vim.lsp.util.buf_versions[source]
  local end_character = client.offset_encoding == "utf-8" and 9
    or client.offset_encoding == "utf-32" and 5 or 6
  local range = { start = { line = 0, character = 3 },
    ["end"] = { line = 0, character = end_character } }
  local function notify(items, document_version)
    client.handlers["$/coq/fileProgress"](nil, {
      textDocument = { uri = vim.uri_from_bufnr(source), version = document_version or version },
      processing = items,
    }, { client_id = client.id })
  end
  notify({ { range = range, kind = 1 } })
  local marks = vim.api.nvim_buf_get_extmarks(source, progress_ns, 0, -1, { details = true })
  assert(#marks == 1 and marks[1][3] == 3 and marks[1][4].end_col == 9,
    "Progress range did not convert Unicode positions to bytes")
  assert(progress.status(source) == "Checking…", "Missing busy status")
  wait_for(function() return panel_lines():find("Checking…", 1, true) end,
    "Busy status did not reach goal panel")
  notify({}, version - 1)
  assert(progress.status(source) == "Checking…", "Stale notification cleared current progress")
  notify({ { range = range, kind = 2 } })
  marks = vim.api.nvim_buf_get_extmarks(source, progress_ns, 0, -1, { details = true })
  assert(marks[1][4].hl_group == "RocqProcessingError", "Fatal range lacks error highlight")
  assert(progress.status(source) == "Checking failed", "Missing fatal status")
  notify({})
  assert(#vim.api.nvim_buf_get_extmarks(source, progress_ns, 0, -1, {}) == 0,
    "Completion left processing markers")
  assert(not progress.status(source), "Completion left busy status")
  notify({ { range = range } })
  local eof = { line = vim.api.nvim_buf_line_count(source), character = 0 }
  notify({ { range = { start = eof, ["end"] = eof }, kind = 1 } })
  assert(not progress.status(source), "Empty EOF range was treated as busy")
  notify({ { range = range } })
  vim.api.nvim_buf_set_text(source, 0, 0, 0, 0, { " " })
  assert(not progress.status(source), "Edit retained progress for old document version")
  assert(#vim.api.nvim_buf_get_extmarks(source, progress_ns, 0, -1, {}) == 0,
    "Edit retained obsolete processing markers")
  version = vim.lsp.util.buf_versions[source]
  notify({ { range = range } })
  vim.api.nvim_exec_autocmds("LspDetach", { buffer = source, data = { client_id = client.id } })
  assert(not progress.status(source), "LSP detach retained progress")

  local chained = 0
  local proxy = { handlers = { ["$/coq/fileProgress"] = function() chained = chained + 1 end } }
  progress.attach(proxy)
  progress.attach(proxy)
  proxy.handlers["$/coq/fileProgress"](nil, nil, { client_id = client.id })
  assert(chained == 1, "Existing handler was lost or wrapped twice")
  assert(vim.api.nvim_get_current_win() == source_win, "Progress update stole focus")
  print("PASS: real-server goals, pins, automatic updates, progress, Unicode ranges, and cleanup")
end, debug.traceback)

for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
