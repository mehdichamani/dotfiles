-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")
o.bind("SUPER + E", "File Manager", "nautilus")

-- Open Omarchy menu by pressing Super alone
o.bind("SUPER + SUPER_L", "Omarchy menu", "omarchy-menu toggle", { release = true })

-- Unbind default SUPER + SPACE from Omarchy menu so Super+Space toggles keyboard layout directly via xkb
hl.unbind("SUPER + SPACE")

-- VS Code (with proxy)
o.bind("SUPER + A", "VS Code", { launch = "withproxy code" })

-- Antigravity IDE (with proxy)
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Antigravity IDE", { launch = "withproxy antigravity-ide" })

-- Obsidian (replace default Pop window out with Obsidian)
hl.unbind("SUPER + O")
o.bind("SUPER + O", "Obsidian", "obsidian")

-- Clipboard manager (replace default Universal paste with Clipboard manager history)
hl.unbind("SUPER + V")
o.bind("SUPER + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")

-- Swap Lock system (SUPER + CTRL + L -> SUPER + L) and Toggle workspace layout (SUPER + L -> SUPER + CTRL + L)
hl.unbind("SUPER + L")
hl.unbind("SUPER + CTRL + L")
o.bind("SUPER + L", "Lock system", "omarchy-system-lock")
o.bind("SUPER + CTRL + L", "Toggle workspace layout", "omarchy-hyprland-workspace-layout-toggle")

-- Floating default terminal
o.bind("SUPER + grave", "Floating Terminal", "setsid uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.terminal --dir=\"$(omarchy-cmd-terminal-cwd)\"")

-- Auto-load keybindings from installed Omarchy plugins
local plugins_dir = os.getenv("HOME") .. "/.config/omarchy/plugins"
local p = io.popen("find " .. plugins_dir .. " -maxdepth 3 -name 'bindings.lua' 2>/dev/null")
if p then
  for file in p:lines() do
    dofile(file)
  end
  p:close()
end
