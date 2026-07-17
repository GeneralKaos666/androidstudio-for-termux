#!/usr/bin/env bash
set -euo pipefail

# ================================================================
# Android Studio Installer for Termux (aarch64)
#
# Merges Termux-native setup (install_Android_Studio.sh) with
# aarch64 SDK/NDK/JBR/IntelliJ-native-binary fixes
# (android-studio-aarch64-install).
#
# Installs:
#   - Termux dependencies (termux-x11, XFCE4, curl, tar, xz, ...)
#   - Android Studio (auto-detected latest version)
#   - IntelliJ Community native binaries (fsnotifier, restarter, ...)
#   - JetBrains Runtime (JBR) — aarch64 JDK for AS
#   - Android SDK (aarch64 community build from HomuHomu833)
#   - Android NDK (aarch64 community build from HomuHomu833)
#   - Shell environment (JAVA_HOME → JBR, PATH)
#   - Desktop launcher for Termux:X11
# ================================================================

clear
cat <<'EOF'
==============================================
Android Studio Installer for Termux (aarch64)
==============================================

What gets installed:
  • Android Studio (latest version, auto-detected)
  • JetBrains Runtime (JBR) — aarch64 JDK
  • IntelliJ Community native binaries (fsnotifier, restarter)
  • Android SDK (aarch64) + NDK (aarch64)
  • Desktop launcher for Termux:X11

Prerequisites:
  • Termux from F-Droid (not Google Play)
  • termux-setup-storage (for shared storage access)
  • At least 6 GB free space

EOF
read -r -p "Press [Enter] to continue, [Ctrl+C] to cancel. "
echo

# ================================================================
# Step 1 — Install Termux dependencies
# ================================================================
echo "[1/9] Installing Termux dependencies..."

pkg update -y
pkg upgrade -y

# x11-repo may already be added; don't fail if it is
pkg install x11-repo -y 2>/dev/null || true

pkg install -y \
    termux-x11-nightly xfce4 \
    curl wget unzip tar xz gzip sed grep coreutils \
    || { echo "ERROR: package installation failed" >&2; exit 1; }

# pigz is optional — parallel gzip decompression
HAVE_PIGZ=0
if command -v pigz &>/dev/null || pkg install pigz -y 2>/dev/null; then
    if command -v pigz &>/dev/null; then
        HAVE_PIGZ=1
        echo "  pigz: enabled (parallel decompression)"
    fi
fi

# ================================================================
# Paths
# ================================================================
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
AS_HOME="${PREFIX}/opt/android-studio"
SDK_HOME="${HOME}/Android/Sdk"
NDK_HOME="${SDK_HOME}/ndk"
CACHE_DIR="${HOME}/.cache/androidstudio-installer"

mkdir -p "${PREFIX}/opt" "${SDK_HOME}" "${NDK_HOME}" "${CACHE_DIR}"

# Detect shell RC file for environment setup
SHELL_NAME=$(basename "${SHELL:-bash}")
case "${SHELL_NAME}" in
    bash) RC_FILE="${HOME}/.bashrc" ;;
    zsh)  RC_FILE="${HOME}/.zshrc"  ;;
    fish) RC_FILE="${HOME}/.config/fish/config.fish" ;;
    *)    RC_FILE="${HOME}/.profile" ;;
esac

# ================================================================
# Versions
#
# AS version is auto-detected from developer.android.com.
# The others are pinned to specific community aarch64 builds.
# The JBR version MUST match what is bundled with the AS release.
# ================================================================
AS_VERSION_FALLBACK="2026.1.1.10"
AS_FILENAME_FALLBACK="android-studio-quail1-patch2-linux.tar.gz"

IDEA_VERSION="2026.1.1"
JBR_VERSION_TAG="21.0.10-linux-aarch64-b1163.108"
SDK_RELEASE_VERSION="36.0.0"
NDK_VERSION="r29"
NDK_BUILD_NUMBER="29.0.14206865"

# ================================================================
# Step 2 — Auto-detect latest Android Studio version
# ================================================================
echo "[2/9] Detecting latest Android Studio version from developer.android.com..."
AS_URL=$(curl -s --max-time 30 https://developer.android.com/studio 2>/dev/null \
    | grep -oP 'https://[^"]*gvt1\.com[^"]*linux\.tar\.gz' | head -1)

if [ -z "${AS_URL}" ]; then
    echo "  Auto-detection failed — using fallback version ${AS_VERSION_FALLBACK}."
    AS_URL="https://redirector.gvt1.com/edgedl/android/studio/ide-zips/${AS_VERSION_FALLBACK}/${AS_FILENAME_FALLBACK}"
fi

AS_FILENAME=$(basename "${AS_URL}")
echo "  Download URL: ${AS_FILENAME}"

# ================================================================
# Utility functions
# ================================================================

