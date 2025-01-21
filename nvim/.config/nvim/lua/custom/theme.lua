local M = {}

M.name = "onedark"

M.plugin = {
  "navarasu/" .. M.name .. ".nvim",
  priority = 1000,
  config = function()
    local theme = require(M.name)
    theme.setup({
      style = "warm",
      transparent = true,
    })
    theme.load()
  end,
}

return M
