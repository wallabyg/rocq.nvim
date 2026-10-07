-- No language server needed: nvim --headless -u NONE -i NONE -l tests/syntax.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local ok, err = xpcall(function()
  -- The standalone syntax must not depend on Coqtail configuration.
  vim.g.coqtail_nosyntax = 1
  vim.cmd("syntax enable")
  local lines = {
    "Lemma identity (α' : Prop) : α' -> α'.",
    "Proof.", "  intros H. (* TODO outer",
    "    (* nested *) exact H.", "  still comment *) exact H.", "Qed.",
    'Notation "(* not a comment *) ""quoted""" := 42 (at level 50).',
    "Check Nat.add.",
    "Definition exact (α' : nat) : nat := α'.",
    "Inductive choice : Type := Here : choice | There : choice.",
    "Record box : Type := { value : nat; flag : bool }.",
    "Ltac finish H := exact H.",
    "Lemma demo : True.", "Proof.", "  assert (H : True) by trivial.",
    "  pose proof H as Hcopy.", "  - finish H.", "Qed.",
    "Goal True.", "Proof.", "  admit.", "Admitted.",
    "Module ExampleModule.", "Definition x := 0.", "End ExampleModule.",
    "#[local] Hint Resolve identity : core.",
    "Next Obligation.", "  reflexivity.", "Qed.",
    "Ltac2 identity2 (x) := x.",
    "CustomExtension foo.", "", -- custom commands must not imply a proof error
  }
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = "coq"
  local function group(row, col)
    return vim.fn.synIDattr(vim.fn.synID(row, col, 1), "name")
  end
  local function at(row, term, expected)
    local col = assert(lines[row]:find(term, 1, true))
    assert(group(row, col) == expected,
      ("%s at %d:%d: expected %s, got %s"):format(term, row, col, expected, group(row, col)))
  end
  assert(vim.b.current_syntax == "coq", "Vendored syntax file was not automatically loaded")
  at(1, "Lemma", "coqVernacCmd")
  at(1, "identity", "coqIdent")
  at(1, "->", "coqKwd")
  at(2, "Proof", "coqProofDelim")
  at(3, "intros", "coqTactic")
  at(3, "TODO", "coqTodo")
  at(4, "nested", "coqComment")
  at(4, "exact", "coqComment")
  at(5, "still", "coqComment")
  at(5, "exact", "coqTactic")
  at(6, "Qed", "coqProofDelim")
  at(7, "not a comment", "coqNotationString")
  at(7, "quoted", "coqNotationString")
  at(7, "at level", "coqNotationKwd")
  at(8, "Check", "coqVernacCmd")
  at(9, "exact", "coqIdent") -- a declaration name, not a tactic
  at(9, "α'", "coqIdent")
  at(10, "Here", "coqConstructor")
  at(11, "flag", "coqField")
  at(12, "finish", "coqIdent")
  at(12, "exact", "coqTactic")
  at(16, "pose proof", "coqTactic")
  at(21, "admit", "coqTacticAdmit")
  at(22, "Admitted", "coqProofAdmit")
  at(23, "Module", "coqVernacCmd")
  at(25, "End", "coqVernacCmd")
  at(26, "local", "coqIdent")
  at(27, "Next", "coqProofDelim")
  at(28, "reflexivity", "coqTactic")
  at(30, "identity2", "coqIdent")
  assert(group(31, 1) ~= "coqError", "Unknown extension was highlighted as a syntax error")
  assert(vim.fn.synIDtrans(vim.fn.synID(22, 1, 1)) == vim.fn.hlID("Error"), "Admitted proof lost error highlight")
  -- Query the end of a larger file without first traversing its syntax states.
  -- Upstream's bounded synchronization should recover the nearby proof region.
  local source = vim.api.nvim_get_current_buf()
  local large = vim.api.nvim_create_buf(false, true)
  local large_lines = {}
  for i = 1, 300 do
    vim.list_extend(large_lines, { "Lemma demo" .. i .. " : True.", "Proof.",
      "  (* α. (* nested *) *)", "  exact I.", "Qed.", "" })
  end
  vim.api.nvim_set_current_buf(large)
  vim.api.nvim_buf_set_lines(large, 0, -1, false, large_lines)
  vim.bo.filetype = "coq"
  local row = #large_lines - 2
  assert(group(row, 3) == "coqTactic", "Syntax did not recover near the end of a larger file")
  vim.api.nvim_set_current_buf(source)
  vim.api.nvim_buf_delete(large, { force = true })
  -- User-defined highlight links survive reloading the syntax file.
  vim.api.nvim_set_hl(0, "coqTactic", { link = "Special" })
  vim.cmd("set syntax=coq")
  assert(vim.api.nvim_get_hl(0, { name = "coqTactic" }).link == "Special", "User highlight was overwritten")
  -- Existing syntax wins, including when explicitly sourcing our file again.
  vim.b.current_syntax = "user_coq"
  vim.cmd("runtime! syntax/coq.vim")
  assert(vim.b.current_syntax == "user_coq", "Existing syntax was overwritten")
  -- Simulate a coq buffer whose Syntax event preceded plugin loading.
  vim.cmd("syntax clear")
  vim.b.current_syntax = nil
  local notify = vim.notify
  vim.notify = function() end -- the deliberate missing executable is irrelevant here
  require("rocq").setup({ cmd = { "rocq-syntax-test-no-server" }, auto_update = false })
  vim.notify = notify
  assert(vim.b.current_syntax == "coq", "Setup did not load syntax for an existing buffer")
  at(3, "intros", "coqTactic")
  print("PASS: vendored syntax, contextual names/tactics, notation, constructors, fields, Ltac/Ltac2, obligations, modules, nested comments, attribution adaptations, and user highlights")
end, debug.traceback)
if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") else vim.cmd("qa!") end
