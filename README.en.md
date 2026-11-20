# m3ify

Material 3 for Spotify Desktop, inspired by [Swiftify](https://shredos.dev/): prominent artwork, quiet surfaces and colour from your music. Spicetify is installed automatically. m3ify is a regular Spicetify theme, compatible with extensions.

[Русская версия](README.md)

## Install
1. Download and extract the entire repository, including `theme`, then open `install.cmd` as a regular user. First installation needs internet access to download the official Spicetify release.
2. Launch Spotify as usual. Its shortcuts and autostart now go through m3ify. After a Spotify update the theme is re-applied automatically.

For the M3 icon on the taskbar: start Spotify, right-click its taskbar button → **Pin to taskbar**, then run `reapply.cmd`.

To re-apply the theme manually, run `reapply.cmd`. To remove everything and restore the original Spotify, run `uninstall.cmd`.

## What it does
- Recolors Spotify's design system (Encore) into an M3 tonal palette, taking the color from the current album art (Material You).
- Swiftify-inspired artwork card on Home with working transport controls, rounded panels and artwork, a tonal player, wavy progress and a thick volume slider. This styles the official Spotify client; it does not implement Swiftify's feature set.
- **My tracks** opens the local collection. “Add a music folder” opens Spotify preferences with instructions for enabling local files and adding a source.
- **Settings**: **Ctrl+Alt+M** or the button next to the volume slider. You can pick the color from album art or a fixed color, and toggle AMOLED black, the wave, reduced motion and Canvas videos.
- **M3 icon**: set on the Spotify Start menu shortcut, on the launcher `m3launch.exe` (about 30 KB, built from `m3launch.cs` during install) and on the Spotify taskbar pin. An unpinned window and Alt+Tab show the regular Spotify icon: Chromium takes it from Spotify.exe, and a modified Spotify.exe won't start.
- **Language**: English and Russian. The mod menu has an Auto / Русский / English switch; Auto follows Spotify's language. The installer follows the Windows display language.

## Automatic repair
- The launcher checks Spotify's version and theme assets before launch, waits for repair and forwards launch arguments.
- A per-user Windows task named `m3ify AutoRepair <SID>` checks every two minutes while Spotify and its installer are closed. Direct taskbar launches are repaired after closing Spotify or next time you use the launcher.
- A fresh `xpui.spa` causes Spicetify to refresh its backup before applying. Legacy m3ify backups are migrated only when the Spotify version matches.
- On failure, repair attempts a Spicetify upgrade once per Spotify version. A newly incompatible Spotify build may require a future Spicetify release. Errors go to `%LOCALAPPDATA%\m3ify\repair.log`; use `reapply.cmd` to retry manually.
- `restore` returns stock Spotify and suspends repair until `apply` or `install`. `uninstall.cmd` also removes the task and restores shortcuts. Spicetify and third-party extensions remain installed; previous theme settings are restored.

## Footprint
No frameworks. Artwork colours are cached and DOM checks follow UI mutations, with no permanent JS polling. Repair runs as a short Windows task rather than a resident process. Canvas can be disabled in theme settings.

## Files
- `m3ify.ps1`: installer and CLI (`install | apply | repair | restore | uninstall | launch | status`).
- `m3launch.cs`: launcher source.
- `theme/m3.css`, `theme/m3.js`: the theme itself.
- Installed copy: `%LOCALAPPDATA%\m3ify`. Spicetify manages current backups. `backup\` is only used to migrate older installations.

Only the spotify.com version of Spotify is supported. The Microsoft Store version is not.

## Development checks
Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/repair.ps1` for isolated filesystem repair checks and launcher compilation. It does not modify installed Spotify.

For UI checks, install Node.js and Edge, run `npm install --no-save --package-lock=false playwright@1.62.1`, then `node tests/ui.cjs`. This uses a browser fixture with a mocked Spicetify API, not real Spotify playback or a live client update.

Design reference: [Swiftify](https://shredos.dev/). Design craft: [unslop by @heydamir](https://heydamir.design/unslop), CC BY 4.0.
