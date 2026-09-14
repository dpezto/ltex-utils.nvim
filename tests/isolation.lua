-- Documents sharing one LTeX client keep their own rules but share dictionaries.
local documents = require("ltex-utils.document_settings")
local lsp = require("ltex-utils.ltex_lsp")
local actions = require("ltex-utils.actions")
local io_utils = require("ltex-utils.settings_io")
local config = require("ltex-utils.config")
local words_cache = require("ltex-utils.words_cache")

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local function buffer(name)
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(buf, dir .. "/" .. name)
	return buf
end
local a, b = buffer("a.md"), buffer("b.md")
local client = { id = 99, handlers = {}, config = { settings = { ltex = {} } } }
client.settings = client.config.settings
function client:notify() return true end
local original_get, original_by_id, original_notify = lsp.get_ltex, vim.lsp.get_client_by_id, vim.notify
lsp.get_ltex = function() return client end
vim.lsp.get_client_by_id = function() return client end
vim.notify = function() end
config.setup({ dictionary = { path = dir .. "/" } })
local function sidecar(name) return io_utils.read_settings(dir .. "/." .. name .. "_md_ltex.json") end

local ok, err = xpcall(function()
	-- the server gets each document's own rules
	assert(io_utils.write(dir .. "/.a_md_ltex.json", vim.json.encode({ disabledRules = { ["en-US"] = { "A" } } })))
	actions.load_ltex_from_file(a)
	actions.load_ltex_from_file(b)
	local function query(buf)
		return client.handlers["workspace/configuration"](nil,
			{ items = { { scopeUri = vim.uri_from_bufnr(buf), section = "ltex" } } },
			{ client_id = client.id })[1]
	end
	assert(query(a).disabledRules["en-US"][1] == "A")
	assert(query(b).disabledRules == nil)

	-- a code action saves to the document it came from, not the current buffer
	vim.api.nvim_set_current_buf(b)
	actions.new_handler("ruleIds", "disabledRules")({ arguments = {
		{ uri = vim.uri_from_bufnr(a), ruleIds = { ["en-US"] = { "A2" } } } } }, { bufnr = b })
	assert(actions.write_ltex_to_file(a) and actions.write_ltex_to_file(b))
	assert(vim.deep_equal(sidecar("a").disabledRules["en-US"], { "A", "A2" }))
	assert(sidecar("b").disabledRules == nil)

	-- a word accepted in B shows up in A's dictionary picker, so editing there keeps it
	actions.new_handler("words", "dictionary")({ arguments = {
		{ uri = vim.uri_from_bufnr(b), words = { ["en-US"] = { "foo" } } } } })
	vim.api.nvim_set_current_buf(a)
	local picker = words_cache:new("dictionary")
	assert(picker:initialise_rules(function() end))
	assert(vim.iter(picker.data):any(function(entry) return entry.text == "en-US: foo" end))

	-- language variants sharing one file are written once, with both word lists
	config.setup({ dictionary = { path = dir .. "/", filename = function(lang)
		return lang:match("^[^-]+") .. ".utf-8.add"
	end } })
	assert(io_utils.update_dictionary_files({ ["en-US"] = { "one" }, ["en-GB"] = { "two" } }, a))
	assert(vim.deep_equal(io_utils.read_dictionary(dir .. "/en.utf-8.add"), { "one", "two" }))
end, debug.traceback)

documents.forget(client, a)
documents.forget(client, b)
lsp.get_ltex, vim.lsp.get_client_by_id, vim.notify = original_get, original_by_id, original_notify
config.setup()
vim.api.nvim_buf_delete(a, { force = true })
vim.api.nvim_buf_delete(b, { force = true })
vim.fn.delete(dir, "rf")
assert(ok, err)
