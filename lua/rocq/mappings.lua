local M = {}
local keys
local installed = {}

local actions = {
  next = function() require("rocq").step(1, vim.v.count1) end,
  prev = function() require("rocq").step(-1, vim.v.count1) end,
  pin = function() require("rocq").pin() end,
  clear_pins = function() require("rocq").clear_pins() end,
  toggle = function() require("rocq").toggle() end,
  focus = function() require("rocq").focus() end,
  goals = function() require("rocq").goals() end,
  interrupt = function() require("rocq").interrupt() end,
  restart = function() require("rocq").restart() end,
}

local targets = {
  next = "<Plug>(RocqNext)", prev = "<Plug>(RocqPrev)",
  pin = "<Plug>(RocqPin)", clear_pins = "<Plug>(RocqClearPins)",
  toggle = "<Plug>(RocqToggle)", focus = "<Plug>(RocqFocus)",
  goals = "<Plug>(RocqGoals)", interrupt = "<Plug>(RocqInterrupt)",
  restart = "<Plug>(RocqRestart)",
}

function M.attach(buf, panel)
  vim.api.nvim_buf_call(buf, function()
    for lhs, owned in pairs(installed[buf] or {}) do
      local map = vim.fn.maparg(lhs, "n", false, true)
      if map.buffer == 1 and map.rhs == owned.rhs and map.desc == owned.desc then
        vim.keymap.del("n", lhs, { buffer = buf })
      end
    end
    installed[buf] = {}
    if keys == false then return end
    for action, lhs in pairs(keys or {}) do
      if actions[action] and lhs and lhs ~= "" and (not panel or action == "toggle" or action == "focus")
        and vim.tbl_isempty(vim.fn.maparg(lhs, "n", false, true)) then
        local desc = "Rocq " .. action:gsub("_", " ")
        vim.keymap.set("n", lhs, targets[action], {
          buffer = buf, silent = true, remap = true, desc = desc,
        })
        installed[buf][lhs] = { rhs = targets[action], desc = desc }
      end
    end
  end)
end

function M.setup(opts)
  keys = opts
  -- Public targets are independent of default keys and available in all buffers.
  -- Read global mappings directly so buffer-local overrides cannot hide them.
  local existing = {}
  for _, map in ipairs(vim.api.nvim_get_keymap("n")) do existing[map.lhs] = true end
  for action, target in pairs(targets) do
    if not existing[target] then
      vim.keymap.set("n", target, actions[action], {
        silent = true, desc = "Rocq " .. action:gsub("_", " "),
      })
    end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      if vim.bo[buf].filetype == "coq" then M.attach(buf)
      elseif vim.bo[buf].filetype == "rocqinfo" then M.attach(buf, true) end
    end
  end
end

function M.forget(buf) installed[buf] = nil end

return M
