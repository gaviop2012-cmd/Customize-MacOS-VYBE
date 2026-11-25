# VYBE 3.0.2 — Video Wallpaper Teardown Fix

## Fix
- Changed video wallpaper teardown to detach each `AVPlayerLayer` from its player before clearing the window content view.
- Flushes the Core Animation transaction after detachment.
- Defers `AVPlayerLooper` release, queue-item removal, and window closing until the next main-run-loop turn so Core Animation/AppKit can process the detach first.
- Keeps the retiring output objects strongly retained throughout that cleanup turn.
- Leaves the player layer attached to its owning `NSView` rather than manually removing a sublayer while AppKit is dismantling the view hierarchy.
- Cancels pending wake-resume work and invalidates playback generation before teardown.

## Validation
- Swift frontend syntax parsing: passed for all project Swift files.
- Xcode project plist validation: passed.
- Shell script syntax validation: passed.
- Full Xcode/macOS build and repeated live video-to-default switching: must still be run on macOS; this environment does not include Xcode or the macOS SDK.
