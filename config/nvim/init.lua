vim.o.winborder = "rounded"      -- floating windows (hover docs, pickers) get rounded borders
vim.o.tabstop = 2                -- a tab character is rendered 2 columns wide
vim.o.ignorecase = true          -- searching is case insensitive
vim.o.shiftwidth = 2             -- >> and << indent by 2
vim.o.smartindent = true         -- indent new lines based on the line above
vim.opt.wrap = false             -- long lines run off the screen instead of wrapping
vim.opt.number = true            -- show line numbers
vim.o.relativenumber = true      -- ...but relative to the cursor, so 5j / 5k are easy to aim
vim.o.termguicolors = true       -- 24 bit color, the colorscheme needs this
vim.o.undofile = true            -- keep undo history on disk, so you can undo after reopening a file
vim.o.incsearch = true           -- jump to the match while you are still typing the search
vim.o.signcolumn = "yes"         -- always show the left gutter (diagnostics live there) so text never jumps
vim.opt.clipboard = "unnamedplus" -- yank and paste use the system clipboard
vim.opt.expandtab = true         -- pressing tab inserts spaces, not a tab character

-- vim.pack is neovim's built in plugin manager. it clones these repos into
-- stdpath("data")/site/pack the first time you start. `vim.pack.update()`
-- updates them.
vim.pack.add({
  { src = "https://github.com/nvim-tree/nvim-web-devicons" },   -- filetype icons (needs a nerd font in your terminal)
  { src = "https://github.com/scottmckendry/cyberdream.nvim" },  -- the colorscheme
  { src = "https://github.com/stevearc/oil.nvim" },              -- file manager that is just an editable buffer
  { src = "https://github.com/neovim/nvim-lspconfig" },          -- ready made configs for language servers
  { src = "https://github.com/saghen/blink.cmp" },               -- the autocomplete popup
  { src = "https://github.com/folke/snacks.nvim" },              -- grab bag of small tools. we use the picker, terminal and lazygit
  { src = "https://github.com/folke/todo-comments.nvim" },       -- highlights TODO/FIXME/HACK and can list them
  { src = "https://github.com/folke/trouble.nvim" },             -- a readable list of errors and warnings
  { src = "https://github.com/nvim-treesitter/nvim-treesitter" },-- real syntax parsing, better highlighting
  { src = "https://github.com/j-hui/fidget.nvim" },              -- little lsp progress spinner in the corner
  { src = "https://github.com/nvim-lualine/lualine.nvim" },      -- the statusline at the bottom
})

-- most plugins only need setup() called with no arguments to turn them on.
require("blink.cmp").setup()
require("todo-comments").setup()
require("trouble").setup()
require("fidget").setup()
require("lualine").setup({
  options = {
    -- plain | instead of the default powerline arrows, so it looks right in any font
    component_separators = { left = "|", right = "|" },
    section_separators = { left = "|", right = "|" },
  },
})
require("oil").setup({
  default_file_explorer = true,          -- opening a directory opens oil instead of netrw
  delete_to_trash = true,                -- deleting a file in oil sends it to the trash, not the void
  skip_confirm_for_simple_edits = true,  -- don't ask "are you sure" for renames and single deletes
  view_options = { show_hidden = true }, -- show dotfiles
  -- oil's own keymaps, inside an oil buffer only.
  keymaps = {
    ["g?"] = { "actions.show_help", mode = "n" }, -- everything oil can do
    ["<CR>"] = "actions.select",                  -- open the file/directory under the cursor
    ["-"] = { "actions.parent", mode = "n" },     -- go up one directory
    ["_"] = { "actions.open_cwd", mode = "n" },   -- jump to the directory nvim was started in
    ["`"] = { "actions.cd", mode = "n" },         -- make this directory nvim's working directory
  },
  use_default_keymaps = false,           -- only the five above, nothing else
})
require("snacks").setup({ picker = { ui_select = true } }) -- any "pick one" prompt uses the snacks picker

vim.cmd("colorscheme cyberdream")

-- briefly flash whatever you just yanked, so you can see what got copied
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    vim.highlight.on_yank()
  end,
})


-- These are the language servers we turn on. the server programs themselves are
-- installed by nix (see programs.neovim.extraPackages in flake.nix), this line
-- only tells neovim to start them for the right filetypes.
vim.lsp.enable({ "lua_ls", "ts_ls", "rust_analyzer", "html", "cssls", "jsonls", "nixd" })

