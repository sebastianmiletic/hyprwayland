# Attribution and source mapping

The built-in **Sebastian II · 1:1** preset uses the measured geometry, spacing, rounding, module ordering, and complete Material palette from:

- Repository: <https://github.com/sebastianmiletic/hyprland-dotfiles>
- Source revision: `bb7de915ccf47c92f6570ca1d69ccb4c9418d46f`
- Source path: `.config/quickshell/ii/modules/ii/bar`

That repository currently uses the Illogical Impulse **Quickshell** bar, rather than Waybar. Ryft maps the source bar's left tools trigger, active window, resources, workspaces, clock, network, volume, battery, right control-center trigger, sidebars, wallpaper carousel, favorites, and adaptive wallpaper colors to native SwiftUI modules.

Reference snapshots used for the port are included under `Sources/Ryft/Resources/Upstream/SebastianII`. They preserve provenance and make future comparisons possible. Ryft does not execute Linux QML or shell scripts on macOS.

The optional downloadable wallpaper collection comes from [ItsTerm1n4l/Wallpapers-old-archive](https://github.com/ItsTerm1n4l/Wallpapers-old-archive). Ryft downloads the archive only after the user chooses **Install GitHub wallpaper collection**, preserving its Abstract, Fantasy, Favorites, Nord, Space, Winter, and other source folders. The archive states that images originate from multiple creators; image rights remain with their respective creators.

The optional Hyprland cursor uses the **Bibata Modern Classic** pointer from [ful1e5/Bibata_Cursor](https://github.com/ful1e5/Bibata_Cursor). The pointer source and GPL-3.0 license are bundled under `Sources/Ryft/Resources/ThirdParty/Bibata`; Ryft recolors the upstream SVG template to the Modern Classic white and dark palette and generates the bundled PNG from that source.

Ryft’s automatic tiler is an independent native implementation of the Dwindle interaction model associated with Hyprland and also used by projects such as [OmniWM](https://github.com/OmniNull/OmniWM). It does not include or execute OmniWM source or binaries.
