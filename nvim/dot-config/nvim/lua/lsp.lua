-- Native Neovim 0.12 LSP Configuration (rust-analyzer & clangd)
-- Dynamically resolves in-tree AOSP prebuilts (matching Soong's sysroot toolchain) +
-- rust-project.json / compile_commands.json, watches repo roots to auto-attach / reload
-- after `sdv-tools build`, and surfaces zero-plugin LSP progress in the statusline.

local capabilities = vim.lsp.protocol.make_client_capabilities()
local ok_blink, blink = pcall(require, "blink.cmp")
if ok_blink then
  capabilities = blink.get_lsp_capabilities(capabilities)
end

local function find_latest_aosp_clang_tool(aosp_root, tool_name)
  local stable = aosp_root .. "/prebuilts/clang/host/linux-x86/clang-stable/bin/" .. tool_name
  if vim.fn.executable(stable) == 1 then
    return stable
  end
  local matches = vim.fn.glob(
    aosp_root .. "/prebuilts/clang/host/linux-x86/clang-r*/bin/" .. tool_name,
    true,
    true
  )
  table.sort(matches)
  for i = #matches, 1, -1 do
    if vim.fn.executable(matches[i]) == 1 then
      return matches[i]
    end
  end
  return tool_name
end

local function read_rust_project_sysroot(aosp_root)
  local rp_path = aosp_root .. "/rust-project.json"
  local fd = vim.uv.fs_open(rp_path, "r", 438)
  if not fd then
    return nil
  end
  -- `"sysroot"` appears at the start of Soong / sdv-tools rust-project.json
  local head = vim.uv.fs_read(fd, 1024, 0)
  vim.uv.fs_close(fd)
  if not head then
    return nil
  end
  local raw = head:match('"sysroot"%s*:%s*"([^"]+)"')
  if not raw or raw == "" then
    return nil
  end
  local norm = raw:gsub("//+", "/")
  if vim.startswith(norm, "/") then
    return norm
  end
  return aosp_root .. "/" .. norm
end

local function resolve_aosp_rust_analyzer(aosp_root)
  if aosp_root then
    local sysroot = read_rust_project_sysroot(aosp_root)
    if sysroot then
      local sysroot_ra = sysroot .. "/bin/rust-analyzer"
      if vim.fn.executable(sysroot_ra) == 1 then
        return sysroot_ra
      end
    end
    local stable_ra = aosp_root .. "/prebuilts/rust-toolchain/linux-x86/stable/rust-analyzer"
    if vim.fn.executable(stable_ra) == 1 then
      return stable_ra
    end
  end
  return "rust-analyzer"
end

local function build_ra_settings(root)
  if root and vim.uv.fs_stat(root .. "/.repo") then
    return {
      linkedProjects = { root .. "/rust-project.json" },
      checkOnSave = false,
      cachePriming = { enable = false },
      rustfmt = {
        extraArgs = {
          "--config-path=" .. root .. "/build/soong/scripts/rustfmt.toml",
        },
      },
      diagnostics = {
        disabled = {
          "unresolved-proc-macro",
          "unresolved-extern-crate",
          "inactive-code",
        },
      },
      files = {
        watcher = "client",
        excludeDirs = {
          ".repo",
          "out",
        },
      },
    }
  end
  return {
    check = { command = "clippy" },
  }
end

-- Track active LspProgress tokens per client id for zero-plugin statusline & `gd` hints
local active_progress = {} -- client_id -> { [token] = { title = ..., message = ..., percentage = ... } }

local function client_busy_summary(client_id)
  local map = active_progress[client_id]
  if not map then
    return nil
  end
  for _, item in pairs(map) do
    local parts = { item.title or "indexing" }
    if item.message and item.message ~= "" then
      table.insert(parts, item.message)
    end
    if item.percentage then
      table.insert(parts, string.format("%d%%", item.percentage))
    end
    return table.concat(parts, " ")
  end
  return nil
end

function _G.sdv_lsp_status()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients == 0 then
    return ""
  end
  local parts = {}
  for _, c in ipairs(clients) do
    local busy = client_busy_summary(c.id)
    if busy then
      table.insert(parts, c.name .. ": " .. busy)
    else
      table.insert(parts, c.name)
    end
  end
  return "[" .. table.concat(parts, " | ") .. "]"
end

vim.opt.statusline = " %f %m%r%h%w %= %{v:lua.sdv_lsp_status()}  %y  %l:%c  %p%% "

local progress_grp = vim.api.nvim_create_augroup("sdv-lsp-progress", { clear = true })

vim.api.nvim_create_autocmd("LspProgress", {
  group = progress_grp,
  callback = function(ev)
    local cid = ev.data and ev.data.client_id
    local params = ev.data and ev.data.params
    if not cid or not params or params.token == nil or type(params.value) ~= "table" then
      return
    end
    local tok = tostring(params.token)
    local val = params.value
    active_progress[cid] = active_progress[cid] or {}
    if val.kind == "begin" then
      active_progress[cid][tok] = {
        title = val.title or tok,
        message = val.message,
        percentage = val.percentage,
      }
    elseif val.kind == "report" then
      local cur = active_progress[cid][tok] or { title = val.title or tok }
      if val.message ~= nil then
        cur.message = val.message
      end
      if val.percentage ~= nil then
        cur.percentage = val.percentage
      end
      active_progress[cid][tok] = cur
    elseif val.kind == "end" then
      active_progress[cid][tok] = nil
      if next(active_progress[cid]) == nil then
        active_progress[cid] = nil
      end
    end
    vim.cmd.redrawstatus()
  end,
})

vim.api.nvim_create_autocmd("LspDetach", {
  group = progress_grp,
  callback = function(ev)
    local cid = ev.data and ev.data.client_id
    if cid and #vim.lsp.get_clients({ id = cid }) == 0 then
      active_progress[cid] = nil
    end
    vim.cmd.redrawstatus()
  end,
})

-- 1. rust-analyzer
local active_ra_bins = {} -- client_id -> resolved binary path

vim.lsp.config("rust_analyzer", {
  filetypes = { "rust" },
  capabilities = capabilities,
  settings = {},
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    if fname == "" then
      return
    end
    local aosp_root = vim.fs.root(fname, ".repo")
    if aosp_root then
      if vim.uv.fs_stat(aosp_root .. "/rust-project.json") then
        on_dir(aosp_root)
      end
      return
    end
    local cargo_root = vim.fs.root(fname, { "rust-project.json", "Cargo.toml" })
    if cargo_root then
      on_dir(cargo_root)
    end
  end,
  cmd = function(dispatchers, config)
    local root = config.root_dir
    local bin = resolve_aosp_rust_analyzer(root)
    config._resolved_ra_bin = bin
    return vim.lsp.rpc.start({ bin }, dispatchers, { cwd = root })
  end,
  before_init = function(init_params, config)
    local ra_settings = build_ra_settings(config.root_dir)
    config.settings = config.settings or {}
    config.settings["rust-analyzer"] = ra_settings
    init_params.initializationOptions = ra_settings
  end,
  on_init = function(client)
    -- Ensure `client.settings` (read by Neovim 0.11's workspace/configuration handler)
    -- holds the exact rust-analyzer settings rather than an empty table.
    local ra_settings = build_ra_settings(client.config.root_dir)
    client.settings = vim.tbl_deep_extend("force", client.settings or {}, {
      ["rust-analyzer"] = ra_settings,
    })
    active_ra_bins[client.id] = client.config._resolved_ra_bin
  end,
})

-- 2. clangd
vim.lsp.config("clangd", {
  filetypes = { "c", "cpp", "objc", "objcpp" },
  capabilities = capabilities,
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    if fname == "" then
      return
    end
    local aosp_root = vim.fs.root(fname, ".repo")
    if aosp_root then
      on_dir(aosp_root)
      return
    end
    local root = vim.fs.root(fname, { "compile_commands.json", ".clangd", ".git" })
    if root then
      on_dir(root)
    end
  end,
  cmd = function(dispatchers, config)
    local root = config.root_dir
    local bin = "clangd"
    local args = { "--pch-storage=memory", "--background-index", "--clang-tidy=false" }
    if root and vim.uv.fs_stat(root .. "/.repo") then
      bin = find_latest_aosp_clang_tool(root, "clangd")
      table.insert(args, "--compile-commands-dir=" .. root)
    end
    return vim.lsp.rpc.start(vim.list_extend({ bin }, args), dispatchers, { cwd = root })
  end,
})

vim.lsp.enable({ "rust_analyzer", "clangd" })

-- Watch AOSP repo roots so creating/updating `rust-project.json` via `sdv-tools build`
-- automatically starts or reloads `rust-analyzer` in already-open Neovim sessions.
local repo_watchers = {} -- aosp_root -> { handle = uv_fs_event, timer = uv_timer, sig = string|nil }

local function rust_project_sig(aosp_root)
  local st = vim.uv.fs_stat(aosp_root .. "/rust-project.json")
  if not st then
    return nil
  end
  return string.format("%d:%d:%d", st.ino or 0, st.size or 0, st.mtime and st.mtime.sec or 0)
end

local function rust_buffers_in_repo(aosp_root)
  local bufs = {}
  local prefix = aosp_root .. "/"
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "rust" then
      local name = vim.api.nvim_buf_get_name(buf)
      if vim.startswith(name, prefix) then
        table.insert(bufs, buf)
      end
    end
  end
  return bufs
end

local function on_rust_project_changed(aosp_root)
  local clients = vim.lsp.get_clients({ name = "rust_analyzer" })
  local matched_client = nil
  for _, c in ipairs(clients) do
    if c.config and c.config.root_dir == aosp_root then
      matched_client = c
      break
    end
  end

  local bufs = rust_buffers_in_repo(aosp_root)
  if not matched_client then
    if #bufs > 0 then
      vim.notify("rust-project.json ready — starting rust-analyzer...", vim.log.levels.INFO)
      for _, buf in ipairs(bufs) do
        vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
      end
    end
    return
  end

  local new_bin = resolve_aosp_rust_analyzer(aosp_root)
  local old_bin = active_ra_bins[matched_client.id]
  if old_bin and old_bin ~= new_bin then
    vim.notify("Rust toolchain updated — restarting rust-analyzer...", vim.log.levels.INFO)
    matched_client:stop()
    vim.defer_fn(function()
      for _, buf in ipairs(rust_buffers_in_repo(aosp_root)) do
        vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
      end
    end, 500)
    return
  end

  vim.notify("rust-project.json updated — reloading rust-analyzer workspace...", vim.log.levels.INFO)
  matched_client:request("rust-analyzer/reloadWorkspace", vim.NIL, function() end)
end

local function ensure_aosp_rust_watcher(aosp_root)
  if repo_watchers[aosp_root] then
    return
  end
  local handle = vim.uv.new_fs_event()
  local timer = vim.uv.new_timer()
  if not handle or not timer then
    return
  end
  local entry = {
    handle = handle,
    timer = timer,
    sig = rust_project_sig(aosp_root),
  }
  repo_watchers[aosp_root] = entry

  handle:start(aosp_root, {}, function(err, filename)
    if err or (filename and filename ~= "rust-project.json" and not filename:find("rust%-project%.json")) then
      return
    end
    timer:stop()
    timer:start(350, 0, vim.schedule_wrap(function()
      local new_sig = rust_project_sig(aosp_root)
      if new_sig and new_sig ~= entry.sig then
        entry.sig = new_sig
        on_rust_project_changed(aosp_root)
      else
        entry.sig = new_sig
      end
    end))
  end)
end

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("sdv-aosp-rust-watch", { clear = true }),
  pattern = "rust",
  callback = function(ev)
    local fname = vim.api.nvim_buf_get_name(ev.buf)
    if fname == "" then
      return
    end
    local aosp_root = vim.fs.root(fname, ".repo")
    if not aosp_root then
      return
    end
    ensure_aosp_rust_watcher(aosp_root)

    -- If rust-project.json does not exist yet, give a clear message on `gd`
    -- instead of falling back silently to Vim's local-variable `gd`.
    -- Overwritten automatically once LspAttach fires.
    if not vim.uv.fs_stat(aosp_root .. "/rust-project.json") then
      vim.keymap.set("n", "gd", function()
        vim.notify(
          "No rust-project.json in "
            .. vim.fn.fnamemodify(aosp_root, ":t")
            .. " — run `sdv-tools build` (rust-analyzer will attach automatically when ready).",
          vim.log.levels.WARN
        )
      end, { buffer = ev.buf, desc = "Go to definition (awaiting rust-project.json)" })
    end
  end,
})

