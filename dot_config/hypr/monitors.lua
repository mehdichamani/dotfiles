-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 1

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

-- Monitor 1: MSI MP275 E2 (27" 120Hz) - Main Display
hl.monitor({ output = "DP-1", mode = "1920x1080@120", position = "0x0", scale = omarchy_monitor_scale })

-- Monitor 2: Samsung LS24D300G (24" 100Hz) - Secondary Display (Right)
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@100", position = "1920x0", scale = omarchy_monitor_scale })

-- Dedicated Workspace Ranges:
-- DP-1 (Main): Workspaces 1-5
hl.workspace_rule({ workspace = "1", monitor = "DP-1", default = true })
hl.workspace_rule({ workspace = "2", monitor = "DP-1" })
hl.workspace_rule({ workspace = "3", monitor = "DP-1" })

-- HDMI-A-1 (Secondary): Workspaces 6-10
hl.workspace_rule({ workspace = "4", monitor = "HDMI-A-1", default = true })
hl.workspace_rule({ workspace = "5", monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "6", monitor = "HDMI-A-1" })
