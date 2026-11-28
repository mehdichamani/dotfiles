-- Window rules: floating, scratchpad, and workspace assignments.

-- =============================================================================
-- Scratchpad (Super+S)
-- =============================================================================
o.window("PattN", { float = true, size = { 1047, 688 }, workspace = "special:scratchpad silent" })
o.window("app.hiddify.com", { float = true, size = { 406, 602 }, workspace = "special:scratchpad silent" })
o.window("com.arman.firefoxvpn", { float = true, size = { 400, 521 }, workspace = "special:scratchpad silent" })
o.window("Windscribe", { float = true, center = true, size = { 1048, 734 }, workspace = "special:scratchpad silent" })

-- =============================================================================
-- Floating Windows
-- =============================================================================
o.window("org.gnome.Nautilus", { float = true })
o.window("org.gnome.Loupe", { tag = "+floating-window" })
o.window("org.localsend.localsend_app", { float = true })
o.window({ class = "^org\\.remmina\\.Remmina$", title = "^Remmina Remote Desktop Client$" }, { float = true })

-- =============================================================================
-- Workspace Assignments
-- =============================================================================
o.window("antigravity", { workspace = "1" })
o.window("com.microsoft.VSCode", { workspace = "2" })
o.window("md.obsidian.Obsidian", { workspace = "5" })
o.window("firefox", { workspace = "6" })
o.window("org.remmina.Remmina", { workspace = "7" })
o.window("(xfreerdp|xfreerdp3|wlfreerdp|FreeRDP)", { workspace = "7" })
o.window("gliff", { workspace = "7" })
o.window("zuno", { workspace = "8" })
