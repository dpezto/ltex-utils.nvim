local ltex_lsp = require("ltex-utils.ltex_lsp")
local documents = require("ltex-utils.document_settings")

-- ltex-ls code action arguments; everything else uses Neovim's lsp.* types
---@class LTeXUtils.command_argument
---@field uri string
---@field falsePositives? table<string, string[]>
---@field ruleIds? table<string, string[]>
---@field words? table<string, string[]>

---@type table<string, string>
local setting_quickfix_map = {
	hiddenFalsePositives = "quickfix.ltex.hideFalsePositives",
	disabledRules = "quickfix.ltex.disableRules",
	dictionary = "quickfix.ltex.addToDictionary",
}

---@type table<string, string>
local cfg_cmd_map = {
	hiddenFalsePositives = "falsePositives",
	disabledRules = "ruleIds",
}

---@class Telescope.entry
---@field bufnr integer The buffer number this entry corresponds to
---@field filename string The filename this entry corresponds to
---@field lnum integer The line number where this entry can be found
---@field col integer The column number where this entry can be found
---@field text string Display text of this entry
---@field type string Type of diagnostic severity (vim.diagnostic.severity)

---@class LTeXUtils.cache
---@field data Telescope.entry[]
---@field initial table<string, true> Entry texts the settings held at initialisation
---@field collecting boolean|nil Diagnostics collection still running
---@field setting_cfg string
---@field update_flag boolean
local M = {}
M.__index = M

---@type table<integer|string, integer|string>
local severities = vim.diagnostic.severity

---Constructor
---@param setting_cfg string|nil Identifier of settings type to cache
--                               (allowing nil for inheritance)
---@return LTeXUtils.cache
function M:new(setting_cfg)
	self.__index = self
	return setmetatable({
			setting_cfg = setting_cfg,
			update_flag = false,
		},
		self
	)
end

---Callback function for deleting entries
---@param selection table picker item with `index` field
---@return boolean
---@return string|nil
function M:delete_cb(selection)
	if not self.data[selection.index] then
		return false, "Error in delete_cb: nothing at index " ..
			tostring(selection.index)
	end
	self.data[selection.index] = nil
	self.update_flag = true
	return true
end

---Updates an entry in `self.data`
---@param row integer Index of the respective row to update
---@param text string
function M:update_entry(row, text)
	---@type Telescope.entry
	local entry = self.data[row]
	if entry then
		entry.text = text
		---@cast severities table<integer, string>
		entry.type = severities[4]
		self.update_flag = true
	end
end

---Resets the keys of `self.data` to be a list of consecutive integers
function M:reset_indices()
	---@type table<integer, Telescope.entry>
	local res = {}
	---@type integer
	local i = 1
	---@type integer
	local n = table.maxn(self.data)
	-- can't use `pairs(...)` here because order isn't guaranteed
	for j = 1, n do
		---@type Telescope.entry
		local entry = self.data[j]
		if entry ~= nil then
			res[i] = entry
			i = i + 1
		end
	end
	self.data = res
end

---Converts a language identifier and rule string into Telescope entry text 
---@param lang string
---@param rule string
---@return string
function M.lang_rule_to_str(lang, rule)
	return string.format("%s: %s", lang, rule)
end

---Transforms selection into language and rule pair.
---@param selection table picker item with `text` field
---@return string # Language descriptor
---@return string # Rule
function M.selection_to_lang_rule(selection)
	-- Get selection text; varies based on diagnostic usage
	---@type string
	local text=selection.text or selection.value.text
	return text:match("^%s*(.-)%s*:%s*(.*)$")
end

---Extracts server settings rules and saves them to `self.data`
---@param settings table
---@param bufnr integer
function M:extract_rules(settings, bufnr)
	---@type string
	local filename = vim.api.nvim_buf_get_name(bufnr)

	for lang, rules in pairs(settings) do
		for _, rule in ipairs(rules) do
			---@type string
			local text = self.lang_rule_to_str(lang, rule)
			self.data[text] = {
				bufnr = bufnr,
				filename = filename,
				lnum = 1,
				col = 1,
				text = text,
				---@cast severities table<integer, string>
				type = severities[1],
			}
		end
	end
