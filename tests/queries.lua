-- Run from rocq.nvim: nvim --headless -u NONE -i NONE -l tests/queries.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function query_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].filetype == "rocqquery" then return buf end
  end
end

local function query_text()
  local buf = query_buf()
  return buf and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") or ""
end

local function query_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "rocqquery" then return win end
  end
end

local function wait_for(predicate, message)
  assert(vim.wait(15000, predicate, 20), message .. "\nQuery: " .. query_text())
end

local ok, err = xpcall(function()
  vim.cmd.edit("examples/Basic.v")
  vim.bo.filetype = "coq"
  local source = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local rocq = require("rocq")
  rocq.setup({ cmd = { vim.env.COQ_LSP_BIN or "coq-lsp" }, auto_update = false })
  wait_for(function()
    local client = vim.lsp.get_clients({ bufnr = source, name = "coq_lsp" })[1]
    return client and client.initialized
  end, "LSP initialization failed")
  local original = vim.api.nvim_buf_get_lines(source, 0, -1, false)
  local tick = vim.api.nvim_buf_get_changedtick(source)
  vim.api.nvim_win_set_cursor(win, { 3, 9 })
  vim.cmd("RocqCheck")
  wait_for(function() return query_text():match("H\n%s*: P") end,
    "Check did not use identifier under cursor and local proof context")
  assert(query_text():find("At Basic.v:3:10", 1, true), "Query position was not labeled")
  assert(vim.api.nvim_get_current_win() == win, "Query stole source focus")
  assert(not vim.bo[query_buf()].modifiable, "Query result buffer is editable")

  vim.cmd("RocqPrint Nat.add.")
  wait_for(function() return query_text():find("Nat.add =", 1, true) end,
    "Print did not show definition or mishandled trailing period")
  vim.api.nvim_win_set_cursor(win, { 5, 3 })
  vim.cmd('RocqSearch "identity"')
  wait_for(function() return query_text():match("identity%s*:") end,
    "Search did not return lemma at selected position")
  assert(vim.deep_equal(original, vim.api.nvim_buf_get_lines(source, 0, -1, false))
    and tick == vim.api.nvim_buf_get_changedtick(source), "Queries modified proof text")

  vim.api.nvim_win_set_cursor(win, { 2, 5 })
  vim.cmd("RocqCheck H")
  wait_for(function() return query_text():find("Rocq:", 1, true) end,
    "Check incorrectly saw a hypothesis introduced at a later position")
  vim.api.nvim_win_set_cursor(win, { 3, 10 })
  rocq.goals()
  wait_for(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].filetype == "rocqinfo" then
        return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("H : P", 1, true)
      end
    end
  end, "Queries changed the proof state")

  vim.cmd("RocqCheck missing_name")
  wait_for(function() return query_text():find("Rocq:", 1, true) end, "Query error was not displayed")
  vim.cmd("RocqCheck H")
  wait_for(function() return query_text():match("H\n%s*: P") end, "Query did not recover after error")
  vim.cmd("RocqCheck H")
  vim.cmd("RocqCheck nat")
  wait_for(function() return query_text():match("nat\n%s*: Set") end,
    "An older query overwrote the newest result")

  vim.cmd("RocqCheck H")
  vim.api.nvim_buf_set_text(source, 0, 0, 0, 0, { "(* edit *) " })
  wait_for(function() return query_text():find("Proof changed", 1, true) end,
    "Stale query reply was presented as current")
  vim.cmd("RocqCheck H")
  vim.cmd("RocqQueryClose")
  vim.wait(250, function() return false end, 20)
  assert(not query_win(), "Late query reply reopened manually closed result panel")
  vim.cmd("RocqCheck H")
  wait_for(function() return query_win() and query_text():match("H\n%s*: P") end,
    "New query did not reopen result panel")
  vim.api.nvim_set_current_win(query_win())
  vim.api.nvim_feedkeys("q", "xt", false)
  assert(not query_win(), "q mapping did not close query panel")
  assert(vim.api.nvim_get_current_win() == win, "Closing query panel lost source focus")

  -- Qualified names and Unicode identifiers are kept intact by the default
  -- Check argument scanner, independently of filetype-specific iskeyword.
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "Check Nat.add.", "exact α'." })
  local queries = require("rocq.queries")
  assert(queries.identifier(scratch, { 1, 10 }) == "Nat.add", "Qualified identifier was split")
  assert(queries.identifier(scratch, { 2, 6 }) == "α'", "Unicode identifier was split")
  vim.api.nvim_buf_delete(scratch, { force = true })
  vim.cmd("RocqCheck H")
  vim.api.nvim_buf_delete(source, { force = true })
  vim.wait(150, function() return false end, 20)
  assert(not query_buf(), "Wiping proof buffer left query results behind")
  print("PASS: real-server Check/Print/Search, cursor context, unchanged proofs, errors, stale replies, and panel cleanup")
end, debug.traceback)

for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
