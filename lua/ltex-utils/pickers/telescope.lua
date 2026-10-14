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

---Removes deprecated entries from the cache and rebuilds the picker from it.
---Works on the cache, not on visible rows: those depend on the prompt filter,
---the sorting strategy and any multi-selection.
---@param ui LTeXUtils.UI
---@param prompt_bufnr integer
---@param new_finder fun(): table
local function cleanup_rules(ui, prompt_bufnr, new_finder)
	local action_state = require("telescope.actions.state")
	local severities = vim.diagnostic.severity

	for i = 1, table.maxn(ui.cache.data) do
		local entry = ui.cache.data[i]
		if entry ~= nil and entry.type == severities[1] then
			ui.cache:delete_cb({ index = i })
		end
	end
	-- the new finder numbers entries by list position, so close the holes
	ui.cache:reset_indices()
	action_state.get_current_picker(prompt_bufnr):refresh(new_finder(), { reset_prompt = false })
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

	local function new_finder()
		return finders.new_table {
			results     = ui.cache.data,
			entry_maker = not opts.use_diags and make_simple_entries()
				or extra.entry_maker
				or make_entry.gen_from_diagnostics(extra),
		}
	end

	pickers.new(extra, {
		prompt_title = opts.title,
		default_text = "",
		finder = new_finder(),
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
					ui.cache:delete_cb(selection)
				end)
			end)

			if opts.use_diags then
				-- cleanup deprecated rules
				map('n', opts.keys.cleanup, function(prompt_bufnr)
					cleanup_rules(ui, prompt_bufnr, new_finder)
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
