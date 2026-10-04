#!/bin/bash

# Exit immediately if any command fails
set -e

# ================================================================
# Android Studio Installer for Termux (aarch64, native — no proot)
#
# Android Studio only ships as an x86_64 glibc Linux build. On an
# aarch64 device none of its native pieces (JBR, fsnotifier, ...) can
# execute, so the stock tarball will never draw a window in Termux:X11.
#
# This script converts the download in place:
#   1. Swaps the bundled x86_64 JetBrains Runtime for the matching
#      aarch64 JBR (downloaded from the JetBrains CDN).
#   2. Merges the aarch64 native binaries (fsnotifier, restarter,
#      lib/jna, lib/native, lib/pty4j) from an IntelliJ Community
#      aarch64 build — exact companion version if published, else the
#      newest published aarch64 build (JetBrains dropped Linux-aarch64
#      Community releases after the 2025.2 line).
#   3. Patches `amd64` -> `aarch64` in launcher scripts and
#      product-info.json, and disables the x86_64 `bin/studio` ELF.
#   4. Re-points every ELF's dynamic linker/RUNPATH to Termux's glibc
#      runtime ($PREFIX/glibc), because the aarch64 JetBrains binaries
#      are glibc-linked and Android is bionic.
#   5. Installs a `studio-termux` launcher and Termux:X11 desktop entry.
# ================================================================

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
INSTALL_DIR="${PREFIX}/opt"
AS_HOME="${INSTALL_DIR}/android-studio"
CACHE_DIR="${HOME}/.cache/androidstudio-installer"
GLIBC_LIB="${PREFIX}/glibc/lib"
GLIBC_LOADER="${GLIBC_LIB}/ld-linux-aarch64.so.1"
DESKTOP_FILE="${HOME}/Desktop/AndroidStudio.desktop"

mkdir -p "${INSTALL_DIR}" "${CACHE_DIR}" "${HOME}/Desktop"

# aarch64 only — the whole conversion below is pointless otherwise
if [ "$(uname -m)" != "aarch64" ]; then
	echo "❌ This installer only supports aarch64. Detected: $(uname -m)"
	exit 1
fi

# Extract <label> <archive> [tar flags...], showing a progress bar via pv
# (falls back to plain tar if pv is unavailable). Pipeline exit code is
# tar's, so callers can still use `if extract ...; then ...; fi`.
extract() {
	if command -v pv >/dev/null 2>&1; then
		pv -N "$1" -w 60 "$2" | tar -xzf - "${@:3}"
	else
		tar -xzf "$2" "${@:3}"
	fi
}

# ================================================================
# Step 1 — Packages (includes the Termux glibc runtime)
# ================================================================
echo "🔄 Updating Termux package repositories..."
pkg update -y && pkg upgrade -y

echo "📦 Installing required dependencies..."
pkg install x11-repo -y
pkg install glibc-repo -y
pkg install termux-x11-nightly xfce4 openjdk-21 maven wget curl unzip tar gzip sed grep coreutils glibc-runner patchelf pv -y

if [ ! -f "${GLIBC_LOADER}" ]; then
	echo "⚠️ Termux glibc runtime missing or broken at ${GLIBC_LOADER} — repairing..."
	pkg reinstall glibc bash-glibc termux-exec-glibc -y
fi
if [ ! -f "${GLIBC_LOADER}" ]; then
	echo "❌ Termux glibc runtime still missing at ${GLIBC_LOADER}"
	echo "   Reinstall manually: pkg reinstall glibc bash-glibc termux-exec-glibc -y"
	exit 1
fi

# ================================================================
# Shell RC file detection (for environment setup)
# ================================================================
SHELL_NAME=$(basename "${SHELL:-bash}")
case "${SHELL_NAME}" in
bash) RC_FILE="${HOME}/.bashrc" ;;
zsh) RC_FILE="${HOME}/.zshrc" ;;
fish) RC_FILE="${HOME}/.config/fish/config.fish" ;;
*) RC_FILE="${HOME}/.profile" ;;
esac

# ================================================================
# Step 2 — Auto-detect latest Android Studio version
# ================================================================
echo "🔍 Detecting latest Android Studio version..."
STUDIO_URL=$(curl -s https://developer.android.com/studio |
	grep -oP 'https://[^"]*gvt1\.com[^"]*linux\.tar\.gz' | head -1)

