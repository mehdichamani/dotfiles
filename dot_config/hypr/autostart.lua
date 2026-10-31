-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Window rules: float and size into scratchpad (Super+S)
o.window("PattN", { float = true, center = true, size = { 1048, 734 }, workspace = "special:scratchpad silent" })
o.window("com.arman.firefoxvpn", { float = true, center = true, size = { 1048, 734 }, workspace = "special:scratchpad silent" })

-- Workspace assignments
o.window("antigravity-ide", { workspace = "1" })
o.window("firefox", { workspace = "2" })
o.window("antigravity", { workspace = "3" })
o.window("md.obsidian.Obsidian", { workspace = "4" })
o.window("org.remmina.Remmina", { workspace = "5" })
o.window("(xfreerdp|xfreerdp3|wlfreerdp|FreeRDP)", { workspace = "6" })

