-- SDV / AAOS Monorepo Integration (2-Tier Search, sdv_build Quickfix, sdv_runtime test, & sdv_status)

local M = {}

local dirs_cache = {}

function M.current_aosp_root()
  local bufname = vim.api.nvim_buf_get_name(0)
  local start = bufname ~= "" and bufname or vim.fn.getcwd()
  return vim.fs.root(start, ".repo")
end

function M.get_sdv_dirs(aosp_root)
  if dirs_cache[aosp_root] then
    return dirs_cache[aosp_root]
  end
  local res = vim.system(
    { "sdv_learn", "sdv-dirs", "--relative", "--repo", aosp_root },
    { text = true }
  ):wait()
  if res.code == 0 and res.stdout then
    local dirs = {}
    for line in res.stdout:gmatch("[^\r\n]+") do
      if line ~= "" then
        table.insert(dirs, line)
      end
    end
    if #dirs > 0 then
      dirs_cache[aosp_root] = dirs
      return dirs
    end
  end
  return nil
end

-- Tier 1 Search: Curated SDV + AAOS directories inside AOSP (or normal cwd outside AOSP)
function M.tier1_files()
  local fzf = require("fzf-lua")
  local root = M.current_aosp_root()
  if not root then
    return fzf.files()
  end
  local dirs = M.get_sdv_dirs(root)
  if not dirs then
    return fzf.files({ cwd = root })
  end
  return fzf.files({
    cwd = root,
    search_paths = dirs,
    prompt = "SDV+AAOS Files> ",
  })
end

function M.tier1_grep()
  local fzf = require("fzf-lua")
  local root = M.current_aosp_root()
  if not root then
    return fzf.live_grep()
  end
  local dirs = M.get_sdv_dirs(root)
  if not dirs then
    return fzf.live_grep({ cwd = root })
  end
  return fzf.live_grep({
    cwd = root,
    search_paths = dirs,
    prompt = "SDV+AAOS Grep> ",
  })
end

-- Tier 2 Search: Full AOSP checkout (excluding out*, .repo, prebuilts)
local AOSP_EXCLUDE_FD = "--type f --exclude '.repo' --exclude 'out*' --exclude 'prebuilts'"
local AOSP_EXCLUDE_RG = "--column --line-number --no-heading --color=always --smart-case "
  .. "-g '!.repo/**' -g '!out*/**' -g '!prebuilts/**'"

function M.tier2_aosp_files()
  local fzf = require("fzf-lua")
  local root = M.current_aosp_root()
  if not root then
    return fzf.files()
  end
  return fzf.files({
    cwd = root,
    fd_opts = AOSP_EXCLUDE_FD,
    prompt = "All AOSP Files> ",
  })
end

function M.tier2_aosp_grep()
  local fzf = require("fzf-lua")
  local root = M.current_aosp_root()
  if not root then
    return fzf.live_grep()
  end
  return fzf.live_grep({
    cwd = root,
    rg_opts = AOSP_EXCLUDE_RG,
    prompt = "All AOSP Grep> ",
  })
end

-- Async single-file module build/check via `sdv_build file` -> Quickfix
local function strip_ansi(s)
  return (s:gsub("\27%[[0-9;?]*[A-Za-z]", ""):gsub("\r", ""))
end

