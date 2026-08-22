local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- ۱. شل پیش‌فرض
config.default_prog = { 'pwsh.exe', '-NoLogo' }

-- ۲. زبان فارسی و فونت
config.bidi_enabled = true
config.bidi_direction = 'LeftToRight'
config.font = wezterm.font_with_fallback({
  'Hurmit Nerd Font',
  'Vazirmatn',
  'Segoe UI',
})
config.font_size = 11.0

-- ۳. ظاهر و تم رنگی (گزینه‌های پیشنهادی: 'Catppuccin Mocha' یا 'Tokyo Night')
config.color_scheme = 'Catppuccin Mocha'

-- ۴. شیشه‌ای کردن پس‌زمینه (ویندوز ۱۱)
config.win32_system_backdrop = 'Mica' -- یا 'Acrylic'

-- ۵. بهینه‌سازی کادر و تب‌بار
-- دکوراسیون کامل همراه با دکمه‌های بالایی و قابلیت جابجایی
config.window_decorations = 'INTEGRATED_BUTTONS|RESIZE'
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = false
config.window_padding = {
  left = 12,
  right = 12,
  top = 10,
  bottom = 8,
}

-- ۶. مکان‌نما (Cursor)
config.default_cursor_style = 'BlinkingBar'
config.cursor_blink_rate = 600

-- ۷. کلیدهای میانبر کاربردی
config.keys = {
  -- ساخت تب جدید با باز شدن در همان مسیر
  { key = 't', mods = 'CTRL|SHIFT', action = wezterm.action.SpawnTab 'CurrentPaneDomain' },
  -- تقسیم صفحه افقی و عمودی (Splits)
  { key = 'd', mods = 'CTRL|ALT', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 's', mods = 'CTRL|ALT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  -- بستن پن فعلی
  { key = 'w', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentPane { confirm = false } },
  -- کپی و پیست استاندارد
  { key = 'c', mods = 'CTRL|SHIFT', action = wezterm.action.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL|SHIFT', action = wezterm.action.PasteFrom 'Clipboard' },
}

return config