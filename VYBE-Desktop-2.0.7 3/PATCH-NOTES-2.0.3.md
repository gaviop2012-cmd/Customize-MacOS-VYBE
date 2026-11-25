# VYBE 2.0.3 — Xcode Build Fix

## Fixed Swift compiler errors
- Corrected four `strokeCurve` calls in `VYBE/DesktopEnvironment.swift`.
- The helper is declared with an unlabeled first parameter (`_ y: CGFloat`), so the call sites now pass the first coordinate without the invalid `y:` argument label.

## Updated Xcode build settings
- Set `ALWAYS_SEARCH_USER_PATHS = NO` in all four project/target Debug and Release build configurations to remove the deprecated traditional headermap behavior warning.
- Xcode will use its supported separate headermap behavior with the legacy always-search-user-paths behavior disabled.

## Validation performed here
- Swift frontend syntax parsing for all Swift source files.
- Xcode project file lint/format validation.
- ZIP archive integrity check.

A full macOS Xcode build and runtime test cannot be performed in this non-macOS environment.
