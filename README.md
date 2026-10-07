# rocq.nvim

A Lua Neovim plugin for interactive proving with [Rocq](https://rocq-prover.org/)
and [coq-lsp](https://github.com/rocq-community/rocq-lsp). Goals follow your
cursor, with goal pins, sentence navigation, proof queries, processing
indicators, and basic source syntax highlighting.

## Requirements

- Neovim 0.11 or later (tested with 0.12.3).
- Rocq and a compatible `coq-lsp` server available in your environment.
  Basic goal features target `coq-lsp` 0.2.4+; queries require the Pétanque API.
  The integration tests use `coq-lsp` 0.2.5+9.1 with Rocq 9.1.

The plugin starts `coq-lsp` from your `PATH` by default. Install the server
separately using the [upstream installation instructions](https://github.com/rocq-community/rocq-lsp#-installation),
and select a server build that matches your Rocq version. If you use an opam
switch or another project environment, launch Neovim from that environment.
Nix is optional; Nix users can provide the matching Rocq libraries and server
through their own development shell.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim), add the following plugin spec.
In LazyVim, place this spec in `lua/plugins/rocq.lua` 
within your Neovim configuration directory.

```lua
return {
  {
    "wallabyg/rocq.nvim",
    main = "rocq",
    ft = "coq",
    init = function()
      -- Treat .v files as Rocq in a Rocq-focused configuration.
      vim.filetype.add({ extension = { v = "coq" } })
    end,
    opts = {},
  },
}
```

The `.v` extension is also used by Verilog. If you edit both languages, omit
that extension override and use `:set ft=coq` for Rocq buffers, or configure
project-specific filetype detection. Filetype detection must happen before
`ft = "coq"` can load the plugin.

No build step or plugin dependencies are required. The plugin reuses an
attached `coq_lsp`/`rocq_lsp` client, including one started by LazyVim or
`nvim-lspconfig`. Otherwise it starts its own client; separate LSP configuration
is optional. When using an externally managed server with LazyVim, configure
its LSP spec with `mason = false` to use that server.

With another plugin manager, add the repository to your runtime and call:

```lua
require("rocq").setup({})
```

## Quick start

Open a named `.v` file and check that `:set filetype?` reports `coq`. Try this proof:

```coq
Lemma identity (P : Prop) : P -> P.
Proof.
  intros H.
  exact H.
Qed.
```

Wait for the server to attach, then place the cursor on the final period of
`intros H.`. The goal panel should show `H : P` and the goal `P`. At `exact H.`,
it should show no goals. Cursor movement and edits refresh the panel after
150 ms of inactivity, including in insert mode. Focus stays in the source window.
`:RocqGoals` refreshes immediately, and `:RocqStart` retries startup if needed.

The repository includes this proof as `examples/Basic.v`. From a clone's root:

```sh
nvim examples/Basic.v
```

## Configuration

Customize the plugin spec's `opts`, or pass the same table to `setup()`:

```lua
opts = {
  cmd = { "coq-lsp" }, -- replace with an executable path if needed
  auto_update = true, -- false: refresh through explicit commands
  update_delay = 150, -- milliseconds
  infoview = { width = 45 },
  query = { height = 12 },
  mappings = false, -- omit this to enable default buffer-local mappings
},
```

## Syntax highlighting

The plugin includes `syntax/coq.vim`, adapted from
[Coqtail](https://github.com/whonore/Coqtail), using Neovim's native syntax engine.
Its context-specific rules cover declarations, proof bodies, Gallina terms,
notation, modules, records, typeclasses, obligations, Ltac/Ltac2, and nested
comments. No Tree-sitter parser or Coqtail installation is required.

These are static syntax rules, so custom commands and notation can exceed
their coverage. Unsupported text is not highlighted as an error; normal LSP
diagnostics report actual proof errors. Explicit `admit` and `Admitted` markers
keep their error highlighting.

Highlighting loads for the `coq` syntax when Neovim's syntax highlighting is
enabled. If it is disabled in your configuration, run `:syntax enable`.
Check `:set syntax?`; it should report `coq`. Existing syntax definitions take
precedence, and the goal/query panels currently remain plain text.

Groups link to your colorscheme's standard highlights. Override a group in
your colorscheme configuration or a `ColorScheme` autocommand, for example:

```lua
vim.api.nvim_set_hl(0, "coqTactic", { link = "Function" })
vim.api.nvim_set_hl(0, "coqComment", { link = "Comment" })
```

The vendored rules retain Coqtail's `coq*` group names. Common customization
points include `coqVernacular`, `coqProofDelim`, `coqIdent`, `coqConstructor`,
`coqField`, `coqNotationKwd`, and `coqProofAdmit`. These replace the earlier
basic syntax file's `Rocq*` groups. The syntax file's header records the upstream
revision and adaptations.

## Interrupt and restart

`:RocqInterrupt` cancels pending goal, pin, navigation, and query requests for
the current proof and pauses its automatic goal updates. Requests for other
proofs remain active. Run `:RocqGoals`, Next/Prev, or a query to resume updates.
Interrupt also works from the proof's goal or query panel.

Cancellation depends on the server cooperating; background document checking
can continue. If the server becomes unresponsive, use `:RocqRestart` to restart
it, or `:RocqRestart!` to terminate it immediately. Normal restart first requests
a graceful shutdown, then forces termination after two seconds if necessary.

Restart reattaches all loaded buffers sharing that server and preserves its
configuration, unsaved text, pin positions, hidden panels, and window focus.
Pins refresh against the new server; pending queries are canceled and can be
run again. The selected proof's goals refresh if its source window is open.
If no server is attached, Restart starts one with the plugin's configured command.

## Panel controls and mappings

`:RocqToggle` hides or reopens the current proof's goal panel without taking
focus away from the source. `:RocqFocus` switches from the proof to its panel
and back. Both commands work in the panel too. If its source window has been
closed, Focus recreates a source split.

Closing the panel with `:close`, or replacing its buffer, also keeps it hidden.
Cursor movement, edits, progress notifications, and commands such as Next or
Goals do not reopen a hidden panel. Use Toggle or Focus to reopen it. Pins are
preserved while the panel is hidden.

Default normal-mode mappings use `<localleader>` (backslash unless configured):

| Mapping | Action |
| --- | --- |
| `<localleader>j` | Next sentence; accepts counts |
| `<localleader>k` | Previous sentence; accepts counts |
| `<localleader>p` | Pin the cursor's goal position |
| `<localleader>P` | Clear pins |
| `<localleader>i` | Toggle the goal panel |
| `<localleader>f` | Switch focus between proof and goals |

Proof mappings are buffer-local; the panel gets only Toggle and Focus. Existing
user mappings are preserved. Set `mappings = false` in `opts` to disable them,
or customize individual entries:

```lua
opts = {
  mappings = {
    next = "]p",
    prev = "[p",
    pin = "<localleader>p",
    clear_pins = "<localleader>P",
    toggle = "<localleader>i",
    focus = "<localleader>f",
  },
},
```

Set an individual entry to `false` to disable that binding. Changing `opts`
requires restarting Neovim or running `require("rocq").setup()` again with the
desired configuration.

### Public `<Plug>` mappings

The following normal-mode targets are available after `setup()`, including
when `mappings = false`. Default keys also use these targets.

| Target | Action |
| --- | --- |
| `<Plug>(RocqNext)` | Next sentence; accepts counts |
| `<Plug>(RocqPrev)` | Previous sentence; accepts counts |
| `<Plug>(RocqGoals)` | Refresh goals |
| `<Plug>(RocqPin)` | Pin the cursor's goal position |
| `<Plug>(RocqClearPins)` | Clear pins |
| `<Plug>(RocqToggle)` | Toggle the goal panel |
| `<Plug>(RocqFocus)` | Switch focus between proof and goals |
| `<Plug>(RocqInterrupt)` | Cancel pending proof requests and pause updates |
| `<Plug>(RocqRestart)` | Restart the server gracefully |

Use Next/Prev, Goals, and pin actions in the proof buffer. Toggle/Focus also
work in the goal panel; Interrupt/Restart also work in the goal and query panels.
Use `:RocqRestart!` for a forced restart and Ex commands for queries with arguments.
Targets do not overwrite existing global mappings with the same name.

Choose your own keys, for example in the plugin spec's `init` function:

```lua
vim.keymap.set("n", "]p", "<Plug>(RocqNext)", { desc = "Next Rocq sentence" })
vim.keymap.set("n", "[p", "<Plug>(RocqPrev)", { desc = "Previous Rocq sentence" })
```

These custom keys work once the plugin has loaded through `ft = "coq"`.
Neovim remaps `<Plug>` targets even with `vim.keymap.set`'s default `noremap`
behavior. To restrict your keys to proof buffers, define them in a `FileType`
autocommand with `pattern = "coq"` and `buffer = args.buf`.

## Goal pins

On `intros H.`, run `:RocqPin`, then move to `exact H.`. The top of the panel
follows the cursor and shows no goals, while the `Pin` section below still shows
`H : P` and the goal `P`. You can pin multiple positions. Each pin has a matching
marker at the end of its source line; pinning the same position twice reuses it.

Run `:RocqClearPins` in the proof buffer to remove all its pins and source markers.
Pins belong to their source buffer and are removed when that buffer is wiped.

Pins track positions with extmarks and refresh when the document changes. They
show the state at that position in the current document, rather than a frozen
snapshot. If an edit deletes the pinned text, the panel labels the position as
deleted. Undo can restore the position; automatic updates or `:RocqGoals` then
refresh it. Closing Neovim discards the pins.

## Queries

Run queries from the proof buffer:

| Command | Result |
| --- | --- |
| `:RocqCheck H` | Type of a term in the cursor's proof context |
| `:RocqCheck` | Check the identifier under the cursor, including qualified names |
| `:RocqPrint Nat.add` | Definition of a term |
| `:RocqSearch "identity"` | Lemmas matching a Rocq Search pattern |
| `:RocqQueryClose` | Close the query results for this proof |

Results appear in a separate bottom split labeled with the command and source
position. Focus stays in the proof. Move into the query panel with ordinary
window navigation; `q` closes it. A trailing period in the command argument is
optional. Arguments can contain spaces, parentheses, or quoted search patterns.
Set `query = { height = 12 }` in `opts` to customize the split height.

At `intros H.` in `Basic.v`, Check H returns `H : P`. At `Proof.`, H has not yet
been introduced. At `Qed.`, Search "identity" finds the completed lemma.
Queries use the state after the sentence at the cursor, or the previous state
when the cursor is between sentences. They do not insert commands into the
proof or change its document state.

Results stay anchored to the position where you ran the query when you move the
cursor. If the proof changes while a query is pending, its reply is marked stale.
Running another query supersedes an earlier pending result. Closing the panel
keeps it closed until you run another query.

Queries require a server providing Pétanque's run-at-position API (tested with
0.2.5+9.1). Both `petanque/run_at_pos` and the installed server's older method
name `petanque/run_at_point` are supported. Unsupported servers report an error
in the query panel; the proof is left unchanged.

## Checking progress

Server progress notifications highlight the remaining processing ranges in the
proof buffer, with a `▸` gutter marker and `Checking…` above the goals. A fatal
processing range uses an error highlight and `!` marker. On a short proof such
as `Basic.v`, the indicators may disappear too quickly to notice.

The markers disappear on completion, edits, or LSP detachment. Notifications for
older document versions are ignored. Processing markers report server activity;
they do not certify that a proof is complete or that the file is error-free.
Normal LSP diagnostics still report proof errors.

The highlight groups are `RocqProcessing` (default: `DiffChange`),
`RocqProcessingSign` (`DiagnosticInfo`), and `RocqProcessingError`
(`DiagnosticError`). You can customize them with `vim.api.nvim_set_hl`.

## Sentence navigation

`:RocqNext` moves to the final character of the next sentence endpoint after
the cursor and immediately refreshes its goals. If you are inside a sentence,
the first Next lands on that sentence's final character. Repeating it advances
through the proof. `:RocqPrev` moves to the preceding endpoint. Counts work:
`:3RocqNext` and `:2RocqPrev`. Large counts stop at the first/last sentence.

From the start of `Basic.v`, three Next commands land on `intros H.` and show
the identity goal. Another Next lands on `exact H.` and shows no goals. Prev
returns to the goal after `intros H.`. Navigation also refreshes when
`auto_update = false`.

The server provides parsed sentence ranges through `coq/getDocument`; no Lua
dot-based sentence scanner is used. Synthetic document nodes are skipped.
Bullets are separate sentences, even on a line containing a tactic. Ranges are
cached for fully checked, unchanged documents and fetched again after edits.
The first navigation request may wait for document checking; if a syntax error
prevents parsing later sentences, only the available parsed ranges are usable.

These commands navigate document states. They do not explicitly rewind the
prover or restrict checking to a selected endpoint. The server still checks
continuously.

Alternatively, with plugin mappings disabled, optional LazyVim mappings can be
added to the local plugin spec:

```lua
keys = {
  { "]p", function() require("rocq").step(1, vim.v.count1) end,
    ft = "coq", desc = "Next Rocq sentence" },
  { "[p", function() require("rocq").step(-1, vim.v.count1) end,
    ft = "coq", desc = "Previous Rocq sentence" },
},
```

## Verification

From the repository root, with `coq-lsp` on your `PATH`, run:

```sh
nvim --headless -u NONE -i NONE -l tests/integration.lua
nvim --headless -u NONE -i NONE -l tests/navigation.lua
nvim --headless -u NONE -i NONE -l tests/panels.lua
nvim --headless -u NONE -i NONE -l tests/queries.lua
nvim --headless -u NONE -i NONE -l tests/lifecycle.lua
nvim --headless -u NONE -i NONE -l tests/syntax.lua
```

The integration suites start a real server and check goal display, unsaved edits,
error recovery, stale reply rejection, duplicate-client prevention, and source
window focus. They also check automatic cursor/edit updates, debounce behavior,
and buffer switching.
Pin checks cover multiple positions, Unicode and line edits, changed hypotheses,
deleted positions, marker cleanup, and late replies after clearing.
Progress checks cover real server notifications, completion including an empty
EOF range, Unicode columns, stale versions, edits, fatal ranges, detachment,
and coexistence with existing LSP handlers.
Navigation tests cover counts, rapid commands, cached ranges, edits, stale
replies, boundary conditions, nested comments, qualified names, bullets, and
Unicode columns using the real server.
Panel tests cover toggle/focus, manual closure, hidden updates, source window
recovery, buffer-local mappings, public `<Plug>` targets and counts, user mapping
preservation, and disabling or customizing bindings.
Query tests cover Check/Print/Search, implicit identifiers, local proof context,
unchanged proof text and goals, errors, superseded/stale replies, panel closure,
qualified and Unicode identifiers, and cleanup when wiping the proof buffer.
Lifecycle tests cover cancellation isolation, automatic update pause/resume,
graceful and forced restart, shared buffers, hidden panels, unsaved edits, pins,
server configuration, duplicate restart commands, focus, and crash recovery.
The syntax suite runs without a server and checks automatic syntax loading,
context-specific declaration names and tactics, notation, constructors, record
fields, Ltac/Ltac2, modules, obligations, nested comments, quoted strings,
Unicode identifiers, unknown extensions, and user highlight overrides.

Set `COQ_LSP_BIN` to override the server executable when running integration tests:

```sh
COQ_LSP_BIN=/path/to/coq-lsp nvim --headless -u NONE -i NONE -l tests/integration.lua
```

## License and acknowledgments

Licensed under the [MIT License](LICENSE), copyright 2026 wallabyg.

Syntax highlighting is adapted from [Coqtail](https://github.com/whonore/Coqtail).
Original attribution is preserved in `syntax/coq.vim`; see the included
[Coqtail MIT license](LICENSES/Coqtail-MIT.txt).

[Coqtail](https://github.com/whonore/Coqtail) and
[lean.nvim](https://github.com/Julian/lean.nvim) were used as design references
for the proof workflow and goal-panel interaction. Proof checking and queries
are provided by [coq-lsp](https://github.com/rocq-community/rocq-lsp).