end

---Updates server with cached rules
---@param bufnr integer
---@return boolean
---@return string|nil
function M:apply_cache(bufnr)
	if not self.update_flag then
		return false, "Update flag set to false"
	end

	---@type table|nil
	local client = ltex_lsp.get_ltex(bufnr)
	if not client then
		return false, "No active LTeX LSP server"
	end

	---@type table<string, string[]>
	local res = {}
	---@type table<string, true>
	local kept = {}

	for _, selection in pairs(self.data) do
		-- skip diagnostics-only entries; they are not server rules
		if selection.type ~= severities[2] then
			---@type string, string
			local lang, rule = self.selection_to_lang_rule(selection)
			kept[selection.text] = true
			if not res[lang] then
				res[lang] = { rule }
			else
				table.insert(res[lang], rule)
			end
		end
	end

	-- keep rules added (e.g. by a code action) after the picker opened
	local doc = documents.get(client, bufnr)
	for lang, rules in pairs(doc[self.setting_cfg] or {}) do
		for _, rule in ipairs(rules) do
			local text = self.lang_rule_to_str(lang, rule)
			if not self.initial[text] and not kept[text] then
				kept[text] = true
				res[lang] = res[lang] or {}
				table.insert(res[lang], rule)
			end
		end
	end
	doc[self.setting_cfg] = res

	-- send updated settings to LSP server
	ltex_lsp.notify_settings(client)

	self.data = nil
	self.initial = nil
	self.update_flag = false
	self.setting_cfg = nil

	return true
end

---Insert or update rule given by `lang_rule`. If rule already in `self.data`
---uppdates entry with diagnostics, otherwise inserts new entry.
---@param self LTeXUtils.cache
---@param diags table
---@param col integer 1-based byte column of the diagnostic
---@param lang_rule string[]
---@param filename string
---@param bufnr integer
local function process_rule(self, diags, col, lang_rule, filename, bufnr)
	---@type string
	local text = self.lang_rule_to_str(unpack(lang_rule))
	---@type Telescope.entry
	local curr_entry = self.data[text]

	if curr_entry then
		-- only update server's rules
		if curr_entry.type == severities[1] then
			curr_entry.lnum = diags.range.start.line + 1
			curr_entry.col = col
			curr_entry.type = severities[3]
		end
	else
		self.data[text] = {
			bufnr = bufnr,
			filename = filename,
			lnum = diags.range.start.line + 1,
			col = col,
			text = text,
			type = severities[2],
		}
	end
end

---Returns respective quickfix from action
---@param actions lsp.CodeAction[]
---@param setting_cfg string
---@return table|nil
local function quickfix_from_action(actions, setting_cfg)
	for _, action in ipairs(actions or {}) do
		if action.kind == setting_quickfix_map[setting_cfg] then
			return action
		end
	end
	return nil
end

---Callback for collecting code actions.
---@param self LTeXUtils.cache
---@param bufnr integer
---@param err string
---@param actions lsp.CodeAction[]
local function actions_cb(self, bufnr, err, actions)
	if err then
		vim.notify(
			"Error getting code actions: " .. vim.inspect(err),
			vim.log.levels.ERROR
		)
		return
	end

	---@type lsp.CodeAction|nil
	local quickfix = quickfix_from_action(actions, self.setting_cfg)
	if not quickfix then
		vim.notify("Error retrieving " .. self.setting_cfg .. " from actions")
		return
	end
	local client = ltex_lsp.get_ltex(bufnr)
	local encoding = client and client.offset_encoding or "utf-16"
	for i, argument in ipairs(quickfix.command.arguments) do
		---@type string
		local filename = argument.uri and argument.uri:sub(8)
				or vim.api.nvim_buf_get_name(bufnr)
		local diag = quickfix.diagnostics[i]
		-- LSP columns count `encoding` units; pickers and cursors want bytes
		local start = diag.range.start
		local line = vim.api.nvim_buf_get_lines(bufnr, start.line, start.line + 1, false)[1] or ""
		local col = vim.str_byteindex(line, encoding, start.character, false) + 1
		for lang, rules in pairs(argument[cfg_cmd_map[self.setting_cfg]]) do
			for _, rule in ipairs(rules) do
				process_rule(
					self,
					diag,
					col,
					{ lang, rule },
					filename,
					bufnr
				)
			end
		end
	end
