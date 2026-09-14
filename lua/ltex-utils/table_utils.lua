local M = {}

---Merges two input lists into one, removing any duplicates.
---@param list1 string[]|nil
---@param list2 string[]|nil
---@return string[]
function M.merge_lists_unique(list1, list2)
	-- Create a table to store the unique elements
	---@type table<string, boolean>
	local unique_elements = {}

	-- not `ipairs({ list1, list2 })`: that stops at index 1 when list1 is nil
	for _, list in pairs({ list1, list2 }) do
		for _, element in ipairs(list) do
			unique_elements[element] = true
		end
	end

	---@type string[]
	local res = vim.tbl_keys(unique_elements)
	-- keep dictionary files stable across writes
	table.sort(res)
	return res
end

return M
