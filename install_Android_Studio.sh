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
JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java 2>/dev/null))) 2>/dev/null) || JAVA_HOME="/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk"

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

echo "📥 Downloading Android Studio ${VERSION_NUM} (${VERSION_NAME})..."
# Use -c to allow resuming download if it gets interrupted
wget -c "$STUDIO_URL" -O "$TAR_FILE"

echo "📦 Extracting archive to ${INSTALL_DIR}..."
tar -xzf "$TAR_FILE" -C "$INSTALL_DIR"

# Cleanup the installer package to save storage space
rm "$TAR_FILE"

# Set up environmental variables safely in ~/.zshrc (preventing duplicate appends)
echo "⚙️ Configuring environment paths in ~/.zshrc..."
grep -q "JAVA_HOME=${JAVA_HOME}" ~/.zshrc 2>/dev/null || echo "export JAVA_HOME=${JAVA_HOME}" >> ~/.zshrc
grep -q "PATH=\$PATH:\$JAVA_HOME/bin" ~/.zshrc 2>/dev/null || echo 'export PATH=$PATH:$JAVA_HOME/bin' >> ~/.zshrc
grep -q "PATH=.*android-studio/bin" ~/.zshrc 2>/dev/null || echo "export PATH=\$PATH:${INSTALL_DIR}/android-studio/bin" >> ~/.zshrc

# Create X11 Application Desktop Shortcut with matching version titles
echo "🖥️ Creating Termux-X11 desktop launcher..."
mkdir -p ~/Desktop
cat <<EOF > ~/Desktop/AndroidStudio.desktop
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

# Grant execution permissions to the desktop launcher entry
chmod +x ~/Desktop/AndroidStudio.desktop

echo "✅ Android Studio ${VERSION_NUM} (${VERSION_NAME}) setup completed successfully!"
echo "💡 Reload your terminal context using: source ~/.zshrc"
echo "🚀 Start your IDE within your X11 session or run: studio.sh"
