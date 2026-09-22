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

1. Open **Bar** and choose placement, height, radius, inset, and opacity. The desktop bar updates live.
2. Ryft reads `NSScreen` safe areas on each display and keeps the center clear on MacBooks with a notch. Enable **Split bar around notch** to stop the left and right surfaces before the camera area. The preview simulates the protected area.
3. **Sebastian II · 1:1** reproduces the source QML's 42pt base height, 5pt outer gap, 4pt center spacing, 18pt rounding, full `bb7de91` palette, source module order, and grouped status treatment. The style library shows one vertically centered, production-rendered `BarView` preview per row. Module islands and Nord intentionally have no enclosing bar box. Connected edge-to-edge presentation is a separate setting, so it can be combined with any style.
4. Enable **Black notch shelf** under Bar > Placement to paint the physical notch row with an opaque RGB `0,0,0`, square-edged mask and move the complete Ryft bar below it. macOS and MacBook display hardware do not expose an API for disabling only the notch-row backlight, so software cannot physically turn off that strip. The opaque zero-RGB mask is the darkest result the panel can produce.
5. Open **Widgets** to edit the same `BarView` renderer used on the desktop. Drag widgets directly across Far left, Before notch, After notch, and Far right, or use the detailed controls. Every widget has its own SF Symbol or image, visibility, pill style, text color, background, typography, padding, radius, and click action.
6. Add a **Shell widget** to display the first output line from any local command on a configurable refresh interval.
7. Desktop buttons now read the real ordered Mission Control Spaces every 50 ms and also react directly to Space-change notifications. The selected number updates without a visual animation or artificial delay, including during trackpad and Control+Arrow changes. The active-application label uses notifications plus an 80 ms frontmost-app monitor. Clicking a number updates optimistically before sending the native Control+Number shortcut.
8. The enabled **Wallpaper** add-on sits on the far left of the bar. Its palette-driven SwiftUI carousel has no generic title bar or loading spinner. Left/Right selects a preview and Return applies it to the current desktop. Down moves keyboard focus to the two apply actions, Left/Right chooses one, Return activates it, and Up returns to previews. **Apply to all desktops** visits every ordinary SkyLight-managed Mission Control Space, writes the wallpaper with `NSWorkspace`, and restores the originally active Spaces; it does not depend on Control-number shortcuts or System Events exposing only the current desktop.
9. Wallpaper command shortcuts, including Option+W and Random Wallpaper, are removed from configuration and the keybind editor. Option+A and Option+N remain system-wide sidebar shortcuts. Bar controls use a consistent press response, the Controls button is a real button, and clicking Settings again closes its window.
10. The assistant control is a simple white, rounded four-point sparkle. Gemini uses the source configuration’s exact text routing order and daily Pacific-time quotas: Gemini 3.5 Flash Lite, Gemini 3.1 Flash Lite, Gemma 4 31B, then Gemini 3.7, 3.6, and 3 Flash. It automatically falls back on unavailable or exhausted models, displays model usage and token counts, preserves local conversation history, and supports new chat, copy, and stop controls. The API key uses a non-interactive Keychain account so opening or using Gemini never requests the Mac login password. The source prompt behavior, temperature 0.5, macOS context substitutions, and output rules are preserved.
11. The Transparency control is expressed in the expected direction: 0% is opaque and 100% is transparent. Bar panels participate separately in each Space instead of exposing a stationary panel over the compositor's black transition frame. Optional Blur uses a cached wallpaper-backed texture instead of `NSVisualEffectView`, preventing macOS from changing material emphasis during four-finger Space gestures. Changes save automatically to `~/Library/Application Support/Ryft/config.json`.
12. Ryft never opens a Location prompt at launch. The first explicit Wi-Fi click may request Location once because macOS requires it to reveal SSIDs; the decision is remembered and never re-requested by Ryft. The themed Wi-Fi popover then lists every scanned network, supports secure password entry and Return-to-connect, and retains power/current-network controls.
13. The first launch opens a concise, skippable Permissions and Quick Start flow. Permissions are requested only from explicit buttons and remain available as a settings page. The settings interface is a compact semi-transparent SwiftUI workbench with a custom navigation rail, centered live bar, interactive style previews, and Reduce-Motion-aware transitions.
14. Use the Ryft icon in the macOS menu bar, or the gear widget in the desktop bar, to reopen settings after closing the window. Each opening lands on a one-time navigation home view showing the active wallpaper and clean Mac, system, memory, processor, display, and uptime specifications; Overview is intentionally absent from the settings navigation.
15. The supported plan for custom Ryft-initiated workspace animations is documented in `TRANSITIONS_PLAN.md`. macOS does not provide a supported way to replace or retime the native four-finger Mission Control animation itself.

While Ryft runs, it hides the native menu bar and renders the matching wallpaper crop beneath its own bar so the system menu cannot show through transparent space. Native menu-bar visibility is restored when Ryft quits. Both side panels sit below this cover; Gemini stays open until explicitly dismissed, while Controls uses a longer inactivity timeout.

## Configuration

Ryft stores configuration at:

```text
~/Library/Application Support/Ryft/config.json
```

Profiles can be imported and exported from the General screen. No web server, JavaScript runtime, SketchyBar installation, or Linux compatibility layer is used.

## Upstream preset

See [ATTRIBUTION.md](ATTRIBUTION.md). The upstream repository uses Quickshell rather than Waybar. Ryft ports the real module arrangement and palette to native macOS behavior.