-- This means that we should run the callback when the event LspAttach happens
-- aka. when a language server attaches to the buffer. that is when these
-- keymaps start doing something useful, so we only set them then.
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition)               -- go to where the thing under the cursor is defined
    vim.keymap.set('n', 'gD', vim.lsp.buf.declaration)              -- go to its declaration (mostly a C/C++ thing)
    vim.keymap.set('n', 'gr', Snacks.picker.lsp_references)         -- list every place it is used
    vim.keymap.set('n', 'gt', Snacks.picker.lsp_type_definitions)   -- go to the definition of its type
    vim.keymap.set('n', '<leader>ss', Snacks.picker.lsp_symbols)    -- search symbols in this file
    vim.keymap.set('n', '<leader>sS', Snacks.picker.lsp_workspace_symbols) -- search symbols in the whole project
    vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action)      -- offer the fixes/refactors the server suggests
    vim.keymap.set('n', '<leader>cr', vim.lsp.buf.rename)           -- rename it everywhere at once
  end
})

-- This is your leader key. set it to whatever you like. but space is nice i think
vim.g.mapleader = " "
-- space+o in normal mode saves this file and re-runs it, so config changes apply
-- without restarting neovim. (to update the plugins themselves: :lua vim.pack.update())
vim.keymap.set('n', '<leader>o', ':update<CR>:source<CR>')
-- space+w in normal mode writes (saves) the current buffer
vim.keymap.set('n', '<leader>w', ':write<CR>')
-- space+q in normal mode quits
vim.keymap.set('n', '<leader>q', ':quit<CR>')
-- space+f in normal mode opens a file picker where you can fuzzy search for files by their name
vim.keymap.set('n', '<leader>f', function() Snacks.picker.files() end)
-- space+sg in normal mode opens a fuzzy searcher that searches through the contents of all files
vim.keymap.set('n', '<leader>sg', function() Snacks.picker.grep() end)
-- space+e in normal mode opens a new buffer with Oil. this is the file manager or what you would call it
-- The cool thing about oil is that you can edit all of your files like neovim buffers
vim.keymap.set('n', '<leader>e', ':Oil<CR>')

-- ctrl+h/j/k/l move to the split left/down/up/right. <C-w>h is neovim's own
-- "go to the window on the left", these just put it on an easier key.
-- normal mode only: inside the terminal these keys belong to the shell
-- (ctrl+l clears it), and you leave that terminal with ctrl+t anyway.
vim.keymap.set('n', '<C-h>', '<C-w>h')
vim.keymap.set('n', '<C-l>', '<C-w>l')
vim.keymap.set('n', '<C-k>', '<C-w>k')
vim.keymap.set('n', '<C-j>', '<C-w>j')

-- ctrl+t toggles a floating zsh terminal. it works both in normal mode and from
-- inside the terminal itself, so the same key opens and closes it
vim.keymap.set({ "n", "t" }, "<C-t>", function() Snacks.terminal.toggle("zsh") end)
-- space+g in normal mode opens lazygit in floating window (tui for git)
vim.keymap.set('n', '<leader>g', function() Snacks.lazygit() end)
-- space+t in normal mode opens a picker of todo comments where you can search through them
vim.keymap.set('n', '<leader>t', function() Snacks.picker.todo_comments() end)
-- space+x in normal mode opens a bottom bar that shows warning and errors from your LSP in the current buffer
vim.keymap.set('n', '<leader>x', ":Trouble diagnostics toggle filter.buf=0<CR>")
-- space+shift+X does the same but for every file in the project
vim.keymap.set('n', '<leader>X', ":Trouble diagnostics<CR>")
-- space+| in normal mode vertically splits the current buffer
vim.keymap.set('n', '<leader>|', ":vsplit<CR>")
-- space+_ in normal mode horizontally splits the current buffer
vim.keymap.set('n', '<leader>_', ":split<CR>")
-- ESC in normal mode clears the highlighting left over from your last search
vim.keymap.set('n', '<ESC>', ":noh<CR>")
-- > in visual mode indents the selected lines (gv reselects them so you can keep pressing >)
vim.keymap.set("v", ">", ">gv", { silent = true, desc = "Indent and reselect" })
-- < in visual mode unindents the selected lines
vim.keymap.set("v", "<", "<gv", { silent = true, desc = "Unindent and reselect" })
-- space+lf in normal mode calls the lsp's formatter on the current buffer
vim.keymap.set('n', '<leader>lf', vim.lsp.buf.format)
