local Config = require("ltex-utils.config")


local M = {}

-- A client may ask for its settings again while diagnostics are collected.
-- Keep suppression in client.config, but expose the original rules to saves.
local suspended = setmetatable({}, { __mode = "k" })

---@param client table
---@return table|nil
function M.settings_for_save(client)
	local settings = client.config.settings.ltex
	local pending = suspended[client]
	if not pending then return settings end
	settings = vim.deepcopy(settings)
	settings[pending.key] = pending.rules
	return settings
end

---@param client table
---@param key string
---@return function|nil restore
---@return string|nil error
function M.suspend_rules(client, key)
	if suspended[client] then return nil, "LTeX diagnostics collection already in progress" end
	local pending = { key = key, rules = client.config.settings.ltex[key] }
	suspended[client] = pending
	client.config.settings.ltex[key] = nil
	return function()
		if suspended[client] ~= pending then return end
		client.config.settings.ltex[key] = pending.rules
		suspended[client] = nil
	end
end

---Returns the first active LTeX LSP client attached to a buffer.
---NOTE: vim.lsp.buf_get_clients() is deprecated;
---use vim.lsp.get_active_clients instead.
---NOTE: vim.lsp.get_active_clients is deprecated form nvim 0.12;
---use vim.lsp.get_clients instead.
---@param bufnr integer|nil Buffer number; if not provided uses current buffer.
---@return table|nil # LTeX LSP client if found, otherwise nil.
function M.get_ltex(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		if client.name == Config.backend then
			return client
		end
	end

	return nil
end

---Returns the LSP server settings for a specified 'option' from the given
---'client'. Initializes an empty table for the 'option' if it doesn't exist.
---@param client table LTeX LSP client
---@param option string
---@return table<string, string[]>
function M.get_settings_or_init(client, option)
	---@type table
	local settings = client.config.settings.ltex
	if not settings then
		settings = {}
		client.config.settings.ltex = settings
	end

	if not settings[option] then
		settings[option] = {}
	end

	return settings
end

---Retrieves specified settings from the LTeX LSP server configuration.
---@param client table LTeX LSP client
---@param setting_cfg string The settings configuration to retrieve.
---@return table<string, string[]>|nil # Returns the settings table if found.
---@return string|nil # Returns nil and an error message if not found.
function M.get_settings(client, setting_cfg)
	---@type table
	local settings = client.config.settings.ltex

	-- Check if active server has settings `setting_cfg`
	if not settings or not settings[setting_cfg] then
		return nil, string.format(
			"The current LTeX server has no settings: %s\n",
			setting_cfg
		)
	end

	return settings[setting_cfg]
end

---Returns a handler for `textDocument/publishDiagnostics` notifications.
---The handler collects diagnostics data using a timer to batch process it.
---@param accumulated_diagnostics table Table to store diagnostics data
---@param callback fun(timed_out: boolean) Called on completion or timeout
---@param original_handler? function
---@return function(table, vim.lsp.diagnostic.diagnostic, table) # "textDocument/publishDiagnostics"-notification handler
---@return function cancel
function M.on_publish_diags(accumulated_diagnostics, callback, original_handler)
	local diag_timer = vim.uv.new_timer()
	local timeout_timer = vim.uv.new_timer()
	local done = false
	local function cancel()
		if done then return false end
		done = true
		for _, timer in ipairs({ diag_timer, timeout_timer }) do
			timer:stop()
			timer:close()
		end
		return true
	end
	local function finish(timed_out)
		if cancel() then callback(timed_out) end
	end

	-- Start immediately: the server may never publish a diagnostic notification.
	timeout_timer:start(Config.diagnostics.timeout_ms, 0, vim.schedule_wrap(function()
		finish(true)
	end))

	return function(err, result, ctx)
		if done then return end
		if err then
			vim.notify("Error on 'textDocument/publishDiagnostics': " ..
				vim.inspect(err), vim.log.levels.ERROR)
			finish(true)
			return
		end
		(original_handler or vim.lsp.diagnostic.on_publish_diagnostics)(err, result, ctx)
		table.insert(accumulated_diagnostics, result)
		-- the server answered; only the debounce decides from here, however
		-- long a large document takes to check
		timeout_timer:stop()
		diag_timer:stop()
		diag_timer:start(Config.diagnostics.debounce_time_ms, 0, vim.schedule_wrap(function()
			if done or diag_timer:is_active() then return end
			finish(false)
		end))
	end, cancel
end

---Requests code actions for given diagnostics, processes them, and triggers a
---final callback.
---@param client table The LTeX LSP server.
---@param bufnr integer The buffer number.
---@param diags vim.lsp.diagnostic.diagnostic List of diagnostics.
---@param process_action function(string, vim.lsp.diagnostic.action[]) Function to process each code action.
---@param final_cb function() Function called when all requests have been processed.
function M.actions_from_diags(client, bufnr, diags, process_action, final_cb)
	---@type integer
	local pending_reqs = 0
	for _, chunk in ipairs(diags) do
		pending_reqs = pending_reqs + #chunk.diagnostics
	end

	local function finish()
		-- Restore the server before opening a picker, which may itself fail.
		client:notify("workspace/didChangeConfiguration", client.config.settings)
		final_cb()
	end
	if pending_reqs == 0 then
		finish()
		return
	end

	for _, chunk in ipairs(diags) do
		for _, diag in ipairs(chunk.diagnostics) do
			local params = {
				textDocument = { uri = chunk.uri },
				range = diag.range,
				context = { diagnostics = { diag } },
			}
			local completed = false
			local function complete(err, actions)
				if completed then return end
				completed = true
				if not err then
					local ok, processing_err = pcall(process_action, nil, actions or {})
					if not ok then err = processing_err end
				end
				if err then
					vim.notify("Error getting code action: " .. vim.inspect(err), vim.log.levels.ERROR)
				end
				pending_reqs = pending_reqs - 1
				if pending_reqs == 0 then finish() end
			end
			local ok, sent = pcall(client.request, client,
				"textDocument/codeAction", params, complete, bufnr)
			if not ok or not sent then
				complete(not ok and sent or "Code action request could not be sent")
			end
		end
	end
end

return M
