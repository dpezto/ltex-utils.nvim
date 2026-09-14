local Config = require("ltex-utils.config")
local table_utils = require("ltex-utils.table_utils")
local uv = vim.uv

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
---from VimLeavePre still complete before Neovim exits.
---@param filepath string path to target file
---@param data string data to write
---@param callback function|nil function to be executed after writing
---@return boolean success
---@return string|nil error
function M.write(filepath, data, callback)
	-- Preserve symlinks (for example dictionaries managed with dotfiles).
	local link = uv.fs_lstat(filepath)
	if link and link.type == "link" then
		local target, err = uv.fs_realpath(filepath)
		if not target then
			vim.notify("Error resolving " .. filepath .. ": " .. tostring(err), ERROR)
			return false, err
		end
		filepath = target
	end
	-- Keep the temporary file beside its destination so rename is atomic.
	local fd, temporary_or_err = uv.fs_mkstemp(filepath .. ".XXXXXX")
	local temporary = fd and temporary_or_err or nil
	local function fail(err)
		if fd then uv.fs_close(fd) end
		if temporary then uv.fs_unlink(temporary) end
		local message = "Error writing " .. filepath .. ": " .. tostring(err)
		vim.notify(message, ERROR)
		return false, message
	end
	if not fd then return fail(temporary_or_err) end

	local stat = uv.fs_stat(filepath)
	if stat then
		local ok, err = uv.fs_fchmod(fd, stat.mode)
		if not ok then return fail(err) end
	end
	local written, write_err = uv.fs_write(fd, data, 0)
	if written ~= #data then return fail(write_err or "short write") end
	local synced, sync_err = uv.fs_fsync(fd)
	if not synced then return fail(sync_err) end
	local closed, close_err = uv.fs_close(fd)
	fd = nil
	if not closed then return fail(close_err) end
	local renamed, rename_err = uv.fs_rename(temporary, filepath)
	if not renamed then return fail(rename_err) end
	if callback then callback() end
	return true
end

---@param lang string
---@param bufnr? integer
---@return string
function M.dictionary_filename(lang, bufnr)
	return Config.dictionary.path .. Config.dictionary.filename(lang, bufnr)
end

---Combine languages that share one file, retaining empty dictionaries for deletion.
function M.group_dictionaries(dictionaries, bufnr)
	local files = {}
	for lang, words in pairs(dictionaries) do
		local filename = M.dictionary_filename(lang, bufnr)
		files[filename] = table_utils.merge_lists_unique(files[filename], words)
	end
	return files
end

---Merge dictionaries into their saved files, once per destination.
---@return string[]|nil languages
---@return string|nil error
function M.update_dictionary_files(dictionaries, bufnr)
	for filename, dict in pairs(M.group_dictionaries(dictionaries, bufnr)) do
		local saved_dict, read_err = M.read_dictionary(filename)
		if read_err and read_err:sub(1, 6) ~= "ENOENT" then
			vim.notify(read_err, ERROR)
			return nil, read_err
		end
		dict = table_utils.merge_lists_unique(dict, saved_dict)
		local ok, err = M.write(filename, table.concat(dict, "\n") .. "\n")
		if not ok then return nil, err end
	end
	return vim.tbl_keys(dictionaries)
end

---Loads the dictionaries at `Config.dictionary.path` for languages `langs`.
---@param langs string[] List of language identifiers
---@return table<string, string[]>
function M.load_dictionaries(langs, bufnr)
	---@type table<string, string[]>
	local server_dics = {}
	for _, lang in ipairs(langs) do
		---@type string[]|nil, string|nil
		local dict, err = M.read_dictionary(
			M.dictionary_filename(lang, bufnr)
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
