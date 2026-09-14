-- Minimal self-check: `nvim -l tests/run.lua` from the repository root.
-- Covers pure logic and mocked LSP/file persistence; no live server required.
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local table_utils = require("ltex-utils.table_utils")
local hfp_cache = require("ltex-utils.hfp_cache")
local cache = require("ltex-utils.cache")

-- every module loads
for _, mod in ipairs({
	"ltex-utils",
	"ltex-utils.actions",
	"ltex-utils.builtin",
	"ltex-utils.config",
	"ltex-utils.diagnostics",
	"ltex-utils.ltex_lsp",
	"ltex-utils.pickers",
	"ltex-utils.rule_ui",
	"ltex-utils.settings_io",
	"ltex-utils.words_cache",
}) do
	require(mod)
end

-- merge_lists_unique: nil first argument must not swallow the second list
assert(vim.deep_equal(table_utils.merge_lists_unique(nil, { "de", "en" }),
	{ "de", "en" }))
assert(vim.deep_equal(table_utils.merge_lists_unique({ "en" }, nil), { "en" }))
-- deduplicated and sorted
assert(vim.deep_equal(
	table_utils.merge_lists_unique({ "fr", "en" }, { "en", "de" }),
	{ "de", "en", "fr" }
))

assert(table_utils.max_index({ [1] = "a", [7] = "b" }) == 7)

-- hidden-false-positive rules round-trip, keeping ltex-ls' key order
local rule = '{"rule":"UPPERCASE_SENTENCE_START","sentence":"^\\\\Qa b\\\\E$"}'
local text = hfp_cache.lang_rule_to_str("en-GB", rule)
local lang, encoded = hfp_cache.selection_to_lang_rule({ text = text })
assert(lang == "en-GB", lang)
assert(encoded == rule, encoded)

-- quotes and backslashes survive the round-trip
local tricky = vim.json.encode({ rule = 'a"b\\c', sentence = "x" })
local _, re_encoded = hfp_cache.selection_to_lang_rule({
	text = hfp_cache.lang_rule_to_str("de-DE", tricky),
})
assert(vim.deep_equal(vim.json.decode(re_encoded),
	{ rule = 'a"b\\c', sentence = "x" }))

-- plain rules split on the first colon only
local l, r = cache.selection_to_lang_rule({ text = "en-US: FOO: BAR" })
assert(l == "en-US" and r == "FOO: BAR", r)

-- reset_indices closes the holes left by delete_cb
local c = cache:new("disabledRules")
c.data = { { text = "a" }, { text = "b" }, { text = "c" } }
assert(c:delete_cb({ index = 2 }))
c:reset_indices()
assert(#c.data == 2 and c.data[2].text == "c")
assert(select(1, c:delete_cb({ index = 99 })) == false)

dofile("tests/isolation.lua")
dofile("tests/regressions.lua")

print("ok")
