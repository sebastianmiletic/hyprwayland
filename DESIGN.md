---
name: Hyprshell
description: A native macOS control surface for a Linux-shaped desktop.
colors:
  charred-plum: "#141313"
  raised-plum: "#2D2A2F"
  pearl-text: "#E6E1E1"
  smoke-text: "#948F94"
  mineral-accent: "#CBC4CB"
  sage-success: "#B5CCBA"
typography:
  title:
    fontFamily: "SF Pro Rounded, -apple-system, sans-serif"
    fontSize: "27px"
    fontWeight: 700
    lineHeight: 1.2
  body:
    fontFamily: "SF Pro Text, -apple-system, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.45
  label:
    fontFamily: "SF Pro Text, -apple-system, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.2
rounded:
  control: "7px"
  group: "12px"
  bar: "17px"
  pill: "999px"
spacing:
  xs: "5px"
  sm: "8px"
  md: "12px"
  lg: "18px"
  xl: "28px"
components:
  desktop-bar:
    backgroundColor: "{colors.charred-plum}"
    textColor: "{colors.pearl-text}"
    rounded: "{rounded.bar}"
    height: "38px"
    padding: "0 12px"
  selected-workspace:
    backgroundColor: "{colors.mineral-accent}"
    textColor: "{colors.charred-plum}"
    rounded: "{rounded.pill}"
    size: "24px"
  settings-group:
    backgroundColor: "{colors.raised-plum}"
    textColor: "{colors.pearl-text}"
    rounded: "{rounded.group}"
    padding: "18px"
---

# Design System: Hyprshell

## 1. Overview

**Creative North Star: "The Native Rice Workbench"**

Hyprshell should feel like a carefully tuned desktop environment that happens to obey macOS conventions. The persistent bar is compact and expressive; the editor is calmer and more familiar so users can make consequential desktop changes with confidence.

The system is technical, tactile, and composed. Density is welcome where it supports scanning, but decoration never competes with status or control. It explicitly rejects SaaS dashboard framing, decorative glassmorphism, terminal cosplay, nested cards, and controls that only simulate an outcome.

**Key Characteristics:**
- The Sebastian II bar, wallpaper selector, and both sidebars mapped directly from the source QML at commit `bb7de91`.
- A dense, rounded bar paired with a quiet native editor.
- Immediate live feedback for every visual change.
- A visible protected notch zone with symmetric left and right segments that can stop before the camera area.
- Muted mineral color with rare, meaningful state emphasis.
- Familiar macOS labels, controls, focus behavior, and keyboard access.

## 2. Colors

The default Sebastian II palette uses warm charcoal and mineral neutrals rather than generic blue-black developer tooling.

### Primary
- **Mineral Accent:** Selection, active workspace, and focused controls only.

### Secondary
- **Sage Success:** Saved, connected, and healthy state indicators.

### Neutral
- **Charred Plum:** The bar foundation and deepest surface.
- **Raised Plum:** Module pills and grouped controls.
- **Pearl Text:** High-emphasis labels and values.
- **Smoke Text:** Supporting copy and inactive status.

**The Earned Accent Rule.** Accent marks selection or action. It is never ambient decoration.

**The User Palette Rule.** Custom colors are allowed, but symbols and labels must continue to carry state when contrast becomes weak.

## 3. Typography

**Display Font:** SF Pro Rounded (with the macOS system fallback)
**Body Font:** SF Pro Text (with the macOS system fallback)
**Label/Mono Font:** SF Mono for shortcut and color values

**Character:** Native system typography keeps a high-control customization tool legible. Rounded headings and bar labels echo the source desktop without introducing an ornamental display face.

### Hierarchy
- **Display** (700, 27px, 1.2): Page titles only.
- **Headline** (600, 17px, 1.25): Major empty states and gallery headings.
- **Title** (600, 13px, 1.3): Setting names and theme names.
- **Body** (400, 13px, 1.45): Explanations, capped near 70 characters when practical.
- **Label** (600, 12px, 0.7px tracking when uppercase): Group labels, status values, and bar modules.

