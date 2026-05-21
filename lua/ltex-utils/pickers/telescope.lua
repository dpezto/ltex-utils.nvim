local M = {}

---Entry maker for non-diagnostic items (disabledRules, dictionary).
---@return function
local function make_simple_entries()
	return function(entry)
		local bufnr = entry.bufnr or vim.fn.bufnr()
		return {
			valid    = true,
			value    = entry,
			ordinal  = entry.text or "",
			display  = entry.text or "",
			bufnr    = bufnr,
			lnum     = entry.lnum or 0,
			col      = entry.col  or 0,
			type     = entry.type or 1,
			filename = entry.filename or vim.api.nvim_buf_get_name(bufnr),
		}
	end
end

---Removes deprecated entries from the current telescope picker.
---@param ui LTeXUtils.UI
---@param prompt_bufnr integer
local function cleanup_rules(ui, prompt_bufnr)
	local action_state = require("telescope.actions.state")
	local table_utils  = require("ltex-utils.table_utils")

	local picker    = action_state.get_current_picker(prompt_bufnr)
	local severities = vim.diagnostic.severity
	local n          = table_utils.max_index(ui.cache.data)
	local row        = 0

	for i = 1, n do
		local entry = ui.cache.data[i]
		if entry ~= nil then
			if entry.type == severities[2] then
				picker:set_selection(0)
				break
			elseif entry.type == severities[1] then
				picker:set_selection(row)
				picker:delete_selection(function(selection)
					ui:delete_item(selection)
				end)
			end
			row = row + 1
		end
	end
end

---@param ui LTeXUtils.UI
---@param opts table
function M.open(ui, opts)
	local pickers          = require("telescope.pickers")
	local finders          = require("telescope.finders")
	local make_entry       = require("telescope.make_entry")
	local telescope_actions = require("telescope.actions")
	local action_state     = require("telescope.actions.state")
	local conf             = require("telescope.config").values

	local extra = opts.extra or {}

	pickers.new(extra, {
		prompt_title = opts.title,
		default_text = "",
		finder = finders.new_table {
			results     = ui.cache.data,
			entry_maker = not opts.use_diags and make_simple_entries()
				or extra.entry_maker
				or make_entry.gen_from_diagnostics(extra),
		},
		previewer = opts.use_diags and conf.qflist_previewer(extra) or nil,
		sorter    = conf.prefilter_sorter {
			tag    = "type",
			sorter = conf.generic_sorter(extra),
		},
		attach_mappings = function(_, map)
			local function map_mk(modes_keys, func)
				for mode, keys in pairs(modes_keys) do
					for _, key in ipairs(keys) do
						map(mode, key, func)
					end
				end
			end

			-- modify
			map_mk(
				{ n = { opts.keys.modify }, i = { opts.keys.modify } },
				function(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if not selection then return end
					local saved_flag = ui.cache.update_flag
					ui.cache.update_flag = false
					telescope_actions.close(prompt_bufnr)
					ui:open_modify_popup(selection, opts.use_diags, saved_flag)
				end
			)

			-- delete
			map('n', opts.keys.delete, function(prompt_bufnr)
				local picker = action_state.get_current_picker(prompt_bufnr)
				picker:delete_selection(function(selection)
					ui:delete_item(selection)
				end)
			end)

			if opts.use_diags then
				-- cleanup deprecated rules
				map('n', opts.keys.cleanup, function(prompt_bufnr)
					cleanup_rules(ui, prompt_bufnr)
				end)

				-- goto diagnostic location
				map('n', opts.keys.goto, function(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					telescope_actions.close(prompt_bufnr)
					ui:goto_item(selection)
				end)
			end

			-- close + show diagnostics
			map_mk({ n = { '<Esc>', 'q' } }, function(prompt_bufnr)
				telescope_actions.close(prompt_bufnr)
				ui:show_diags()
			end)

			return true
		end,
	}):find()
end

return M