-- Diagnostics styling
vim.diagnostic.config({
  severity_sort = true,
  virtual_text = { spacing = 2, prefix = "●" },
  float = { border = "rounded", source = true },
})

-- Buffer-local LSP keybindings & inlay hints on attach
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("sdv-lsp-attach", { clear = true }),
  callback = function(event)
    local bufnr = event.buf
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    local fzf = require("fzf-lua")

    local function map(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc })
    end

    local function nav_with_indexing_hint(fn)
      return function()
        for _, c in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
          local busy = client_busy_summary(c.id)
          if busy then
            vim.notify(
              string.format("%s is still indexing (%s) — results may be incomplete", c.name, busy),
              vim.log.levels.INFO
            )
            break
          end
        end
        fn()
      end
    end

    map("gd", nav_with_indexing_hint(fzf.lsp_definitions), "Go to definition (LSP)")
    map("gD", nav_with_indexing_hint(fzf.lsp_declarations), "Go to declaration (LSP)")
    map("gr", nav_with_indexing_hint(fzf.lsp_references), "Find references (LSP)")
    map("gi", nav_with_indexing_hint(fzf.lsp_implementations), "Go to implementation (LSP)")
    map("gy", nav_with_indexing_hint(fzf.lsp_typedefs), "Go to type definition (LSP)")
    map("K", vim.lsp.buf.hover, "Hover documentation")
    map("<leader>ca", fzf.lsp_code_actions, "Code action")
    map("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
    map("<leader>s", fzf.lsp_document_symbols, "Document symbols")
    map("<leader>S", fzf.lsp_live_workspace_symbols, "Workspace symbols")
    map("<leader>d", fzf.diagnostics_document, "Buffer diagnostics")
    map("]d", function()
      vim.diagnostic.jump({ count = 1, float = true })
    end, "Next diagnostic")
    map("[d", function()
      vim.diagnostic.jump({ count = -1, float = true })
    end, "Prev diagnostic")

    if client and client:supports_method("textDocument/inlayHint") then
      vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
      map("<leader>ih", function()
        local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr })
        vim.lsp.inlay_hint.enable(not enabled, { bufnr = bufnr })
      end, "Toggle LSP inlay hints")
    end
    vim.cmd.redrawstatus()
  end,
})