**The Native Scale Rule.** Product copy stays within the macOS type scale. Large typography must never displace useful controls.

## 4. Elevation

Hyprshell is flat by default. Depth comes from tonal layering, thin neutral outlines, native macOS material blur, and window hierarchy. Real desktop blur is user-controlled for the bar and side panels; tint opacity determines how much live wallpaper remains visible. The bar uses no shadow because it already occupies the highest desktop layer; settings groups use a subtle full perimeter stroke rather than dramatic lift.

**The Tonal Depth Rule.** Use surface contrast first. A shadow is reserved for an actual floating system window, never for routine settings groups.

## 5. Components

### Buttons
- **Shape:** Native macOS controls in the editor; circular or capsule hit areas in the bar.
- **Primary:** System accent with standard control padding.
- **Hover / Focus:** Native focus ring and a 160ms state transition where custom drawing is used.
- **Ghost:** Bar utility controls use no background at rest and a tinted circular pressed state.

### Chips
- **Style:** Module and workspace chips use Raised Plum and compact 24 to 28px heights.
- **State:** Active workspaces invert to Mineral Accent with Charred Plum text.

### Cards / Containers
- **Corner Style:** Gently curved groups (12px).
- **Background:** One raised neutral layer.
- **Shadow Strategy:** None at rest.
- **Border:** A full 1px neutral stroke at low opacity.
- **Internal Padding:** 18px.

### Inputs / Fields
- **Style:** Native sliders, pickers, toggles, steppers, and color wells.
- **Focus:** Standard macOS focus treatment.
- **Error / Disabled:** Supporting text explains required permissions or unavailable development-only behavior.

### Navigation
- A native sidebar uses icon plus label, a persistent selected state, and standard keyboard navigation. It collapses only when the host window requires it.

### Source Sidebars
- The Arch mark opens the source tab structure: Assistant, Translator, and Anime.
- Clock and status controls open the right control center with uptime, system actions, sliders, two-column quick toggles, resource indicators, calendar, and tasks.
- Wi-Fi, sound, and battery drill into interactive native controls rather than static status displays.
- Sidebar surfaces use the source Layer 0 and Layer 1 hierarchy, 17 to 18px rounding, compact 9 to 10px gaps, and full perimeter outlines.

### Wallpaper Selector
- The selector is an 880 to 900px by 380 to 420px floating surface derived directly from `WallpaperSelectorContent.qml`.
- It provides current-wallpaper home, a 310px search field, carousel and grid modes, favorites, random selection, keyboard-friendly controls, and wallpaper-derived colors.

### Desktop Bar
- The bar is a nonactivating AppKit panel rendered on each selected display.
- Far left, before-notch, after-notch, and far-right zones keep controls clear of MacBook camera hardware using native screen safe areas.
- Split mode renders equal-width left and right surfaces, preventing visual drift and stopping both backgrounds before the notch.
- Every widget exposes position, order, SF Symbol, icon/value visibility, plain/filled/outlined treatment, foreground, background, and click action.
- Shell widgets display local command output at a user-controlled interval.
- Geometry and palette updates are live. Widget removal must reflow rather than leave empty placeholders.

## 6. Do's and Don'ts

### Do:
- **Do** show the real desktop bar while its controls are being edited.
- **Do** use Charred Plum, Raised Plum, and Pearl Text as the default tonal hierarchy.
- **Do** preserve native keyboard navigation, VoiceOver labels, and reduced-motion behavior.
- **Do** preview the MacBook notch and all four widget zones while editing.
- **Do** keep a settings gear in the desktop bar and a persistent Hyprshell menu-bar item.
- **Do** explain macOS permissions and system shortcut prerequisites next to the affected control.

### Don't:
- **Don't** make this look like a SaaS dashboard.
- **Don't** use decorative glassmorphism, excessive neon, terminal cosplay, or nested cards.
- **Don't** add controls that only preview an effect and do not affect the real desktop.
- **Don't** use a colored side stripe, gradient text, or an animated layout property.
- **Don't** hide failures. Wallpaper, login-item, and permission errors need plain language feedback.
