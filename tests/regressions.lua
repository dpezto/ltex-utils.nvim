-- One check per fixed bug, against a mocked LSP client and real temp files.
local config = require("ltex-utils.config")
local lsp = require("ltex-utils.ltex_lsp")
local documents = require("ltex-utils.document_settings")
local actions = require("ltex-utils.actions")
local settings_io = require("ltex-utils.settings_io")
local cache = require("ltex-utils.cache")
local words_cache = require("ltex-utils.words_cache")
local pickers = require("ltex-utils.pickers")
local builtin = require("ltex-utils.builtin")
local ltex_utils = require("ltex-utils")
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
local original_by_id, original_open = vim.lsp.get_client_by_id, pickers.open
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

	-- a code action during diagnostics collection survives the restore; columns
	-- are bytes, not UTF-16 units; percent-encoded URIs become file names
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "é wrong" })
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
			arguments = { { uri = vim.uri_from_fname(dir .. "/a b.md"), ruleIds = { ["en-US"] = { "R" } } } } } } })
		return true
	end
	client.handlers["textDocument/publishDiagnostics"](nil,
		{ uri = vim.uri_from_bufnr(bufnr), diagnostics = { wrong } }, {})
	assert(vim.wait(1000, function() return opened end))
	assert(vim.deep_equal(documents.get(client, bufnr).disabledRules["en-US"], { "KEEP", "NEW" }))
	assert(vim.deep_equal(served().disabledRules["en-US"], { "KEEP", "NEW" }))
	local proposed = find(rules.data, "en-US: R")
	assert(proposed.col == 4 and vim.fs.normalize(proposed.filename) == vim.fs.normalize(dir .. "/a b.md"),
		vim.inspect(proposed))

	-- applying the picker keeps rules added after it opened
	assert(rules:delete_cb({ index = select(2, find(rules.data, "en-US: KEEP")) }))
	actions.new_handler("ruleIds", "disabledRules")({ arguments = {
		{ uri = vim.uri_from_bufnr(bufnr), ruleIds = { ["en-US"] = { "LATE" } } } } })
	assert(rules:apply_cache(bufnr))
	local applied = documents.get(client, bufnr).disabledRules["en-US"]
	table.sort(applied)
	assert(vim.deep_equal(applied, { "LATE", "NEW" }), vim.inspect(applied))

	-- a second command while collecting is refused instead of replacing the cache;
	-- the edit popup reopens the picker already dirty (mini.pick blocks in open);
	-- quitting with the picker open still saves its edits; detaching drops the autocmds
	local open_flags = {}
	pickers.open = function(ui) table.insert(open_flags, ui.cache.update_flag) end
	documents.forget(client, bufnr)
	ltex_utils.on_attach(bufnr)
	documents.get(client, bufnr).disabledRules = { ["en-US"] = { "OLD" } }
	builtin.modify_disabledRules()
	local first = builtin.wins[bufnr].cache
	builtin.modify_disabledRules()
	assert(builtin.wins[bufnr].cache == first)
	client.handlers["textDocument/publishDiagnostics"](nil, { uri = vim.uri_from_bufnr(bufnr), diagnostics = {} }, {})
	assert(vim.wait(1000, function() return #open_flags == 1 end))
	builtin.wins[bufnr]:open_modify_popup({ text = "en-US: OLD", index = 1 }, true, false)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "EDITED" })
	vim.fn.maparg("<CR>", "n", false, true).callback()
	assert(open_flags[2] == true and first.update_flag)
	vim.api.nvim_exec_autocmds("VimLeavePre", {})
	assert(vim.deep_equal(settings_io.read_settings(dir .. "/.new.md_ltex.json").disabledRules,
		{ ["en-US"] = { "EDITED" } }))
	vim.api.nvim_exec_autocmds("LspDetach", { buffer = bufnr, data = { client_id = client.id } })
	assert(not pcall(vim.api.nvim_get_autocmds, { group = "LTeXUtils_" .. bufnr }))

	-- settings saved under the old file name move to the new one on load
	local legacy = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(legacy, dir .. "/old.v1.md")
	assert(settings_io.write(dir .. "/.old_v1_md_ltex.json",
		vim.json.encode({ disabledRules = { ["en-US"] = { "OLD" } } })))
	assert(actions.load_ltex_from_file(legacy))
	assert(not vim.uv.fs_stat(dir .. "/.old_v1_md_ltex.json"))
	assert(settings_io.read_settings(dir .. "/.old.v1.md_ltex.json").disabledRules["en-US"][1] == "OLD")
	assert(actions.write_ltex_to_file(legacy))
	assert(settings_io.read_settings(dir .. "/.old.v1.md_ltex.json").disabledRules["en-US"][1] == "OLD")
	documents.forget(client, legacy)
	vim.api.nvim_buf_delete(legacy, { force = true })

	-- an unnamed buffer loads dictionaries and saves without a settings file
	local unnamed = vim.api.nvim_create_buf(true, false)
	local loaded, load_err = actions.load_ltex_from_file(unnamed)
	assert(not loaded and load_err == nil and actions.write_ltex_to_file(unnamed))
	documents.forget(client, unnamed)
	vim.api.nvim_buf_delete(unnamed, { force = true })

	-- unchanged dictionaries are not rewritten on save
	local writes, original_write = 0, settings_io.write
	settings_io.write = function(...) writes = writes + 1 return original_write(...) end
	local updated = settings_io.update_dictionary_files({ ["en-US"] = { "saved" } }, bufnr)
	settings_io.write = original_write
	assert(updated and writes == 0)

	-- a directory without trailing separator; language variants sharing a file
	-- drop a word deleted under either; words accepted after the picker opened stay
	config.setup({ dictionary = { path = dir, filename = function(lang)
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
vim.lsp.get_client_by_id, pickers.open = original_by_id, original_open
config.setup()
documents.forget(client, bufnr)
vim.api.nvim_buf_delete(bufnr, { force = true })
vim.fn.delete(dir, "rf")
assert(ok, err)
