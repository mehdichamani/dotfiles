-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Launch PattN silently into the scratchpad (hidden workspace toggled by Super+S), float and size it
o.window("PattN", { float = true, center = true, size = { 1048, 734 }, workspace = "special:scratchpad silent" })
o.launch_on_start(os.getenv("HOME") .. "/.local/share/PattN/PattN")

-- Workspace assignments
o.window("antigravity-ide", { workspace = "1" })
o.window("code", { workspace = "1" })
o.window("firefox", { workspace = "2" })
o.window("md.obsidian.Obsidian", { workspace = "4" })
