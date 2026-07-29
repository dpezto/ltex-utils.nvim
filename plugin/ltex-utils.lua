if vim.g.loaded_ltex_utils == 1 then
  return
end
vim.g.loaded_ltex_utils = 1

local builtin = require("ltex-utils.builtin")

vim.api.nvim_create_user_command("LTeXUtils", function(opts)
	local fn = builtin[opts.args]
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
		local commands = vim.tbl_filter(function(key)
			return type(builtin[key]) == "function"
				and vim.startswith(key, arg_lead)
		end, vim.tbl_keys(builtin))
		table.sort(commands)
		return commands
	end,
})
