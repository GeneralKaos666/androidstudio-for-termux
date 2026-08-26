# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Skip re-download if installed Android Studio version already matches the latest detected version
- Skip env var setup if `JAVA_HOME` and `PATH` entries already exist in the shell RC file
- Skip desktop entry creation if launcher already exists with the current version
- Single "already up to date" message when all three checks pass

### Fixed
- Quoted `JAVA_HOME` subshells to prevent word splitting on paths with spaces

### Changed
- README: Fixed script filename references (`install_Android_Studio.sh`)
- README: Updated "What the script does" to match actual script behavior
- README: Updated "Updating" section to document skip-if-up-to-date behavior

## [1.0.0] - 2025-01-01

### Added
- Initial release
- Auto-detect latest Android Studio version from Google's developer site
- Fallback to hardcoded version if auto-detection fails
- Install dependencies (`x11-repo`, `termux-x11-nightly`, `XFCE4`, `openjdk-21`, `maven`, `wget`, `unzip`, `tar`)
- Configure `JAVA_HOME` and `PATH` in user's shell RC file with duplicate guards
- Create Termux-X11 desktop launcher
- Auto-detect user's default shell (bash, zsh, fish) for correct RC file
