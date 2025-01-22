return {
  { -- Collection of various small independent plugins/modules
    "echasnovski/mini.nvim",
    config = function()
      -- Better Around/Inside textobjects
      --
      -- Examples:
      --  - va)  - [V]isually select [A]round [)]paren
      --  - yinq - [Y]ank [I]nside [N]ext [Q]uote
      --  - ci'  - [C]hange [I]nside [']quote
      require("mini.ai").setup({ n_lines = 500 })

      -- Add/delete/replace surroundings (brackets, quotes, etc.)
      --
      -- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
      -- - sd'   - [S]urround [D]elete [']quotes
      -- - sr)'  - [S]urround [R]eplace [)] [']
      require("mini.surround").setup()

      -- Simple and easy statusline.
      --  You could remove this setup call if you don't like it,
      --  and try some other statusline plugin
      local statusline = require("mini.statusline")
      -- set use_icons to true if you have a Nerd Font
      statusline.setup({})

      -- You can configure sections in the statusline by overriding their
      -- default behavior. For example, here we set the section for
      -- cursor location to LINE:COLUMN
      ---@diagnostic disable-next-line: duplicate-set-field
      statusline.section_location = function()
        return "%2l:%-2v"
      end

      require("mini.pairs").setup()

      require("mini.comment").setup()

      local minifiles = require("mini.files")
      minifiles.setup({
        options = {
          permanent_delete = false,
          use_as_default_explorer = false, -- We want to open Telescope instead
        },
      })
      vim.keymap.set("n", "<leader>e", function()
        local buf_name = vim.api.nvim_buf_get_name(0)
        local path = vim.fn.filereadable(buf_name) == 1 and buf_name or vim.fn.getcwd()
        minifiles.open(path)
        minifiles.reveal_cwd()
      end, { desc = "Open file [E]xplorer" })

      vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesBufferCreate",
        callback = function(ev)
          vim.schedule(function()
            -- Also map :w to synchronize the prepared filesystem modifications.
            vim.api.nvim_set_option_value("buftype", "acwrite", { buf = ev.data.buf_id })
            vim.api.nvim_buf_set_name(0, tostring(vim.api.nvim_get_current_win()))
            vim.api.nvim_create_autocmd("BufWriteCmd", {
              buffer = ev.data.buf_id,
              callback = function()
                require("mini.files").synchronize()
              end,
            })

            --- Map escape to close the file explorer
            vim.keymap.set("n", "<Esc>", function()
              require("mini.files").close()
            end, { buffer = ev.data.buf_id })
          end)
        end,
      })

      -- Also map ENTER to open the selected file.
      vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesBufferCreate",
        callback = function(ev)
          vim.schedule(function()
            vim.keymap.set("n", "<CR>", function()
              require("mini.files").go_in({ close_on_file = true })
            end, { buffer = ev.data.buf_id })
          end)
        end,
      })

      -- ... and there is more!
      --  Check out: https://github.com/echasnovski/mini.nvim
    end,
  },
}
