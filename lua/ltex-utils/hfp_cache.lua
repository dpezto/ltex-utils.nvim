local cache = require("ltex-utils.cache")

---@class LTeXUtils.hfp_cache: LTeXUtils.cache
---@field initialise_rules function(picker_cb: function(), use_diags: boolean): boolean, string|nil
local M = cache:new()

---Transforms selection into language and rule pair.
---@param selection table picker item with `text` field
---@return string # Language descriptor
---@return string # Rule
function M.selection_to_lang_rule(selection)
	-- Get selection text; varies based on diagnostic usage.
	---@type string
	local text = selection.text or selection.value.text
	---@type string, string, string
	local lang, rule, sentence = text:match("^(.-)%s*,%s*(.-)%s*:%s*(.*)$")

	-- Encoding a table would sort the keys alphabetically; ltex-ls writes
	-- `rule` before `sentence`, so build the object by hand.
	return lang, string.format(
		'{"rule":%s,"sentence":%s}',
		vim.json.encode(rule),
		vim.json.encode(sentence)
	)
end

---Converts a language and rule pair into a formatted Telescope entry string
---@param lang string
---@param rule string
---@return string
function M.lang_rule_to_str(lang, rule)
	rule = vim.json.decode(rule)
	return string.format("%s, %s: %s", lang, rule.rule, rule.sentence)
end

return M
