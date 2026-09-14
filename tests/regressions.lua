-- One check per fixed bug, against a mocked LSP client and real temp files.
local config = require("ltex-utils.config")
local lsp = require("ltex-utils.ltex_lsp")
local documents = require("ltex-utils.document_settings")
local actions = require("ltex-utils.actions")
local settings_io = require("ltex-utils.settings_io")
local cache = require("ltex-utils.cache")
local uv = vim.uv

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local bufnr = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(bufnr, dir .. "/new.md")
vim.api.nvim_set_current_buf(bufnr)

local client = { config = { settings = { ltex = {} } }, handlers = {} }
function client:notify() return true end
local original_get_ltex, original_notify = lsp.get_ltex, vim.notify
lsp.get_ltex = function() return client end
vim.notify = function() end
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
	client.config.settings.ltex = { disabledRules = { ["en-US"] = { "KEEP" } } }
	local opened = false
	assert(cache:new("disabledRules"):initialise_rules(function() opened = true end, true))
	assert(documents.get(client, bufnr).disabledRules == nil)
	assert(vim.wait(1000, function() return documents.get(client, bufnr).disabledRules ~= nil end))
	assert(client.handlers["textDocument/publishDiagnostics"] == original_handler and not opened)

	-- diagnostics arriving just before the timeout still open the picker
	assert(cache:new("disabledRules"):initialise_rules(function() opened = true end, true))
	vim.wait(50)
	client.handlers["textDocument/publishDiagnostics"](nil, { uri = vim.uri_from_bufnr(bufnr), diagnostics = {} }, {})
	assert(vim.wait(1000, function() return opened end))

	-- a document without a sidecar still loads its language's dictionary
	assert(settings_io.write(dir .. "/en-US.txt", "saved\n"))
	documents.forget(client, bufnr)
	client.config.settings.ltex = {}
	actions.load_ltex_from_file(bufnr)
	assert(client.config.settings.ltex.dictionary["en-US"][1] == "saved")

	-- a failed write leaves the original file untouched and no temp file behind
	local target, original_rename = dir .. "/atomic.txt", uv.fs_rename
	assert(settings_io.write(target, "original"))
	uv.fs_rename = function() return nil, "EACCES" end
	local written = settings_io.write(target, "replacement")
	uv.fs_rename = original_rename
	assert(not written and vim.fn.readfile(target)[1] == "original")
	assert(#vim.fn.glob(target .. ".*", false, true) == 0)
end, debug.traceback)

lsp.get_ltex, vim.notify, lsp.timeout_ms = original_get_ltex, original_notify, 10000
config.setup()
documents.forget(client, bufnr)
vim.api.nvim_buf_delete(bufnr, { force = true })
vim.fn.delete(dir, "rf")
assert(ok, err)
