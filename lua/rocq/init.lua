local M = {}
local options
local generations = {}
local scheduled = {}
local paused = {}
local restarting = {}

local function schedule_update()
  if not options.auto_update then return end
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "coq" then return end
  if paused[buf] or restarting[buf] then return end
  local win = vim.api.nvim_get_current_win()
  local token = {}
  scheduled[buf] = token
  -- Invalidate a reply immediately, including during the debounce interval.
  generations[buf] = (generations[buf] or 0) + 1
  vim.defer_fn(function()
    if scheduled[buf] ~= token then return end
    scheduled[buf] = nil
    if not vim.api.nvim_buf_is_valid(buf)
      or not vim.api.nvim_win_is_valid(win)
      or vim.api.nvim_get_current_win() ~= win
      or vim.api.nvim_win_get_buf(win) ~= buf then return end
    M.goals(true)
  end, options.update_delay)
end

local function client_for(buf)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if client.name == "coq_lsp" or client.name == "rocq_lsp" then return client end
  end
end

function M.start(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "coq" then return end
  -- Lazy loading may add our runtime after the first Syntax event already ran.
  if vim.g.syntax_on and vim.bo[buf].syntax == "coq" and not vim.b[buf].current_syntax then
    vim.api.nvim_buf_call(buf, function() vim.cmd("runtime! syntax/coq.vim") end)
  end
  if restarting[buf] then return end
  local progress = require("rocq.progress")
  require("rocq.mappings").attach(buf)
  progress.track(buf)
  local existing = client_for(buf)
  if existing then
    progress.attach(existing)
    return existing.id
  end
  if vim.fn.executable(options.cmd[1]) ~= 1 then
    vim.notify("Rocq: executable not found: " .. options.cmd[1], vim.log.levels.ERROR)
    return
  end
  local filename = vim.api.nvim_buf_get_name(buf)
  if filename == "" then
    vim.notify("Rocq: save the proof to a .v file first", vim.log.levels.WARN)
    return
  end
  local id = vim.lsp.start({
    name = "coq_lsp",
    cmd = options.cmd,
    root_dir = vim.fs.root(buf, { "_RocqProject", "_CoqProject", "dune-project", ".git" })
      or vim.fs.dirname(filename),
    init_options = { pp_type = 0, goal_after_tactic = true },
  }, { bufnr = buf })
  if id then progress.attach(vim.lsp.get_client_by_id(id)) end
  return id
end

function M.goals(automatic)
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  if vim.bo[buf].filetype ~= "coq" then return end
  if restarting[buf] or (automatic and paused[buf]) then return end
  if not automatic then paused[buf] = nil end
  scheduled[buf] = nil
  if not automatic then M.start(buf) end
  local client = client_for(buf)
  if not client or not client.initialized then
    if not automatic then
      vim.notify("Rocq: server is starting; run :RocqGoals again shortly")
    end
    return
  end
  local generation = (generations[buf] or 0) + 1
  generations[buf] = generation
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
  params.textDocument.version = vim.lsp.util.buf_versions[buf]
  params.pp_format = "Str"
  params.mode = "After"
  local panel = require("rocq.infoview")
  require("rocq.pins").refresh(buf, client, function()
    if (panel.source() == buf or vim.b.rocq_query_source == buf) and client_for(buf) == client then
      panel.show(buf, nil, options.infoview.width)
    end
  end)
  panel.show(buf, { "Loading goals…" }, options.infoview.width)
  client:request("proof/goals", params, function(err, result)
    if not vim.api.nvim_buf_is_valid(buf) or generations[buf] ~= generation
      or (panel.source() ~= buf and vim.b.rocq_query_source ~= buf) then return end
    local stale = vim.api.nvim_buf_get_changedtick(buf) ~= tick
      or not vim.api.nvim_win_is_valid(win)
      or vim.api.nvim_win_get_buf(win) ~= buf
      or not vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor)
      or client_for(buf) ~= client
    if stale then
      if options.auto_update then
        schedule_update()
      else
        panel.show(buf, { "Position changed; run :RocqGoals to refresh." }, options.infoview.width)
      end
      return
    end
    local lines = err and { "Rocq: " .. err.message }
      or require("rocq.render").goals(result or {})
    panel.show(buf, lines, options.infoview.width)
  end, buf)
end

function M.pin()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "coq" then return end
  require("rocq.pins").add(buf, vim.api.nvim_win_get_cursor(0))
  M.goals()
end

function M.clear_pins()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "coq" then return end
  require("rocq.pins").clear(buf)
  M.goals()
