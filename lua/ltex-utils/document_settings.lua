local M = {}

-- Rules belong to one document. Everything else, dictionaries included (they
-- are one file per language anyway), stays shared in client.settings (what
-- Neovim answers the server with; client.config.settings may be nil).
local PER_DOCUMENT = { "hiddenFalsePositives", "disabledRules" }

---@type table<table, { buffers: table<integer, table>, original: function|nil, handler: function, suspended: table|nil }>
local clients = setmetatable({}, { __mode = "k" })

---@param client table
---@return table
function M.shared(client)
	client.settings.ltex = client.settings.ltex or {}
	return client.settings.ltex
end

---Shared settings with this document's rules on top, as sent to the server.
---@param client table
---@param bufnr integer
---@return table
function M.merged(client, bufnr)
	local merged = vim.tbl_extend("force", {}, M.shared(client))
	local doc = M.get(client, bufnr)
	for _, key in ipairs(PER_DOCUMENT) do merged[key] = doc[key] end
	return merged
end

-- ltex-ls asks for section "ltex" once per document, with its URI as scopeUri.
local function configuration_handler(fallback)
	return function(err, params, ctx, ...)
		local result, response_err = fallback(err, params, ctx, ...)
		local client = vim.lsp.get_client_by_id(ctx.client_id)
		local state = client and clients[client]
		if err or response_err or not state or type(result) ~= "table" then
			return result, response_err
		end
		-- one pass over the documents, not one per requested item
		local by_uri = {}
		for bufnr in pairs(state.buffers) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				by_uri[vim.uri_from_bufnr(bufnr)] = bufnr
			end
		end
		local suspended = state.suspended
		for i, item in ipairs(params.items or {}) do
			local bufnr = item.section == "ltex" and item.scopeUri and by_uri[item.scopeUri]
			if bufnr then
				result[i] = M.merged(client, bufnr)
				if suspended and suspended.doc == state.buffers[bufnr] then
					result[i][suspended.key] = nil
				end
			end
		end
		return result
	end
end

---Returns the table holding this document's own rules.
---@param client table
---@param bufnr? integer
---@return table
function M.get(client, bufnr)
	bufnr = bufnr and bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()
	local state = clients[client]
	if not state then
		local method = "workspace/configuration"
		state = { buffers = {}, original = client.handlers[method] }
		state.handler = configuration_handler(state.original or vim.lsp.handlers[method])
		client.handlers[method] = state.handler
		clients[client] = state
	end
	if not state.buffers[bufnr] then
		local doc = {}
		for _, key in ipairs(PER_DOCUMENT) do
			doc[key] = vim.deepcopy(M.shared(client)[key])
		end
		state.buffers[bufnr] = doc
	end
	return state.buffers[bufnr]
end

---Returns the table that owns `key` for `bufnr`: the document's for rules,
---the client's shared settings otherwise.
---@param client table
---@param bufnr? integer
---@param key string
---@return table
function M.owner(client, bufnr, key)
	return vim.tbl_contains(PER_DOCUMENT, key) and M.get(client, bufnr)
		or M.shared(client)
end

---Withhold this document's `key` rules from the server until `resume()` is
---called. The document keeps them meanwhile, so code actions and saves made
---during the suspension still land in (and persist from) the real rule table.
---@param client table
---@param bufnr? integer
---@param key string
---@return function|nil resume # nil if another suspension is in progress
function M.suspend(client, bufnr, key)
	local doc = M.get(client, bufnr)
	local state = clients[client]
	if state.suspended then return nil end
	local pending = { doc = doc, key = key }
	state.suspended = pending
	return function()
		if state.suspended == pending then state.suspended = nil end
	end
end

---Release a detached buffer, restoring the handler when the last one leaves.
function M.forget(client, bufnr)
	local state = clients[client]
	if not state then return end
	state.buffers[bufnr] = nil
	if next(state.buffers) then return end
	if client.handlers["workspace/configuration"] == state.handler then
		client.handlers["workspace/configuration"] = state.original
	end
	clients[client] = nil
end

return M
