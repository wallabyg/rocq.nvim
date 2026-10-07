local M = {}
local panels = {}

local function visible(panel)
  return panel and panel.win and vim.api.nvim_win_is_valid(panel.win)
    and panel.buf and vim.api.nvim_win_get_buf(panel.win) == panel.buf
end

function M.source()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype == "coq" then return buf end
  return vim.b[buf].rocq_source
end

local function source_window(source, panel)
  if panel.source_win and vim.api.nvim_win_is_valid(panel.source_win)
    and vim.api.nvim_win_get_buf(panel.source_win) == source
    and vim.api.nvim_win_get_tabpage(panel.source_win) == vim.api.nvim_get_current_tabpage() then
    return panel.source_win
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == source then return win end
  end
end

function M.show(source, lines, width, reopen)
  local panel = panels[source]
  if not panel then
    panel = { hidden = false }
    panels[source] = panel
  end
  if panel.win and not visible(panel) then panel.hidden, panel.win = true, nil end
  if reopen then panel.hidden = false end
  panel.lines = lines or panel.lines or { "Loading goals…" }
  panel.width = width
  if panel.hidden then return end
  if vim.api.nvim_get_current_buf() == source then
    panel.source_win = vim.api.nvim_get_current_win()
  end
  if not panel.buf or not vim.api.nvim_buf_is_valid(panel.buf) then
    panel.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[panel.buf].bufhidden = "hide"
    vim.bo[panel.buf].swapfile = false
    vim.bo[panel.buf].filetype = "rocqinfo"
    vim.b[panel.buf].rocq_source = source
    vim.api.nvim_buf_set_name(panel.buf, "rocq://goals/" .. source)
    require("rocq.mappings").attach(panel.buf, true)
  end
  if not visible(panel) then
    panel.win = vim.api.nvim_open_win(panel.buf, false, {
      split = "right", win = source_window(source, panel) or 0, width = width,
    })
    vim.wo[panel.win].number = false
    vim.wo[panel.win].relativenumber = false
    vim.wo[panel.win].signcolumn = "no"
    vim.wo[panel.win].wrap = true
  end
  local output = vim.deepcopy(panel.lines)
  local status = require("rocq.progress").status(source)
  if status then
    table.insert(output, 1, "")
    table.insert(output, 1, status)
  end
  vim.list_extend(output, require("rocq.pins").lines(source))
  vim.bo[panel.buf].modifiable = true
  vim.api.nvim_buf_set_lines(panel.buf, 0, -1, false, output)
  vim.bo[panel.buf].modifiable = false
end

function M.hide(source)
  local panel = panels[source]
  if not panel then
    panels[source] = { hidden = true }
    return
  end
  panel.hidden = true
  if visible(panel) then
    if vim.api.nvim_get_current_win() == panel.win then
      local win = source_window(source, panel)
      if not win then win = vim.api.nvim_open_win(source, true, { split = "left", win = panel.win }) end
      vim.api.nvim_set_current_win(win)
    end
    vim.api.nvim_win_close(panel.win, true)
  end
  panel.win = nil
end

function M.hidden(source)
  local panel = panels[source]
  if panel and not visible(panel) then panel.hidden, panel.win = true, nil end
end

function M.toggle(source, width)
  if visible(panels[source]) then
    M.hide(source)
    return false
  end
  M.show(source, nil, width, true)
  return true
end

function M.focus(source, width)
  local panel = panels[source]
  if panel and visible(panel) and vim.api.nvim_get_current_win() == panel.win then
    local win = source_window(source, panel)
    if not win then win = vim.api.nvim_open_win(source, true, { split = "left", win = panel.win }) end
    vim.api.nvim_set_current_win(win)
    return false
  end
  M.show(source, nil, width, true)
  return panels[source].win
end

function M.refresh(source)
  local panel = panels[source]
  if panel and panel.buf and vim.api.nvim_buf_is_valid(panel.buf) and panel.win
    and vim.api.nvim_win_is_valid(panel.win)
    and vim.api.nvim_win_get_buf(panel.win) == panel.buf then
    M.show(source, nil, panel.width)
  end
end

-- Lifecycle messages update existing panels without opening new splits.
function M.status(source, message)
  local panel = panels[source]
  if not panel then return end
  panel.lines = { message }
  M.refresh(source)
end

function M.close(source)
  local panel = panels[source]
  if panel and panel.buf and vim.api.nvim_buf_is_valid(panel.buf) then
    vim.api.nvim_buf_delete(panel.buf, { force = true })
  end
  panels[source] = nil
end

return M
