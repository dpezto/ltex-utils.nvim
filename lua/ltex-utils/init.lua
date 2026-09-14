local M = {}

local builtin = require("ltex-utils.builtin")
local Config = require("ltex-utils.config")
local ltex = require("ltex-utils.actions")
local ltex_lsp = require("ltex-utils.ltex_lsp")
local rule_ui = require("ltex-utils.rule_ui")

-- Writes current LTeX LSP server settings to file
---@return string|nil  # error message if writing to file fails
local function on_exit(bufmeta)
	---@type integer
	local bufnr = bufmeta.buf

	-- delete current buffer from windows list
	builtin.wins[bufnr] = nil

	---@type boolean, string|nil
	local ok, err = pcall(ltex.write_ltex_to_file, bufnr)

	if not ok then
		vim.notify("Error on exit: " .. vim.inspect(err), vim.log.levels.ERROR)
		return err
	end
end

vim.api.nvim_create_autocmd("User", {
	pattern = "TelescopePreviewerLoaded",
	group = vim.api.nvim_create_augroup("LTeXUtils", { clear = true }),
	callback = function(args)
		if args.data == nil or args.data.bufname == nil then
			return
		end
		---@type string|nil
		local extension = args.data.bufname:match("%.(%w+)$")
		if extension == "md" or extension == "tex" then
			vim.wo.number = Config.rule_ui.previewer_line_number
			vim.wo.wrap = Config.rule_ui.previewer_wrap
		end
	end,
})

---Set up the buffer-local autocommands for an attached buffer.
---Scoped to `bufnr` rather than to `*.tex`/`*.md`, so every filetype ltex
---supports (rst, org, typst, bib, ...) gets its settings saved too.
---@param bufnr integer
local function autocmd_ltex(bufnr)
	-- own group per buffer: re-attaching replaces this buffer's autocommands
	-- without clearing those of the other attached buffers
	---@type integer
	local augroup_id = vim.api.nvim_create_augroup(
		"LTeXUtils_" .. bufnr,
		{ clear = true }
	)

	-- LspDetach, not BufUnload: the buffer's `on_detach` callback (which
	-- removes the buffer from `client.attached_buffers`) runs *before*
	-- BufUnload, so the client is already gone by then. LspDetach fires
	-- while the client is still attached, and covers closing the buffer
	-- and stopping the server.
	vim.api.nvim_create_autocmd("LspDetach", {
		buffer = bufnr,
		callback = function(args)
			---@type vim.lsp.Client|nil
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			-- ignore other language servers detaching from this buffer
			if not client or client.name ~= Config.backend then return end
			on_exit(args)
		end,
		group = augroup_id,
		desc = "save ltex settings to files",
	})

	-- Quitting Neovim never fires LspDetach: the client's exit handler
	-- schedules it, and Neovim is gone before the schedule runs. The client
	-- is still attached during VimLeavePre, so save here too.
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			-- skip buffers already saved and detached (e.g. closed earlier)
			if not vim.api.nvim_buf_is_valid(bufnr)
				or not ltex_lsp.get_ltex(bufnr) then
				return
			end
			on_exit({ buf = bufnr })
		end,
		group = augroup_id,
		desc = "save ltex settings to files on exit",
	})

	vim.api.nvim_create_autocmd("BufEnter", {
		buffer = bufnr,
		callback = function()
			---@type LTeXUtils.UI|nil
			local wins = builtin.wins[bufnr]
			if wins ~= nil and wins.cache ~= nil then
				wins.cache:apply_cache(bufnr)
			end
		end,
		group = augroup_id,
		desc = "apply cached rule changes",
	})
end

---Called when an LTeX LSP server is attached. Adds custom LSP commands.
---Creates auto commands. Loads saved server settings.
---@param bufnr integer
---@return string|nil # error message if file exists but can't be loaded
function M.on_attach(bufnr)
	-- Use local variables to reduce table lookup cost
	---@type table
	local cmds = vim.lsp.commands

	---@type function(table)
	local dict_handler = ltex.new_handler("words", "dictionary")
	-- Add custom LSP commands for the ltex language server
	cmds["_ltex.addToDictionary"] = Config.dictionary.use_vim_dict and
	function(command)
		dict_handler(command)
		-- save previously used spelllang for current buffer
		local spellfile = vim.api.nvim_get_option_value(
			"spellfile",
			{ buf = 0 }
		)
		for lang, words in pairs(command.arguments[1]["words"]) do
			vim.api.nvim_set_option_value(
				"spellfile",
				Config.dictionary.path .. Config.dictionary.filename(lang),
				{ buf = 0 }
			)
			for _, word in ipairs(words) do
				vim.api.nvim_cmd({
					cmd = "spellgood",
					args = { word, },
				}, { output = not Config.dictionary.vim_cmd_output, })
			end
		end
		-- restore spellfile and spelllang
		vim.api.nvim_set_option_value("spellfile", spellfile, { buf = 0 } )
	end or dict_handler

	cmds["_ltex.hideFalsePositives"] = ltex.new_handler(
		"falsePositives",
		"hiddenFalsePositives"
	)
	cmds["_ltex.disableRules"] = ltex.new_handler(
		"ruleIds",
		"disabledRules"
	)

	-- create autocommands
	autocmd_ltex(bufnr)

	-- create ui instance for modifying rules; guarantees that
	-- managing rules in different buffers work as expected
	builtin.wins[bufnr] = rule_ui.new()

	-- load server settings if they exist
	---@type boolean, string|nil
	local ok, err = ltex.load_ltex_from_file(bufnr)
	if not ok and err then
		-- if settings file does not exist yet, inform user and
		-- continue with emtpy settings
		if string.sub(err, 1, 6) == 'ENOENT' then
			vim.notify(
				"No existing settings file yet. " ..
				"Will be generated automatically when file closed.",
				vim.log.levels.INFO
			)
		else
			vim.notify(
				"Error on attach: " .. vim.inspect(err),
				vim.log.levels.ERROR
			)
			return err
		end
	end
end

-- Sets up the module with user-defined options.
---@param opts? LTeXUtils.Config A table containing user-defined options.
function M.setup(opts)
	-- use custom options if provided
	Config.setup(opts)
end

return setmetatable(M, {
	__index = function(_, k)
		return require("ltex-utils.builtin")[k]
	end,
})
