[English](#english) | [中文](#中文)

# Android Studio Installer for Termux (aarch64)

**This is the main installer:** [`install-android-studio-termux-aarch64.sh`](install-android-studio-termux-aarch64.sh) — merges Termux-native setup with aarch64 SDK/NDK/JBR/IntelliJ-native-binary fixes for a fully working Android Studio on aarch64 Termux.

Auto-detects the latest Android Studio, downloads community aarch64 builds of SDK/NDK, merges IntelliJ Community aarch64 native binaries, and patches everything so it runs natively on arm64 Linux (no proot/chroot container required).

## Prerequisites

- Termux (F-Droid version recommended)
- Storage permission: `termux-setup-storage`
- At least 4 GB free space

## Installation

```bash
git clone https://github.com/GeneralKaos666/androidstudio-for-termux
cd androidstudio-for-termux
chmod +x install-android-studio-termux-aarch64.sh
./install-android-studio-termux-aarch64.sh
```

## What the script does

1. Updates packages and installs dependencies (`x11-repo`, `termux-x11-nightly`, `XFCE4`, `curl`, `wget`, `tar`, ...)
2. Auto-detects the latest Android Studio download URL from Google's developer site
3. Downloads and extracts Android Studio (excluding bundled x86 JBR and x86 native libs)
4. Downloads IntelliJ Community **aarch64** build and merges its native binaries (fsnotifier, restarter, JNA, pty4j)
5. Downloads JetBrains Runtime (JBR) **aarch64** — the JDK Android Studio needs
6. Downloads **aarch64 Android SDK** (community build from HomuHomu833)
7. Downloads **aarch64 Android NDK** (community build from HomuHomu833)
8. Patches `amd64` → `aarch64` in shell scripts and `product-info.json`
9. Configures `JAVA_HOME` → JBR, updates `PATH`, creates desktop launcher

## Usage

1. Start Termux X11: `termux-x11 :1 &`
2. Start XFCE4: `xfce4-session &`
3. Launch Android Studio:
   - Desktop icon: double-click `AndroidStudio.desktop`
   - Terminal: `studio.sh` (if path sourced) or:
     ```
     /data/data/com.termux/files/usr/opt/android-studio/bin/studio.sh
     ```

### Post-install: Setup Wizard

1. Choose **"Custom"** install type
2. **Uncheck** "Android Virtual Device (AVD)" — the emulator won't work on aarch64 Termux; use a physical device instead
3. Ignore warnings about missing Emulator components

### Gradle Configuration

Add to your project's `gradle.properties`:
```ini
android.aapt2FromMavenOverride=${ANDROID_HOME}/build-tools/36.1.0/aapt2
```
The SDK path is auto-resolved from `ANDROID_HOME` (set to `~/Android/Sdk`).

## Updating

Re-run the script — it auto-detects the latest version and the `~/.zshrc`/`~/.bashrc` guards prevent duplicate entries.

## Uninstall

```bash
rm -rf /data/data/com.termux/files/usr/opt/android-studio
rm -rf ~/Android/Sdk
rm ~/Desktop/AndroidStudio.desktop
# Remove JAVA_HOME and PATH additions from ~/.zshrc or ~/.bashrc
```

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Reference: Running Android Studio in a Linux Container (proot/chroot)

The following is a translation of [lfdevs's blog post](https://blog.lfdevs.com/posts/run-android-studio-on-android/) (published 2025-03-18). It covers an **alternative approach** — running Android Studio inside a Linux container (proot/chroot) on Termux, with manual tool patching. This is the approach that inspired parts of the automated script above.

### Overview

Generally, deploying a Linux container via Android Termux to run native arm64 apps works out of the box with few issues. However, Android Studio — built on the IntelliJ IDEA Community Edition — only has a Linux x86 release, not a Linux arm64 one. Most of its components are Java-based though, so we can make it work in a Linux arm64 container by modifying some files and configuration. Apart from the XML layout previewer and the emulator, everything else should work fine.

*The Linux container environment in this article is based on Qualcomm Snapdragon platforms with hardware acceleration, but in theory it works with both Proot and Chroot containers, regardless of whether GPU acceleration is enabled.*

### Installation Steps

1. **Install prerequisites:**

   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo apt install wget ark -y
   ```

2. **Download Android Studio, SDK, NDK, and JBR:**

   ```bash
   cd ~/Downloads
   wget https://redirector.gvt1.com/edgedl/android/studio/ide-zips/2024.2.2.15/android-studio-2024.2.2.15-linux.tar.gz
   wget https://github.com/lzhiyong/android-sdk-tools/releases/download/34.0.3/android-sdk-tools-static-aarch64.zip
   wget https://github.com/lzhiyong/termux-ndk/releases/download/android-ndk/android-ndk-r27b-aarch64.zip
   wget https://cache-redirector.jetbrains.com/intellij-jbr/jbr_jcef-21.0.5-linux-aarch64-b750.29.tar.gz
   ```

3. **Extract Android Studio:**

   ```bash
   mkdir ~/Android
   tar -zxvf ./android-studio-*-linux.tar.gz -C ~/Android/
   ```

4. **Replace JBR with arm64 version:**

   ```bash
   tar -zxvf ./jbr_jcef-*-linux-aarch64-*.tar.gz
   cp -f ./jbr_jcef-*-linux-aarch64-* ~/Android/android-studio/jbr/
   ```

5. **Set environment variables** in `~/.profile`:

   ```bash
   export ANDROID_HOME=$HOME/Android/Sdk
   export ANDROID_USER_HOME=$HOME/.android
   export ANDROID_EMULATOR_HOME=$ANDROID_USER_HOME
   export ANDROID_AVD_HOME=$ANDROID_EMULATOR_HOME/avd/
   export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin:$ANDROID_HOME/platform-tools
   ```

   ```bash
   source ~/.profile
   ```

6. **Launch Android Studio:**

   ```bash
   ~/Android/android-studio/bin/studio.sh
   ```

### SDK & NDK Configuration

1. In the setup wizard, choose **"Custom"** and **uncheck** "Android Virtual Device (AVD)".
2. Use an emulator stub patch (`emulator-ultracompact.zip` — see [Stack Overflow answer](https://stackoverflow.com/a/77020732/31562594)) to prevent AVD-related errors. Extract the `emulator` directory into `~/Android/Sdk/`.
3. Extract `platform-tools` from `android-sdk-tools-static-aarch64.zip` (v34.0.3 recommended) into `~/Android/Sdk/`.
4. In SDK Manager, install desired Build-Tools and NDK versions. Then replace the x86 `build-tools` and `ndk` binaries with the arm64 versions from lzhiyong's builds.
5. Add to `gradle.properties`:

   ```ini
   sdk.dir=/home/<your_username>/Android/Sdk
   ndk.dir=/home/<your_username>/Android/Sdk/ndk/27.1.12297006
   android.aapt2FromMavenOverride=/home/<your_username>/Android/Sdk/build-tools/<patched_version>/aapt2
   ```

### Running & Debugging Apps

- Use **Wireless Debugging** (Android 11+) in Developer Options.
- Open the pairing dialog, keep it open, then use `adb pair 127.0.0.1:<pairing_port>` from the Linux container.
- After pairing, connect with `adb connect 127.0.0.1:<wireless_debugging_port>`.
- If `adb pair` gives `unknown command`, you likely have a system `adb` < v30. Purge it: `sudo apt purge adb -y`.
- Building, debugging, and packaging APKs follows standard PC tutorials.

### Known Limitations

- **No XML layout previewer** — uses SKIA rendering that requires GPU features unavailable in containers.
- **No emulator** — AVD requires KVM, which is unavailable on Android. Use a physical device via USB/wireless ADB.

### Related Resources

- [android-sdk-tools (lzhiyong)](https://github.com/lzhiyong/android-sdk-tools) — precompiled aarch64 SDK tools
- [termux-ndk (lzhiyong)](https://github.com/lzhiyong/termux-ndk) — precompiled aarch64 NDK
- [Android Studio Archive](https://developer.android.google.cn/studio/archive)
- [JetBrainsRuntime](https://github.com/JetBrains/JetBrainsRuntime)
- [Does an Android Studio Linux arm64 version exist? — Stack Overflow](https://stackoverflow.com/questions/71067886/does-an-android-studio-linux-arm64-version-exist/77020732#77020732)

