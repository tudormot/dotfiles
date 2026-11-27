-- Core Neovim Options & Editor Keymaps

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 250
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
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR><Esc>", { silent = true })

-- Exit terminal mode into Terminal-Normal mode with Ctrl+Space
-- (bind both <C-Space> and <C-@> for tmux/xterm compatibility)
for _, lhs in ipairs({ "<C-Space>", "<C-@>" }) do
  vim.keymap.set("t", lhs, [[<C-\><C-n>]], { desc = "Exit terminal mode" })
end

-- Seamless window / tmux pane navigation with Ctrl-h/j/k/l
local function smart_split_nav(dir, tmux_flag)
  return function()
    local cur_win = vim.api.nvim_get_current_win()
    vim.cmd.wincmd(dir)
    if vim.api.nvim_get_current_win() == cur_win and vim.env.TMUX then
      vim.system({ "tmux", "select-pane", tmux_flag })
    end
  end
end

for _, nav in ipairs({
  { lhs = "<C-h>", dir = "h", flag = "-L", label = "left" },
  { lhs = "<C-j>", dir = "j", flag = "-D", label = "lower" },
  { lhs = "<C-k>", dir = "k", flag = "-U", label = "upper" },
  { lhs = "<C-l>", dir = "l", flag = "-R", label = "right" },
}) do
  vim.keymap.set("n", nav.lhs, smart_split_nav(nav.dir, nav.flag), {
    desc = "Move to " .. nav.label .. " split / tmux pane",
  })
  -- Work from Neovim shell terminals too, while keeping Ctrl-j/k intact inside fzf-lua
  vim.keymap.set("t", nav.lhs, function()
    if vim.bo.filetype == "fzf" then
      return nav.lhs
    end
    vim.schedule(function()
      vim.cmd("stopinsert")
      smart_split_nav(nav.dir, nav.flag)()
    end)
    return ""
  end, {
    expr = true,
    desc = "Move to " .. nav.label .. " split / tmux pane",
  })
end

-- Move by visual lines
vim.keymap.set("n", "j", "gj")
vim.keymap.set("n", "k", "gk")

-- Stay in visual mode after indenting
vim.keymap.set("v", "<", "<gv")
vim.keymap.set("v", ">", ">gv")

-- Highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Highlight when yanking text",
  group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
  callback = function()
    vim.highlight.on_yank({ timeout = 500 })
  end,
})
