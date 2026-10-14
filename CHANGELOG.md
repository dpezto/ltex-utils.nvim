# Changelog

## 1.0.0 (2026-10-14)


### Features

* **pickers:** add mini.pick backend ([083de81](https://github.com/dpezto/ltex-utils.nvim/commit/083de813ab51ddf74102f87c72fbe1670ad225c5))
* **pickers:** add telescope.nvim backend ([3a851dd](https://github.com/dpezto/ltex-utils.nvim/commit/3a851dd49e8dd0ff7de2806c6722e96795058366))
* replace telescope with multi-backend picker abstraction ([d9b203f](https://github.com/dpezto/ltex-utils.nvim/commit/d9b203fffbcd9fa21112969593e06cc2bb167f9e))


### Bug Fixes

* **cache:** don't rely on pairs() iteration order in apply_cache ([f44c6a4](https://github.com/dpezto/ltex-utils.nvim/commit/f44c6a4f04df08471602223632d1e3f6d1f720dd))
* **config:** handle region-less languages and empty fileencoding ([b67e8b8](https://github.com/dpezto/ltex-utils.nvim/commit/b67e8b8782b543863c7a0153f6449c3c27a1ae44))
* correctness and performance fixes ([#1](https://github.com/dpezto/ltex-utils.nvim/issues/1)) ([986f261](https://github.com/dpezto/ltex-utils.nvim/commit/986f261e19a3173e182a8531b3790a777f9abd93))
* dictionary path separator, list merging, and missing warnings ([4050fa5](https://github.com/dpezto/ltex-utils.nvim/commit/4050fa580e3a2862dffe380da20ecc714c699fdc))
* **io:** harden file error paths ([9a92632](https://github.com/dpezto/ltex-utils.nvim/commit/9a926327b75255884a9fd5d02bbf2ad3ae5df1eb))
* **io:** write settings and dictionary files synchronously ([c63174e](https://github.com/dpezto/ltex-utils.nvim/commit/c63174e1c14ab7f971ad0a2e62d99727599e21d4))
* keep rules per document on a shared client, write shared dictionary files once ([b2f857a](https://github.com/dpezto/ltex-utils.nvim/commit/b2f857aa1ce09ad7e286af2e132baf4b251d50eb))
* load dictionaries for documents without a settings file ([96a95cf](https://github.com/dpezto/ltex-utils.nvim/commit/96a95cf1f1870c284075d50f317f8a2916480094))
* load settings for the attaching buffer, not the current one ([dce201c](https://github.com/dpezto/ltex-utils.nvim/commit/dce201ca0dbe36ab2b82e324a1054fb55e5ee3bf))
* **lsp:** don't stall the rule picker on empty diagnostics or nil actions ([1d456bc](https://github.com/dpezto/ltex-utils.nvim/commit/1d456bc5e55360bc6ee18dc521bef53da89cb86a))
* **lsp:** harden rule inspection against failed requests and missing diagnostics ([649d8d7](https://github.com/dpezto/ltex-utils.nvim/commit/649d8d7149634b5fbd2c506eed34425e0ea1e7c1))
* **lsp:** keep initialized ltex settings table attached to the client ([8939b1e](https://github.com/dpezto/ltex-utils.nvim/commit/8939b1ed24c25618384cca39903151893f38fbba))
* **lsp:** use method-form client calls and a single debounce timer ([7789cdc](https://github.com/dpezto/ltex-utils.nvim/commit/7789cdc25953f0a6b32161cb54a104733c892b87))
* **pickers:** clear update_flag before the mini picker closes ([913fa06](https://github.com/dpezto/ltex-utils.nvim/commit/913fa06b4ff551389ee7c716c2164a85ad759dbd))
* prefix settings filename with dot to hide by default ([2f65e1c](https://github.com/dpezto/ltex-utils.nvim/commit/2f65e1cbca56e1d1259140eb2d674f641002a0a9))
* report unknown :LTeXUtils subcommands instead of erroring ([4929886](https://github.com/dpezto/ltex-utils.nvim/commit/49298867371ba8a22e03824941131f258255a0b1))
* **rule_ui:** pass a 0-based column to nvim_win_set_cursor ([ca841fe](https://github.com/dpezto/ltex-utils.nvim/commit/ca841feb3923399feec284d0cb0b4a6e9968307d))
* **rule_ui:** replace plenary.popup with a native float ([bfa161b](https://github.com/dpezto/ltex-utils.nvim/commit/bfa161b60871e342cef9148b005be53e1a20e247))
* save settings on LspDetach instead of BufUnload ([5031a72](https://github.com/dpezto/ltex-utils.nvim/commit/5031a72779d27b972622e2eced47f3b493958b53))
* save settings on VimLeavePre, LspDetach never fires on quit ([9a2087d](https://github.com/dpezto/ltex-utils.nvim/commit/9a2087d0dc3936a333d799857d64ef41041c3cf4))
* scope TelescopePreviewerLoaded autocmd to the LTeXUtils augroup ([d254240](https://github.com/dpezto/ltex-utils.nvim/commit/d25424060b9a0a81983285e2b0a4e210677e7a49))
* scope the autocommands to the attached buffer ([5143c1a](https://github.com/dpezto/ltex-utils.nvim/commit/5143c1ac5b150f9b70f532c86e2ca6b195bfccaa))
* write files atomically and propagate write errors ([bb36cdb](https://github.com/dpezto/ltex-utils.nvim/commit/bb36cdbabe6c78d24e1b72aa61375b4841da1cd0))
