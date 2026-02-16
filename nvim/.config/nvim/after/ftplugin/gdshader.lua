vim.lsp.start({
  name = "gdshader",
  cmd = { "gdshader-language-server", "-debug" },
  capabilities = vim.lsp.protocol.make_client_capabilities(),
  trace = "messages",
})
