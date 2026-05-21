local M = {}

---Detect which picker backend to use.
---Respects `Config.picker_backend`; falls back to auto-detection.
---@return string "snacks"|"telescope"
local function detect()
	local backend = require("ltex-utils.config").picker_backend
	if backend == "snacks" then return "snacks" end
	if backend == "telescope" then return "telescope" end
	-- auto: prefer snacks, fall back to telescope
	if pcall(require, "snacks.picker") then return "snacks" end
	if pcall(require, "telescope") then return "telescope" end
	error(
		"ltex-utils: no supported picker found. " ..
		"Install snacks.nvim or telescope.nvim."
	)
end

---Open a rule picker using the configured or auto-detected backend.
---@param ui LTeXUtils.UI
---@param opts table
---  title      string
---  items      table             unified picker items (from rule_ui.build_items)
---  use_diags  boolean
---  keys       {modify,delete,cleanup,goto: string}
---  extra      table             backend-specific extra options
function M.open(ui, opts)
	require("ltex-utils.pickers." .. detect()).open(ui, opts)
end

return M
