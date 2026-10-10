local M = {}

local Config = require("ltex-utils.config")
local documents = require("ltex-utils.document_settings")
local ltex_lsp = require("ltex-utils.ltex_lsp")
local settings_io = require("ltex-utils.settings_io")
local table_utils = require("ltex-utils.table_utils")

---Settings file of a document: `.<file name>_ltex.json` in its directory, or
---nil for an unnamed buffer. The second value is the name used before, which
---folded dots into underscores (so `a.b.tex` and `a_b.tex` collided); it is
---renamed to the first on load, so settings saved under it carry over.
---@param absolutePath string
---@return string|nil, string|nil
local function ltex_filename(absolutePath)
    -- Separate path and filename
    local path, name_with_possible_ext = absolutePath:match("^(.-)([^/]+)$")
    if not name_with_possible_ext then return nil end

    -- Split filename into name and its optional extension using your pattern
    local name, ext = name_with_possible_ext:match("^([^%.]*)(%.?.*)$")
    local legacy = path .. "." .. name .. ext:gsub("%.", "_") .. "_ltex.json"

    return path .. "." .. name_with_possible_ext .. "_ltex.json", legacy
end

---Generates a code action handler updating LSP server settings with 'cmd_cfg'
---and 'setting_cfg' fields.
---@param cmd_cfg string The key for the code action command
---@param setting_cfg string The key of the server settings
---@return fun(command: lsp.Command, ctx: table) # The code action handler
function M.new_handler(cmd_cfg, setting_cfg)
	return function (command, ctx)
		---@type table|nil
		local argument = command.arguments[1]
		local bufnr = argument.uri and vim.uri_to_bufnr(argument.uri)
			or (ctx and ctx.bufnr) or vim.api.nvim_get_current_buf()
		local client = ltex_lsp.get_ltex(bufnr)
		-- if no active ltex client abort
		if not client then return end

		---@type table<string, string[]>
		local settings = ltex_lsp.get_settings_or_init(client, setting_cfg, bufnr)

		for lang, rules in pairs(command.arguments[1][cmd_cfg]) do
			settings[setting_cfg][lang] = vim.list_extend(settings[setting_cfg][lang] or {}, rules)
		end

		ltex_lsp.notify_settings(client)
	end
end

---Writes the current LTeX LSP server settings to a JSON file. It saves the
---current dictionaries and their languages, hidden false positives, and
---disabled rules. The settings are written to a JSON file, named
---'.current_filename_ltex.json' located in its parent directory.
function M.write_ltex_to_file(bufnr)
	---@type integer
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	---@type table|nil
	local client = ltex_lsp.get_ltex(bufnr)
	-- if no active ltex client abort
	if not client then
		vim.notify("No active ltex client found", vim.log.levels.ERROR)
		return false, "No active ltex client found"
	end

	-- Use local variables to reduce table lookup cost
	---@type table
	local settings = documents.merged(client, bufnr)

	---@type string[]
	local langs
	if Config.dictionary.use_vim_dict then
		-- Neovim takes care of saving dictionaries
		-- only remember used languages
		if settings.dictionary then
			langs = vim.tbl_keys(settings.dictionary)
		end
	else
		-- save dictionaries; update them if necessary
		if settings.dictionary then
			local ok, err = pcall(vim.fn.mkdir, Config.dictionary.path, "p")
			if not ok then return false, err end
			langs, err = settings_io.update_dictionary_files(settings.dictionary, bufnr)
			if not langs then return false, err end
		end
	end

	---@type table<string, string[]>
	local settings_to_save = {}

	for _, settings_cfg in ipairs({ "hiddenFalsePositives", "disabledRules" }) do
		if settings[settings_cfg] then
			settings_to_save[settings_cfg] = settings[settings_cfg]
			langs = table_utils.merge_lists_unique(
				langs,
				vim.tbl_keys(settings[settings_cfg])
			)
		end
	end

	if settings.language then
		langs = table_utils.merge_lists_unique(langs, { settings.language })
	end

	settings_to_save.langs = langs

	---@type string|nil
	local settings_filename = ltex_filename(vim.api.nvim_buf_get_name(bufnr))
	-- an unnamed buffer has nowhere to keep its rules (yet)
	if not settings_filename then return true end
	return settings_io.write(
		settings_filename,
		vim.json.encode(settings_to_save)
	)
end

---Loads LTeX  LSP settings from JSON file. Updates the active LTeX LSP
---server with read settings (hidden false positives, disabled rules, and
---specific language dictionaries). Settings file given by
---'.buffer_filename_ltex.json'.  If settings file doesn't exist, an
---notification is printed.
---@param bufnr integer|nil Buffer number; if not provided uses current buffer.
---@return boolean # true if successful, false otherwise.
---@return string|nil # nil if successful, error message otherwise.
function M.load_ltex_from_file(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	---@type table|nil
	local client = ltex_lsp.get_ltex(bufnr)
	-- if no active ltex client abort
	if not client then
		return false, "No active ltex client found"
	end

	---@type string|nil, string|nil
	local settings_filename, legacy_filename =
		ltex_filename(vim.api.nvim_buf_get_name(bufnr))

	---@type table<string, string[]>|nil, string|nil
	local saved_settings, err
	if settings_filename then
		saved_settings, err = settings_io.read_settings(settings_filename)
		-- move settings saved under the previous file name to the current one
		if not saved_settings and err:sub(1, 6) == "ENOENT"
			and vim.uv.fs_rename(legacy_filename, settings_filename) then
			saved_settings, err = settings_io.read_settings(settings_filename)
		end
	end
	-- A new (or unnamed) document still needs the user's shared dictionaries.
	local missing = not saved_settings
		and (not settings_filename or err:sub(1, 6) == "ENOENT")
	if not saved_settings and not missing then return false, err end

	if saved_settings then
		local doc = documents.get(client, bufnr)
		doc.hiddenFalsePositives = saved_settings.hiddenFalsePositives
		doc.disabledRules = saved_settings.disabledRules
	end

	-- Dictionaries are shared by every document on the client: merge, never
	-- replace, so other documents' unsaved words survive.
	-- en-US is LTeX's default when no language is configured.
	local shared = documents.shared(client)
	local langs = saved_settings and saved_settings.langs
		or { shared.language or "en-US" }
	for lang, words in pairs(settings_io.load_dictionaries(langs, bufnr)) do
		shared.dictionary = shared.dictionary or {}
		shared.dictionary[lang] = table_utils.merge_lists_unique(shared.dictionary[lang], words)
	end

	ltex_lsp.notify_settings(client)
	if missing then return false, err end
	return true, nil
end

return M
