local M = {}
local namespace = vim.api.nvim_create_namespace("rocq.progress")
local states = {}
local tracked = {}
local attached = setmetatable({}, { __mode = "k" })

local function refresh_panel(buf)
  vim.schedule(function() require("rocq.infoview").refresh(buf) end)
end

function M.clear(buf, client_id)
  local state = states[buf]
  if client_id and state and state.client_id ~= client_id then return end
  states[buf] = nil
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  end
  refresh_panel(buf)
end

function M.track(buf)
  if tracked[buf] then return end
  tracked[buf] = vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if states[buf] then M.clear(buf) end
    end,
    on_detach = function()
      tracked[buf] = nil
      M.clear(buf)
    end,
  })
end

function M.status(buf)
  local state = states[buf]
  if not state then return end
  if state.busy then return "Checking…" end
  if state.failed then return "Checking failed" end
end

local function mark_range(buf, client, range, failed)
  local start, finish = range.start, range["end"]
  if start.line == finish.line and start.character == finish.character then return end
  local count = vim.api.nvim_buf_line_count(buf)
  if start.line < 0 or start.line >= count or finish.line < start.line or finish.line > count then
    return
  end
  local function column(pos)
    if pos.line == count then return 0 end
    local text = vim.api.nvim_buf_get_lines(buf, pos.line, pos.line + 1, false)[1]
    return vim.str_byteindex(text, client.offset_encoding, pos.character, false)
  end
  vim.api.nvim_buf_set_extmark(buf, namespace, start.line, column(start), {
    end_row = finish.line, end_col = column(finish),
    hl_group = failed and "RocqProcessingError" or "RocqProcessing",
    sign_text = failed and "!" or "▸",
    sign_hl_group = failed and "RocqProcessingError" or "RocqProcessingSign",
    priority = 90,
  })
  return true
end

function M.handle(err, params, ctx)
  if err or not params or not params.textDocument then return end
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  if not client or client:is_stopped() then return end
  local buf = vim.uri_to_bufnr(params.textDocument.uri)
  if not vim.api.nvim_buf_is_loaded(buf) or not client.attached_buffers[buf] then return end
  -- Progress belongs to the document version checked by the server, not to
  -- positions that extmarks happened to follow after an edit.
  if params.textDocument.version ~= vim.lsp.util.buf_versions[buf] then return end
  M.clear(buf)
  local state = { client_id = client.id, busy = false, failed = false }
  for _, item in ipairs(params.processing or {}) do
    local failed = item.kind == 2
    -- Some server versions report completion as an empty EOF range instead
    -- of an empty list. Malformed or obsolete ranges also cannot be marked.
    if item.range then
      local ok, marked = pcall(mark_range, buf, client, item.range, failed)
      if ok and marked then
        state.busy = state.busy or not failed
        state.failed = state.failed or failed
      end
    end
  end
  states[buf] = state
  refresh_panel(buf)
end

function M.attach(client)
  if not client or attached[client] then return end
  attached[client] = true
  local method = "$/coq/fileProgress"
  local previous = client.handlers[method] or vim.lsp.handlers[method]
  client.handlers[method] = function(err, params, ctx, config)
    M.handle(err, params, ctx)
    if previous then previous(err, params, ctx, config) end
  end
end

function M.highlights()
  vim.api.nvim_set_hl(0, "RocqProcessing", { default = true, link = "DiffChange" })
  vim.api.nvim_set_hl(0, "RocqProcessingSign", { default = true, link = "DiagnosticInfo" })
  vim.api.nvim_set_hl(0, "RocqProcessingError", { default = true, link = "DiagnosticError" })
end

return M
