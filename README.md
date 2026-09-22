# Waycode

Waycode is a native macOS desktop bar and customization app inspired by Hyprland setups. It runs as a menu-bar utility without a Dock icon, renders its own notch-aware multi-display bar, and includes a live widget editor, global shortcut mapping, native wallpaper gallery, JSON profiles, shell widgets, and a port of the Sebastian II Quickshell bar from `sebastianmiletic/hyprland-dotfiles`.

## Requirements

- macOS 13 or newer
- Swift 5.9 or newer to build

## Build and run

```bash
swift build
swift run Waycode
```

Build a signed local application bundle:

```bash
./scripts/build-app.sh
open dist/Waycode.app
```

Move `dist/Waycode.app` to `/Applications` to make Launch at Login registration available.

## First run

1. Open **Bar** and choose placement, height, radius, inset, and opacity. The desktop bar updates live.
2. Waycode reads `NSScreen` safe areas on each display and keeps the center clear on MacBooks with a notch. Enable **Split bar around notch** to stop the left and right surfaces before the camera area. The preview simulates the protected area.
3. **Sebastian II · 1:1** reproduces the source QML's 42pt base height, 5pt outer gap, 4pt center spacing, 18pt rounding, full `bb7de91` palette, source module order, and grouped status treatment. The style library is a three-column gallery rendered by the production `BarView`. Module islands and Nord intentionally have no enclosing bar box. Connected edge-to-edge presentation is a separate setting, so it can be combined with any style.
4. Enable **Black notch shelf** under Bar > Placement to paint the physical notch row with an opaque RGB `0,0,0`, square-edged mask and move the complete Waycode bar below it. macOS and MacBook display hardware do not expose an API for disabling only the notch-row backlight, so software cannot physically turn off that strip. The opaque zero-RGB mask is the darkest result the panel can produce.
5. Open **Widgets** to edit the same `BarView` renderer used on the desktop. Drag widgets directly across Far left, Before notch, After notch, and Far right, or use the detailed controls. Every widget has its own SF Symbol or image, visibility, pill style, text color, background, typography, padding, radius, and click action.
6. Add a **Shell widget** to display the first output line from any local command on a configurable refresh interval.
7. Desktop buttons now read the real ordered Mission Control Spaces every 50 ms and also react directly to Space-change notifications. The selected number updates without a visual animation or artificial delay, including during trackpad and Control+Arrow changes. The active-application label uses notifications plus an 80 ms frontmost-app monitor. Clicking a number updates optimistically before sending the native Control+Number shortcut.
8. Press **Option+W** from any app or Space to toggle the wallpaper library. Its content is a custom palette-driven SwiftUI interface with a cleaner branded header, themed search, category previews, grid/carousel modes, favorites, keyboard navigation, and focused Apply action. AppKit is used only as the required native borderless window host. Archive installation preserves the original category folders.
9. Option+W, Option+A, and Option+N are fixed system-wide macOS hotkeys registered directly against Carbon’s global event dispatcher; they no longer depend on the in-app keybind list, settings window, or application focus. Global key-state polling and a passive event monitor remain as fallbacks with duplicate suppression. Option+1 through Option+9 select the matching Mission Control desktop.
10. Click the Arch mark or press **Option+A** for the Gemini assistant. Press **Option+N** for Controls. Clicking the bar battery toggles Low Power Mode directly without opening a Waycode panel or popover. Battery symbols track fullness and are always white normally or yellow in Low Power Mode—never green. A bolt is overlaid whenever the Mac is charging.
11. The Transparency control is expressed in the expected direction: 0% is opaque and 100% is transparent. Bar panels participate separately in each Space instead of exposing a stationary panel over the compositor's black transition frame. Optional Blur uses a cached wallpaper-backed texture instead of `NSVisualEffectView`, preventing macOS from changing material emphasis during four-finger Space gestures. Changes save automatically to `~/Library/Application Support/Waycode/config.json`.
12. Waycode checks notification and Location authorization silently and never opens a permission prompt at launch. Clicking Wi-Fi no longer requests Location: an existing grant enables nearby SSID scanning, while Wi-Fi power and current status remain available without it. Accessibility checks are also silent. Production builds use the stable `Termatica Release Signing` identity so macOS can retain TCC grants across updates.
13. **Tiling** is an event-driven Hyprland-style window manager. With one existing window, opening a second splits the desktop exactly into the original client on the left and the new client on the right, respecting configured gaps. Additional clients recursively split the remaining leaf using Hyprland dwindle behavior. Window identity uses stable Core Graphics window numbers, and current-Space detection uses public on-screen window data so other desktops are not moved. Launch, window-created, close, minimize, activation, and display events trigger automatic reflow. Dialogs, fullscreen windows, fixed-size windows, and exceptions float. Waycode checks Accessibility silently; it only displays the macOS permission request after the user explicitly presses **Grant Accessibility**.
14. The settings interface is implemented in SwiftUI with a custom navigation rail, centered live bar, interactive style previews, and custom surfaces. AppKit is restricted to macOS window-level integration; no C UI toolkit is used. The settings window stays above normal application windows when opened.
15. Use the Waycode icon in the macOS menu bar, or the gear widget in the desktop bar, to reopen settings after closing the window.
16. The supported plan for custom Waycode-initiated workspace animations is documented in `TRANSITIONS_PLAN.md`. macOS does not provide a supported way to replace or retime the native four-finger Mission Control animation itself.

For a full replacement look, turn on macOS menu bar auto-hide in **System Settings > Desktop & Dock**. Waycode deliberately does not modify that system preference behind your back.

## Configuration

Waycode stores configuration at:

```text
~/Library/Application Support/Waycode/config.json
```

Profiles can be imported and exported from the General screen. No web server, JavaScript runtime, SketchyBar installation, or Linux compatibility layer is used.

## Upstream preset

See [ATTRIBUTION.md](ATTRIBUTION.md). The upstream repository uses Quickshell rather than Waybar. Waycode ports the real module arrangement, palette, and wallpaper shortcut to native macOS behavior.
