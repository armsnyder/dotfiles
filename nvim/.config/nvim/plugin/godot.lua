local cwd = vim.fn.getcwd()

if vim.uv.fs_stat(cwd .. "/project.godot") then
  if not vim.uv.fs_stat(cwd .. "/server.pipe") then
    vim.fn.serverstart(cwd .. "/server.pipe")
  end

  local lspconfig = require("lspconfig")
  lspconfig.gdscript.setup({})
end