# curl_resume: download with resume, retries, exponential backoff
curl_resume() {
    local url="$1" out="$2"
    local tmp="${out}.part"
    local tries=8 wait=3 i=1
    while :; do
        if curl -L --fail-with-body --retry 10 --retry-delay 5 --retry-all-errors \
            --connect-timeout 15 --max-time 0 \
            -C - -o "$tmp" "$url"; then
            mv -f "$tmp" "$out"
            return 0
        fi
        if (( i >= tries )); then
            echo "  ERROR: download failed after ${tries} attempts" >&2
            echo "  URL: ${url}" >&2
            return 1
        fi
        echo "  Retrying in ${wait}s... (attempt $i of ${tries})"
        sleep "$wait"
        i=$((i+1))
        (( wait < 30 )) && wait=$((wait*2))
    done
}

# tar_gz_file: decompress .tar.gz → extract to dest, optional tar flags
tar_gz_file() {
    local arc="$1" dest="$2"
    shift 2
    if [ "${HAVE_PIGZ}" = 1 ]; then
        pigz -d -c "$arc" | tar --no-same-owner -C "$dest" -x -f - "$@"
    else
        gzip -d -c "$arc" | tar --no-same-owner -C "$dest" -x -f - "$@"
    fi
}

# tar_xz_file: decompress .tar.xz → extract to dest, optional tar flags
tar_xz_file() {
    local arc="$1" dest="$2"
    shift 2
    # Try multi-threaded xz first; fall back to single-threaded
    if xz -T0 -d -c "$arc" 2>/dev/null | tar --no-same-owner -C "$dest" -x -f - "$@"; then
        return 0
    fi
    xz -d -c "$arc" | tar --no-same-owner -C "$dest" -x -f - "$@"
}

# ================================================================
# Step 3 — Download and extract Android Studio core
# ================================================================
echo "[3/9] Downloading Android Studio..."
AS_TGZ="${CACHE_DIR}/${AS_FILENAME}"
curl_resume "${AS_URL}" "${AS_TGZ}"

echo "  Extracting (excluding bundled JBR and x86 native libs)..."
tar_gz_file "${AS_TGZ}" "${PREFIX}/opt" \
    --exclude 'android-studio/jbr/*' \
    --exclude 'android-studio/lib/jna/*' \
    --exclude 'android-studio/lib/native/*' \
    --exclude 'android-studio/lib/pty4j/*'

# ================================================================
# Step 4 — Merge IntelliJ Community native binaries
#         (fsnotifier, restarter, JNA, pty4j — needed on aarch64)
# ================================================================
echo "[4/9] Downloading IntelliJ Community for aarch64 native binaries..."
IDEA_URL="https://download.jetbrains.com/idea/idea-${IDEA_VERSION}-aarch64.tar.gz"
IDEA_TGZ="${CACHE_DIR}/ideaIC-${IDEA_VERSION}-aarch64.tar.gz"

curl_resume "${IDEA_URL}" "${IDEA_TGZ}"

echo "  Merging native binaries..."
tar_gz_file "${IDEA_TGZ}" "${AS_HOME}" \
    --wildcards '*/bin/fsnotifier' '*/bin/restarter' \
    '*/lib/jna' '*/lib/native' '*/lib/pty4j' \
    --strip-components=1

# ================================================================
# Step 5 — Install JetBrains Runtime (JBR) for aarch64
# ================================================================
echo "[5/9] Downloading JetBrains Runtime (JBR) for aarch64..."
JBR_URL="https://cache-redirector.jetbrains.com/intellij-jbr/jbrsdk_ft-${JBR_VERSION_TAG}.tar.gz"
JBR_TGZ="${CACHE_DIR}/jbrsdk_${JBR_VERSION_TAG}.tar.gz"

curl_resume "${JBR_URL}" "${JBR_TGZ}"

echo "  Extracting JBR to ${AS_HOME}/jbr..."
mkdir -p "${AS_HOME}/jbr"
tar_gz_file "${JBR_TGZ}" "${AS_HOME}/jbr" --strip-components=1

# ================================================================
# Step 6 — Install Android SDK (aarch64 community build)
# ================================================================
echo "[6/9] Downloading Android SDK (aarch64 community build)..."
SDK_URL="https://github.com/HomuHomu833/android-sdk-custom/releases/download/${SDK_RELEASE_VERSION}/android-sdk-aarch64-linux-musl.tar.xz"
SDK_TXZ="${CACHE_DIR}/android-sdk-${SDK_RELEASE_VERSION}-aarch64-linux-musl.tar.xz"

curl_resume "${SDK_URL}" "${SDK_TXZ}"

echo "  Extracting SDK to ${SDK_HOME}..."
tar_xz_file "${SDK_TXZ}" "${SDK_HOME}" --strip-components=1

