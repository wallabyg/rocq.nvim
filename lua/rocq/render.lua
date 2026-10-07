local M = {}

local function append(lines, text)
  if text == nil or text == vim.NIL then return end
  vim.list_extend(lines, vim.split(tostring(text), "\n", { plain = true }))
end

local function group(lines, title, goals)
  if not goals or goals == vim.NIL or #goals == 0 then return end
  append(lines, title .. " (" .. #goals .. ")")
  for i, goal in ipairs(goals) do
    append(lines, "")
    append(lines, "Goal " .. i)
    for _, hyp in ipairs(goal.hyps or {}) do
      local names = table.concat(hyp.names or {}, ", ")
      local body = hyp.def and hyp.def ~= vim.NIL and (" := " .. hyp.def) or ""
      append(lines, names .. body .. " : " .. hyp.ty)
    end
    append(lines, "────────────────────")
    append(lines, goal.ty)
  end
  append(lines, "")
end

function M.goals(result)
  local lines = {}
  local config = result.goals
  if config and config ~= vim.NIL then
    group(lines, "Goals", config.goals)
    for i, frame in ipairs(config.stack or {}) do
      group(lines, "Background " .. i .. " (before)", frame[1])
      group(lines, "Background " .. i .. " (after)", frame[2])
    end
    group(lines, "Shelved", config.shelf)
    group(lines, "Given up", config.given_up)
    if #lines == 0 then append(lines, "No goals at this position.") end
  else
    append(lines, "No proof state at this position.")
  end
  for _, message in ipairs(result.messages or {}) do
    append(lines, type(message) == "table" and message.text or message)
  end
  append(lines, result.error)
  return lines
end

return M
