-- Run from rocq.nvim: nvim --headless -u NONE -i NONE -l tests/panels.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.maplocalleader = ","

local function panel_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "rocqinfo" then return win end
  end
end

local function panel_text()
  local win = panel_win()
  if not win then return "" end
  return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n")
end

local function wait_for(predicate, message)
  assert(vim.wait(15000, predicate, 20), message .. "\nPanel: " .. panel_text())
end

local ok, err = xpcall(function()
  vim.cmd.edit("examples/Basic.v")
  vim.bo.filetype = "coq"
  local source = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local user_map = function() end
  vim.keymap.set("n", ",p", user_map, { buffer = source })
  local rocq = require("rocq")
  local cmd = { vim.env.COQ_LSP_BIN or "coq-lsp" }
  rocq.setup({ cmd = cmd, update_delay = 50 })
  wait_for(function() return panel_win() and panel_text():find("No proof state", 1, true) end,
    "Initial panel did not open")
  assert(vim.fn.maparg(",p", "n", false, true).callback == user_map, "User mapping was overwritten")
  assert(vim.fn.maparg(",j", "n", false, true).buffer == 1, "Next mapping is not buffer-local")
  assert(vim.fn.maparg(",j", "n", false, true).rhs == "<Plug>(RocqNext)", "Default next key bypasses Plug target")
  local keys = vim.api.nvim_replace_termcodes("3,j", true, false, true)
  vim.api.nvim_feedkeys(keys, "xt", false)
  wait_for(function() return vim.deep_equal(vim.api.nvim_win_get_cursor(source_win), { 3, 10 }) end,
    "Count was not respected by Next mapping")
  wait_for(function() return panel_text():find("H : P", 1, true) end, "Mapped navigation did not refresh goals")

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Plug>(RocqFocus)", true, false, true), "xt", false)
  assert(vim.api.nvim_get_current_win() == panel_win(), "Focus did not enter panel")
  assert(vim.fn.maparg(",f", "n", false, true).buffer == 1, "Panel lacks focus mapping")
  assert(vim.tbl_isempty(vim.fn.maparg(",j", "n", false, true)), "Panel acquired proof navigation mapping")
  vim.cmd("RocqFocus")
  assert(vim.api.nvim_get_current_win() == source_win, "Focus did not return to proof")
  vim.cmd("RocqToggle")
  assert(not panel_win(), "Toggle did not hide panel")
  vim.api.nvim_win_set_cursor(source_win, { 4, 2 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = source })
  vim.wait(250, function() return false end, 20)
  assert(not panel_win(), "Automatic refresh reopened hidden panel")
  vim.cmd("RocqGoals")
  vim.wait(150, function() return false end, 20)
  assert(not panel_win(), "Explicit goal refresh reopened hidden panel")
  vim.cmd("RocqToggle")
  wait_for(function() return panel_text():find("No goals", 1, true) end, "Toggle did not reopen and refresh")
  assert(vim.api.nvim_get_current_win() == source_win, "Toggle stole source focus")

  -- A plain :close in the panel must also suppress automatic reopening.
  vim.cmd("RocqFocus")
  vim.cmd("close")
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = source })
  vim.wait(250, function() return false end, 20)
  assert(not panel_win(), "Manual :close was undone by automatic refresh")
  vim.cmd("RocqFocus")
  assert(vim.api.nvim_get_current_win() == panel_win(), "Focus did not reopen panel")
  wait_for(function() return panel_text():find("No goals", 1, true) end,
    "Goal reply was discarded while panel was focused")
  vim.cmd("RocqToggle")
  assert(vim.api.nvim_get_current_win() == source_win and not panel_win(), "Toggle from panel did not return to proof")

  -- Replacing the panel's buffer must leave the replacement untouched.
  vim.cmd("RocqFocus")
  vim.cmd("enew")
  local unrelated = vim.api.nvim_get_current_buf()
  local unrelated_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(source_win)
  vim.cmd("RocqGoals")
  vim.wait(150, function() return false end, 20)
  assert(not panel_win(), "Replacing panel buffer did not hide panel")
  assert(vim.api.nvim_win_get_buf(unrelated_win) == unrelated, "Refresh replaced unrelated window buffer")
  assert(vim.tbl_isempty(vim.api.nvim_buf_call(unrelated, function()
    return vim.fn.maparg(",j", "n", false, true)
  end)), "Proof mapping leaked into unrelated buffer")

  rocq.setup({ cmd = cmd, mappings = false })
  assert(vim.tbl_isempty(vim.fn.maparg(",j", "n", false, true)), "Disabling mappings left plugin mapping")
  assert(vim.fn.maparg(",p", "n", false, true).callback == user_map, "Disabling mappings removed user mapping")
  for _, action in ipairs({ "Next", "Prev", "Goals", "Pin", "ClearPins", "Toggle", "Focus", "Interrupt", "Restart" }) do
    local target = vim.fn.maparg("<Plug>(Rocq" .. action .. ")", "n", false, true)
    assert(target.buffer == 0 and type(target.callback) == "function", "Missing public Plug target: " .. action)
  end
  local restart_target = vim.fn.maparg("<Plug>(RocqRestart)", "n", false, true).callback
  local user_restart = function() end
  vim.keymap.set("n", "<Plug>(RocqRestart)", user_restart)
  rocq.setup({ cmd = cmd, mappings = false })
  assert(vim.fn.maparg("<Plug>(RocqRestart)", "n", false, true).callback == user_restart,
    "Setup overwrote an existing public target")
  vim.keymap.set("n", "<Plug>(RocqRestart)", restart_target)
  vim.keymap.set("n", "]p", "<Plug>(RocqNext)", { buffer = source })
  vim.keymap.set("n", "[p", "<Plug>(RocqPrev)", { buffer = source })
  vim.api.nvim_win_set_cursor(source_win, { 1, 0 })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("3]p", true, false, true), "xt", false)
  wait_for(function() return vim.deep_equal(vim.api.nvim_win_get_cursor(source_win), { 3, 10 }) end,
    "Custom Plug mapping with disabled defaults lost Next count")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("2[p", true, false, true), "xt", false)
  wait_for(function() return vim.api.nvim_win_get_cursor(source_win)[1] == 1 end,
    "Custom Plug mapping lost Prev count")
  vim.keymap.set("n", ",j", "<Plug>(RocqNext)", { buffer = source, desc = "User next" })
  rocq.setup({ cmd = cmd, mappings = { next = ",n" } })
  assert(vim.fn.maparg(",n", "n", false, true).buffer == 1, "Custom next mapping was not installed")
  assert(vim.fn.maparg(",j", "n", false, true).desc == "User next", "Setup removed custom user Plug mapping")
  vim.keymap.del("n", ",j", { buffer = source })
  -- Replacing one of the plugin's default RHS mappings must survive setup.
  vim.keymap.set("n", ",n", "<Plug>(RocqNext)", { buffer = source, desc = "User replacement" })
  rocq.setup({ cmd = cmd, mappings = false })
  assert(vim.fn.maparg(",n", "n", false, true).desc == "User replacement", "Setup removed a user replacement")
  vim.keymap.del("n", ",n", { buffer = source })
  rocq.setup({ cmd = cmd, mappings = { next = ",n" } })

  vim.cmd("RocqFocus")
  -- Remove all windows except the panel. Focus must recreate the source split.
  local info_win = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= info_win then vim.api.nvim_win_close(win, true) end
  end
  vim.cmd("RocqFocus")
  assert(vim.api.nvim_get_current_buf() == source, "Focus did not recover missing source window")
  vim.cmd("RocqFocus")
  vim.cmd("RocqToggle")
  assert(vim.api.nvim_get_current_buf() == source and not panel_win(), "Panel toggle lost recovered source")
  print("PASS: real-server panel controls, hidden updates, public Plug targets, disabled defaults, counts, user mapping preservation, and source recovery")
end, debug.traceback)

for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