if [ -z "$STUDIO_URL" ]; then
	echo "⚠️ Auto-detection failed, using fallback version..."
	VERSION_NUM="2026.1.1.10"
	VERSION_NAME="quail1-patch2"
	STUDIO_URL="https://edgedl.me.gvt1.com/android/studio/ide-zips/${VERSION_NUM}/android-studio-${VERSION_NAME}-linux.tar.gz"
fi

TAR_FILE=$(basename "$STUDIO_URL")
VERSION_NUM=$(echo "$STUDIO_URL" | grep -oP '/\d+\.\d+\.\d+\.\d+/' | tr -d '/')
VERSION_NAME=$(echo "$TAR_FILE" | sed 's/android-studio-//;s/-linux\.tar\.gz//')
CACHED_TAR="${CACHE_DIR}/${TAR_FILE}"

# ================================================================
# Step 3 — Decide what (if anything) still needs doing
# ================================================================
SKIP_DOWNLOAD=false
SKIP_CONVERT=false
SKIP_ENV=false
SKIP_DESKTOP=false

INSTALLED_BUILD="${AS_HOME}/build.txt"
VERSION_STAMP="${AS_HOME}/.installer-version"

# Skip the (large) Android Studio download when the version we would
# download is already installed OR already cached:
#   1. installed — build.txt, product-info.json, or our own stamp file
#      contains VERSION_NUM or VERSION_NAME
#   2. cached — ${CACHE_DIR}/${TAR_FILE} already exists (reused in 4a)
INSTALLED_TEXT=""
if [ -f "$INSTALLED_BUILD" ]; then
	INSTALLED_TEXT="${INSTALLED_TEXT}$(cat "$INSTALLED_BUILD" 2>/dev/null || true)
"
fi
if [ -f "${AS_HOME}/product-info.json" ]; then
	INSTALLED_TEXT="${INSTALLED_TEXT}$(cat "${AS_HOME}/product-info.json" 2>/dev/null || true)
"
fi
if [ -f "$VERSION_STAMP" ]; then
	INSTALLED_TEXT="${INSTALLED_TEXT}$(cat "$VERSION_STAMP" 2>/dev/null || true)"
fi

if [ -n "$VERSION_NUM" ] && echo "$INSTALLED_TEXT" | grep -qF "$VERSION_NUM"; then
	SKIP_DOWNLOAD=true
elif [ -n "$VERSION_NAME" ] && echo "$INSTALLED_TEXT" | grep -qF "$VERSION_NAME"; then
	SKIP_DOWNLOAD=true
fi

if [ "$SKIP_DOWNLOAD" = true ]; then
	echo "📦 Android Studio ${VERSION_NUM} (${VERSION_NAME}) already installed — skipping download."
elif [ -f "$CACHED_TAR" ]; then
	echo "📦 Cached Android Studio archive found (${CACHED_TAR}) — reusing, no download needed."
fi

# A "converted" install: aarch64 JBR, x86 launcher disabled, wrapper present
if [ -f "${AS_HOME}/jbr/release" ] &&
	grep -q 'OS_ARCH="aarch64"' "${AS_HOME}/jbr/release" 2>/dev/null &&
	[ ! -f "${AS_HOME}/bin/studio" ] &&
	[ -f "${AS_HOME}/bin/studio-termux" ]; then
	SKIP_CONVERT=true
fi

if grep -q "JAVA_HOME=.*android-studio/jbr" "$RC_FILE" 2>/dev/null &&
	grep -q "PATH=\$PATH:\$JAVA_HOME/bin" "$RC_FILE" 2>/dev/null &&
	grep -q "PATH=.*android-studio/bin" "$RC_FILE" 2>/dev/null; then
	SKIP_ENV=true
fi

if [ -f "$DESKTOP_FILE" ] && grep -q "Version=${VERSION_NUM}" "$DESKTOP_FILE" 2>/dev/null; then
	SKIP_DESKTOP=true
fi

# ================================================================
# Step 4 — Download and install
# ================================================================
if [ "$SKIP_DOWNLOAD" = true ] && [ "$SKIP_CONVERT" = true ] &&
	[ "$SKIP_ENV" = true ] && [ "$SKIP_DESKTOP" = true ]; then
	echo "✅ Android Studio ${VERSION_NUM} (${VERSION_NAME}) is already up to date. Nothing to do."
