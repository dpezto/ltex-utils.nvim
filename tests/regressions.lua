-- One check per fixed bug, against a mocked LSP client and real temp files.
local config = require("ltex-utils.config")
local lsp = require("ltex-utils.ltex_lsp")
local documents = require("ltex-utils.document_settings")
local actions = require("ltex-utils.actions")
local settings_io = require("ltex-utils.settings_io")
local cache = require("ltex-utils.cache")
local words_cache = require("ltex-utils.words_cache")
local uv = vim.uv

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local bufnr = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(bufnr, dir .. "/new.md")
vim.api.nvim_set_current_buf(bufnr)

-- started without `settings`: client.config.settings stays nil
local client = { id = 98, name = config.backend, config = {}, settings = { ltex = {} },
	handlers = {}, offset_encoding = "utf-16" }
function client:notify() return true end
local original_get_ltex, original_notify = lsp.get_ltex, vim.notify
local original_by_id = vim.lsp.get_client_by_id
lsp.get_ltex = function() return client end
vim.lsp.get_client_by_id = function() return client end
vim.notify = function() end
-- what the server is told for this document
local function served()
	return client.handlers["workspace/configuration"](nil,
		{ items = { { scopeUri = vim.uri_from_bufnr(bufnr), section = "ltex" } } },
		{ client_id = client.id })[1]
end
local function find(data, text)
	for i, entry in pairs(data) do
		if entry.text == text then return entry, i end
	end
end
config.setup({ dictionary = { path = dir .. "/" },
	diagnostics = { debounce_time_ms = 100 } })
lsp.timeout_ms = 100

local ok, err = xpcall(function()
	-- code actions: diagnostics sent as an array; a failed request still finishes
	local diag = { range = { start = { line = 0, character = 0 },
		["end"] = { line = 0, character = 1 } } }
	local n, finished = 0, 0
	function client:request(_, params, cb)
		assert(vim.islist(params.context.diagnostics))
		n = n + 1
		cb(n == 1 and { message = "failure" } or nil, {})
		return true
	end
	lsp.actions_from_diags(client, bufnr, { { uri = "file:///x", diagnostics = { diag, diag } } },
		function() end, function() finished = finished + 1 end)
	assert(finished == 1)

	-- no diagnostics at all: the timeout restores rules without opening the picker
	local original_handler = function() end
	client.handlers["textDocument/publishDiagnostics"] = original_handler
	client.settings.ltex = { disabledRules = { ["en-US"] = { "KEEP" } } }
	local opened = false
	assert(cache:new("disabledRules"):initialise_rules(function() opened = true end, true))
	assert(served().disabledRules == nil and documents.get(client, bufnr).disabledRules ~= nil)
	assert(vim.wait(1000, function() return served().disabledRules ~= nil end))
	assert(client.handlers["textDocument/publishDiagnostics"] == original_handler and not opened)

	-- diagnostics arriving just before the timeout still open the picker
	assert(cache:new("disabledRules"):initialise_rules(function() opened = true end, true))
	vim.wait(50)
	client.handlers["textDocument/publishDiagnostics"](nil, { uri = vim.uri_from_bufnr(bufnr), diagnostics = {} }, {})
	assert(vim.wait(1000, function() return opened end))

	-- a document without a sidecar still loads its language's dictionary
	assert(settings_io.write(dir .. "/en-US.txt", "saved\n"))
	documents.forget(client, bufnr)
	client.settings.ltex = {}
	actions.load_ltex_from_file(bufnr)
	assert(client.settings.ltex.dictionary["en-US"][1] == "saved")

	-- a failed write leaves the original file untouched and no temp file behind
	local target, original_rename = dir .. "/atomic.txt", uv.fs_rename
	assert(settings_io.write(target, "original"))
	uv.fs_rename = function() return nil, "EACCES" end
	local written = settings_io.write(target, "replacement")
	uv.fs_rename = original_rename
	assert(not written and vim.fn.readfile(target)[1] == "original")
	assert(#vim.fn.glob(target .. ".*", false, true) == 0)

	-- a code action during diagnostics collection survives the restore
	documents.forget(client, bufnr)
	documents.get(client, bufnr).disabledRules = { ["en-US"] = { "KEEP" } }
	local rules = cache:new("disabledRules")
	opened = false
	assert(rules:initialise_rules(function() opened = true end, true))
	actions.new_handler("ruleIds", "disabledRules")({ arguments = {
		{ uri = vim.uri_from_bufnr(bufnr), ruleIds = { ["en-US"] = { "NEW" } } } } })
	assert(served().disabledRules == nil)
	local wrong = { range = { start = { line = 0, character = 2 }, ["end"] = { line = 0, character = 7 } } }
	function client:request(_, _, cb)
		cb(nil, { { kind = "quickfix.ltex.disableRules", diagnostics = { wrong }, command = {
			arguments = { { uri = "file://" .. dir .. "/a%20b.md", ruleIds = { ["en-US"] = { "R" } } } } } } })
		return true
	end
	client.handlers["textDocument/publishDiagnostics"](nil,
		{ uri = vim.uri_from_bufnr(bufnr), diagnostics = { wrong } }, {})
	assert(vim.wait(1000, function() return opened end))
	assert(vim.deep_equal(documents.get(client, bufnr).disabledRules["en-US"], { "KEEP", "NEW" }))
	assert(vim.deep_equal(served().disabledRules["en-US"], { "KEEP", "NEW" }))

	-- applying the picker keeps rules added after it opened
	assert(rules:delete_cb({ index = select(2, find(rules.data, "en-US: KEEP")) }))
	actions.new_handler("ruleIds", "disabledRules")({ arguments = {
		{ uri = vim.uri_from_bufnr(bufnr), ruleIds = { ["en-US"] = { "LATE" } } } } })
	assert(rules:apply_cache(bufnr))
	local applied = documents.get(client, bufnr).disabledRules["en-US"]
	table.sort(applied)
	assert(vim.deep_equal(applied, { "LATE", "NEW" }), vim.inspect(applied))

	-- language variants sharing a file drop a word deleted under either; words
	-- accepted after the picker opened stay
	config.setup({ dictionary = { path = dir .. "/", filename = function(lang)
		return lang:match("^[^-]+") .. ".txt"
	end } })
	client.settings.ltex = { dictionary = { ["en-US"] = { "foo" }, ["en-GB"] = { "foo" } } }
	local words = words_cache:new("dictionary")
	assert(words:initialise_rules(function() end))
	assert(words:delete_cb({ index = select(2, find(words.data, "en-US: foo")) }))
	actions.new_handler("words", "dictionary")({ arguments = {
		{ uri = vim.uri_from_bufnr(bufnr), words = { ["en-GB"] = { "late" } } } } })
	assert(words:apply_cache(bufnr))
	assert(vim.deep_equal(settings_io.read_dictionary(dir .. "/en.txt"), { "late" }))
	assert(vim.deep_equal(client.settings.ltex.dictionary["en-GB"], { "late" }))
end, debug.traceback)

lsp.get_ltex, vim.notify, lsp.timeout_ms = original_get_ltex, original_notify, 10000
vim.lsp.get_client_by_id = original_by_id
config.setup()
documents.forget(client, bufnr)
vim.api.nvim_buf_delete(bufnr, { force = true })
vim.fn.delete(dir, "rf")
assert(ok, err)
