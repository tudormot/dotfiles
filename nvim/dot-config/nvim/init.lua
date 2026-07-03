-- Neovim Version Lock
local expected_version = { major = 0, minor = 11, patch = 6 }
local v = vim.version()
if v.major ~= expected_version.major or v.minor ~= expected_version.minor or v.patch ~= expected_version.patch then
  vim.api.nvim_err_writeln(string.format(
    "Error: Neovim version mismatch!\nExpected: %d.%d.%d\nRunning: %d.%d.%d",
    expected_version.major, expected_version.minor, expected_version.patch,
    v.major, v.minor, v.patch
  ))
end

vim.g.mapleader = " "

-- General Settings
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.showcmd = true
vim.opt.wildmenu = true
vim.opt.showmatch = true
vim.opt.hidden = true
vim.opt.scrolloff = 8
vim.opt.clipboard = "unnamedplus"

-- Search
vim.opt.incsearch = true
vim.opt.hlsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Indentation
vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.autoindent = true

-- List chars
vim.opt.list = true
vim.opt.listchars = { tab = "» ", trail = "°" }

-- Clear search highlight
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR><Esc>', { silent = true })

-- Exit insert mode
vim.keymap.set('i', 'jj', '<Esc>')
vim.keymap.set('i', 'jk', '<Esc>')

-- Window navigation
vim.keymap.set('n', '<C-h>', '<C-w>h')
vim.keymap.set('n', '<C-j>', '<C-w>j')
vim.keymap.set('n', '<C-k>', '<C-w>k')
vim.keymap.set('n', '<C-l>', '<C-w>l')

-- Move by visual lines
vim.keymap.set('n', 'j', 'gj')
vim.keymap.set('n', 'k', 'gk')

-- Stay in visual mode after indenting
vim.keymap.set('v', '<', '<gv')
vim.keymap.set('v', '>', '>gv')

vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking text',
  group = vim.api.nvim_create_augroup('highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank({ timeout = 500 })
  end,
})

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Configure Plugins
require("lazy").setup({
  -- Icons (needed for Oil and FZF)
  { "nvim-tree/nvim-web-devicons" },

  -- Oil.nvim (File Explorer)
  {
    'stevearc/oil.nvim',
    opts = {},
    config = function()
      require("oil").setup()
      -- Open parent directory with `-`
      vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })
    end
  },

  -- FZF Lua (Replacing FZF.vim)
  {
    "ibhagwan/fzf-lua",
    config = function()
      local fzf = require("fzf-lua")
      vim.keymap.set("n", "<leader>f", fzf.files, { desc = "Fzf Files" })
      vim.keymap.set("n", "<leader>b", fzf.buffers, { desc = "Fzf Buffers" })
      vim.keymap.set("n", "<leader>g", fzf.live_grep, { desc = "Fzf Live Grep" })
      vim.keymap.set("n", "<leader>t", fzf.tags, { desc = "Fzf Tags" })
    end
  },

  -- OSC52 Yank (Replacing vim-oscyank)
  {
    'ojroques/nvim-osc52',
    config = function()
      require('osc52').setup({
        max_length = 0,      -- Maximum length of selection (0 for no limit)
        silent = false,      -- Disable message on successful copy
        trim = false,        -- Trim surrounding whitespaces before copy
      })
      -- Map yank to OSC52
      local function copy()
        if vim.v.event.operator == 'y' and vim.v.event.regname == '' then
          require('osc52').copy_register('')
        end
      end
      vim.api.nvim_create_autocmd('TextYankPost', { callback = copy })
    end
  },

  -- Treesitter for syntax highlighting
  {
    "nvim-treesitter/nvim-treesitter",
    branch = vim.fn.has("nvim-0.12") == 1 and "main" or "master", -- Dynamic branch based on Nvim version
    build = ":TSUpdate",
    main = "nvim-treesitter.configs",
    opts = {
      ensure_installed = {
        "c",
        "cpp",
        "rust",
        "python",
        "markdown",
        "markdown_inline",
        "proto",
        "textproto",
      },
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
      },
      indent = { enable = true },
    },
  },
})
