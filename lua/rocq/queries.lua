local M = {}
local panels = {}
local pending = {}
local methods = setmetatable({}, { __mode = "k" })

local function visible(panel)
  return panel and panel.win and vim.api.nvim_win_is_valid(panel.win)
    and panel.buf and vim.api.nvim_win_get_buf(panel.win) == panel.buf
end

local function show(source, lines, win, height, reopen)
  local panel = panels[source] or {}
  panels[source] = panel
  panel.lines = lines
  if not reopen and not visible(panel) then return end
  if not panel.buf or not vim.api.nvim_buf_is_valid(panel.buf) then
    panel.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[panel.buf].filetype = "rocqquery"
    vim.bo[panel.buf].bufhidden = "hide"
    vim.bo[panel.buf].swapfile = false
    vim.b[panel.buf].rocq_query_source = source
    vim.api.nvim_buf_set_name(panel.buf, "rocq://queries/" .. source)
    vim.keymap.set("n", "q", function() M.hide(source) end, { buffer = panel.buf, desc = "Close Rocq query results" })
  end
  if not visible(panel) then
    panel.win = vim.api.nvim_open_win(panel.buf, false, { split = "below", win = win, height = height })
    vim.wo[panel.win].number = false
    vim.wo[panel.win].relativenumber = false
    vim.wo[panel.win].signcolumn = "no"
    vim.wo[panel.win].wrap = true
  end
  vim.bo[panel.buf].modifiable = true
  vim.api.nvim_buf_set_lines(panel.buf, 0, -1, false, lines)
  vim.bo[panel.buf].modifiable = false
end

function M.hide(source)
  source = source or vim.b.rocq_query_source or vim.api.nvim_get_current_buf()
  local panel = panels[source]
  if not visible(panel) then return end
  if #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(panel.win)) == 1
    and vim.api.nvim_buf_is_valid(source) then
    vim.api.nvim_open_win(source, true, { split = "above", win = panel.win })
  end
  vim.api.nvim_win_close(panel.win, true)
  panel.win = nil
end

function M.clear(source)
  pending[source] = nil
  local panel = panels[source]
  if panel and panel.buf and vim.api.nvim_buf_is_valid(panel.buf) then
    vim.api.nvim_buf_delete(panel.buf, { force = true })
  end
  panels[source] = nil
end

function M.cancel(source, message)
  local token = pending[source]
  pending[source] = nil
  if token then
    show(source, vim.list_extend(vim.deepcopy(token.header), { message }), token.win, token.height)
  end
end

function M.identifier(buf, cursor)
  local text = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1]
  local function part(index)
    local byte = text:byte(index)
    return byte and (byte >= 128 or text:sub(index, index):match("[%w_'%.]"))
  end
  local first, last = cursor[2] + 1, cursor[2] + 1
  if not part(first) then return "" end
  while part(first - 1) do first = first - 1 end
  while part(last + 1) do last = last + 1 end
  return text:sub(first, last):gsub("^%.+", ""):gsub("%.+$", "")
end

local function append(lines, text)
  if text and text ~= vim.NIL then
    vim.list_extend(lines, vim.split(tostring(text), "\n", { plain = true }))
  end
end

function M.run(buf, win, client, kind, argument, height)
  argument = vim.trim(argument or "")
  local cursor = vim.api.nvim_win_get_cursor(win)
  if kind == "Check" and argument == "" then argument = M.identifier(buf, cursor) end
  if argument == "" then
    vim.notify("Rocq: provide a term or place the cursor on an identifier", vim.log.levels.WARN)
    return
  end
  local command = kind .. " " .. argument
  if command:sub(-1) ~= "." then command = command .. "." end
  local header = { command, "At " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
    .. ":" .. cursor[1] .. ":" .. (cursor[2] + 1), "" }
  local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
  params.textDocument.version = vim.lsp.util.buf_versions[buf]
  params.command = command
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local token = { header = header, win = win, height = height }
  pending[buf] = token
  show(buf, vim.list_extend(vim.deepcopy(header), { "Running query…" }), win, height, true)
  local function request(method, fallback)
    local accepted = client:request(method, params, function(err, result)
      if pending[buf] ~= token or not vim.api.nvim_buf_is_valid(buf) then return end
      if vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        pending[buf] = nil
        show(buf, vim.list_extend(vim.deepcopy(header), { "Proof changed; run the query again." }), win, height)
        return
      end
      if client:is_stopped() or not client.attached_buffers[buf] then return end
      if err and err.code == -32601 and fallback then
        request(fallback)
        return
      end
      pending[buf] = nil
      local lines = vim.deepcopy(header)
      if err then
        append(lines, "Rocq: " .. err.message)
        local data = type(err.data) == "table" and err.data or {}
        for _, message in ipairs(data.feedback or data) do
          append(lines, type(message) == "table" and (message.text or message[2]) or message)
        end
      else
        methods[client] = method
        for _, message in ipairs((result or {}).feedback or {}) do
          append(lines, type(message) == "table" and (message.text or message[2]) or message)
        end
        if #lines == #header then append(lines, "No results.") end
      end
      show(buf, lines, win, height)
    end, buf)
    if not accepted then
      pending[buf] = nil
      show(buf, vim.list_extend(vim.deepcopy(header), { "Rocq: server is unavailable." }), win, height)
    end
  end
  local method = methods[client] or "petanque/run_at_pos"
  request(method, method == "petanque/run_at_pos" and "petanque/run_at_point" or "petanque/run_at_pos")
end

return M
