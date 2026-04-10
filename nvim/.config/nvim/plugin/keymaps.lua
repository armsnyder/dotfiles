-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Diagnostic keymaps
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostic [Q]uickfix list" })
vim.keymap.set("n", "<leader>de", vim.diagnostic.open_float, { desc = "Open [D]iagnostic [E]rror" })

-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
-- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
-- is not what someone will guess without a bit more experience.
--
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- TIP: Disable arrow keys in normal mode
-- vim.keymap.set('n', '<left>', '<cmd>echo "Use h to move!!"<CR>')
-- vim.keymap.set('n', '<right>', '<cmd>echo "Use l to move!!"<CR>')
-- vim.keymap.set('n', '<up>', '<cmd>echo "Use k to move!!"<CR>')
-- vim.keymap.set('n', '<down>', '<cmd>echo "Use j to move!!"<CR>')

-- Preserve past register when pasting
vim.keymap.set("n", "<leader>p", '"_dP', { desc = "[P]aste and preserve register" })
vim.keymap.set("n", "x", '"_x')

-- Indent
vim.keymap.set("v", "<Tab>", ">gv", { desc = "Indent" })
vim.keymap.set("v", "<S-Tab>", "<gv", { desc = "Un-indent" })

-- Keep search results in the center of the screen
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- Keep cursor in place while jumping
vim.keymap.set("n", "J", "mzJ`z")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")

-- Move chunks of code
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- Git branches
vim.keymap.set("n", "<leader>sb", function()
  require("telescope.builtin").git_branches(require("telescope.themes").get_ivy())
end, { desc = "[S]earch git [b]ranches" })

local function require_tmux()
  if not os.getenv("TMUX") then
    vim.notify("Not in a tmux session", vim.log.levels.ERROR)
    return false
  end
  return true
end

local function shell(cmd)
  local out = vim.fn.system(string.format("zsh -ic %s", vim.fn.shellescape(cmd)))
  if vim.v.shell_error ~= 0 then
    vim.notify(out, vim.log.levels.ERROR)
  end
end

local function ivy_picker(title, results, entry_maker, on_select)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local conf = require("telescope.config").values

  pickers
    .new(require("telescope.themes").get_ivy(), {
      prompt_title = title,
      finder = finders.new_table({ results = results, entry_maker = entry_maker }),
      sorter = conf.generic_sorter(),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            on_select(selection)
          end
        end)
        return true
      end,
    })
    :find()
end

-- Tmux window switcher
vim.keymap.set("n", "<leader>sw", function()
  if not require_tmux() then return end
  local windows = vim.fn.systemlist("tmux list-windows -a -F '#{session_name}:#{window_index}: #{window_name}#{?window_active, (active),}'")
  ivy_picker("Tmux Windows", windows, nil, function(sel)
    local target = sel[1]:match("^(%S+:%d+):")
    if target then
      vim.fn.system("tmux switch-client -t " .. vim.fn.shellescape(target))
    end
  end)
end, { desc = "[S]earch tmux [w]indows" })

-- Jump to recent branch across all repos
vim.keymap.set("n", "<leader>sj", function()
  if not require_tmux() then return end

  local results = {}
  for _, line in ipairs(vim.fn.systemlist("zsh -ic '_list_recent_branches 20'")) do
    local date, branch, repo, repo_dir = line:match("^(.-)|(.-)|(.-)|(.*)")
    if date and branch and repo and repo_dir then
      table.insert(results, { date = date, branch = branch, repo = repo, repo_dir = repo_dir })
    end
  end

  ivy_picker("Recent Branches", results, function(entry)
    local display = string.format("%-30s %-40s %s", entry.repo, entry.branch, entry.date)
    return { value = entry, display = display, ordinal = entry.repo .. " " .. entry.branch }
  end, function(sel)
    local e = sel.value
    if e.branch == "main" then
      shell("ide " .. vim.fn.shellescape(e.repo_dir))
    else
      shell("cd " .. vim.fn.shellescape(e.repo_dir) .. " && wta " .. vim.fn.shellescape(e.branch))
    end
  end)
end, { desc = "[S]earch & [j]ump to recent branch" })

-- Open repo in new tmux session with IDE layout
vim.keymap.set("n", "<leader>si", function()
  if not require_tmux() then return end
  local repos = vim.fn.systemlist("zsh -ic '_list_repos'")
  ivy_picker("Open Repo", repos, function(path)
    local display = path:gsub(os.getenv("HOME") .. "/", "")
    return { value = path, display = display, ordinal = display }
  end, function(sel)
    shell("ide " .. vim.fn.shellescape(sel.value))
  end)
end, { desc = "[S]earch repos & open [I]DE" })

-- Close current tmux session (cleans up worktrees first)
local function quit_session()
  if not require_tmux() then return end
  shell("idec")
end
vim.keymap.set("n", "<leader>wq", quit_session, { desc = "[W]orkspace: [q]uit session" })
vim.keymap.set("n", "<leader>wtq", quit_session, { desc = "[W]ork[t]ree: [q]uit session" })

-- Worktrees
vim.keymap.set("n", "<leader>wta", function()
  if not require_tmux() then return end
  vim.ui.input({ prompt = "Worktree name: " }, function(name)
    if not name or name == "" then return end
    shell("wta " .. vim.fn.shellescape(name))
  end)
end, { desc = "[W]ork[t]ree: [a]dd" })

vim.keymap.set("n", "<leader>wtr", function()
  if not require_tmux() then return end
  shell("wtr")
end, { desc = "[W]ork[t]ree: [r]emove" })
