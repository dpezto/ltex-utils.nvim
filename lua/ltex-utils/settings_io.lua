local Config = require("ltex-utils.config")
local table_utils = require("ltex-utils.table_utils")
local uv = vim.loop

---@class vim.file

local M = {}

-- use local variables to safe lookup costs
local ERROR = vim.log.levels.ERROR

---Reads file at `filename` and returns its contents as a string
---@param filename string
---@return string|nil
---@return nil|string
local function read(filename)
	---@type integer|nil, nil|string
	local fd, err_open = uv.fs_open(filename, "r", 438) -- 438 = 0o666
--	---@type vim.file|nil, string|nil
--	local fd, err_open = uv.fs_open(filename, "r", 420)  -- 420 = 0o644
	if err_open then
		return nil, err_open
	end

	-- Get the file size
	---@type table|nil, nil|string
	local stat, err_stat = uv.fs_fstat(fd)
	if err_stat then
		uv.fs_close(fd)
		return nil, err_stat
	end

	---@cast stat table
	---@type integer
	local file_size = stat.size or 0

	-- Read the contents of the file
	---@type string|nil, nil|string
	local data, err_read = uv.fs_read(fd, file_size, 0)
	if err_read then
		uv.fs_close(fd)
		return nil, err_read
	end

	uv.fs_close(fd)

	return data, nil
end

---Reads a dictionary file where each word is on a separate line.
---Notice that dictionaries end with an emtpy newline.
---@param filename string
---@return string[]|nil
---@return nil|string
function M.read_dictionary(filename)
	local data, err = read(filename)

	if err then
		return nil, err
	end

-------------------------------------------------------------------------------
	---Delete this eventually. Only there to simplify switch to new
	---dictionary file format.
	---@cast data string
	local ok_json, contents_json = pcall(vim.json.decode, data)
	if ok_json and type(contents_json) == "table" then
		return contents_json, nil
	end
-------------------------------------------------------------------------------

	---@cast data string
	local dict = vim.split(vim.trim(data), "\n")
	if dict[#dict] == "" then
		table.remove(dict, #dict)
	end

	return dict, nil
end

 ---Reads and decodes a JSON file.
 ---@param filename string name (path) of the file to be read an decoded
 ---@return table|nil # returns decoded content if successful; `nil` when an error occurs
 ---@return nil|string # respective error message or nil if successful
function M.read_settings(filename)
	local contents, err = read(filename)
	if err then
		return nil, err
	end

	---@cast contents string
	---@type boolean, table|string|nil
	local ok_decode, contents_json = pcall(vim.json.decode, contents)
	if not ok_decode then
		-- In this case, `contents_json` holds the error message.
		---@cast contents_json string
		return nil, contents_json
	end

	---@cast contents_json table
	return contents_json, nil
end

---Writes `data` to file at `filepath`. Synchronous so that writes triggered
---from BufUnload still complete before Neovim exits.
---@param filepath string path to target file
---@param data string data to write
---@param callback function|nil function to be executed after writing
function M.write(filepath, data, callback)
	---@type integer|nil, nil|string
	local fd, err_open = uv.fs_open(filepath, "w", 438) -- 438 = 0o666
	if not fd then
		vim.notify("Error opening file: " .. tostring(err_open), ERROR)
		return
	end

	---@type integer|nil, nil|string
	local _, err_write = uv.fs_write(fd, data, -1)
	if err_write then
		vim.notify("Error writing to file: " .. vim.inspect(err_write), ERROR)
	end

	uv.fs_close(fd)

	if callback then
		callback()
	end
end

---Check if the folder exists and create it if not
---@param path string
---@return string|nil
function M.ensure_folder_exists(path)
	---@type table|nil, string|nil
	local folder_stat, err_stat = uv.fs_stat(path)
	-- If there's an error and the folder does not exist, create it
	if not folder_stat and err_stat then
		---@type boolean|nil, string|nil
		local ok, err = uv.fs_mkdir(path, 448) -- octal representation of the permission bits (0700)
		if not ok then
			-- Handle any error during folder creation
			vim.notify("Error creating folder: " .. vim.inspect(err), ERROR)
			return err
		end
	end
	-- If no error, the folder exists or has been created successfully
	return nil
end

---Updates language-specific dictionary files avoiding duplicates.
---@param dictionaries table<string, string[]> Table with language keys and associated word lists.
---@return string[] # A list of languages that have been updated.
function M.update_dictionary_files(dictionaries)
	---@type string[]
	local used_langs = {}
	for lang, dict in pairs(dictionaries) do
		---@type string
		local filename = Config.dictionary.path ..
											Config.dictionary.filename(lang)
		---@type string[]|nil
		local saved_dict = M.read_dictionary(filename)
		-- if there is already a saved dictionary merge it with current one
		if saved_dict then
			dict = table_utils.merge_lists_unique(dict, saved_dict)
		end
		M.write(filename, table.concat(dict, "\n") .. "\n")
		table.insert(used_langs, lang)
	end

	return used_langs
end

---Loads the dictionaries at `Config.dictionary.path` for languages `langs`.
---@param langs string[] List of language identifiers
---@return table<string, string[]>
function M.load_dictionaries(langs)
	---@type table<string, string[]>
	local server_dics = {}
	for _, lang in ipairs(langs) do
		---@type string[]|nil, string|nil
		local dict, err = M.read_dictionary(
			Config.dictionary.path .. Config.dictionary.filename(lang)
		)
		if err then
			if string.sub(err, 1, 6) ~= 'ENOENT' then
				-- if error, update user about problem and continue
				-- loading remaining dictionaries
				vim.notify("Error loading dicitonary: " .. err, ERROR)
			end
		else
			server_dics[lang] = dict
		end
	end

	return server_dics
end

return M
