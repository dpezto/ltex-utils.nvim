local M = {}

---@param ui LTeXUtils.UI
---@param opts table
function M.open(ui, opts)
	local MiniPick = require("mini.pick")

	-- Local copy — mutated by delete/cleanup actions without touching opts.items
	local items = opts.items

	-- -----------------------------------------------------------------------
	-- Custom key mappings
	-- -----------------------------------------------------------------------

	local mappings = {}

	mappings.ltex_delete = {
		char = opts.keys.delete,
		func = function()
			local item = MiniPick.get_picker_matches().current
			if not item then return end
			ui:delete_item(item)
			items = vim.tbl_filter(
				function(v) return v.index ~= item.index end,
				items
			)
			MiniPick.set_picker_items(items)
			-- return nil → keep picker open
		end,
	}

	if opts.use_diags then
		mappings.ltex_cleanup = {
			char = opts.keys.cleanup,
			func = function()
				items = ui:cleanup_items(items)
				MiniPick.set_picker_items(items)
			end,
		}

		mappings.ltex_goto = {
			char = opts.keys.goto,
			func = function()
				local item = MiniPick.get_picker_matches().current
				if not item then return end
				vim.schedule(function()
					ui:goto_item(item)
				end)
				return true -- close picker
			end,
		}
	end

	-- -----------------------------------------------------------------------
	-- Optional file preview (diagnostic mode only)
	-- -----------------------------------------------------------------------

	local preview_fn = nil
	if opts.use_diags then
		preview_fn = function(buf_id, item)
			if not item or not item.file then return end
			local ok, lines = pcall(vim.fn.readfile, item.file)
			if not ok or #lines == 0 then return end
			vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
			local ft = vim.filetype.match({ filename = item.file })
			if ft then vim.bo[buf_id].filetype = ft end
			-- Scroll preview window to item location
			if item.pos and item.pos[1] > 0 then
				local state = MiniPick.get_picker_state()
				local pwin  = state and state.windows and state.windows.preview
				if pwin and vim.api.nvim_win_is_valid(pwin) then
					local lnum = math.min(item.pos[1], #lines)
					local col  = math.max(0, (item.pos[2] or 1) - 1)
					vim.api.nvim_win_set_cursor(pwin, { lnum, col })
				end
			end
		end
	end

	-- -----------------------------------------------------------------------
	-- Start picker
	-- MiniPick uses item.text automatically for display and matching
	-- -----------------------------------------------------------------------

	MiniPick.start(vim.tbl_extend("force", opts.extra or {}, {
		source = {
			name    = opts.title,
			items   = items,
			-- <CR> triggers the modify popup (same as telescope/snacks default)
			choose  = function(item)
				if not item then return end
				vim.schedule(function()
					local saved_flag = ui.cache.update_flag
					ui.cache.update_flag = false
					ui:open_modify_popup(item, opts.use_diags, saved_flag)
				end)
			end,
			preview = preview_fn,
		},
		mappings = mappings,
	}))

	-- Runs after the picker closes via any path (Esc, q, choose, goto, …)
	ui:show_diags()
end

return M