end

function M.step(direction, count)
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "coq" then return end
  if restarting[buf] then return end
  paused[buf] = nil
  M.start(buf)
  local client = client_for(buf)
  if not client or not client.initialized then
    vim.notify("Rocq: server is starting; retry navigation shortly")
    return
  end
  require("rocq.navigation").step(buf, vim.api.nvim_get_current_win(), client,
    direction * (count or 1), function() M.goals() end)
end

function M.toggle()
  local panel = require("rocq.infoview")
  local source = panel.source()
  if not source or not vim.api.nvim_buf_is_valid(source) then return end
  if panel.toggle(source, options.infoview.width) then M.goals() end
end

function M.focus()
  local panel = require("rocq.infoview")
  local source = panel.source()
  if not source or not vim.api.nvim_buf_is_valid(source) then return end
  local win = panel.focus(source, options.infoview.width)
  if win then
    M.goals()
    vim.api.nvim_set_current_win(win)
  end
end

function M.query(kind, argument)
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "coq" then return end
  if restarting[buf] then return end
  paused[buf] = nil
  M.start(buf)
  local client = client_for(buf)
  if not client or not client.initialized then
    vim.notify("Rocq: server is starting; retry the query shortly")
    return
  end
  require("rocq.queries").run(buf, vim.api.nvim_get_current_win(), client,
    kind, argument, options.query.height)
end

local function source_buffer()
  return require("rocq.infoview").source() or vim.b.rocq_query_source
end

local request_methods = {
  ["proof/goals"] = true, ["coq/getDocument"] = true,
  ["petanque/run_at_pos"] = true, ["petanque/run_at_point"] = true,
}

local function invalidate(buf, message)
  generations[buf] = (generations[buf] or 0) + 1
  scheduled[buf] = nil
  require("rocq.navigation").clear(buf)
  require("rocq.pins").reset(buf, message)
  require("rocq.queries").cancel(buf, message)
  require("rocq.infoview").status(buf, message)
end

