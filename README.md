# Android Studio Installer for Termux

Auto-detects and installs the latest Android Studio with native Termux X11 support.

## Prerequisites

- Termux (F-Droid version recommended)
- Storage permission: `termux-setup-storage`
- At least 4 GB free space

## Installation

```bash
git clone https://github.com/GeneralKaos666/androidstudio-for-termux
cd androidstudio-for-termux
chmod +x install_Android_Studio.sh
./install_Android_Studio.sh
```

## What the script does

1. Updates packages and installs dependencies (`x11-repo`, `termux-x11-nightly`, `XFCE4`, `OpenJDK 21`, `wget`, `unzip`, `tar`)
2. Auto-detects the latest Android Studio download URL from Google's developer site (falls back to a known version if unreachable)
3. Downloads and extracts to `$PREFIX/opt/android-studio`
4. Auto-detects Java installation path and appends `JAVA_HOME` + `PATH` to `~/.zshrc` (skips if already present)
5. Creates a desktop launcher at `~/Desktop/AndroidStudio.desktop`

## Usage

1. Start Termux X11: `termux-x11 :1 &`
2. Start XFCE4: `xfce4-session &`
3. Launch Android Studio:
   - Desktop icon: double-click `AndroidStudio.desktop`
   - Terminal: `studio.sh` (if path sourced) or full path:
     ```
     /data/data/com.termux/files/usr/opt/android-studio/bin/studio.sh
     ```

## Updating

Re-run the script — it auto-detects the latest version and the `~/.zshrc` guards prevent duplicate entries.

## Uninstall

```bash
rm -rf /data/data/com.termux/files/usr/opt/android-studio
rm ~/Desktop/AndroidStudio.desktop
# Remove JAVA_HOME and PATH additions from ~/.zshrc
```

## License

MIT License — see [LICENSE](LICENSE) for details.
