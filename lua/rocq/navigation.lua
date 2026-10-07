local M = {}
local cache = {}
local pending = {}

local function before(a, b)
  return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
end

local function endpoints(buf, client, document)
  local points, seen = {}, {}
  for _, span in ipairs(document.spans or {}) do
    local range = span.range
    -- Initial/final synthetic nodes can cover comments or duplicate a real
    -- sentence's range. Only parsed commands carry an AST.
    if span.ast and span.ast ~= vim.NIL and range and before({ range.start.line, range.start.character },
      { range["end"].line, range["end"].character }) then
      local row = range["end"].line
      local col = range["end"].character
      if col == 0 then row = row - 1 end
      if row >= 0 and row < vim.api.nvim_buf_line_count(buf) then
        local text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
        local byte = col == 0 and #text or vim.str_byteindex(text, client.offset_encoding, col, false)
        local index = vim.str_utfindex(text, "utf-32", byte, false)
        if index > 0 then
          -- LSP ranges end just after the sentence. Land on its last character
          -- so proof/goals selects that sentence instead of the following one.
          byte = vim.str_byteindex(text, "utf-32", index - 1, false)
          local key = row .. ":" .. byte
          if not seen[key] then
            seen[key] = true
            table.insert(points, { row + 1, byte })
          end
        end
      end
    end
  end
  table.sort(points, before)
  return points
end

local function move(win, cursor, points, delta, refresh)
  local targets = {}
  if delta > 0 then
    for _, point in ipairs(points) do
      if before(cursor, point) then table.insert(targets, point) end
    end
  elseif delta < 0 then
    for i = #points, 1, -1 do
      if before(points[i], cursor) then table.insert(targets, points[i]) end
    end
  else
    return
  end
  if #targets == 0 then
    vim.notify(delta > 0 and "Rocq: no later sentence" or "Rocq: no earlier sentence")
    return
  end
  vim.api.nvim_win_set_cursor(win, targets[math.min(math.abs(delta), #targets)])
  refresh()
end

function M.clear(buf)
  cache[buf], pending[buf] = nil, nil
end

function M.step(buf, win, client, delta, refresh)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local current = pending[buf]
  if current and current.client == client and current.win == win and current.tick == tick
    and vim.deep_equal(current.cursor, cursor) then
    current.delta = current.delta + delta
    return
  end
  pending[buf] = nil
  local cached = cache[buf]
  if cached and cached.client == client and cached.tick == tick then
    move(win, cursor, cached.points, delta, refresh)
    return
  end
  current = { client = client, win = win, cursor = cursor, tick = tick, delta = delta }
  pending[buf] = current
  local accepted = client:request("coq/getDocument", {
    textDocument = { uri = vim.uri_from_bufnr(buf), version = vim.lsp.util.buf_versions[buf] },
    ast = true,
  }, function(err, result)
    if pending[buf] ~= current then return end
    pending[buf] = nil
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win)
      or vim.api.nvim_get_current_win() ~= win or vim.api.nvim_win_get_buf(win) ~= buf
      or vim.api.nvim_buf_get_changedtick(buf) ~= tick
      or not vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor)
      or client:is_stopped() or not client.attached_buffers[buf] then return end
    if err then
      vim.notify("Rocq navigation: " .. err.message, vim.log.levels.ERROR)
      return
    end
    local points = endpoints(buf, client, result or {})
    -- A stopped/failed document may acquire more spans without a text edit.
    if result and result.completed and result.completed.status[1] == "Yes" then
      cache[buf] = { client = client, tick = tick, points = points }
    end
    move(win, cursor, points, current.delta, refresh)
  end, buf)
  if not accepted then pending[buf] = nil end
end

return M
