# Medal.tv on Linux (Wine) — working setup

How to use **Medal.tv on Linux** to upload and share clips. Medal has no Linux
version and does not support Wine. This guide gets the Medal desktop app running
under Wine, and uses **OBS** to record. New OBS replays import into Medal
automatically, and Medal uploads them.

**What works:** the Medal app (library, editor, upload, sharing, Discord sign-in),
automatic import of OBS clips, a tray icon, and start at login.
**What does not work:** Medal's own recorder (it crashes under Wine), and game
tags on clips (Medal cannot detect Linux games).

Tested in October 2026 with:

| Part | Version |
|---|---|
| Distro | EndeavourOS (Arch) |
| Desktop | KDE Plasma 6.7, Wayland |
| GPU | NVIDIA RTX 4060 Ti, driver 615 |
| Wine | 11.19 (plain `~/.wine` prefix) |
| Medal | 2641.538.1 |
| OBS | 32.2 (Flatpak) |

Other distros should work. The tray show/hide needs **KDE Plasma 6** (it uses KWin
scripting). Everything else works on any desktop.

## How it works

```
OBS replay buffer ──saves──▶ ~/Videos/OBS/Replay ….mp4
                                   │
                    medal-obs-import (inotify watcher)
                                   │  MedalIPC.fileImport(…) over 127.0.0.1:9222
                                   ▼
                    Medal app in Wine ──uploads──▶ medal.tv
```

## Problems this setup fixes

| Problem | Cause | Fix |
|---|---|---|
| PC freezes, OOM killer, Medal uses 10–20 GB | Ad webviews on Home/Library load header-bidding iframes; under Wine each is a ~500 MB renderer | Ad hosts fail to resolve inside Medal (`--host-resolver-rules`), memory cap with a systemd scope |
| "recorder crashed! exit code 4294930434" / crash loop | `MedalEncoder.exe` crashes in native code under Wine (also with .NET 4.8) | Turn the recorder off, record with OBS |
| External Recorder folder sync does nothing | That sync runs inside the crashed recorder | `medal-obs-import` watcher calls Medal's own import |
| Discord sign-in hangs on "Connecting to Discord…" | Linux does not know `medal://` links | `medal://` link handler |
| Title bar drawn over Medal's own top bar, content offset, no drag | Medal draws its own title bar; window manager adds another | Wine `Decorated=N` for `Medal.exe` |
| Black window after `Decorated=N` | GPU compositing in an undecorated Wine window | `--disable-gpu-compositing` |
| White border around the window / white lines on other monitors | Wine "light" theme draws the frame | Turn off the Wine theme, dark frame colors |
| No tray icon ("Tray icon unavailable") | Wine reports a 0×0 tray icon, so Medal removes it | Separate tray app (`medal-tray`) |
| Medal starts by itself with no memory cap | Medal adds itself to the Wine `Run` key | Registry fix removes it |

## Requirements

- Wine (any recent version, tested with 11.19)
- Node.js 22 or newer (for the watcher; uses the built-in WebSocket)
- `inotify-tools`, `xdotool`, Python 3 with PyQt6
- systemd (user session)
- OBS Studio

Arch: `sudo pacman -S wine nodejs inotify-tools xdotool python-pyqt6 obs-studio`
Debian/Ubuntu: `sudo apt install wine nodejs inotify-tools xdotool python3-pyqt6 obs-studio`
Fedora: `sudo dnf install wine nodejs inotify-tools xdotool python3-pyqt6 obs-studio`

## Setup

### 1. Install Medal in Wine

1. Download `MedalSetup.exe` from <https://medal.tv/download>.
2. Run it: `wine ~/Downloads/MedalSetup*.exe`
3. If Wine asks to install Wine Mono, you can click Cancel. Medal does not need it here.
4. Let Medal finish its first update, then close it.

### 2. Run the installer

```sh
git clone https://github.com/FURRO404/medal-linux-wine.git
cd medal-linux-wine
./install.sh
```

If your Wine prefix is not `~/.wine`, run `WINEPREFIX=/path/to/prefix ./install.sh`
and set the same `WINEPREFIX` in `~/.local/bin/medal`.

`install.sh` does this:

- copies `medal`, `medal-tray`, `medal-obs-import` to `~/.local/bin/`
- adds the `medal://` link handler (for Discord sign-in)
- points Medal's menu entry at the capped launcher and removes Medal's desktop shortcuts
- imports `files/medal-wine.reg` (no title bar, no theme, dark border, no Wine autostart)
- adds the tray to autostart and starts the `medal-obs-import` user service

### 3. Start Medal and sign in

```sh
~/.local/bin/medal-tray &
```

The tray starts Medal and hides the window. Click the tray icon to show or hide it.
Sign in. For Discord sign-in, approve in the browser, and let the browser open
"Medal (link handler)".

### 4. Medal settings

- **Turn the recorder OFF.** It crashes under Wine and makes Medal heavy.
- **Turn "Launch on startup" OFF.** Otherwise Medal adds itself back to Wine autostart without the cap. The tray already starts it at login.
- "Disable Windows Game Mode", "Run as Administrator" and "HAGS" do nothing under Wine. Leave them.
- Do not use **Sync an External Recorder** for OBS. It does not work without the recorder. The watcher does the import.