# ================================================================
# Step 7 — Install Android NDK (aarch64 community build)
# ================================================================
echo "[7/9] Downloading Android NDK (aarch64 community build)..."
NDK_URL="https://github.com/HomuHomu833/android-ndk-custom/releases/download/${NDK_VERSION}/android-ndk-${NDK_VERSION}-aarch64-linux-android.tar.xz"
NDK_TXZ="${CACHE_DIR}/android-ndk-${NDK_VERSION}-aarch64-linux-android.tar.xz"

curl_resume "${NDK_URL}" "${NDK_TXZ}"

echo "  Extracting NDK..."
tar_xz_file "${NDK_TXZ}" "${NDK_HOME}"

# Rename to the build-number format Android Studio expects
if [ -d "${NDK_HOME}/android-ndk-${NDK_VERSION}" ]; then
    mv "${NDK_HOME}/android-ndk-${NDK_VERSION}" "${NDK_HOME}/${NDK_BUILD_NUMBER}"
fi
echo "  NDK installed at ${NDK_HOME}/${NDK_BUILD_NUMBER}"

# ================================================================
# Step 8 — Patch x86_64 references to aarch64
# ================================================================
echo "[8/9] Patching scripts for aarch64..."

# Rename the raw shell script (used by JetBrains launcher scripts)
mv "${AS_HOME}/bin/studio" "${AS_HOME}/bin/studio.do_not_use" 2>/dev/null || true

# Replace amd64 references with aarch64 in shell scripts
sed -i 's/amd64/aarch64/g' "${AS_HOME}/bin/"*.sh 2>/dev/null || true

# Patch product-info.json so the launcher resolves aarch64 native libs
sed -i 's/amd64/aarch64/g' "${AS_HOME}/product-info.json" 2>/dev/null || true
echo "  Patched: bin/*.sh, product-info.json"

# ================================================================
# Step 9 — Configure environment variables and desktop launcher
# ================================================================
echo "[9/9] Configuring shell environment and desktop launcher..."

# JAVA_HOME → JBR (the aarch64 JDK bundled with AS)
JAVA_HOME_VAL="${AS_HOME}/jbr"
grep -q 'JAVA_HOME.*android-studio/jbr' "${RC_FILE}" 2>/dev/null \
    || echo "export JAVA_HOME=${JAVA_HOME_VAL}" >> "${RC_FILE}"

# Add JBR's bin to PATH
grep -q 'PATH=.*\$JAVA_HOME/bin' "${RC_FILE}" 2>/dev/null \
    || echo 'export PATH=$PATH:$JAVA_HOME/bin' >> "${RC_FILE}"

# Add Android Studio's bin to PATH
grep -q 'PATH=.*android-studio/bin' "${RC_FILE}" 2>/dev/null \
    || echo "export PATH=\$PATH:${AS_HOME}/bin" >> "${RC_FILE}"

# Add Android SDK platform-tools to PATH
grep -q 'PATH=.*Android/Sdk' "${RC_FILE}" 2>/dev/null \
    || echo "export PATH=\$PATH:${SDK_HOME}/platform-tools" >> "${RC_FILE}"

# Desktop launcher for Termux:X11
mkdir -p "${HOME}/Desktop"
cat << LAUNCHER > "${HOME}/Desktop/AndroidStudio.desktop"
[Desktop Entry]
Type=Application
Name=Android Studio
Comment=Android Studio IDE (aarch64) — Termux:X11
Icon=${AS_HOME}/bin/studio.png
Exec=${AS_HOME}/bin/studio.sh
Terminal=false
StartupNotify=true
LAUNCHER
chmod +x "${HOME}/Desktop/AndroidStudio.desktop"
echo "  Created: ~/Desktop/AndroidStudio.desktop"

# ================================================================
# Done
# ================================================================
echo
echo "=============================================="
echo " Android Studio installation complete!"
echo "=============================================="
echo
echo "  Start Termux:X11 and XFCE:"
echo "    termux-x11 :1 &"
echo "    xfce4-session &"
echo
echo "  Launch Android Studio:"
echo "    • Desktop icon (within XFCE): double-click AndroidStudio.desktop"
echo "    • Terminal: source ${RC_FILE} && studio.sh"
echo "    • Full path: ${AS_HOME}/bin/studio.sh"
echo
echo "  Setup wizard:"
echo "    1. Choose 'Custom' install type"
echo "    2. Uncheck 'Android Virtual Device (AVD)' — emulator won't"
echo "       work on aarch64 Termux; use a physical device instead"
echo "    3. Ignore warnings about missing Emulator components"
echo
echo "  REQUIRED — Add to your project's gradle.properties:"
echo "    android.aapt2FromMavenOverride=${SDK_HOME}/build-tools/36.1.0/aapt2"
echo
echo "  Reload your terminal: source ${RC_FILE}"
echo
