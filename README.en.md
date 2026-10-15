# m3ify

Material 3 (Expressive) for Spotify Desktop, styled after Pixel / Android 16. It installs on top of Spotify like spicetify does, but has no marketplace, no extensions and nothing extra.

[Русская версия](README.md)

## Install
1. Double-click `install.cmd`.
2. Launch Spotify as usual. Its shortcuts and autostart now go through m3ify. After a Spotify update the theme is re-applied automatically.

For the M3 icon on the taskbar: start Spotify, right-click its taskbar button → **Pin to taskbar**, then run `reapply.cmd`.

To re-apply the theme manually, run `reapply.cmd`. To remove everything and restore the original Spotify, run `uninstall.cmd`.

## What it does
- Recolors Spotify's design system (Encore) into an M3 tonal palette, taking the color from the current album art (Material You).
- Pixel / Android 16 look:
  - wavy progress bar like the Android media player;
  - thick volume slider;
  - home shortcuts styled as Quick Settings tiles;
  - filled cards;
  - Spotify settings shown as grouped Android-style cards with M3 switches.
- **My tracks**: "Add a music folder" turns on Spotify's local files and opens the folder picker. "Open my tracks" jumps to them.
- **Settings**: **Ctrl+Alt+M** or the button next to the volume slider. You can pick the color from album art or a fixed color, and toggle AMOLED black, the wave, reduced motion and Canvas videos.
- **M3 icon**: set on the Spotify Start menu shortcut, on the launcher `m3launch.exe` (about 30 KB, built from `m3launch.cs` during install) and on the Spotify taskbar pin. An unpinned window and Alt+Tab show the regular Spotify icon: Chromium takes it from Spotify.exe, and a modified Spotify.exe won't start.
- **Language**: English and Russian. The mod menu has an Auto / Русский / English switch; Auto follows Spotify's language. The installer follows the Windows display language.

## Footprint
- The mod itself is about 40 KB: CSS plus a few hundred lines of JS with no frameworks and no timers.
- The album color is recomputed only when the track changes, from a 24×24 image.
- The wave animation runs at about 10 fps inside a small isolated layer.
- Spotify itself still uses around 700–800 MB of RAM. The theme barely changes that. Hiding Canvas and music videos helps the most.

## Files
- `m3ify.ps1`: installer and CLI (`install | apply | restore | uninstall | launch | status`).
- `m3launch.cs`: launcher source.
- `theme/m3.css`, `theme/m3.js`: the theme itself.
- Installed copy: `%LOCALAPPDATA%\m3ify`. The original `xpui.spa` backup is in `backup\`.

Only the spotify.com version of Spotify is supported. The Microsoft Store version is not.