function M.build_current_file(check_only)
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then
    vim.notify("Buffer has no file path", vim.log.levels.WARN)
    return
  end
  local root = M.current_aosp_root()
  if not root then
    vim.notify("Current file is not inside an AOSP checkout", vim.log.levels.WARN)
    return
  end

  vim.cmd("silent! update")
  local cmd = { "sdv_build", "file", filepath }
  if check_only then
    table.insert(cmd, "--check")
  end
  local mode_label = check_only and "Checking" or "Building"
  vim.notify(mode_label .. " module for " .. vim.fn.fnamemodify(filepath, ":t") .. "...", vim.log.levels.INFO)

  vim.system(cmd, { cwd = root, text = true }, function(res)
    vim.schedule(function()
      local combined = strip_ansi((res.stdout or "") .. "\n" .. (res.stderr or ""))
      local lines = vim.split(combined, "\n", { trimempty = true })

      -- Parse standard rustc (`--> file:line:col`) and clang (`file:line:col: error:`) diagnostics
      local items = {}
      local pending_msg = nil
      for _, line in ipairs(lines) do
        local r_msg = line:match("^error[^:]*:%s*(.+)$") or line:match("^warning[^:]*:%s*(.+)$")
        if r_msg then
          pending_msg = line
        end
        local r_file, r_lnum, r_col = line:match("^%s*%-%->%s*([^:]+):(%d+):(%d+)")
        if r_file then
          table.insert(items, {
            filename = vim.startswith(r_file, "/") and r_file or (root .. "/" .. r_file),
            lnum = tonumber(r_lnum),
            col = tonumber(r_col),
            text = pending_msg or "Compiler diagnostic",
            type = (pending_msg and pending_msg:match("^warning")) and "W" or "E",
          })
          pending_msg = nil
        else
          local c_file, c_lnum, c_col, c_sev, c_txt =
            line:match("^([^:%s]+):(%d+):(%d+):%s*(error|warning):%s*(.+)$")
          if c_file then
            table.insert(items, {
              filename = vim.startswith(c_file, "/") and c_file or (root .. "/" .. c_file),
              lnum = tonumber(c_lnum),
              col = tonumber(c_col),
              text = c_txt,
              type = c_sev == "warning" and "W" or "E",
            })
          end
        end
      end

      if res.code == 0 then
        vim.fn.setqflist({}, " ", { title = "sdv_build", items = items })
        vim.cmd("cclose")
        vim.notify("sdv_build succeeded (" .. vim.fn.fnamemodify(filepath, ":t") .. ")", vim.log.levels.INFO)
      else
        if #items == 0 then
          for _, l in ipairs(lines) do
            table.insert(items, { text = l })
          end
        end
        vim.fn.setqflist({}, " ", { title = "sdv_build errors", items = items })
        vim.cmd("botright copen 12")
        vim.notify("sdv_build failed — see quickfix list", vim.log.levels.ERROR)
      end
    end)
  end)
end

-- Same-window terminal runner for `sdv_runtime test` (integrates with <C-/> flip-back)
function M.run_test(runner, extra_flags)
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then
    vim.notify("Buffer has no file path", vim.log.levels.WARN)
    return
  end
  local root = M.current_aosp_root() or vim.fn.getcwd()
  vim.cmd("silent! update")

  local cmd = { "sdv_runtime", "test", "-r", runner or "default" }
  if extra_flags then
    vim.list_extend(cmd, extra_flags)
  end
  table.insert(cmd, filepath)
  local title = "term://sdv_runtime test (" .. (runner or "default") .. ": " .. vim.fn.fnamemodify(filepath, ":t") .. ")"
  require("terminal").run_cmd_same_window(cmd, root, title)
end

function M.run_abtd_prompt()
  vim.ui.input({ prompt = "ABTD Gerrit CL number (leave empty for LKGB): " }, function(input)
    if input == nil then
      return
    end
    local flags = {}
    local trimmed = vim.trim(input)
    if trimmed ~= "" then
      flags = { "--cl", trimmed }
    end
    M.run_test("abtd", flags)
  end)
end

function M.pick_test_runner()
  local choices = {
    "default (local atest)",
    "atest (local atest)",
    "catbox (local CATBox plan)",
    "abtd (remote Forrest on LKGB)",
    "abtd with Gerrit CL",
    "dry-run: abtd command preview",
  }
  vim.ui.select(choices, { prompt = "Run sdv_runtime test with:" }, function(choice)
    if not choice then
      return
    end
    if vim.startswith(choice, "default") then
      M.run_test("default")
    elseif vim.startswith(choice, "atest") then
      M.run_test("atest")
    elseif vim.startswith(choice, "catbox") then
      M.run_test("catbox")
    elseif choice == "abtd (remote Forrest on LKGB)" then
      M.run_test("abtd")
    elseif choice == "abtd with Gerrit CL" then
      M.run_abtd_prompt()
    elseif vim.startswith(choice, "dry-run") then
      M.run_test("abtd", { "--dry-run" })
    end
  end)
end

-- Floating status viewer (`sdv_status` / `sdv_status --reconcile`)
local _status_win = nil
local _status_buf = nil

