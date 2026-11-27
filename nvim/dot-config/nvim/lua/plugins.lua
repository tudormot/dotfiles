-- Plugin Specifications (lazy.nvim)

local function find_aosp_root_for_buf(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil
  end
  return vim.fs.root(name, ".repo")
end

return {
  -- Icons (needed for Oil and fzf-lua)
  { "nvim-tree/nvim-web-devicons" },

  -- Oil.nvim (File Explorer)
  {
    "stevearc/oil.nvim",
    opts = {},
    config = function()
      require("oil").setup()
      vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory (Oil)" })
    end,
  },

  -- fzf-lua (Fuzzy Finder & LSP UI)
  {
    "ibhagwan/fzf-lua",
    config = function()
      local fzf = require("fzf-lua")
      fzf.setup({
        winopts = {
          height = 0.88,
          width = 0.88,
          preview = { layout = "vertical", vertical = "down:50%" },
        },
      })
      fzf.register_ui_select()
      vim.keymap.set("n", "<leader>b", fzf.buffers, { desc = "Buffers (fzf)" })
    end,
  },

  -- OSC52 Yank (for tmux / mosh / SSH clipboard integration)
  {
    "ojroques/nvim-osc52",
    config = function()
      require("osc52").setup({
        max_length = 0,
        silent = false,
        trim = false,
      })
      vim.api.nvim_create_autocmd("TextYankPost", {
        callback = function()
          if vim.v.event.operator == "y" and vim.v.event.regname == "" then
            require("osc52").copy_register("")
          end
        end,
      })
    end,
  },

  -- Treesitter for syntax highlighting
  -- Pinned to 'master' (legacy nvim-treesitter.configs API) since tree-sitter-cli
  -- required by the 'main' branch rewrite is not installed on these hosts.
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    build = ":TSUpdate",
    main = "nvim-treesitter.configs",
    opts = {
      ensure_installed = {
        "c",
        "cpp",
        "rust",
        "python",
        "starlark",
        "java",
        "bash",
        "markdown",
        "markdown_inline",
        "proto",
        "textproto",
        "json",
        "xml",
        "lua",
        "commonlisp",
      },
      auto_install = false,
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
      },
      indent = { enable = true },
    },
  },

  -- Kanagawa Color Scheme (dims inactive splits AND unfocused tmux panes)
  {
    "rebelot/kanagawa.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("kanagawa").setup({
        dimInactive = true,
      })
      vim.cmd("colorscheme kanagawa-dragon")

      -- Also dim the active Neovim split when its enclosing tmux pane loses focus
      local focus_grp = vim.api.nvim_create_augroup("sdv-tmux-focus-dim", { clear = true })
      vim.api.nvim_create_autocmd("FocusLost", {
        group = focus_grp,
        callback = function()
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_config(win).relative == "" and vim.wo[win].winhighlight == "" then
              vim.w[win]._sdv_dimmed = true
              vim.wo[win].winhighlight = "Normal:NormalNC,SignColumn:NormalNC"
            end
          end
        end,
      })
      vim.api.nvim_create_autocmd("FocusGained", {
        group = focus_grp,
        callback = function()
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.w[win]._sdv_dimmed then
              vim.w[win]._sdv_dimmed = nil
              vim.wo[win].winhighlight = ""
            end
          end
        end,
      })
    end,
  },

  -- Surround
  {
    "kylechui/nvim-surround",
    version = "^4.0.0",
    event = "VeryLazy",
  },

  -- Fast Rust-backed LSP & buffer completion
  {
    "saghen/blink.cmp",
    tag = "v1.10.2",
    opts = {
      keymap = { preset = "default" },
      appearance = { nerd_font_variant = "mono" },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
      },
      signature = { enabled = true },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
    },
  },

  -- Auto Format-on-Save matching AOSP / SDV presubmit hooks (no manual format keymap)
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo", "FormatToggle" },
    config = function()
      vim.g.autoformat_enabled = true

      require("conform").setup({
        format_on_save = function(bufnr)
          if not vim.g.autoformat_enabled or vim.b[bufnr].autoformat_enabled == false then
            return nil
          end
          return { timeout_ms = 3000, lsp_format = "fallback" }
        end,
        formatters_by_ft = {
          rust = { "aosp_rustfmt" },
          bzl = { "aosp_bpfmt" },
          textproto = { "txtpbfmt" },
          aidl = { "aosp_aidl_format" },
          c = { "aosp_clang_format" },
          cpp = { "aosp_clang_format" },
          proto = { "aosp_clang_format" },
        },
        formatters = {
          aosp_rustfmt = {
            command = function(self, ctx)
              local root = find_aosp_root_for_buf(ctx.buf)
              if root then
                local bin = root .. "/prebuilts/rust-toolchain/linux-x86/stable/rustfmt"
                if vim.fn.executable(bin) == 1 then
                  return bin
                end
              end
              return "rustfmt"
            end,
            args = function(self, ctx)
              local root = find_aosp_root_for_buf(ctx.buf)
              if root then
                local cfg = root .. "/build/soong/scripts/rustfmt.toml"
                if vim.uv.fs_stat(cfg) then
                  return { "--config-path=" .. cfg, "--emit=stdout" }
                end
              end
              return { "--emit=stdout" }
            end,
            stdin = true,
          },
          aosp_bpfmt = {
            command = function(self, ctx)
              local root = find_aosp_root_for_buf(ctx.buf)
              if root then
                local bin = root .. "/prebuilts/build-tools/linux-x86/bin/bpfmt"
                if vim.fn.executable(bin) == 1 then
                  return bin
                end
              end
              return "bpfmt"
            end,
            args = { "-o" },
            stdin = true,
          },
          txtpbfmt = {
            command = "/google/bin/releases/text-proto-format/public/fmt",
            args = {},
            stdin = true,
            condition = function()
              return vim.fn.executable("/google/bin/releases/text-proto-format/public/fmt") == 1
            end,
          },
          aosp_aidl_format = {
            command = function(self, ctx)
              local root = find_aosp_root_for_buf(ctx.buf)
              if root then
                local bin = root .. "/system/tools/aidl/aidl-format.sh"
                if vim.fn.executable(bin) == 1 then
                  return bin
                end
              end
              return "aidl-format.sh"
            end,
            args = {},
            stdin = true,
            condition = function(self, ctx)
              local root = find_aosp_root_for_buf(ctx.buf)
              return root ~= nil and vim.fn.executable(root .. "/system/tools/aidl/aidl-format.sh") == 1
            end,
          },
          aosp_clang_format = {
            command = function(self, ctx)
              local root = find_aosp_root_for_buf(ctx.buf)
              if root then
                local stable = root .. "/prebuilts/clang/host/linux-x86/clang-stable/bin/clang-format"
                if vim.fn.executable(stable) == 1 then
                  return stable
                end
                local matches = vim.fn.glob(
                  root .. "/prebuilts/clang/host/linux-x86/clang-r*/bin/clang-format",
                  true,
                  true
                )
                table.sort(matches)
                for i = #matches, 1, -1 do
                  if vim.fn.executable(matches[i]) == 1 then
                    return matches[i]
                  end
                end
              end
              return "clang-format"
            end,
            args = { "--assume-filename", "$FILENAME" },
            stdin = true,
          },
        },
      })

      vim.api.nvim_create_user_command("FormatToggle", function(args)
        if args.bang then
          vim.b.autoformat_enabled = not (vim.b.autoformat_enabled ~= false)
          vim.notify("Buffer format-on-save: " .. tostring(vim.b.autoformat_enabled))
        else
          vim.g.autoformat_enabled = not vim.g.autoformat_enabled
          vim.notify("Global format-on-save: " .. tostring(vim.g.autoformat_enabled))
        end
      end, {
        desc = "Toggle auto format-on-save (use :FormatToggle! for current buffer only)",
        bang = true,
      })
    end,
  },

  -- Git signs & hunk actions (attaches automatically to enclosing AOSP subproject .git)
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      on_attach = function(bufnr)
        local gs = package.loaded.gitsigns
        local function map(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
        end
        map("n", "]c", function()
          if vim.wo.diff then
            vim.cmd.normal({ "]c", bang = true })
          else
            gs.nav_hunk("next")
          end
        end, "Next git hunk")
        map("n", "[c", function()
          if vim.wo.diff then
            vim.cmd.normal({ "[c", bang = true })
          else
            gs.nav_hunk("prev")
          end
        end, "Prev git hunk")
        map({ "n", "v" }, "<leader>hs", ":Gitsigns stage_hunk<CR>", "Stage git hunk")
        map({ "n", "v" }, "<leader>hr", ":Gitsigns reset_hunk<CR>", "Reset git hunk")
        map("n", "<leader>hb", function()
          gs.blame_line({ full = true })
        end, "Git blame line")
      end,
    },
  },

  -- Self-documenting keybinding popup
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>a", group = "AOSP Full Search" },
        { "<leader>t", group = "Terminal (same-window)" },
        { "<leader>x", group = "SDV Tests (atest/catbox/abtd)" },
        { "<leader>h", group = "Git Hunks" },
        { "<leader>c", group = "Code Actions" },
        { "<leader>r", group = "Rename" },
        { "<leader>i", group = "Inlay Hints" },
      },
    },
  },

  -- Common Lisp development environment
  {
    "vlime/vlime",
    ft = { "lisp", "commonlisp" },
    config = function(plugin)
      vim.opt.rtp:append(plugin.dir .. "/vim")
    end,
  },

  {
    "julienvincent/nvim-paredit",
    ft = { "clojure", "fennel", "scheme", "lisp", "commonlisp", "janet" },
    config = function()
      require("nvim-paredit").setup({
        indent = {
          enabled = true,
        },
        filetypes = { "clojure", "fennel", "scheme", "lisp", "commonlisp", "janet" },
      })
    end,
  },
}
