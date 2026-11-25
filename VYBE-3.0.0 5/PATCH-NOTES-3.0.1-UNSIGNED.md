# VYBE 3.0.1 — Unsigned Build Configuration

- Disabled code signing in all Xcode project Debug and Release build configurations.
- Removed the Apple Development signing identity and automatic signing requirement.
- Added `Scripts/build-unsigned-release.sh` to create a Release `.app` without a code signature and package it as a ZIP.
- Added a post-build signature check so the script refuses to label an unexpectedly signed app as unsigned.
- Updated validation and GitHub Actions to build and publish the unsigned artifact.
- Documented Gatekeeper, notarization, and distribution limitations.

A real Xcode build must run on macOS with Xcode installed. Static checks on non-macOS hosts do not establish that the app compiles or launches.
