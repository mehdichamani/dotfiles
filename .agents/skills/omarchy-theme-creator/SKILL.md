---
name: omarchy-theme-creator
description: >-
  Create, customize, and structure Omarchy Linux themes from images or color palettes.
  Covers token-efficient palette extraction, wallpaper handling, colors.toml, preview.png,
  optional Plymouth/SDDM unlock screens when requested, and chezmoi tracking.
---

# Omarchy Theme Creator Skill

This skill provides a standardized, clean workflow for creating and maintaining custom themes in Omarchy Linux.

---

## 1. Directory & File Structure of an Omarchy Theme

Each custom theme lives in `~/.config/omarchy/themes/<theme-slug>/` and contains:

```
~/.config/omarchy/themes/<theme-slug>/
├── colors.toml               # Core 16-color ANSI & surface palette
├── shell.lock.toml           # (Optional) Text and border colors for shell lock screen
├── preview.png               # 16:9 theme picker thumbnail (e.g. 960x540)
├── backgrounds/              # Wallpapers for this theme (16:9 Landscape)
│   ├── <name>1.jpg
│   └── <name>2.jpg
├── unlock.png                # [ONLY IF EXPLICITLY REQUESTED] Logo/badge for Plymouth & SDDM login screen
└── preview-unlock.png        # [ONLY IF EXPLICITLY REQUESTED] 1920x1080 preview shown in "Unlock" switcher
```

---

## 2. Token-Efficient Color Palette Extraction (Python)

When creating a theme from images, **NEVER read large raw images into the AI context**. Always use local Python with `PIL` on downscaled in-memory thumbnails:

```python
from PIL import Image
import colorsys

# 1. Resize in memory to 64x64 or 128x128
im = Image.open("image.jpg").resize((64, 64)).convert("RGB")
pixels = list(im.getdata())

# 2. Extract dominant and vibrant accent colors
# Sort by saturation * value to find signature neon / highlight colors
vibrant = []
for r, g, b in pixels:
    h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    vibrant.append((s * v, h * 360, s, v, r, g, b))
vibrant.sort(key=lambda x: x[0], reverse=True)
```

---

## 3. Formatting `colors.toml`

Create `~/.config/omarchy/themes/<theme-slug>/colors.toml`:

```toml
mode = "dark"

accent = "#eb2abc"
selection = "#2a1e38"
muted = "#5d5778"

background = "#0c0d14"
dark_background = "#08080e"
darker_background = "#050508"
lighter_background = "#181a28"

foreground = "#d8ddf2"
dark_foreground = "#6d7396"
light_foreground = "#b8bfdf"
bright_foreground = "#f0f3ff"

red = "#eb2a70"
yellow = "#f5c542"
orange = "#ff7844"
green = "#2bd99f"
cyan = "#12c4e0"
blue = "#2080f6"
magenta = "#eb2abc"
brown = "#7a4258"

bright_red = "#ff4d8d"
bright_yellow = "#ffd666"
bright_green = "#4ef2b8"
bright_cyan = "#38e0fc"
bright_blue = "#4fa5ff"
bright_magenta = "#ff55d4"
```

---

## 4. Wallpapers & Orientation

1. Ensure wallpapers are in **Landscape (16:9 / horizontal)** format.
2. If images are portrait (9:16), rotate them (e.g. 90° counter-clockwise):
   ```python
   rotated = im.transpose(Image.Transpose.ROTATE_90)
   rotated.save("backgrounds/wall.jpg", quality=95)
   ```
3. Place in `~/.config/omarchy/themes/<theme-slug>/backgrounds/`.

---

## 5. Theme Previews (`preview.png`)

Omarchy's theme switcher (`omarchy-theme-switcher` / `omarchy menu` -> Theme) requires `preview.png`:

```python
im = Image.open("backgrounds/wall1.jpg")
preview = im.copy()
preview.thumbnail((960, 540))
preview.save("preview.png", "PNG")
```

If cached previews are stale, clear cache and regenerate:
```bash
rm -rf ~/.cache/omarchy/theme-selector ~/.cache/omarchy/image-selector
omarchy-theme-switcher --preload
```

---

## 6. Plymouth / SDDM Boot & Login Screen ("Unlock" Menu) — OPTIONAL

> [!NOTE]
> **Only create `unlock.png` and `preview-unlock.png` if the user explicitly asks for Plymouth/boot/login unlock screen customization.**

When requested:
1. **`unlock.png`**: The logo/emblem centered on the boot/login screen.
   - Extract the signature motif or eye/emblem from the wallpaper.
   - Apply soft radial feathering/transparency around the edges.
   - Save to `~/.config/omarchy/themes/<theme-slug>/unlock.png`.

2. **`preview-unlock.png`**: 1920x1080 mock preview of the boot screen.
   - Background matching theme background `#0c0d14`.
   - `unlock.png` centered at the top.
   - Password entry box and lock icon below tinted in foreground color.
   - Save to `~/.config/omarchy/themes/<theme-slug>/preview-unlock.png`.

3. **Applying Unlock Style**:
   ```bash
   omarchy plymouth set <Theme-Name>
   ```

---

## 7. Applying & Chezmoi Tracking

```bash
# Apply the theme
omarchy theme set <theme-slug>

# Track in Chezmoi
chezmoi add ~/.config/omarchy/themes/<theme-slug>
```
