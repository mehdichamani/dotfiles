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
hl.unbind("SUPER + CTRL + E")
o.bind("SUPER + PERIOD", "Emojis", "omarchy-shell shell toggle omarchy.emojis")
o.bind("SUPER + E", "File Manager", "strata")

-- Float Strata file manager on open
o.window("io.github.lgse.Strata", { tag = "+floating-window" })

-- Open Omarchy menu by pressing Super alone
o.bind("SUPER + SUPER_L", "Omarchy menu", "omarchy-menu toggle", { release = true })

-- Unbind default SUPER + SPACE from Omarchy menu so Super+Space toggles keyboard layout directly via xkb
hl.unbind("SUPER + SPACE")

-- Antigravity IDE (with proxy)
o.bind("SUPER + A", "Antigravity IDE", { launch = "withproxy antigravity-ide" })

-- Antigravity 2.0 App (with proxy, replace default ChatGPT webapp)
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Antigravity App", { launch = "withproxy /home/unreal/.local/bin/antigravity" })

-- Remmina
o.bind("SUPER + R", "Remmina", { launch = "remmina" })

-- Obsidian (SUPER + N)
hl.unbind("SUPER + N")
o.bind("SUPER + N", "Obsidian", "obsidian")

-- Telegram (SUPER + SHIFT + T)
hl.unbind("SUPER + SHIFT + T")
o.bind("SUPER + SHIFT + T", "Telegram", { launch = "Telegram" })

-- LocalSend (SUPER + SHIFT + S, float with current/remembered size)
hl.unbind("SUPER + SHIFT + S")
o.bind("SUPER + SHIFT + S", "LocalSend", { launch = "localsend" })
o.window("org.localsend.localsend_app", { float = true })

-- Clipboard manager (replace default Universal paste with Clipboard manager history)
hl.unbind("SUPER + V")
o.bind("SUPER + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")

-- Swap Lock system (SUPER + CTRL + L -> SUPER + L) and Toggle workspace layout (SUPER + L -> SUPER + CTRL + L)
hl.unbind("SUPER + L")
hl.unbind("SUPER + CTRL + L")
o.bind("SUPER + L", "Lock system", "omarchy-system-lock")
o.bind("SUPER + CTRL + L", "Toggle workspace layout", "omarchy-hyprland-workspace-layout-toggle")
o.bind("SUPER + SHIFT + L", "Toggle screensaver", "omarchy-toggle-screensaver")

-- Floating default terminal
o.bind("SUPER + grave", "Floating Terminal", "setsid uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.terminal --dir=\"$(omarchy-cmd-terminal-cwd)\"")

-- WezTerm (override default Tmux binding)
hl.unbind("SUPER + ALT + RETURN")
o.bind("SUPER + ALT + RETURN", "WezTerm", "setsid uwsm-app -- wezterm start --cwd \"$(omarchy-cmd-terminal-cwd)\"")

-- Auto-load keybindings from installed Omarchy plugins (including omalt-tab: io.github.codesmith28.omalt-tab)
local plugins_dir = os.getenv("HOME") .. "/.config/omarchy/plugins"
local p = io.popen("find " .. plugins_dir .. " -maxdepth 3 -name 'bindings.lua' 2>/dev/null")
if p then
  for file in p:lines() do
    dofile(file)
  end
  p:close()
end

-- strata-installer: file-manager start
hl.unbind("SUPER + SHIFT + F")
hl.unbind("SUPER + ALT + SHIFT + F")
o.bind("SUPER + SHIFT + F", "File manager", { launch = "/home/unreal/.local/bin/strata" })
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)",
  "uwsm-app -- /home/unreal/.local/bin/strata \"$(omarchy-cmd-terminal-cwd)\"")
-- strata-installer: file-manager end

