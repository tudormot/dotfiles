-- Neovim Version Lock
local expected_version = { major = 0, minor = 12, patch = 4 }
local v = vim.version()
if v.major ~= expected_version.major or v.minor ~= expected_version.minor or v.patch ~= expected_version.patch then
  vim.api.nvim_err_writeln(string.format(
    "Error: Neovim version mismatch!\nExpected: %d.%d.%d\nRunning: %d.%d.%d",
    expected_version.major, expected_version.minor, expected_version.patch,
    v.major, v.minor, v.patch
  ))
end

vim.g.mapleader = " "
vim.g.maplocalleader = ","

-- Ensure ~/.local/bin (where sdv-tools / sdv_* live) is on PATH
local local_bin = vim.fn.expand("~/.local/bin")
if not string.find(":" .. (vim.env.PATH or "") .. ":", ":" .. local_bin .. ":", 1, true) then
  vim.env.PATH = local_bin .. ":" .. (vim.env.PATH or "")
end

require("options")
require("filetypes")

-- Force git to use standard 'files' ref format (avoiding 'reftable' format issue with lazy.nvim)
vim.env.GIT_CONFIG_PARAMETERS = "'init.defaultRefFormat'='files'"

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "-c",
    "init.defaultRefFormat=files",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup(require("plugins"), {
  change_detection = { notify = false },
})

require("lsp")
require("terminal")
require("sdv")