end

---Converts `self.data` to sorted list. Sorted by type first, then line number,
---then column.
function M:sorted_rules_list()
	---@type Telescope.entry[]
	local list = vim.tbl_values(self.data)

	table.sort(list, function(a,b)
		if a.type == b.type then
			if a.lnum == b.lnum then
				return a.col < b.col
			else
				return a.lnum < b.lnum
			end
		else
			return a.type < b.type
		end
	end)

	self.data = list
end

---Initialises the rules cache
---@param picker_cb function()
---@param use_diags boolean
---@return boolean
---@return string|nil
function M:initialise_rules(telescope_cb, use_diags)
	---@type integer
	local bufnr = vim.api.nvim_get_current_buf()
	---@type table|nil
	local client = ltex_lsp.get_ltex(bufnr)
	if not client then return false, "No active LTeX LSP server" end
	-- use local variable to safe lookup costs
	---@type string
	local setting_cfg = self.setting_cfg

	-- get server settings
	---@type table<string, string[]>|nil, string|nil
	local settings, stgs_err = ltex_lsp.get_settings(client, setting_cfg, bufnr)
	if not settings then
		return false, stgs_err or ("Server has no settings: " .. setting_cfg)
	end

	-- initialise rules table with server settings
	self.data = {}; self:extract_rules(settings, bufnr)
	self.initial = vim.tbl_map(function() return true end, self.data)

	-- if no diags need to be included return table
	if not use_diags then
		self:sorted_rules_list(); telescope_cb()
		return true
	end

	---@type fun(err: any, actions: lsp.CodeAction[])
	local process_action = function(err, actions)
		actions_cb(self, bufnr, err, actions)
	end

	---@type function()
	local final_actions_cb = function()
		if vim.api.nvim_get_current_buf() ~= bufnr then
			vim.notify("LTeXUtils: return to the original buffer and reopen the rule picker",
				vim.log.levels.INFO)
			return
		end
		self:sorted_rules_list(); telescope_cb()
	end

	---@type lsp.Handler|nil
	local old_handler = client.handlers["textDocument/publishDiagnostics"]

	-- Initialise empty diagnostics table and nil timer
	---@type lsp.PublishDiagnosticsParams[]
	local acc_diags = {}

	local restore, suspend_err = ltex_lsp.suspend_rules(client, setting_cfg, bufnr)
	if not restore then return false, suspend_err end
	self.collecting = true

	---@type function()
	local final_diags_cb = function(timed_out)
		-- restore handler again
		client.handlers["textDocument/publishDiagnostics"] = old_handler
		restore()
		-- a pending code action can't block new pickers; rule_ui drops
		-- this one's picker if another cache replaced it meanwhile
		self.collecting = nil
		if timed_out then
			ltex_lsp.notify_settings(client)
			vim.notify("LTeXUtils: diagnostics collection failed or timed out; please retry",
				vim.log.levels.WARN)
			return
		end
		ltex_lsp.actions_from_diags(
			client,
			bufnr,
			acc_diags,
			process_action,
			final_actions_cb
		)
	end

	-- Overwrite the diagnostics handler
	local handler, cancel = ltex_lsp.on_publish_diags(acc_diags, final_diags_cb, old_handler, vim.uri_from_bufnr(bufnr))
	client.handlers["textDocument/publishDiagnostics"] = handler

	local ok, sent = pcall(ltex_lsp.notify_settings, client)
	if not ok or not sent then
		cancel()
		restore()
		self.collecting = nil
		client.handlers["textDocument/publishDiagnostics"] = old_handler
		return false, "Could not request diagnostics from LTeX"
	end

	return true
end

return M
