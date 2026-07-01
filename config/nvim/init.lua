vim.o.winborder = "rounded"
vim.o.tabstop = 2
vim.o.ignorecase = true
vim.o.shiftwidth = 2
vim.o.smartindent = true
vim.opt.wrap = false
vim.opt.number = true
vim.o.relativenumber = true
vim.o.termguicolors = true
vim.o.undofile = true
vim.o.incsearch = true
vim.o.signcolumn = "yes"
vim.opt.clipboard = "unnamedplus"
vim.opt.expandtab = true

-- On NixOS the flake provides plugins (vim.g.nix_managed set in the flake);
-- on Arch, vim.pack fetches them at runtime. Both paths keep working.
if not vim.g.nix_managed then
  vim.pack.add({
    { src = "https://github.com/nvim-tree/nvim-web-devicons" },
    { src = "https://github.com/scottmckendry/cyberdream.nvim" },
    { src = "https://github.com/stevearc/oil.nvim" },
    { src = "https://github.com/neovim/nvim-lspconfig" },
    { src = "https://github.com/chomosuke/typst-preview.nvim" },
    { src = "https://github.com/saghen/blink.cmp" },
    { src = "https://github.com/dynamotn/Navigator.nvim" },
    { src = "https://github.com/folke/snacks.nvim" },
    { src = "https://github.com/folke/todo-comments.nvim" },
    { src = "https://github.com/folke/trouble.nvim" },
    { src = "https://github.com/nvim-treesitter/nvim-treesitter" },
    { src = "https://github.com/j-hui/fidget.nvim" },
    { src = "https://github.com/nvim-lualine/lualine.nvim" },
  })
end

require("blink.cmp").setup()
require("Navigator").setup()
require("todo-comments").setup()
require("trouble").setup()
require("fidget").setup()
require("lualine").setup({
  options = {
    component_separators = { left = "|", right = "|" },
    section_separators = { left = "|", right = "|" },
  },
})
require("oil").setup({
  default_file_explorer = true,
  delete_to_trash = true,
  skip_confirm_for_simple_edits = true,
  view_options = { show_hidden = true },
  keymaps = {
    ["g?"] = { "actions.show_help", mode = "n" },
    ["<CR>"] = "actions.select",
    ["-"] = { "actions.parent", mode = "n" },
    ["_"] = { "actions.open_cwd", mode = "n" },
    ["`"] = { "actions.cd", mode = "n" },
  },
  use_default_keymaps = false,
})
require("snacks").setup({ picker = { ui_select = true } })

vim.cmd("colorscheme cyberdream")
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    vim.highlight.on_yank()
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "typst",
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
  end,
})

vim.lsp.enable({ "lua_ls", "svelte", "tinymist", "ts_ls", "rust_analyzer", "yamlls", "html", "cssls", "jsonls", "nixd", "zls" })
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition)
    vim.keymap.set('n', 'gD', vim.lsp.buf.declaration)
    vim.keymap.set('n', 'gr', Snacks.picker.lsp_references)
    vim.keymap.set('n', 'gt', Snacks.picker.lsp_type_definitions)
    vim.keymap.set('n', '<leader>ss', Snacks.picker.lsp_symbols)
    vim.keymap.set('n', '<leader>sS', Snacks.picker.lsp_workspace_symbols)
    vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action)
    vim.keymap.set('n', '<leader>cr', vim.lsp.buf.rename)
  end
})

vim.g.mapleader = " "
vim.keymap.set('n', '<leader>o', ':update<CR> :source<CR>')
vim.keymap.set('n', '<leader>w', ':write<CR>')
vim.keymap.set('n', '<leader>q', ':quit<CR>')
vim.keymap.set('n', '<leader>f', function() Snacks.picker.files() end)
vim.keymap.set('n', '<leader>sg', function() Snacks.picker.grep() end)
vim.keymap.set('n', '<leader>e', ':Oil<CR>')
vim.keymap.set({ 'n', 't' }, '<C-h>', ':NavigatorLeft<CR>')
vim.keymap.set({ 'n', 't' }, '<C-l>', ':NavigatorRight<CR>')
vim.keymap.set({ 'n', 't' }, '<C-k>', ':NavigatorUp<CR>')
vim.keymap.set({ 'n', 't' }, '<C-j>', ':NavigatorDown<CR>')
vim.keymap.set({ "n", "t" }, "<C-t>", function() Snacks.terminal.toggle("zsh") end) -- Open Snacks picker
vim.keymap.set('n', '<leader>g', function() Snacks.lazygit() end)
vim.keymap.set('n', '<leader>t', function() Snacks.picker.todo_comments() end)
vim.keymap.set('n', '<leader>x', ":Trouble diagnostics toggle filter.buf=0<CR>")
vim.keymap.set('n', '<leader>X', ":Trouble diagnostics<CR>")
vim.keymap.set('n', '<leader>|', ":vsplit<CR>")
vim.keymap.set('n', '<leader>_', ":split<CR>")
vim.keymap.set('n', '<ESC>', ":noh<CR>")
vim.keymap.set("v", ">", ">gv", { silent = true, desc = "Indent and reselect" })
vim.keymap.set("v", "<", "<gv", { silent = true, desc = "Unindent and reselect" })
vim.keymap.set('n', '<leader>lf', vim.lsp.buf.format)
