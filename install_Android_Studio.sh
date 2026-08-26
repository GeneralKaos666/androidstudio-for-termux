#!/bin/bash

# Exit immediately if any command fails
set -e

# Update and upgrade packages cleanly
echo "🔄 Updating Termux package repositories..."
pkg update -y && pkg upgrade -y

# Install necessary packages for graphic UI environment
echo "📦 Installing required dependencies..."
pkg install x11-repo -y
pkg install termux-x11-nightly xfce4 openjdk-21 maven wget unzip tar -y

# Auto-detect JAVA_HOME from installed JDK with fallback
JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(which java 2>/dev/null)")")" 2>/dev/null) || JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk"

# Detect user's default shell and set the appropriate RC file
SHELL_NAME=$(basename "$SHELL")
case "$SHELL_NAME" in
    bash)  RC_FILE="$HOME/.bashrc" ;;
    zsh)   RC_FILE="$HOME/.zshrc" ;;
    fish)  RC_FILE="$HOME/.config/fish/config.fish" ;;
    *)     RC_FILE="$HOME/.profile" ;;
esac

# Define and build the target installation directory
INSTALL_DIR="/data/data/com.termux/files/usr/opt"
mkdir -p "$INSTALL_DIR"

# Auto-detect latest Android Studio version from official page
echo "🔍 Detecting latest Android Studio version..."
STUDIO_URL=$(curl -s https://developer.android.com/studio | \
    grep -oP 'https://[^"]*gvt1\.com[^"]*linux\.tar\.gz' | head -1)

# Fallback to known version if auto-detection fails
if [ -z "$STUDIO_URL" ]; then
    echo "⚠️ Auto-detection failed, using fallback version..."
    VERSION_NUM="2026.1.1.10"
    VERSION_NAME="quail1-patch2"
    STUDIO_URL="https://edgedl.me.gvt1.com/android/studio/ide-zips/${VERSION_NUM}/android-studio-${VERSION_NAME}-linux.tar.gz"
fi

TAR_FILE=$(basename "$STUDIO_URL")
VERSION_NUM=$(echo "$STUDIO_URL" | grep -oP '/\d+\.\d+\.\d+\.\d+/' | tr -d '/')
VERSION_NAME=$(echo "$TAR_FILE" | sed 's/android-studio-//;s/-linux\.tar\.gz//')

# Check what's already installed
SKIP_DOWNLOAD=false
SKIP_ENV=false
SKIP_DESKTOP=false
INSTALLED_BUILD="${INSTALL_DIR}/android-studio/build.txt"
DESKTOP_FILE=~/Desktop/AndroidStudio.desktop

if [ -f "$INSTALLED_BUILD" ]; then
    INSTALLED_VERSION=$(cat "$INSTALLED_BUILD")
    if echo "$INSTALLED_VERSION" | grep -q "$VERSION_NAME"; then
        SKIP_DOWNLOAD=true
    fi
fi

if grep -q "JAVA_HOME=${JAVA_HOME}" "$RC_FILE" 2>/dev/null && \
   grep -q "PATH=\$PATH:\$JAVA_HOME/bin" "$RC_FILE" 2>/dev/null && \
   grep -q "PATH=.*android-studio/bin" "$RC_FILE" 2>/dev/null; then
    SKIP_ENV=true
fi

if [ -f "$DESKTOP_FILE" ] && grep -q "Version=${VERSION_NUM}" "$DESKTOP_FILE" 2>/dev/null; then
    SKIP_DESKTOP=true
fi

if [ "$SKIP_DOWNLOAD" = true ] && [ "$SKIP_ENV" = true ] && [ "$SKIP_DESKTOP" = true ]; then
    echo "✅ Android Studio ${VERSION_NUM} (${VERSION_NAME}) is already up to date. Nothing to do."
else
    # Download and extract if needed
    if [ "$SKIP_DOWNLOAD" = false ]; then
        echo "📥 Downloading Android Studio ${VERSION_NUM} (${VERSION_NAME})..."
        wget -c "$STUDIO_URL" -O "$TAR_FILE"
        echo "📦 Extracting archive to ${INSTALL_DIR}..."
        tar -xzf "$TAR_FILE" -C "$INSTALL_DIR"
        rm "$TAR_FILE"
    fi

    # Configure environment if needed
    if [ "$SKIP_ENV" = false ]; then
        echo "⚙️ Configuring environment paths in ${RC_FILE}..."
        grep -q "JAVA_HOME=${JAVA_HOME}" "$RC_FILE" 2>/dev/null || echo "export JAVA_HOME=${JAVA_HOME}" >> "$RC_FILE"
        grep -q "PATH=\$PATH:\$JAVA_HOME/bin" "$RC_FILE" 2>/dev/null || echo 'export PATH=$PATH:$JAVA_HOME/bin' >> "$RC_FILE"
        grep -q "PATH=.*android-studio/bin" "$RC_FILE" 2>/dev/null || echo "export PATH=\$PATH:${INSTALL_DIR}/android-studio/bin" >> "$RC_FILE"
    fi

    # Create desktop entry if needed
    if [ "$SKIP_DESKTOP" = false ]; then
        echo "🖥️ Creating Termux-X11 desktop launcher..."
        mkdir -p ~/Desktop
        cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Type=Application
Version=${VERSION_NUM}
Name=Android Studio
Comment=Run Android Studio inside Termux-X11
Icon=${INSTALL_DIR}/android-studio/bin/studio.png
Exec=${INSTALL_DIR}/android-studio/bin/studio.sh
Terminal=false
StartupNotify=true
EOF
        chmod +x "$DESKTOP_FILE"
    fi
fi

echo "✅ Android Studio ${VERSION_NUM} (${VERSION_NAME}) setup completed successfully!"
echo "💡 Reload your terminal context using: source ${RC_FILE}"
echo "🚀 Start your IDE within your X11 session or run: studio.sh"