### 5. OBS settings

1. Settings → Output → Replay Buffer: turn it on, set the length (for example 30 s).
2. Settings → Output → Recording Path: `~/Videos/OBS`. To use another folder, set `OBS_DIR` in `~/.config/systemd/user/medal-obs-import.service`, then run `systemctl --user daemon-reload && systemctl --user restart medal-obs-import`.
3. Settings → Hotkeys → Save Replay: pick a key.
4. Optional, start OBS at login with the replay buffer on: `obs --minimize-to-tray --startreplaybuffer` (Flatpak: `flatpak run com.obsproject.Studio --minimize-to-tray --startreplaybuffer`).

### 6. Test

Press your Save Replay key. In a few seconds the clip shows up in Medal. Check the log:

```sh
journalctl --user -u medal-obs-import -f
# 21:58:33 new clip: Replay 2026-10-12 21-58-33.mp4
# 21:58:37 imported 1/1: Z:\home\you\Videos\OBS\Replay 2026-10-12 21-58-33.mp4
```

## Daily use

- Medal runs hidden at login. Click the tray icon to open it.
- Do not close Medal with its X button. Under Wine that quits Medal. Use the tray icon to hide it.
- If Medal is closed when you save a clip, the watcher retries every 30 seconds until Medal runs.
- Always start Medal from the tray or the menu entry. A shortcut that Medal makes after an update starts it without the cap and the fixes.

## Troubleshooting

| Symptom | Check / fix |
|---|---|
| Medal is slow or freezes | `systemctl --user status 'medal-*'` shows memory. If it is near 8 GB, a new ad host got through. Open `http://127.0.0.1:9222/json/list` while Medal runs, find the new ad domain, and add it to `ADS` in `~/.local/bin/medal`. |
| Medal closed by itself | It hit the 9 GB cap: `journalctl --user | grep medal- | grep oom`. Same fix as above. |
| Clips do not import | `journalctl --user -u medal-obs-import -n 20`. "Medal not reachable" means Medal is not running, or it was not started with `~/.local/bin/medal`. |
| Black Medal window | The launcher must have `--disable-gpu-compositing`. |
| Title bar or white border is back | Run `wine regedit /S files/medal-wine.reg` again and restart Medal. |
| Discord sign-in does not return | `xdg-mime query default x-scheme-handler/medal` must print `medal-url-handler.desktop`. |
| Tray icon shows, but click does nothing | Show/hide needs KDE Plasma 6 (`qdbus6`). On other desktops use your window manager to show Medal. |

## Things that do not work (so you do not have to try them)

- **Medal's recorder under Wine.** `MedalEncoder.exe` (a .NET Framework 4.6.2 app) crashes with
  exit code `0xffff7002` on Wine Mono and with `-1` after `winetricks dotnet48`. Its crash report is
  native (`sentry.native`, access violations), probably in the screen capture setup. It also cannot
  capture native Linux games.
- **Removing or blocking `MedalEncoder.exe`.** Medal checks its files, downloads it again, and runs it
  from a temp folder.
- **`MEDAL_ENCODER_EXE`** to swap the recorder. Medal reads it only in developer builds.
- **"Sync an External Recorder".** The folder watch runs in the recorder, so nothing gets imported.
- **A KWin "no titlebar" window rule.** Wine keeps space for the old title bar, so you get a
  transparent strip or offset content, and dragging breaks. Use `Decorated=N` instead.
- **Medal's own tray icon.** Wine reports its size as 0×0, and Medal removes it.

## Security note

The launcher opens Chromium's DevTools port on `127.0.0.1:9222` so the watcher can call Medal's
import. Other computers cannot reach it, but any program on your PC can use it to control Medal
(and your Medal session). If you do not want that, remove the two `--remote-debugging-*` flags and
the watcher, and import clips by drag and drop or the Import button.

## Uninstall

```sh
systemctl --user disable --now medal-obs-import.service
rm ~/.local/bin/{medal,medal-tray,medal-obs-import}
rm ~/.config/systemd/user/medal-obs-import.service ~/.config/autostart/medal-tray.desktop
rm ~/.local/share/applications/medal-url-handler.desktop
```

## Files

| File | What it does |
|---|---|
| `files/medal` | Launcher: memory cap, ad-host block, drawing fix, DevTools port |
| `files/medal-obs-import` | Watches the OBS folder, imports new `.mp4` files into Medal |
| `files/medal-obs-import.service` | systemd user service for the watcher |
| `files/medal-tray` | Tray icon: start, show/hide, quit Medal (PyQt6 + KWin script) |
| `files/medal-tray.desktop` | Autostart entry for the tray |
| `files/medal-url-handler.desktop` | Opens `medal://` links in Medal (Discord sign-in) |
| `files/medal-wine.reg` | Wine registry fixes |
| `install.sh` | Copies and enables everything |

Not affiliated with Medal.tv.
