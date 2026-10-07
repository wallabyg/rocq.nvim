local M = {}
local namespace = vim.api.nvim_create_namespace("rocq.pins")
local buffers = {}
local next_id = 0

local function position(buf, pin)
  local mark = vim.api.nvim_buf_get_extmark_by_id(buf, namespace, pin.mark, { details = true })
  if #mark == 0 or mark[3].invalid then return end
  return mark[1], mark[2]
end

function M.add(buf, cursor)
  local pins = buffers[buf] or {}
  buffers[buf] = pins
  for _, pin in ipairs(pins) do
    local row, col = position(buf, pin)
    if row == cursor[1] - 1 and col == cursor[2] then return end
  end
  next_id = next_id + 1
  local pin = { id = next_id, active = true, lines = { "Loading pinned goals…" } }
  pin.mark = vim.api.nvim_buf_set_extmark(buf, namespace, cursor[1] - 1, cursor[2], {
    right_gravity = false, invalidate = true,
    virt_text = { { "Pin " .. pin.id, "Special" } }, virt_text_pos = "eol",
  })
  table.insert(pins, pin)
end

function M.clear(buf)
  for _, pin in ipairs(buffers[buf] or {}) do pin.active = false end
  buffers[buf] = nil
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  end
end

function M.reset(buf, message)
  for _, pin in ipairs(buffers[buf] or {}) do
    pin.token, pin.tick, pin.client = nil, nil, nil
    pin.lines = { message }
  end
end

function M.lines(buf)
  local lines = {}
  for _, pin in ipairs(buffers[buf] or {}) do
    local row, col = position(buf, pin)
    local label = row and (" — " .. (row + 1) .. ":" .. (col + 1)) or " — position deleted"
    vim.list_extend(lines, { "", "════════════════════", "Pin " .. pin.id .. label })
    vim.list_extend(lines, row and pin.lines or { "Pinned text was deleted; clear pins or undo the edit." })
  end
  return lines
end

function M.refresh(buf, client, changed)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  for _, pin in ipairs(buffers[buf] or {}) do
    local row, col = position(buf, pin)
    if row and (pin.tick ~= tick or pin.client ~= client or pin.row ~= row or pin.col ~= col) then
      pin.tick, pin.client, pin.row, pin.col = tick, client, row, col
      local token = {}
      pin.token = token
      pin.lines = { "Loading pinned goals…" }
      local text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
      client:request("proof/goals", {
        textDocument = { uri = vim.uri_from_bufnr(buf), version = vim.lsp.util.buf_versions[buf] },
        position = { line = row, character = vim.str_utfindex(text, client.offset_encoding, col, false) },
        pp_format = "Str", mode = "After",
      }, function(err, result)
        if not pin.active or pin.token ~= token or not vim.api.nvim_buf_is_valid(buf) then return end
        local current_row, current_col = position(buf, pin)
        if vim.api.nvim_buf_get_changedtick(buf) ~= tick
          or current_row ~= row or current_col ~= col or client:is_stopped() then
          pin.tick = nil
          return
        end
        pin.lines = err and { "Rocq: " .. err.message }
          or require("rocq.render").goals(result or {})
        changed()
      end, buf)
    end
  end
end

return M