else
	# --- 4a. Download and extract Android Studio core ---
	JBR_RELEASE=""
	IDE_INFO=""

	if [ "$SKIP_DOWNLOAD" = false ]; then
		if [ ! -f "$CACHED_TAR" ]; then
			echo "📥 Downloading Android Studio ${VERSION_NUM} (${VERSION_NAME})..."
			wget -c "$STUDIO_URL" -O "$CACHED_TAR"
		else
			echo "📦 Using cached Android Studio archive (${CACHED_TAR})..."
		fi

		# Capture the bundled JBR release file + product-info BEFORE we
		# strip the x86_64 payload, so we can fetch the matching aarch64
		# JBR and IntelliJ natives below.
		JBR_RELEASE=$(tar -xOf "$CACHED_TAR" android-studio/jbr/release 2>/dev/null || true)
		IDE_INFO=$(tar -xOf "$CACHED_TAR" android-studio/product-info.json 2>/dev/null || true)

		echo "📦 Extracting archive to ${INSTALL_DIR} (x86_64 JBR/natives excluded)..."
		extract 'Android Studio' "$CACHED_TAR" -C "$INSTALL_DIR" \
			--exclude 'android-studio/jbr/*' \
			--exclude 'android-studio/lib/jna/*' \
			--exclude 'android-studio/lib/native/*' \
			--exclude 'android-studio/lib/pty4j/*'
	fi

	# --- 4b. aarch64 conversion ---
	if [ "$SKIP_CONVERT" = false ]; then
		# Recover release/product-info from an existing (x86_64) install
		# when repairing in place after a prior script run.
		if [ -z "$JBR_RELEASE" ] && [ -f "${AS_HOME}/jbr/release" ]; then
			JBR_RELEASE=$(cat "${AS_HOME}/jbr/release")
		fi
		if [ -z "$IDE_INFO" ] && [ -f "${AS_HOME}/product-info.json" ]; then
			IDE_INFO=$(cat "${AS_HOME}/product-info.json")
		fi

		# Version/build of the JBR that this AS build bundles
		JBR_VER=$(printf '%s' "$JBR_RELEASE" | grep -oP 'JAVA_VERSION="\K[^"]+' | head -1)
		JBR_BUILD=$(printf '%s' "$JBR_RELEASE" |
			grep -oP 'JAVA_RUNTIME_VERSION="\K[^"]+-[a-z][0-9]+\.[0-9]+' |
			grep -oP '[a-z][0-9]+\.[0-9]+$')
		if [ -z "$JBR_VER" ] || [ -z "$JBR_BUILD" ]; then
			echo "⚠️ Could not read bundled JBR version — using fallback..."
			JBR_VER="25.0.3"
			JBR_BUILD="b508.16"
		fi

		# Human IDEA version, derived from the AS data-directory name
		IDEA_VER=$(printf '%s' "$IDE_INFO" |
			grep -oP '"dataDirectoryName"\s*:\s*"AndroidStudio\K[0-9.]+' | head -1)
		[ -z "$IDEA_VER" ] && IDEA_VER="2026.1.4"

		# 4b-i. Replace the x86_64 JBR with the aarch64 JBR
		JBR_URL="https://cache-redirector.jetbrains.com/intellij-jbr/jbr_jcef-${JBR_VER}-linux-aarch64-${JBR_BUILD}.tar.gz"
		JBR_TGZ="${CACHE_DIR}/jbr_jcef-${JBR_VER}-linux-aarch64-${JBR_BUILD}.tar.gz"
		echo "📥 Downloading aarch64 JetBrains Runtime ${JBR_VER}-${JBR_BUILD}..."
		wget -c "$JBR_URL" -O "$JBR_TGZ"
		echo "📦 Replacing x86_64 JBR with aarch64 JBR..."
		rm -rf "${AS_HOME}/jbr"
		mkdir -p "${AS_HOME}/jbr"
		extract 'aarch64 JBR' "$JBR_TGZ" -C "${AS_HOME}/jbr" --strip-components=1

		# 4b-ii. Merge aarch64 native binaries from IntelliJ Community.
		# Probe the CDN for the exact companion version first, then fall
		# back to the newest published Linux-aarch64 build. The native
		# pieces (fsnotifier, restarter, jna, pty4j, lib/native) are
		# version-independent, so a neighbouring Community build is safe.
		echo "🕵️ Locating an IntelliJ Community aarch64 build for natives..."
		IDEA_URL=""
		IDEA_VER_USED=""
		for cand in "${IDEA_VER}" 2025.2.4 2025.2.3 2025.2.2 2025.2.1 2025.2 \
			2025.1.7 2025.1.6 2025.1.5 2024.3.5; do
			cand_url="https://download.jetbrains.com/idea/ideaIC-${cand}-aarch64.tar.gz"
			cand_code=$(curl -sIL -o /dev/null -w '%{http_code}' --max-time 20 "$cand_url")
			if [ "$cand_code" = "200" ]; then
				IDEA_URL="$cand_url"
				IDEA_VER_USED="$cand"
				break
			fi
			echo "  - ideaIC-${cand}-aarch64.tar.gz unavailable (HTTP ${cand_code})"
		done
		if [ -z "$IDEA_URL" ]; then
			echo "❌ No published IntelliJ Community aarch64 build found."
			exit 1
		fi
		if [ "$IDEA_VER_USED" != "$IDEA_VER" ]; then
			echo "⚠️  No aarch64 Community build of ${IDEA_VER} exists — using"
			echo "    ${IDEA_VER_USED} natives instead (these are version-independent)."
		fi
		IDEA_TGZ="${CACHE_DIR}/ideaIC-${IDEA_VER_USED}-aarch64.tar.gz"
		echo "📥 Downloading IntelliJ Community ${IDEA_VER_USED} (aarch64 natives)..."
		wget -c "$IDEA_URL" -O "$IDEA_TGZ"
		echo "🧩 Merging aarch64 native binaries (fsnotifier, restarter, jna, native, pty4j)..."
		EXTRACTED=0
		for pat in '*/bin/fsnotifier' '*/bin/restarter' \
			'*/lib/jna' '*/lib/native' '*/lib/pty4j'; do
			if extract "${pat#*/}" "$IDEA_TGZ" -C "${AS_HOME}" \
				--strip-components=1 --wildcards "$pat"; then
				EXTRACTED=$((EXTRACTED + 1))
			else
				echo "  ⚠️ pattern '$pat' not found in ${IDEA_TGZ} (skipped)"
			fi
		done
		if [ "$EXTRACTED" -lt 3 ]; then
			echo "❌ IntelliJ Community aarch64 natives missing — is ${IDEA_TGZ} a valid ${IDEA_VER_USED} build?"
			exit 1
		fi
		for bin in bin/fsnotifier bin/restarter; do
			if [ -f "${AS_HOME}/${bin}" ] &&
				[ "$(od -An -tx1 -j18 -N2 "${AS_HOME}/${bin}" | tr -d ' \n')" != "b700" ]; then
				echo "❌ ${bin} is not an aarch64 ELF — conversion incomplete."
				exit 1
			fi
		done

		# 4b-iii. Patch launcher scripts / product metadata
		echo "🩹 Patching launcher scripts and metadata for aarch64..."
		mv "${AS_HOME}/bin/studio" "${AS_HOME}/bin/studio.do_not_use" 2>/dev/null || true
		sed -i 's/amd64/aarch64/g' "${AS_HOME}"/bin/*.sh 2>/dev/null || true
		sed -i 's/amd64/aarch64/g' "${AS_HOME}/product-info.json" 2>/dev/null || true

		# 4b-iv. Re-point every ELF at Termux's glibc runtime
		echo "🔧 Patching ELF interpreter/RUNPATH to Termux glibc (${GLIBC_LIB})..."
		patchelf_glibc() {
			local f="$1"
			local orig new
			[ -e "$f" ] || {
				echo "  ⚠️ missing file (skipped): $f"
				return 0
			}
			# Shared libraries (.so) have no PT_INTERP, so
			# --set-interpreter always fails on them. Set RPATH/RUNPATH
			# on every ELF, but only touch the interpreter on files
			# that actually have one.
			orig=$(patchelf --print-rpath "$f" 2>/dev/null || true)
			new="$GLIBC_LIB"
			[ -n "$orig" ] && new="$new:$orig"
			if ! patchelf --set-rpath "$new" "$f" 2>/dev/null; then
				echo "  ⚠️ patchelf --set-rpath failed: $f"
				return 0
			fi
			if patchelf --print-interpreter "$f" >/dev/null 2>&1; then
				if ! patchelf --set-interpreter "$GLIBC_LOADER" "$f" 2>/dev/null; then
					echo "  ⚠️ patchelf --set-interpreter failed: $f"
				fi
			fi
		}
		patch_elfs() {
			local dir="$1"
			[ -d "$dir" ] || return 0
			local f
			while IFS= read -r -d '' f; do
				if [ "$(head -c 4 "$f" 2>/dev/null)" = "$(printf '\177ELF')" ]; then
					patchelf_glibc "$f"
				fi
			done < <(find "$dir" -type f -print0)
		}
		patch_elfs "${AS_HOME}/jbr"
		patch_elfs "${AS_HOME}/lib/native"
		patch_elfs "${AS_HOME}/lib/jna"
		patch_elfs "${AS_HOME}/lib/pty4j"
		patchelf_glibc "${AS_HOME}/bin/fsnotifier"
		patchelf_glibc "${AS_HOME}/bin/restarter"

		# 4b-v. Termux:X11 launcher wrapper
		cat >"${AS_HOME}/bin/studio-termux" <<'WRAPPER'
#!/bin/sh
# Termux-native launcher for the aarch64-converted Android Studio.
# All ELFs carry a patchelf'd interpreter/RUNPATH to $PREFIX/glibc/lib,
# so we must NOT export LD_LIBRARY_PATH (bionic executables would then
# try to load glibc's linker-script libc.so) and MUST clear LD_PRELOAD
# (Termux injects the bionic libtermux-exec-ld-preload.so everywhere).
export DISPLAY="${DISPLAY:-:0}"
unset LD_PRELOAD
unset LD_LIBRARY_PATH
exec "$(dirname "$0")/studio.sh" "$@"
WRAPPER
		chmod +x "${AS_HOME}/bin/studio-termux"
	fi

	# --- 4c. Environment setup (JAVA_HOME -> aarch64 JBR) ---
	if [ "$SKIP_ENV" = false ]; then
		echo "⚙️ Configuring environment paths in ${RC_FILE}..."
		grep -q "JAVA_HOME=.*android-studio/jbr" "$RC_FILE" 2>/dev/null || {
			sed -i '/^export JAVA_HOME=/d' "$RC_FILE" 2>/dev/null || true
			echo "export JAVA_HOME=${AS_HOME}/jbr" >>"$RC_FILE"
		}
		grep -q "PATH=\$PATH:\$JAVA_HOME/bin" "$RC_FILE" 2>/dev/null || echo 'export PATH=$PATH:$JAVA_HOME/bin' >>"$RC_FILE"
		grep -q "PATH=.*android-studio/bin" "$RC_FILE" 2>/dev/null || echo "export PATH=\$PATH:${AS_HOME}/bin" >>"$RC_FILE"
	fi

	# --- 4d. Termux-X11 desktop launcher ---
	if [ "$SKIP_DESKTOP" = false ]; then
		echo "🖥️ Creating Termux-X11 desktop launcher..."
		cat <<EOF >"$DESKTOP_FILE"
[Desktop Entry]
Type=Application
Version=${VERSION_NUM}
Name=Android Studio
Comment=Run Android Studio inside Termux-X11 (aarch64)
Icon=${AS_HOME}/bin/studio.png
Exec=${AS_HOME}/bin/studio-termux
Terminal=false
StartupNotify=true
EOF
		chmod +x "$DESKTOP_FILE"
	fi

	# Record exactly which upstream tarball this install came from so the
	# Step-3 installed-version check works even if build.txt format changes.
	echo "${VERSION_NUM} ${VERSION_NAME} ${TAR_FILE}" >"${AS_HOME}/.installer-version"
fi

# ================================================================
# Done
# ================================================================
echo "✅ Android Studio ${VERSION_NUM} (${VERSION_NAME}) setup completed successfully!"
echo
echo "  Start Termux:X11, then XFCE:"
echo "    termux-x11 :0 &"
echo "    export DISPLAY=:0"
echo "    xfce4-session &"
echo
echo "  Launch Android Studio:"
echo "    • Desktop icon:  double-click AndroidStudio.desktop in XFCE"
echo "    • Terminal:      source ${RC_FILE} && studio-termux"
echo "    • Full path:     ${AS_HOME}/bin/studio-termux"
echo
echo "  Setup wizard:"
echo "    1. Choose 'Custom' install type"
echo "    2. Uncheck 'Android Virtual Device (AVD)' — emulator won't"
echo "       work on aarch64 Termux; use a physical device instead"
echo "    3. Ignore warnings about missing Emulator components"
echo
echo "  REQUIRED — Add to your project's gradle.properties:"
echo "    android.aapt2FromMavenOverride=\${ANDROID_HOME}/build-tools/36.1.0/aapt2"
echo
echo "  NOTE: the aarch64 JBR is glibc-linked and runs through Termux's"
echo "        glibc runtime. Keep glibc-runner installed, and run the IDE"
echo "        via the 'studio-termux' wrapper (clears LD_PRELOAD)."
echo
