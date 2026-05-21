local M = {}

---@param ui LTeXUtils.UI
---@param opts table
function M.open(ui, opts)
	local list_keys = {
		[opts.keys.modify] = "ltex_modify",
		[opts.keys.delete] = "ltex_delete",
	}
	if opts.use_diags then
		list_keys[opts.keys.cleanup] = "ltex_cleanup"
		list_keys[opts.keys.goto]    = "ltex_goto"
	end

	Snacks.picker.pick(vim.tbl_extend("force", opts.extra or {}, {
		title   = opts.title,
		items   = opts.items,
		format  = "text",
		preview = opts.use_diags and "file" or nil,
		actions = {
			ltex_modify = function(picker)
				local item = picker:current()
				if not item then return end
				local saved_flag = ui.cache.update_flag
				ui.cache.update_flag = false
				picker:close()
				ui:open_modify_popup(item, opts.use_diags, saved_flag)
			end,
			ltex_delete = function(picker)
				local item = picker:current()
				if not item then return end
				ui:delete_item(item)
				for i, v in ipairs(picker.opts.items) do
					if v == item then
						table.remove(picker.opts.items, i)
						break
					end
				end
				picker:refresh()
			end,
			ltex_cleanup = function(picker)
				picker.opts.items = ui:cleanup_items(picker.opts.items)
				picker:refresh()
			end,
			ltex_goto = function(picker)
				local item = picker:current()
				if not item then return end
				picker:close()
				ui:goto_item(item)
			end,
		},
		on_close = function()
			ui:show_diags()
		end,
		win = {
			input = {
				keys = {
					[opts.keys.modify] = { "ltex_modify", mode = { "n", "i" } },
				},
			},
			list = { keys = list_keys },
		},
	}))
end

return M
