<!-- LTeX: language=en -->

# LTeX-Utils.nvim: LTeX Utility functions

> **Note**. This is a fork of [`jhofscheier/ltex-utils.nvim`](https://github.com/jhofscheier/ltex-utils.nvim), which has been unmaintained for some time.
> Compared to upstream, this fork:
>
> - defaults to the community server fork [`ltex-ls-plus`](https://github.com/ltex-plus/ltex-ls-plus) instead of the unmaintained [`ltex-ls`](https://github.com/valentjn/ltex-ls) (configurable via `backend`),
> - supports [snacks.nvim](https://github.com/folke/snacks.nvim), [Telescope](https://github.com/nvim-telescope/telescope.nvim), and [mini.pick](https://github.com/nvim-mini/mini.nvim) as picker backends, auto-detected in that order,
> - drops the [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) dependency (the rule editor is a native floating window),
> - targets Neovim ≥ 0.11 (method-form LSP client calls, `vim.lsp.config`/`vim.lsp.enable`),
> - stores dictionaries under `stdpath("state")` rather than `stdpath("cache")`, so they survive a cache wipe,
> - hides the per-document settings file by prefixing it with a dot,
> - ships a dependency-free self-check: `nvim -l tests/run.lua`.

Neovim plugin implementing functionality for LSP code actions for [`ltex-ls-plus`](https://github.com/ltex-plus/ltex-ls-plus), namely

- [`addToDictionary`](https://ltex-plus.github.io/ltex-plus/ltex-ls-plus/server-usage.html#_ltexaddtodictionary-client),
- [`disableRule`](https://ltex-plus.github.io/ltex-plus/ltex-ls-plus/server-usage.html#_ltexdisablerules-client), and
- [`hideFalsePositive`](https://ltex-plus.github.io/ltex-plus/ltex-ls-plus/server-usage.html#_ltexhidefalsepositives-client).

In addition, the plugin provides functions for loading, saving, and modifying LSP server settings and custom dictionaries.
For a detailed overview, please refer to the [tutorial](TUTORIAL.md#Tutorial).

There are already several excellent Neovim plugins that provide similar functionality: for example, [LTeX_extra.nvim](https://github.com/barreiroleo/ltex_extra.nvim), [LTeX LS Client](https://github.com/icewind/ltex-client.nvim), and [ltex-ls.nvim](https://github.com/vigoux/ltex-ls.nvim).

> **Question**. Why another LTeX plugin?<br>
> **Answer**. The last time I checked, these plugins are well written and do a fantastic job.
> However, all of them perform an excessive number of disk reads and writes.
> Some of them after each code action.
> This plugin follows the strategy to load the sever settings and dictionaries when the LTeX LSP server starts up and then leaves responsibility of keeping the current (language) configuration to the LSP server.
> Settings are automatically written to disk when the buffer is closed.
> Convenience functions allow the user to manually read/write settings from/to disk.

## Requirements

- Neovim ≥ 0.11
- [ltex-ls-plus](https://github.com/ltex-plus/ltex-ls-plus) (or [ltex-ls](https://github.com/valentjn/ltex-ls) with `backend = "ltex"`)
- [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) (optional, for the shipped server config)
- one of the following pickers (auto-detected in order):
  - [snacks.nvim](https://github.com/folke/snacks.nvim)
  - [Telescope](https://github.com/nvim-telescope/telescope.nvim)
  - [mini.pick](https://github.com/nvim-mini/mini.nvim) (part of mini.nvim)

## Installation

Install the plugin with your favourite plugin manager.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "dpezto/ltex-utils.nvim",
  dependencies = {
    "neovim/nvim-lspconfig",
    -- picker: use one of the following
    "folke/snacks.nvim",
    -- "nvim-telescope/telescope.nvim",
    -- "nvim-mini/mini.nvim",
  },
  opts = {
    -- your configuration comes here
    -- or leave it empty to use the default settings
    -- refer to the configuration section below
  },
}
```

Then call `require("ltex-utils").on_attach(bufnr)` once the LTeX server attaches to a buffer.
With Neovim's built-in LSP configuration (0.11+) this looks as follows:

```lua
vim.lsp.config("ltex_plus", {
	capabilities = your_capabilities,
	settings = {
		ltex = { your_settings },
	},
})
vim.lsp.enable("ltex_plus")

vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if client and client.name == "ltex_plus" then
			-- your other on-attach code
			-- for example, set keymaps here, like
			-- vim.keymap.set({ 'n', 'v' }, '<leader>ca', vim.lsp.buf.code_action, opts)
			require("ltex-utils").on_attach(args.buf)
		end
	end,
})
```

The server name must match the `backend` option (`"ltex_plus"` by default, `"ltex"` for the original server).
Check the [nvim-lspconfig documentation](https://github.com/neovim/nvim-lspconfig#quickstart) for further details on how to set keybindings.

## Configuration

By default, dictionaries are saved in a subfolder named `ltex` within Neovim's state directory.
For instance, if Neovim's state folder is located at `~/.local/state/nvim/`, the dictionaries will be stored in `~/.local/state/nvim/ltex/`.
You can change the dictionary folder and other options by running `require("ltex-utils").setup({ your options here })` at an appropriate place in your config code.
For example, for `lazy.nvim` this could be done as follows.
`ltex-utils.nvim` comes with the following defaults:

```lua
{
  "dpezto/ltex-utils.nvim",
  dependencies = {
    "neovim/nvim-lspconfig",
    -- picker: use one of the following
    "folke/snacks.nvim",
    -- "nvim-telescope/telescope.nvim",
    -- "nvim-mini/mini.nvim",
  },
  opts = {
    dictionary = {
      -- Path to the directory where dictionaries are stored.
      -- Defaults to the Neovim state directory.
      path = vim.fn.stdpath("state") .. "/ltex/",
      ---Returns the dictionary file name for given language `lang`
      filename = function(lang)
          return lang .. ".txt"
      end,
      -- use vim internal dictionary to add unkown words
      use_vim_dict = false,
      -- show/suppress vim command output such as `spellgood` or `mkspell`
      vim_cmd_output = false,
    },
    rule_ui = {
      -- key to modify rule
      modify_rule_key = "<CR>",
      -- key to delete rule
      delete_rule_key = "d",
      -- key to cleanup deprecated rules
      cleanup_rules_key = "c",
      -- key to jump to respective place in file
      goto_key = "g",
      -- enable line numbers in preview window
      previewer_line_number = true,
      -- wrap lines in preview window
      previewer_wrap = true,
      -- extra options passed through to the picker (backend-specific)
      picker = {},
    },
    diagnostics = {
      -- time to wait for language tool to complete parsing document
      -- debounce time in milliseconds
      debounce_time_ms = 500,
      -- use diagnostics data for modifying hiddenFalsePositives rules
      diags_false_pos = true,
      -- use diagnostics data for modifying disabledRules rules
      diags_disable_rules = true,
    },
    -- set the ltex-ls ("ltex") or ltex-ls-plus backend ("ltex_plus")
    backend = "ltex_plus",
    -- picker backend: "auto" tries snacks.nvim, telescope.nvim, then mini.pick
    -- set to "snacks", "telescope", or "mini" to skip auto-detection
    picker_backend = "auto",
  },
}
```

When the `use_vim_dict` option is set to `true`, the configuration settings `path` and `filename` are automatically assigned the following default values:

```lua
dictionary = {
	-- first writable of: `stdpath("config") .. "/spell/"`, a `spell/`
	-- directory in the runtimepath, or the current working directory
	path = vim.fn.stdpath("config") .. "/spell/",
	filename = function(lang)
		-- "en-US" -> "en"; a region-less "en" stays "en";
		-- an empty 'fileencoding' falls back to "utf-8"
		local enc = vim.api.nvim_get_option_value("fileencoding", { buf = 0 })
		if enc == "" then enc = "utf-8" end
		return (string.match(lang, "^(%a+)") or lang) .. "." .. enc .. ".add"
	end,
}
```

You can overwrite this behaviour by setting these options yourself.

When `use_vim_dict` is enabled, the plugin uses vim's internal functions to manage dictionaries.
For example:

- The 'Add word to dictionary' code actions uses vim's `spellgood` command to add new words into the internal dictionary.
- `LTeXUtils modify_dict` runs `mkspell` upon exit.

This configuration can be advantageous if you prefer to use a single dictionary for both `ltex-ls-plus` and vim's built-in spell checker.

Alternatively, if you want more control over the dictionary, you may set `use_vim_dict` to `false` while configuring `path` and `filename` to update vim's internal dictionary for additional words accordingly.
Please note that in this case, you will be required to manually execute the `mkspell` command.

## Usage

Using the mentioned configuration above, activate code actions by pressing `<leader>-ca`.
Navigate to an LTeX issue within your text (LaTeX, Markdown, etc.), then press `<leader>-ca` and choose a suitable option from the menu to fix the problem.

Whenever the LTeX server detaches from a buffer — closing the buffer, stopping the server, or quitting Neovim — its settings (including hidden false positives, disabled rules, used languages, and added dictionary words) are saved to disk.
Settings are saved in the same folder as your LaTeX/Markdown file, named after the document with its extension folded in and a leading dot, so `paper.tex` yields `.paper_tex_ltex.json` (the dot keeps it out of ordinary directory listings).
Dictionaries are merged with existing (stored) ones and then saved to preserve all words.
By default, dictionaries are saved in Neovim's state directory, although this can be customised (see [Installation](#installation)).

You can manually save settings with the `:LTeXUtils write_settings_to_file` command, and reload them with `:LTeXUtils load_settings_from_file`.

The `:LTeXUtils modify_dict` command allows you to inspect, edit, or delete entries in the relevant dictionary.

To examine, change, or remove entries in the `disabledRules` or `hiddenFalsePositives` lists, use the `:LTeXUtils modify_disabledRules` or `:LTeXUtils modify_hiddenFalsePositives` commands respectively.

To switch the display of the LTeX LSP server's diagnostics between 'on' and 'off' use `:LTeXUtils toggle_diagnostics`.

Saving is bound to the attached buffer rather than to `*.tex`/`*.md`, so every filetype the LTeX server supports (reStructuredText, Org, Typst, BibTeX, …) gets its settings written too.

More details can be found in the [tutorial](TUTORIAL.md#updating-custom-dictionaries).

## Development

Run the self-check from the repository root; it needs nothing but Neovim:

```sh
nvim -l tests/run.lua
```

## Caveats

If you frequently use the 'Hide False Positive' code action, be mindful that changes to the manuscript may render these rules obsolete.
Accumulating outdated rules can clutter the `hiddenFalsePositives` list, as LTeX doesn't clean them up automatically.

To avoid this, use 'Hide False Positive' sparingly or manually remove obsolete rules through `:LTeXUtils modify_hiddenFalsePositives`.
Direct modification of `.your_file_tex_ltex.json` settings file is not advised.
Using regular expressions for `hiddenFalsePositives` could help prevent clutter in your hidden false positives list.
However, bear in mind that hidden false positive rules hide the entire sentence and might not yield the expected behaviour.
An in-depth explanation is available in the [tutorial](TUTORIAL.md#hide-false-positives).

<!-- vim: set spelllang=en: -->