function M.interrupt()
  local buf = source_buffer()
  if not buf or restarting[buf] then return end
  paused[buf] = true
  invalidate(buf, "Interrupted; run :RocqGoals to resume.")
  local client = client_for(buf)
  if not client then return end
  local ids = {}
  for id, request in pairs(client.requests) do
    if request.bufnr == buf and request.type == "pending" and request_methods[request.method] then
      ids[#ids + 1] = id
    end
  end
  for _, id in ipairs(ids) do client:cancel_request(id) end
end

function M.restart(force)
  local source = source_buffer()
  if not source or restarting[source] then return end
  local old = client_for(source)
  local buffers = {}
  for buf in pairs(old and old.attached_buffers or { [source] = true }) do
    if vim.api.nvim_buf_is_loaded(buf) then buffers[#buffers + 1] = buf end
  end
  local config = old and vim.deepcopy(old.config)
  local token = {}
  for _, buf in ipairs(buffers) do
    restarting[buf], paused[buf] = token, nil
    invalidate(buf, "Restarting Rocq server…")
    require("rocq.progress").clear(buf)
  end
  local function finish(message)
    for _, buf in ipairs(buffers) do
      if restarting[buf] == token then
        restarting[buf] = nil
        if message and vim.api.nvim_buf_is_loaded(buf) then invalidate(buf, message) end
      end
    end
  end
  local function launch()
    local live = {}
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_loaded(buf) and restarting[buf] == token then live[#live + 1] = buf end
    end
    if #live == 0 then finish(); return end
    local id
    if config then
      id = vim.lsp.start(config, { bufnr = live[1], reuse_client = function() return false end })
    else
      restarting[live[1]] = nil
      id = M.start(live[1])
      restarting[live[1]] = token
    end
    if not id then finish("Rocq restart failed; run :RocqStart to retry."); return end
    for _, buf in ipairs(live) do vim.lsp.buf_attach_client(buf, id) end
    local attempts = 0
    local function ready()
      local client = vim.lsp.get_client_by_id(id)
      attempts = attempts + 1
      if not client or client:is_stopped() or attempts > 300 then
        finish("Rocq server did not initialize; run :RocqRestart to retry.")
      elseif not client.initialized then
        vim.defer_fn(ready, 50)
      else
        finish()
        require("rocq.progress").attach(client)
        for _, buf in ipairs(live) do
          require("rocq.pins").refresh(buf, client, function() require("rocq.infoview").refresh(buf) end)
          require("rocq.infoview").status(buf, "Server restarted; run :RocqGoals to refresh.")
        end
        -- Refresh the selected source without changing windows or reopening hidden panels.
        local current = source_buffer()
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if current and vim.api.nvim_win_get_buf(win) == current then
            vim.api.nvim_win_call(win, function() M.goals() end)
            break
          end
        end
      end
    end
    ready()
  end
  if not old then launch(); return end
  old:stop(force == true)
  local attempts = 0
  local function stopped()
    attempts = attempts + 1
    if not vim.lsp.get_client_by_id(old.id) then launch(); return end
    if attempts == 40 then old:stop(true) end
    if attempts > 100 then finish("Rocq server could not stop; retry :RocqRestart!"); return end
    vim.defer_fn(stopped, 50)
  end
  stopped()
end

function M.setup(opts)
  options = vim.tbl_deep_extend("force", {
    cmd = { "coq-lsp" }, infoview = { width = 45 },
    query = { height = 12 },
    auto_update = true, update_delay = 150,
    mappings = {
      next = "<localleader>j", prev = "<localleader>k", pin = "<localleader>p",
      clear_pins = "<localleader>P", toggle = "<localleader>i", focus = "<localleader>f",
    },
  }, opts or {})
  assert(type(options.update_delay) == "number" and options.update_delay >= 0,
    "Rocq: update_delay must be a nonnegative number")
  scheduled = {}
  for buf, generation in pairs(generations) do generations[buf] = generation + 1 end
  local group = vim.api.nvim_create_augroup("RocqNvim", { clear = true })
  require("rocq.mappings").setup(options.mappings)
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group, callback = function(args)
      local source = vim.b[args.buf].rocq_source
      if source then
        vim.schedule(function() require("rocq.infoview").hidden(source) end)
      end
    end,
  })
  require("rocq.progress").highlights()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group, callback = function() require("rocq.progress").highlights() end,
  })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group, callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and (client.name == "coq_lsp" or client.name == "rocq_lsp") then
        require("rocq.progress").track(args.buf)
        require("rocq.progress").attach(client)
      end
    end,
  })
  vim.api.nvim_create_autocmd("LspDetach", {
    group = group, callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and (client.name == "coq_lsp" or client.name == "rocq_lsp") then
        require("rocq.progress").clear(args.buf, client.id)
        require("rocq.navigation").clear(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("FileType", {
    group = group, pattern = "coq", callback = function(args)
      M.start(args.buf)
      schedule_update()
    end,
  })
  vim.api.nvim_create_autocmd({
    "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "TextChangedP",
    "BufEnter", "WinEnter", "LspAttach",
  }, {
    group = group, callback = schedule_update,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group, callback = function(args)
      generations[args.buf] = nil
      scheduled[args.buf] = nil
      paused[args.buf], restarting[args.buf] = nil, nil
      require("rocq.pins").clear(args.buf)
      require("rocq.progress").clear(args.buf)
      require("rocq.navigation").clear(args.buf)
      require("rocq.queries").clear(args.buf)
      require("rocq.infoview").close(args.buf)
      require("rocq.mappings").forget(args.buf)
    end,
  })
  vim.api.nvim_create_user_command("RocqStart", function() M.start() end, { force = true })
  vim.api.nvim_create_user_command("RocqInterrupt", M.interrupt, { force = true })
  vim.api.nvim_create_user_command("RocqRestart", function(args) M.restart(args.bang) end,
    { bang = true, force = true })
  vim.api.nvim_create_user_command("RocqGoals", function() M.goals() end, { force = true })
  vim.api.nvim_create_user_command("RocqPin", M.pin, { force = true })
  vim.api.nvim_create_user_command("RocqClearPins", M.clear_pins, { force = true })
  vim.api.nvim_create_user_command("RocqToggle", M.toggle, { force = true })
  vim.api.nvim_create_user_command("RocqFocus", M.focus, { force = true })
  for _, kind in ipairs({ "Check", "Print", "Search" }) do
    vim.api.nvim_create_user_command("Rocq" .. kind, function(args) M.query(kind, args.args) end,
      { nargs = kind == "Check" and "*" or "+", force = true })
  end
  vim.api.nvim_create_user_command("RocqQueryClose", function() require("rocq.queries").hide() end,
    { force = true })
  vim.api.nvim_create_user_command("RocqNext", function(args) M.step(1, args.count) end,
    { count = 1, force = true })
  vim.api.nvim_create_user_command("RocqPrev", function(args) M.step(-1, args.count) end,
    { count = 1, force = true })
  -- The FileType event that loaded this plugin has already happened.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M.start(buf) end
  end
  schedule_update()
end

return M
