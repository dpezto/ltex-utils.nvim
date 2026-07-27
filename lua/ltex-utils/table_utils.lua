local M = {}

---Extends t1[key] with t2 if this key exists; otherwise sets t1[key]=t2.
---@param t1 table<string, string[]>
---@param key string
---@param t2 string[]
function M.extend_or_init(t1, key, t2)
  if t1[key] then
	  t1[key] = vim.list_extend(t1[key], t2)
  else
    t1[key] = t2
  end
end

---Merges two input lists into one, removing any duplicates.
---@param list1 string[]|nil
---@param list2 string[]|nil
---@return string[]
function M.merge_lists_unique(list1, list2)
	-- Create a table to store the unique elements
	---@type table<string, boolean>
	local unique_elements = {}

	for _, list in ipairs({ list1, list2 }) do
		if list then
			for _, element in ipairs(list) do
				unique_elements[element] = true
			end
		end
	end

	return vim.tbl_keys(unique_elements)
end

---Returns the largest index of a table with keys in the integers >= 1.
---This also needs to work if keys don't form a list of consecutive integers.
---@param tbl table<integer, any>
---@return integer
function M.max_index(tbl)
	---@type integer
	local max = 0
	for i, _ in pairs(tbl) do
		if i > max then
			max = i
		end
	end
	return max
end

return M
