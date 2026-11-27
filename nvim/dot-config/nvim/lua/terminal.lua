-- Minimal Oil-style Same-Window Persistent Terminals
--
-- Keybindings:
--   <leader>tt  (n)    Toggle persistent repo-root terminal in current window
--   <leader>td  (n)    Toggle persistent subproject (.git) terminal in current window
--   <leader>tn  (n)    Open a new terminal buffer in current window
--   <C-/>       (n, t) Instant 1-key flip between code buffer and last active terminal

local M = {}

local state = {
  root_term_buf = nil,        -- Persistent terminal buffer at $ANDROID_BUILD_TOP (or initial cwd)
  dir_term_bufs = {},         -- Map: git_dir -> persistent terminal bufnr
  last_term_buf = nil,        -- Most recently active terminal bufnr (for <C-/>)
  last_code_buf = nil,        -- Most recently active non-terminal code bufnr
}

local function is_valid_term(buf)
  return buf ~= nil
    and vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buftype == "terminal"
end

local function is_valid_code_buf(buf)
  if buf == nil or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  if vim.bo[buf].buftype ~= "" then
    return false
  end
  local name = vim.api.nvim_buf_get_name(buf)
  return not vim.startswith(name, "term://")
end

local function record_current_if_code()
  local cur = vim.api.nvim_get_current_buf()
  if is_valid_code_buf(cur) then
    state.last_code_buf = cur
  end
end

local function return_to_code()
  if is_valid_code_buf(state.last_code_buf) then
    vim.api.nvim_set_current_buf(state.last_code_buf)
    return
  end
  -- Fallback: find most recent listed non-terminal buffer
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if vim.api.nvim_buf_is_valid(info.bufnr) and vim.bo[info.bufnr].buftype ~= "terminal" then
      vim.api.nvim_set_current_buf(info.bufnr)
      return
    end
  end
  vim.cmd("enew")
end

local function open_or_switch_term(existing_buf, cwd, title)
  record_current_if_code()
  if is_valid_term(existing_buf) then
    vim.api.nvim_set_current_buf(existing_buf)
    state.last_term_buf = existing_buf
    vim.cmd("startinsert")
    return existing_buf
  end

  local saved_code = state.last_code_buf
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.fn.jobstart(vim.o.shell, { cwd = cwd, term = true })
  if title then
    pcall(vim.api.nvim_buf_set_name, buf, title)
  end
  state.last_code_buf = saved_code
  state.last_term_buf = buf
  vim.cmd("startinsert")
  return buf
end

local function resolve_repo_root()
  local buf = is_valid_code_buf(state.last_code_buf) and state.last_code_buf or 0
  local name = vim.api.nvim_buf_get_name(buf)
  local start = name ~= "" and name or vim.fn.getcwd()
  return vim.fs.root(start, ".repo") or vim.fn.getcwd()
end

local function resolve_subproject_dir()
  local cur = vim.api.nvim_get_current_buf()
  local ref_buf = vim.bo[cur].buftype ~= "terminal" and cur
    or (is_valid_code_buf(state.last_code_buf) and state.last_code_buf or cur)
  local name = vim.api.nvim_buf_get_name(ref_buf)
  if name == "" then
    return vim.fn.getcwd()
  end
  return vim.fs.root(name, ".git") or vim.fn.fnamemodify(name, ":p:h")
end

-- <leader>tt: Toggle main repo-root terminal in same window
function M.toggle_root_term()
  local cur = vim.api.nvim_get_current_buf()
  if vim.bo[cur].buftype == "terminal" and cur == state.root_term_buf then
    return_to_code()
    return
  end
  local cwd = resolve_repo_root()
  state.root_term_buf = open_or_switch_term(
    state.root_term_buf,
    cwd,
    "term://root (" .. vim.fn.fnamemodify(cwd, ":t") .. ")"
  )
end

-- <leader>td: Toggle current buffer's git-subproject terminal in same window
function M.toggle_dir_term()
  local cur = vim.api.nvim_get_current_buf()
  local dir = resolve_subproject_dir()
  local existing = state.dir_term_bufs[dir]
  if vim.bo[cur].buftype == "terminal" and cur == existing then
    return_to_code()
    return
  end
  local buf = open_or_switch_term(
    existing,
    dir,
    "term://subproject (" .. vim.fn.fnamemodify(dir, ":t") .. ")"
  )
  state.dir_term_bufs[dir] = buf
end

-- <leader>tn: Open a fresh terminal buffer in same window
function M.new_term()
  local cwd = resolve_repo_root()
  open_or_switch_term(nil, cwd, nil)
end

-- <C-/>: Instant flip between code and last active terminal (creates root terminal if none yet)
function M.quick_flip()
  local cur = vim.api.nvim_get_current_buf()
  if vim.bo[cur].buftype == "terminal" then
    state.last_term_buf = cur
    vim.cmd("stopinsert")
    return_to_code()
    return
  end
  if is_valid_term(state.last_term_buf) then
    record_current_if_code()
    vim.api.nvim_set_current_buf(state.last_term_buf)
    vim.cmd("startinsert")
    return
  end
  M.toggle_root_term()
end

-- Run an arbitrary command (e.g. sdv_test) in a same-window terminal while preserving flip-back state
function M.run_cmd_same_window(cmd, cwd, title)
  record_current_if_code()
  local saved_code = state.last_code_buf
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.fn.jobstart(cmd, { cwd = cwd, term = true })
  if title then
    pcall(vim.api.nvim_buf_set_name, buf, title)
  end
  state.last_code_buf = saved_code
  state.last_term_buf = buf
  vim.cmd("startinsert")
  return buf
end

-- Track non-terminal buffers & configure clean terminal buffer defaults (including AOSP gF path resolution)
local grp = vim.api.nvim_create_augroup("sdv-same-win-term", { clear = true })

vim.api.nvim_create_autocmd("BufEnter", {
  group = grp,
  callback = function(ev)
    if is_valid_code_buf(ev.buf) and vim.bo[ev.buf].buflisted and vim.api.nvim_buf_get_name(ev.buf) ~= "" then
      state.last_code_buf = ev.buf
    elseif vim.bo[ev.buf].buftype == "terminal" then
      state.last_term_buf = ev.buf
    end
  end,
})

vim.api.nvim_create_autocmd("TermOpen", {
  group = grp,
  callback = function(ev)
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn = "no"
    -- Allow `gf` / `gF` in terminal Normal mode to resolve AOSP repo-relative paths!
    local aosp = vim.fs.root(vim.fn.getcwd(), ".repo")
    if aosp then
      vim.opt_local.path:prepend(aosp)
    end
    state.last_term_buf = ev.buf
  end,
})

-- Keybindings
vim.keymap.set("n", "<leader>tt", M.toggle_root_term, { desc = "Toggle repo-root terminal (same window)" })
vim.keymap.set("n", "<leader>td", M.toggle_dir_term, { desc = "Toggle subproject .git terminal (same window)" })
vim.keymap.set("n", "<leader>tn", M.new_term, { desc = "New terminal buffer (same window)" })

-- Bind both <C-/> and <C-_> (what tmux / xterm terminals emit on Ctrl + /)
for _, lhs in ipairs({ "<C-/>", "<C-_>" }) do
  vim.keymap.set({ "n", "t" }, lhs, M.quick_flip, { desc = "Flip between code & terminal" })
end

return M
