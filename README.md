<h1 align="center">oklch-color-picker.nvim</h1>

<p align="center">Sometimes the resolution of a cli just isn't enough</p>

<p align="center" width="100%"> 
  <img src="https://github.com/user-attachments/assets/d5a38ffc-0b1b-4af6-a229-5f5963b9a616" alt="screenshot">
</p>

## Features

- Select and edit buffer colors in a graphical picker
- Fast async color highlighting
- Supports multiple formats:
  - Hex (`#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`), CSS (`rgb(..)`, `hsl(..)`, `oklch(..)`)
  - Can recognize any numbers in brackets as a color (e.g., `vec3(0.5, 0.5, 0.5)`)
  - Custom formats can be defined
- Integrated graphical [color picker](https://github.com/eero-lehtinen/oklch-color-picker) using the perceptual Oklch color space:
  - Consists of lightness, chroma, and hue for intuitive adjustments
  - Based on [Oklab](https://bottosson.github.io/posts/oklab/) theory, using L<sub>r</sub> as [an improved lightness estimate](https://bottosson.github.io/posts/colorpicker/#intermission---a-new-lightness-estimate-for-oklab)

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'eero-lehtinen/oklch-color-picker.nvim',
  build = 'download.lua',
  config = function()
    require('oklch-color-picker').setup {}
    -- One handed keymaps recommended, you will be using the mouse
    vim.keymap.set('n', '<leader>v', '<cmd>ColorPickOklch<cr>')
  end,
},
```

You can either include the `build = 'download.lua'` line to download the picker automatically or download it yourself from [the picker application repository](https://github.com/eero-lehtinen/oklch-color-picker) (it's open source too in a different repo!) and put it in your PATH. The picker is a standalone ⚡Rust⚡ application with ⚡blazing fast⚡ performance and startup time.

## Demo

https://github.com/user-attachments/assets/a6df331c-10dc-4e50-8f89-bc4ab191de57

## Default Options

```lua
local default_config = {
  patterns = {
    hex = {
      priority = -1,
      '()#%x%x%x+()%f[%W]',
    },
    css = {
      priority = -1,
      -- commas are not allowed in modern css colors
      -- so use [^,] to differentiate from `numbers_in_brackets`
      '()rgb%([^,]+%)()',
      '()oklch%([^,]+%)()',
      '()hsl%([^,]+%)()',
    },
    numbers_in_brackets = {
      priority = -10,
      -- allows any digits, dots, commas or whitespace within brackets
      '%(()[%d.,%s]+()%)',
    },
  },
  highlight = {
    enabled = true,
    delay = 60,
  },
  log_level = vim.log.levels.INFO,
}
```

## Configuration

Disable default patterns by setting an empty table:

```lua
{
  patterns = {
    css = {}
  }
}
```

Define your own patterns:

```lua
{
  patterns = {
    glsl_vec_linear = {
      -- (Optional) Higher priority patterns are tried first. Defaults to 0.
      priority = 5,
      -- (Optional) Color format for the picker. Auto detect by default.
      format = 'raw_rgb_linear',
      -- (Optional) Filetypes to apply the pattern to. Must be a table.
      ft = { 'glsl' },
      -- The list of patterns.
      'vec3%(()[%d.,%s]+()%)', -- Gets `.1,.2,.3` from code `vec3(.1,.2,.3)`
      'vec4%(()[%d.,%s]+()%)',
    },
    rust_color = {
      ft = { 'rust' },
      'MyColor::rgb%(()[%d.,%s]+()%)',
      'Srgba::new%(()[%d.,%s]+()%)',
    },
    -- You can add as many patterns as you want.
  }
}
```

Highlighting can be controlled at runtime:

```lua
require("oklch-color-picker.highlight").disable()
require("oklch-color-picker.highlight").enable()
require("oklch-color-picker.highlight").toggle()
```

### Color Formats

The picker application supports the following formats: (`hex`, `rgb`, `oklch`, `hsl`, `raw_rgb`, `raw_rgb_float`, `raw_rgb_linear`, `raw_oklch`).
Most of these are auto detected. The non-raw formats are used in css and easily auto detected because the colors are surrounded by `rgb()` etc.

The raw formats are just lists of numbers separated by commas that can be used with any programming language. The picker auto detection assumes raw formats to be either integer `0-255` or float `0.0-1.0` srgb colors (formats `raw_rgb` or `raw_rgb_float`). For `raw_rgb_linear` or `raw_oklch` values you have to specify the format manually. Note that the picker accepts colors with and without alpha (3 or 4 numbers separated by commas).

### Patterns

The patterns used are normal lua patterns. Css color are mostly already supported, so you should probably only add raw color formats to better support the languages you use.

The default `numbers_in_brackets` should already handle most needs. It matches any number of digits, dots and commas inside brackets. The numbers are validated by the picker application so the pattern doesn't need to specify exact number matching. You can still create your own patterns if you have linear colors that can't be auto detected or if your type names clash with css patterns.

The patterns should contain two empty groups `()` to designate the replacement range. E.g. `vec3%(()[%d.,%s]+()%)` will find `.1,.2,.2` from within the text `vec3(.1,.2,.3)`. `[%d.,%s]+` means one or more digits, dots, commas or whitespace characters. Remember to escape literal brackets like this: `%(`.

## Why is the highlighting async and just how fast is it?

I don't like how an insignificant feature like color highlighting can hog CPU resources and cause lag, so this plugin tries to make it fast and unnoticeable. The highlighting is done on a timer after edits to give the immediate CPU time to features you actually care about like Treesitter or LSP. Then after the timer delay has passed, the colors are searched and highlights applied. You can also set the delay to 0 to make highlighting instant.

When you open a new buffer or scroll the view, a whole screen update is done. With my AMD Ryzen 7 5800X3D, this takes around 0.5 ms on a 65 rows by 120 cols window, full of text and 10 hex colors. When the window is filled with 1000 hex colors, the update takes 3 ms, almost half of which is unavoidable Nvim extmark updating overhead.

When editing, only the changed lines are updated. In the common case, when inserting on a line with no colors, the update takes less than 0.05 ms. When inserting on a line with a few colors, the update takes 0.2 ms.

## Other similar plugins

- [KabbAmine/vCoolor.vim](https://github.com/KabbAmine/vCoolor.vim)
- [uga-rosa/ccc.nvim](https://github.com/uga-rosa/ccc.nvim)
- [ziontee113/color-picker.nvim](https://github.com/ziontee113/color-picker.nvim)
- [My previous attempt (oklch-color-picker-0.nvim)](https://github.com/eero-lehtinen/oklch-color-picker-0.nvim)
