# Ryft

Ryft is a native macOS desktop bar and customization app inspired by Hyprland setups. It runs as a menu-bar utility without a Dock icon, renders its own notch-aware multi-display bar, and includes a live widget editor, global shortcut mapping, native wallpaper gallery, JSON profiles, shell widgets, and a port of the Sebastian II Quickshell bar from `sebastianmiletic/hyprland-dotfiles`.

Repository: <https://github.com/sebastianmiletic/ryft>

## Requirements

- macOS 13 or newer
- Swift 5.9 or newer to build

## Build and run

```bash
swift build
swift run Ryft
```

Build a signed local application bundle:

```bash
./scripts/build-app.sh
open dist/Ryft.app
```

Move `dist/Ryft.app` to `/Applications` to make Launch at Login registration available.

## First run

1. Open **Bar** and choose **Floating**, **Touching edges**, or **Top and edges**, then tune height, radius, inset, and opacity. The desktop bar updates live.
2. Ryft reads `NSScreen` safe areas on each display and keeps the center clear on MacBooks with a notch. Enable **Bar avoids notch** to stop the left and right surfaces before the camera area. The preview represents the protected spacing without drawing fake hardware.
3. **Sebastian II · 1:1** reproduces the source QML's 42pt base height, 5pt outer gap, 4pt center spacing, 18pt rounding, full `bb7de91` palette, source module order, and grouped status treatment. The style library shows one centered production-rendered `BarView` preview per row. Every preview follows the current notch-avoidance choices through spacing and splitting, without drawing a fake notch. Module islands and Nord intentionally have no enclosing bar box.
4. **Widgets avoid notch** reserves center space only for controls while keeping a continuous bar surface. **Bar avoids notch** splits the complete bar surface and widgets around the camera area. Enable **Black notch shelf** to paint the physical notch row with opaque RGB `0,0,0` and move the complete Ryft bar below it.
5. Open **Widgets** to edit the same `BarView` renderer used on the desktop. Drag widgets directly across Far left, Before notch, After notch, and Far right, or use the detailed controls. Every widget has its own SF Symbol or image, visibility, pill style, text color, background, typography, padding, radius, and click action.
6. Open **Tiling** to enable Ryft’s built-in Hyprland-style Dwindle engine. One visible application is left untouched. Opening a second application splits the usable display in half; each additional application recursively splits the remaining area. No helper app, download, extra menu-bar item, or competing shortcut system is used.
7. Add a **Shell widget** to display the first output line from any local command on a configurable refresh interval.
8. Desktop buttons read the real ordered Mission Control Spaces every 50 ms and react directly to Space-change notifications. An optional mode replaces each occupied desktop number with the circular icon of its first standard application; empty desktops retain their number. With the optional Screen Recording grant, Ryft-initiated switches use a 220 ms outgoing-desktop slide over a direct SkyLight Space change while the bar remains fixed. Settings closes automatically when the active Space changes.
9. The enabled **Wallpaper** add-on sits on the far left of the bar. Its palette-driven SwiftUI carousel has no generic title bar or loading spinner. Left/Right selects a preview and Return applies it to the current desktop. Down moves keyboard focus to the two apply actions, Left/Right chooses one, Return activates it, and Up returns to previews. **Apply to all desktops** visits every ordinary SkyLight-managed Mission Control Space, writes the wallpaper with `NSWorkspace`, and restores the originally active Spaces; it does not depend on Control-number shortcuts or System Events exposing only the current desktop.
10. Wallpaper command shortcuts, including Option+W and Random Wallpaper, are removed from configuration and the keybind editor. Option+A and Option+N remain system-wide sidebar shortcuts. Bar controls use a consistent press response, the Controls button is a real button, and clicking Settings again closes its window.
11. The assistant control is a simple white, rounded four-point sparkle. Gemini uses the source configuration’s exact text routing order and daily Pacific-time quotas: Gemini 3.5 Flash Lite, Gemini 3.1 Flash Lite, Gemma 4 31B, then Gemini 3.7, 3.6, and 3 Flash. It automatically falls back on unavailable or exhausted models, displays model usage and token counts, preserves local conversation history, and supports new chat, copy, and stop controls. The API key uses a non-interactive Keychain account so opening or using Gemini never requests the Mac login password. The source prompt behavior, temperature 0.5, macOS context substitutions, and output rules are preserved.
12. The Transparency control is expressed in the expected direction: 0% is opaque and 100% is transparent. The experimental stationary bar stays above macOS Space motion. Optional Blur uses a cached wallpaper-backed texture instead of `NSVisualEffectView`. Changes save automatically to `~/Library/Application Support/Ryft/config.json`.
13. Ryft never opens a Location prompt at launch. The first explicit Wi-Fi click may request Location once because macOS requires it to reveal SSIDs; the decision is remembered and never re-requested by Ryft. The themed Wi-Fi popover then lists every scanned network, supports secure password entry and Return-to-connect, and retains power/current-network controls.
14. The first launch opens a concise, skippable Permissions and Quick Start flow. Those onboarding tabs disappear after completion; relevant experimental permissions remain available in General. The compact semi-transparent settings workbench gives custom buttons, navigation items, wallpapers, themes, and style previews consistent hover and press feedback.
15. Use the Ryft icon in the macOS menu bar, or the gear widget in the desktop bar, to reopen settings after closing the window. Each opening lands on a one-time navigation home view showing the active wallpaper and clean Mac, system, memory, processor, display, and uptime specifications; Overview is intentionally absent from the settings navigation.
16. General includes an optional Bibata Modern Classic cursor matching the source Hyprland setup. Because macOS has no cursor-theme API, Ryft implements it as an experimental global pointer overlay and restores the native cursor immediately when disabled or when Ryft quits. macOS does not expose a supported way to replace the native four-finger Mission Control animation; trackpad transitions retain Apple’s timing with the Ryft bar held stationary.

While Ryft runs, it hides the native menu bar and renders the matching wallpaper crop beneath its own bar so the system menu cannot show through transparent space. Native menu-bar visibility is restored when Ryft quits. Both side panels sit below this cover; Gemini stays open until explicitly dismissed, while Controls uses a longer inactivity timeout.

## Configuration

Ryft stores configuration at:

```text
~/Library/Application Support/Ryft/config.json
```

Profiles can be imported and exported from the General screen. No web server, JavaScript runtime, SketchyBar installation, or Linux compatibility layer is used.

## Upstream preset

See [ATTRIBUTION.md](ATTRIBUTION.md). The upstream repository uses Quickshell rather than Waybar. Ryft ports the real module arrangement and palette to native macOS behavior.
