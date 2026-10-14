if vim.g.loaded_ltex_utils == 1 then
  return
end
vim.g.loaded_ltex_utils = 1

-- builtin is required on use: loading it pulls in most of the plugin
vim.api.nvim_create_user_command("LTeXUtils", function(opts)
	local fn = require("ltex-utils.builtin")[opts.args]
	if type(fn) ~= "function" then
		vim.notify(
			"LTeXUtils: unknown command: " .. opts.args,
			vim.log.levels.ERROR
		)
		return
	end
	fn()
end, {
	nargs = 1,
	complete = function(arg_lead)
		local builtin = require("ltex-utils.builtin")
		local commands = vim.tbl_filter(function(key)
			return type(builtin[key]) == "function"
				and vim.startswith(key, arg_lead)
		end, vim.tbl_keys(builtin))
		table.sort(commands)
		return commands
	end,
})
