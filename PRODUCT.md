# Product

## Register

product

## Users
macOS power users who like Hyprland and Linux desktop customization but need a native, dependable macOS tool. They want to shape a persistent desktop bar, shortcuts, colors, modules, and wallpapers without maintaining shell scripts.

## Product Purpose
Hyprshell renders its own native multi-display top bar, provides Hyprland-style window tiling, and offers one place to customize appearance, modules, global controls, named bar configurations, themes, and wallpapers. Success means a user can install the app, choose or build a bar visually, map Option+W to the wallpaper gallery, and keep the setup working after relaunch without installing SketchyBar or running a web service.

## Brand Personality
Technical, tactile, and composed. It combines the density and directness of a well-made Linux desktop with the reliability and legibility of a native macOS utility.

## Anti-references
Not a SaaS dashboard, not a decorative glassmorphism demo, and not a fake Linux skin that only previews settings. Avoid excessive neon, terminal cosplay, nested cards, and controls that do not affect the real desktop.

## Design Principles
1. Show the real result while editing: the live bar is the primary preview.
2. Native first: use macOS frameworks for windows, wallpapers, screens, persistence, and global shortcuts.
3. Power without config-file tax: expose detailed controls visually and save them as a portable JSON profile.
4. Source fidelity, macOS behavior: preserve the exact information architecture, proportions, palette, controls, and interaction model from `sebastianmiletic/hyprland-dotfiles`, replacing only Linux-specific system calls with native macOS equivalents.
5. Every control must work: disable or explain anything that requires macOS permission.

## Accessibility & Inclusion
Target WCAG AA contrast where user-selected colors permit it. Support keyboard navigation, VoiceOver labels, reduced motion, and symbols plus text or shape so state never relies on color alone.
