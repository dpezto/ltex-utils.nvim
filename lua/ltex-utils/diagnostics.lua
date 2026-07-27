local M = {}
local Config = require("ltex-utils.config")
local ltex_lsp = require("ltex-utils.ltex_lsp")

---Returns the namespace of LTeX LSP server for buffer `bufnr`; nil if not
---successful.
---@param bufnr integer
---@return integer|nil
function M.get_ltex_namespace(bufnr)
	---@type table|nil
	local client = ltex_lsp.get_ltex(bufnr)
	if not client then
		return nil
	end

	---@type string
	local lsp_server_name = "vim.lsp." .. Config.backend .. "."
		.. tostring(client.id)
	for ns, ns_metadata in pairs(vim.diagnostic.get_namespaces()) do
		if vim.startswith(ns_metadata.name, lsp_server_name) then
			return ns
		end
	end

	return nil
end

---Toggles the LTeX diagnostics hints on/off
---@param bufnr integer|nil
function M.toggle_diags(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	---@type integer|nil
	local ns = M.get_ltex_namespace(bufnr)
	if not ns then
		vim.notify("Error in toggle_diags: no namespace for LTeX LSP server")
		return
	end

	---@type boolean
	local is_enabled = vim.diagnostic.is_enabled({ bufnr = bufnr, ns_id = ns })

	vim.diagnostic.enable(not is_enabled, { bufnr = bufnr, ns_id = ns })
end

return M
