local Config      = require("ltex-utils.config")
local cache       = require("ltex-utils.cache")
local diagnostics = require("ltex-utils.diagnostics")
local hfp_cache   = require("ltex-utils.hfp_cache")
local words_cache = require("ltex-utils.words_cache")
local popup       = require("plenary.popup")
local table_utils = require("ltex-utils.table_utils")
local pickers     = require("ltex-utils.pickers")

---@class LTeXUtils.UI
---@field cache LTeXUtils.cache|LTeXUtils.hfp_cache|LTeXUtils.words_cache
local rule_ui = {}
rule_ui.__index = rule_ui

---Constructor
---@return LTeXUtils.UI
function rule_ui.new()
	return setmetatable({ cache = nil }, rule_ui)
end

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

---Builds unified picker items from cache data.
---Both snacks and telescope backends consume this format.
---@param data table
---@return table
function rule_ui.build_items(data)
	local n     = table_utils.max_index(data)
	local items = {}
	for i = 1, n do
		local entry = data[i]
		if entry ~= nil then
			items[#items + 1] = {
				text   = entry.text or "",
				file   = entry.filename,
				pos    = entry.lnum and { entry.lnum, entry.col or 0 } or nil,
				_type  = entry.type,
				_bufnr = entry.bufnr,
				index  = i,
			}
		end
	end
	return items
end

-- ---------------------------------------------------------------------------
-- Shared actions called by picker backends
-- ---------------------------------------------------------------------------

---Opens the rule-edit popup window.
---Backends must close the picker and set `update_flag = false` BEFORE calling
---this; pass the saved flag value as `restore_flag`.
---@param item  table   picker item (snacks) or telescope selection
---@param use_diags  boolean
---@param restore_flag boolean  value to restore update_flag to after setup
function rule_ui:open_modify_popup(item, use_diags, restore_flag)
	---@type integer
	local win_id = popup.create('', {
		border    = true,
		line      = math.floor(vim.o.lines   / 2) - 2,
		col       = math.floor(vim.o.columns / 2) - 40,
		width     = 80,
		minheight = 6,
		maxheight = 20,
		enter     = true,
	})

	---@type integer
	local bufnr = vim.api.nvim_win_get_buf(win_id)
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
	vim.api.nvim_set_option_value("wrap",      true,   { win = win_id })

	---@type string, string
	local lang, rule = self.cache.selection_to_lang_rule(item)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { rule })

	vim.keymap.set({ 'i', 'n' }, '<CR>', function()
		local new_rule = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
		self.cache:update_entry(item.index, self.cache.lang_rule_to_str(lang, new_rule))
		self.cache:reset_indices()
		self.cache.update_flag = false
		vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
		self:new_pick_rule_win(self.cache.setting_cfg, use_diags, Config.rule_ui.picker)
		self.cache.update_flag = true
	end, { buffer = bufnr, noremap = false, silent = true })

	self.cache.update_flag = restore_flag
end

---Deletes an item from the cache.
---@param item table  picker item or telescope selection with `index` field
function rule_ui:delete_item(item)
	self.cache:delete_cb(item)
end

---Removes deprecated (ERROR-severity) items from the given list and cache.
---@param items table  list of picker items
---@return table       filtered list (non-deprecated items only)
function rule_ui:cleanup_items(items)
	local severities = vim.diagnostic.severity
	local new_items  = {}
	for _, item in ipairs(items) do
		if item._type == severities[1] then
			self.cache:delete_cb(item)
		else
			new_items[#new_items + 1] = item
		end
	end
	return new_items
end

---Jumps to the file location of the given item.
---Accepts both snacks items (`pos`) and telescope selections (`lnum`/`col`).
---@param item table
function rule_ui:goto_item(item)
	local bufnr = vim.api.nvim_get_current_buf()
	vim.diagnostic.show(diagnostics.get_ltex_namespace(bufnr), bufnr)
	local lnum = item.pos and item.pos[1] or item.lnum
	local col  = item.pos and item.pos[2] or item.col or 0
	if lnum and lnum > 0 then
		vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), { lnum, col })
	end
end

---Shows LTeX diagnostics in the current buffer.
function rule_ui:show_diags()
	local bufnr = vim.api.nvim_get_current_buf()
	vim.diagnostic.show(diagnostics.get_ltex_namespace(bufnr), bufnr)
end

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

---Creates a new picker window for modifying `setting_cfg` rules.
---@param setting_cfg string  'hiddenFalsePositives'|'disabledRules'|'dictionary'
---@param use_diags   boolean
---@param opts        table   extra backend-specific options (from Config.rule_ui.picker)
---@return boolean
function rule_ui:new_pick_rule_win(setting_cfg, use_diags, opts)
	opts = opts or {}

	---@type function()
	local picker_cb = function()
		pickers.open(self, {
			title     = setting_cfg,
			items     = rule_ui.build_items(self.cache.data),
			use_diags = use_diags,
			keys = {
				modify  = Config.rule_ui.modify_rule_key,
				delete  = Config.rule_ui.delete_rule_key,
				cleanup = Config.rule_ui.cleanup_rules_key,
				goto    = Config.rule_ui.goto_key,
			},
			extra = opts,
		})
	end

	-- cache already populated — open picker directly
	if self.cache then
		picker_cb()
		return true
	end

	-- first call — initialise cache then open picker
	---@type LTeXUtils.cache|LTeXUtils.hfp_cache|LTeXUtils.words_cache
	local win_cache
	if setting_cfg == "hiddenFalsePositives" then
		win_cache = hfp_cache:new(setting_cfg)
	elseif setting_cfg == "disabledRules" then
		win_cache = cache:new(setting_cfg)
	else
		win_cache = words_cache:new(setting_cfg)
	end
	self.cache = win_cache

	---@type boolean, string|nil
	local ok, err = win_cache:initialise_rules(picker_cb, use_diags)
	if not ok then
		vim.notify(err or "Error in new_pick_rule_win", vim.log.levels.ERROR)
		return false
	end

	return true
end

return rule_ui
