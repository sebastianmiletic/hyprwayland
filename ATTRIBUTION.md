# Attribution and source mapping

The built-in **Sebastian II · 1:1** preset uses the measured geometry, spacing, rounding, module ordering, and complete Material palette from:

- Repository: <https://github.com/sebastianmiletic/hyprland-dotfiles>
- Source revision: `bb7de915ccf47c92f6570ca1d69ccb4c9418d46f`
- Source path: `.config/quickshell/ii/modules/ii/bar`

That repository currently uses the Illogical Impulse **Quickshell** bar, rather than Waybar. Waycode maps the source bar's left tools trigger, active window, resources, workspaces, clock, network, volume, battery, right control-center trigger, sidebars, wallpaper carousel, favorites, and adaptive wallpaper colors to native SwiftUI modules. The source `Super+W` wallpaper shortcut is mapped to macOS `Option+W`.

Reference snapshots used for the port are included under `Sources/Waycode/Resources/Upstream/SebastianII`. They preserve provenance and make future comparisons possible. Waycode does not execute Linux QML or shell scripts on macOS.

The optional downloadable wallpaper collection comes from [ItsTerm1n4l/Wallpapers-old-archive](https://github.com/ItsTerm1n4l/Wallpapers-old-archive). Waycode downloads the archive only after the user chooses **Install GitHub wallpaper collection**, preserving its Abstract, Fantasy, Favorites, Nord, Space, Winter, and other source folders. The archive states that images originate from multiple creators; image rights remain with their respective creators.
