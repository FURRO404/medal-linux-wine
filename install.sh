#!/bin/sh
# Install the Medal.tv-on-Linux helper files. Run it after Medal is installed in Wine.
# It copies files to ~/.local/bin and ~/.config, applies the Wine registry fixes,
# and starts the OBS import service. Run it again to update; it overwrites its own files.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
F="$HERE/files"
WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"
export WINEPREFIX

for cmd in wine node inotifywait systemd-run python3; do
  command -v "$cmd" >/dev/null || { echo "missing: $cmd (install it first)"; exit 1; }
done
python3 -c 'import PyQt6' 2>/dev/null || echo "note: PyQt6 is missing, so the tray icon will not work (python-pyqt6 / python3-pyqt6)"
command -v qdbus6 >/dev/null || echo "note: qdbus6 is missing, so tray show/hide works only on KDE Plasma 6"
command -v xdotool >/dev/null || echo "note: xdotool is missing, so the tray cannot hide Medal on start"

MEDAL_EXE="$WINEPREFIX/drive_c/users/$USER/AppData/Local/Medal/current/Medal.exe"
[ -f "$MEDAL_EXE" ] || { echo "Medal not found at $MEDAL_EXE. Install Medal in Wine first (see README)."; exit 1; }

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user" "$HOME/.config/autostart" "$HOME/.local/share/applications"

install -m 755 "$F/medal" "$F/medal-tray" "$F/medal-obs-import" "$HOME/.local/bin/"
sed "s|@NODE@|$(command -v node)|" "$F/medal-obs-import.service" > "$HOME/.config/systemd/user/medal-obs-import.service"
sed "s|@HOME@|$HOME|g" "$F/medal-tray.desktop" > "$HOME/.config/autostart/medal-tray.desktop"
sed "s|@HOME@|$HOME|g" "$F/medal-url-handler.desktop" > "$HOME/.local/share/applications/medal-url-handler.desktop"

# medal:// links (Discord sign-in) go back to Medal in Wine.
xdg-mime default medal-url-handler.desktop x-scheme-handler/medal || true
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

# Medal makes its own menu entry; point it at the capped launcher.
for d in "$HOME/.local/share/applications/wine/Programs/Medal.desktop"; do
  [ -f "$d" ] && sed -i "s|^Exec=.*|Exec=$HOME/.local/bin/medal|" "$d"
done
# Medal's desktop shortcuts start it without the cap and the fixes.
rm -f "$HOME/Desktop/Medal.desktop" "$HOME/Desktop/Medal.lnk"

WINEDEBUG=-all wine regedit /S "$F/medal-wine.reg"

systemctl --user daemon-reload
systemctl --user enable --now medal-obs-import.service

echo
echo "Done. Next:"
echo "  1. Start the tray now:  ~/.local/bin/medal-tray &   (it also starts at login)"
echo "  2. In Medal settings: turn the recorder OFF and 'Launch on startup' OFF."
echo "  3. In OBS: turn on the Replay Buffer and save replays to ~/Videos/OBS"
echo "     (or set OBS_DIR in ~/.config/systemd/user/medal-obs-import.service)."
