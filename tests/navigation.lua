-- Run from rocq.nvim: nvim --headless -u NONE -i NONE -l tests/navigation.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function wait_for(predicate, message)
  assert(vim.wait(15000, predicate, 20), message)
end

local function cursor_is(row, col)
  return vim.deep_equal(vim.api.nvim_win_get_cursor(0), { row, col })
end

local function panel_text()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].filetype == "rocqinfo" then
      return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    end
  end
  return ""
end

local ok, err = xpcall(function()
  vim.cmd.edit("examples/Basic.v")
  vim.bo.filetype = "coq"
  local rocq = require("rocq")
  rocq.setup({ cmd = { vim.env.COQ_LSP_BIN or "coq-lsp" }, auto_update = false })
  local source = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  wait_for(function()
    local client = vim.lsp.get_clients({ bufnr = source, name = "coq_lsp" })[1]
    return client and client.initialized
  end, "LSP initialization failed")
  local client = vim.lsp.get_clients({ bufnr = source, name = "coq_lsp" })[1]
  local request = client.request
  local document_requests = 0
  client.request = function(self, method, ...)
    if method == "coq/getDocument" then document_requests = document_requests + 1 end
    return request(self, method, ...)
  end

  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  vim.cmd("RocqNext")
  vim.cmd("RocqNext")
  vim.cmd("RocqNext")
  wait_for(function() return cursor_is(3, 10) end, "Rapid Next commands lost steps")
  assert(document_requests == 1, "Rapid navigation sent duplicate document requests")
  wait_for(function() return panel_text():find("H : P", 1, true) end,
    "Navigation did not refresh goals")
  vim.cmd("2RocqNext")
  assert(cursor_is(5, 3), "Counted forward navigation missed Qed")
  vim.cmd("2RocqPrev")
  assert(cursor_is(3, 10), "Counted backward navigation missed intros")
  assert(document_requests == 1, "Unchanged document ranges were not cached")
  vim.cmd("RocqNext")
  assert(cursor_is(4, 9), "Next did not land on the next sentence terminator")
  wait_for(function() return panel_text():find("No goals", 1, true) end,
    "Expected completed goal after navigating to exact")
  vim.cmd("100RocqNext")
  assert(cursor_is(5, 3), "Large count did not stop at final sentence")
  vim.cmd("RocqNext")
  assert(cursor_is(5, 3), "Next moved past end of proof")
  vim.cmd("100RocqPrev")
  assert(cursor_is(1, 34), "Large backward count did not stop at first sentence")
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  vim.cmd("RocqPrev")
  assert(cursor_is(1, 0), "Prev moved before beginning of proof")

  -- Edits invalidate cached server ranges.
  vim.api.nvim_buf_set_lines(source, 0, 0, false, { "(* inserted comment. *)" })
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  vim.cmd("RocqNext")
  wait_for(function() return cursor_is(2, 34) end, "Navigation reused obsolete ranges after edit")
  assert(document_requests == 2, "Edited document did not fetch new ranges")
  require("rocq.navigation").clear(source)
  vim.cmd("RocqNext")
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  vim.wait(250, function() return false end, 20)
  assert(cursor_is(1, 0), "Stale navigation reply moved the cursor")

  client.request = request
  vim.cmd.edit("examples/Navigation.v")
  vim.bo.filetype = "coq"
  rocq.start()
  local complex = vim.api.nvim_get_current_buf()
  wait_for(function()
    local c = vim.lsp.get_clients({ bufnr = complex, name = "coq_lsp" })[1]
    return c and c.initialized
  end, "Navigation fixture did not attach")
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  vim.cmd("RocqNext")
  wait_for(function() return cursor_is(2, 13) end,
    "Comment or qualified-name dot was treated as a sentence boundary")
  vim.cmd("5RocqNext")
  assert(cursor_is(7, 2), "Bullet was not treated as its own sentence")
  vim.cmd("RocqNext")
  assert(cursor_is(7, 11), "Tactic on same line as bullet was skipped")
  vim.cmd("RocqNext")
  local text = vim.api.nvim_buf_get_lines(complex, 7, 8, false)[1]
  assert(cursor_is(8, assert(text:find("-", 1, true)) - 1),
    "Unicode comment caused incorrect bullet column")
  vim.cmd("RocqNext")
  assert(cursor_is(8, #text - 1), "Unicode line caused incorrect tactic endpoint")
  vim.cmd("RocqPrev")
  assert(cursor_is(8, assert(text:find("-", 1, true)) - 1),
    "Prev skipped bullet on the same line")
  assert(vim.api.nvim_get_current_win() == win, "Navigation stole source focus")
  print("PASS: real-server sentence navigation, counts, queued steps, caching, edits, bullets, Unicode, and stale replies")
end, debug.traceback)

for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