function M.show_status(reconcile)
  local root = M.current_aosp_root() or vim.fn.getcwd()
  local cmd = { "sdv_status" }
  if reconcile then
    table.insert(cmd, "--reconcile")
  end
  vim.notify(
    reconcile and "Reconciling sdv_status..." or "Querying sdv_status...",
    vim.log.levels.INFO
  )

  vim.system(cmd, { cwd = root, text = true }, function(res)
    vim.schedule(function()
      local raw = strip_ansi((res.stdout or "") .. (res.stderr and res.stderr ~= "" and ("\n" .. res.stderr) or ""))
      local lines = vim.split(vim.trim(raw), "\n", { plain = true })
      if #lines == 0 then
        lines = { "(no status output)" }
      end

      if _status_win and vim.api.nvim_win_is_valid(_status_win) then
        vim.api.nvim_win_close(_status_win, true)
      end
      local buf = vim.api.nvim_create_buf(false, true)
      _status_buf = buf
      vim.bo[buf].bufhidden = "wipe"
      vim.bo[buf].filetype = "markdown"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false

      local width = math.min(math.max(math.floor(vim.o.columns * 0.8), 60), 120)
      local height = math.min(math.max(#lines + 2, 10), math.floor(vim.o.lines * 0.75))
      local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
      local col = math.max(0, math.floor((vim.o.columns - width) / 2))

      _status_win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = reconcile and " sdv_status --reconcile (q:close, r:refresh, R:reconcile) "
          or " sdv_status (q:close, r:refresh, R:reconcile) ",
        title_pos = "center",
      })

      local function close_win()
        if _status_win and vim.api.nvim_win_is_valid(_status_win) then
          vim.api.nvim_win_close(_status_win, true)
        end
        _status_win = nil
      end

      vim.keymap.set("n", "q", close_win, { buffer = buf, silent = true, desc = "Close sdv_status" })
      vim.keymap.set("n", "<Esc>", close_win, { buffer = buf, silent = true, desc = "Close sdv_status" })
      vim.keymap.set("n", "r", function()
        M.show_status(false)
      end, { buffer = buf, silent = true, desc = "Refresh sdv_status" })
      vim.keymap.set("n", "R", function()
        M.show_status(true)
      end, { buffer = buf, silent = true, desc = "Reconcile sdv_status" })
    end)
  end)
end

-- Keybindings
vim.keymap.set("n", "<leader>f", M.tier1_files, { desc = "SDV+AAOS files (or cwd)" })
vim.keymap.set("n", "<leader>g", M.tier1_grep, { desc = "SDV+AAOS live grep (or cwd)" })
vim.keymap.set("n", "<leader>af", M.tier2_aosp_files, { desc = "All AOSP files" })
vim.keymap.set("n", "<leader>ag", M.tier2_aosp_grep, { desc = "All AOSP live grep" })

vim.keymap.set("n", "<leader>m", function()
  M.build_current_file(false)
end, { desc = "Build current file module (sdv_build)" })
vim.keymap.set("n", "<leader>M", function()
  M.build_current_file(true)
end, { desc = "Clippy/rustc check current file (sdv_build --check)" })

vim.keymap.set("n", "<leader>xt", function()
  M.run_test("default")
end, { desc = "Test current file (default = atest)" })
vim.keymap.set("n", "<leader>xc", function()
  M.run_test("catbox")
end, { desc = "Test current file (CATBox)" })
vim.keymap.set("n", "<leader>xa", M.run_abtd_prompt, { desc = "Test current file (ABTD)" })
vim.keymap.set("n", "<leader>xp", M.pick_test_runner, { desc = "Pick sdv_runtime test runner" })
vim.keymap.set("n", "<leader>xs", function()
  M.show_status(false)
end, { desc = "Show SDV deployment & build status" })

-- User Commands
vim.api.nvim_create_user_command("SdvBuild", function(opts)
  M.build_current_file(opts.bang)
end, { bang = true, desc = "Build current file's Soong module (:SdvBuild! for --check)" })

vim.api.nvim_create_user_command("SdvTest", function(opts)
  local runner = opts.args ~= "" and opts.args or "default"
  M.run_test(runner)
end, {
  nargs = "?",
  complete = function()
    return { "default", "atest", "catbox", "abtd" }
  end,
  desc = "Run sdv_runtime test on current file",
})

vim.api.nvim_create_user_command("SdvStatus", function(opts)
  M.show_status(opts.bang)
end, { bang = true, desc = "Show SDV status floating window (:SdvStatus! to --reconcile)" })

return M
