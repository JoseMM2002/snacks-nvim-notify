# snacks-nvim-notify

A small Neovim add-on that exposes your `nvim-notify` history through the `snacks.nvim` picker so you can search, preview, and reopen past notifications with ease.

## Features

- Adds the `:SnacksNotifications` command to launch a Snacks picker populated with past notifications from `nvim-notify`.
- Provides rich list entries that include level, icon, category, time and truncated message for quick scanning.
- Shows an inline preview within the picker and reopens a floating window with the full notification when you confirm a selection.
- Applies level-aware highlighting to keep severity information clear while browsing.

## Requirements

- [folke/snacks.nvim](https://github.com/folke/snacks.nvim)
- [rcarriga/nvim-notify](https://github.com/rcarriga/nvim-notify)
- Neovim 0.9 or newer is recommended

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "JoseMM2002/snacks-nvim-notify",
  dependencies = { "folke/snacks.nvim", "rcarriga/nvim-notify" },
  config = function()
    require("snacks-nvim-notify").setup()
  end,
},
```

Load Neovim and run `:Lazy sync` (or your plugin manager's equivalent) to install the dependencies.

## Usage

After installation the plugin registers the `:SnacksNotifications` user command. Running it opens a Snacks picker where you can:

1. Browse notifications with level-aware formatting.
2. See an inline preview of the selected notification within the picker.
3. Press `<CR>` to reopen the selected notification in a floating window. Close it with `q` or `<Esc>`.

The module exposes `require("snacks-nvim-notify").setup(opts)` if you need to extend the behaviour later on. Currently all functionality works out of the box without passing options.

