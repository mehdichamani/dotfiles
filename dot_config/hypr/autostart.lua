-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Window rules: float, size and position into scratchpad (Super+S)
o.window("PattN", { float = true, size = { 1047, 688 }, workspace = "special:scratchpad silent" })
o.window("app.hiddify.com", { float = true, size = { 406, 602 }, workspace = "special:scratchpad silent" })
o.window("com.arman.firefoxvpn", { float = true, size = { 400, 521 }, workspace = "special:scratchpad silent" })
o.window("Windscribe", { float = true, center = true, size = { 1048, 734 }, workspace = "special:scratchpad silent" })

-- Enforce exact positions for scratchpad windows upon launch
local scratchpad_layout = {
  ["PattN"] = { x = 585, y = -1038, w = 1047, h = 688 },
  ["app.hiddify.com"] = { x = 1655, y = -607, w = 406, h = 602 },
  ["com.arman.firefoxvpn"] = { x = 161, y = -530, w = 400, h = 521 },
}

hl.on("window.open", function(win)
  if not win or not win.class then return end
  local cfg = scratchpad_layout[win.class]
  if cfg then
    hl.timer(function()
      local target = "address:" .. win.address
      hl.dispatch(hl.dsp.window.move({ x = cfg.x, y = cfg.y, relative = false, window = target }))
      hl.dispatch(hl.dsp.window.resize({ x = cfg.w, y = cfg.h, relative = false, window = target }))
    end, { timeout = 50, type = "oneshot" })
  end
end)

-- Workspace assignments
o.window("antigravity", { workspace = "1" })
o.window("com.microsoft.VSCode", { workspace = "2" })
o.window("firefox", { workspace = "3" })
o.window("md.obsidian.Obsidian", { workspace = "4" })
o.window("org.remmina.Remmina", { workspace = "5" })
o.window("(xfreerdp|xfreerdp3|wlfreerdp|FreeRDP)", { workspace = "6" })

