# VYBE Desktop 2.0.2

## Changes in 1.8.0

- **Option + D** is registered as a global Carbon hotkey and toggles the VYBE Dock without closing its window or losing its configuration.
- Dock width is recalculated from the actual application names/items whenever the dock collection is persisted. Removing apps now shrinks the panel; adding apps expands it. Resizing keeps the Dock's horizontal centre and bottom edge in place.
- Dock and desktop application tiles now display the real macOS app/folder icon returned by `NSWorkspace.icon(forFile:)`, cached in memory. This replaces the previous generic gradient/blob artwork for arbitrary apps.
- Added Google Gemini through Google AI Studio alongside OpenRouter. Gemini model discovery uses Google's `v1beta/models` endpoint and filters for `generateContent` support. Requests use the selected model and the `x-goog-api-key` header.
- Gemini API key is stored in macOS Keychain. The assistant can now use either provider; OpenRouter keeps its existing `:free` model guard and Gemini availability/quotas are governed by the user's Google AI Studio account.
- AI Settings includes a provider selector, Gemini key validation/model loading, model picker, and link to Google AI Studio.

## Setup

1. Open `VYBE.xcodeproj` in Xcode and build/run the VYBE scheme.
2. Press **Option + D** to hide or show the VYBE Dock.
3. Open VYBE Control Centre and click the AI settings gear.
4. Choose **Google Gemini**, create an API key at https://aistudio.google.com/app/apikey, paste it, then select **Validate & load models**. Choose an available model and Save & Close.
5. Alternatively choose OpenRouter and use the existing OpenRouter key/model settings.

## Notes and verification

- Gemini free-tier access, rate limits and billing eligibility depend on Google's current model/account/region rules. VYBE does not guarantee that a Gemini model is free.
- App icons are obtained from macOS application bundles at runtime; no app bundle is modified.
- Dock resizing is estimated from app title widths and bounded to a maximum panel width; very large collections remain horizontally scrollable.
- This environment does not include Xcode or the macOS SDK. Swift source parsing and ZIP integrity can be checked here, but a full macOS build and runtime validation must be completed on a Mac.

## Existing functionality

All existing VYBE source files and resources from the supplied project are retained. Video wallpaper, static backgrounds, widgets, desktop shortcuts, the Control Centre, and the existing voice assistant remain part of the project.


## VYBE 2.0 Foundation — implementation in this archive

This update adds a first, native implementation slice on top of the 1.8.0 source. It is deliberately a foundation rather than a claim that every item in the VYBE 2.0 master specification is finished.

### Added

- **VYBE Spaces:** five starter environments (COMMAND, FOCUS, PLAY, CREATE, PERSONAL), persisted to UserDefaults. Create, rename, delete, activate, and save a Space. Each Space stores its own selected widget IDs and static wallpaper preset.
- **Space switching:** applies the selected Space's widget selection and static wallpaper through the existing widget and wallpaper managers. This is VYBE's own workspace state; it does not manipulate Apple's native Mission Control desktops.
- **VYBE Command:** floating native `NSPanel` command palette. Searches installed apps and VYBE actions/Spaces; application results use actual macOS application icons. Actions open apps, switch Spaces, open Control Centre/AI, toggle the Dock, and switch the existing video/static wallpaper mode.
- **Radial launcher:** floating native `NSPanel` with selectable Space nodes plus direct Control Centre and AI actions.
- **Holographic HUD:** a lightweight, non-interactive floating panel for VYBE status feedback and Space transitions.
- **Global shortcuts:** `⌘⌥Space` opens VYBE Command; `⌃⌥G` opens the radial launcher; existing `⌥D` Dock, `⌥Space` AI and wallpaper shortcuts are retained. `⌘⌥Space` is used instead of `⌘Space` to avoid taking over macOS Spotlight.

### Known limitations / not yet implemented

- Spaces currently persist widgets and static wallpaper presets. Per-Space Dock contents, app shortcuts, window layouts, and independent video selections are not yet implemented.
- Command currently searches installed applications, VYBE Spaces, and built-in VYBE actions. General file/folder search, clipboard history, arbitrary natural-language AI routing, and user-defined commands are not yet implemented.
- The radial launcher has a configurable ring of built-in VYBE utilities and custom app/URL buttons; recent-app suggestions are not yet implemented.
- This update does not yet implement cross-app window snapping, a window minimap, window portals, or a full native window manager. VYBE-owned widget and Dock panels continue to use the existing AppKit panel implementation.
- Weather and music-reactive ambient wallpaper, system-wide HUD replacement, and AI execution cancellation are not implemented by this foundation.
- The AI provider architecture and existing orb are retained; no new arbitrary shell execution has been introduced.

### Build and test status

- All Swift source files passed `swiftc -frontend -parse` in the available environment.
- The ZIP archive passed its CRC/integrity test.
- A full macOS typecheck, Xcode build, UI launch, global-hotkey test, multi-monitor test, and runtime regression test were **not run** because this environment does not include Xcode or the macOS SDK. Open `VYBE.xcodeproj` on the Mac and build the `VYBE` scheme before replacing the installed copy. Keep the 1.8.0 ZIP as a rollback backup.


## VYBE Display persistence

The AnyDisplay host is installed once at `~/Library/Application Support/VYBE/Display/AnyDisplay.app`. VYBE checks this persistent location at startup and launches the existing host if it is installed but not already running. Opening VYBE does not download or reinstall the host. Use the VYBE Display card in Control Centre only for the first installation or to launch the existing host manually.


## VYBE 2.0.2 — Art wallpapers and radial utilities

- Added 10 new illustrated, procedural desktop artworks: Blue Hour, Velvet Dunes, Solstice, Lunar Tide, Sacred Geometry, Botanical Pulse, Afterglow, Quiet Earth, Electric Bloom, and Monolith. The original preset names remain available and now use layered artwork rather than plain colour gradients. Images are generated locally and cached in `~/Library/Application Support/VYBE/Backgrounds/Artwork-v2/`.
- Fresh Spaces now start with the new art presets. Existing saved Space selections are preserved.
- Expanded the radial launcher with 12 additional utilities: Clean Text, Web Search, Translate, Calculate, Quick Note, Screen OCR, Password, Desktop Icons, Save Clipboard, QR Code, Open Link, and Focus 25. Existing saved radial buttons are migrated once; removing a button remains persistent.
- Dictation now inserts recognized speech as it arrives. It replaces revised partial text rather than waiting for the user to stop, displays a non-activating live transcript panel, and preserves the previous clipboard when possible. It requests permission to post keyboard events and reports permission failures rather than silently listening without typing.
- Dictation uses Apple Speech partial recognition and system microphone capture. Apple notes that partial results can arrive multiple times and that recognition availability depends on the selected language/service. See [Apple Speech partial-results documentation](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/shouldreportpartialresults).

### Radial shortcuts

- `⌃⌥G` — open the VYBE radial launcher.
- **Clean Text** — normalize copied text and copy the cleaned version.
- **Web Search / Translate** — send copied text to the browser.
- **Calculate** — evaluate a copied arithmetic expression and copy the result.
- **Quick Note** — save clipboard text into VYBE Quick Notes and open it.
- **Screen OCR** — select a screen region, extract text with Vision, and copy it.
- **Password** — generate and copy a random 22-character password.
- **Desktop Icons** — toggle Finder desktop icon visibility.
- **Save Clipboard** — save copied text to a text file.
- **QR Code** — render a QR code from clipboard text or a URL.
- **Open Link** — open the copied URL.
- **Focus 25** — start a 25-minute focus sprint.

### Dictation permissions

For live insertion, allow VYBE under System Settings → Privacy & Security → Microphone, Speech Recognition, and Accessibility (keyboard-event posting). Keep a text field focused in the app where you want the words inserted before choosing **Dictate**. The live dictation panel is non-activating so it should not steal the text-field focus.


## VYBE 2.0.5 — Screen OCR permission identity fix

- Screen OCR now checks Screen Recording permission from inside VYBE using `CGPreflightScreenCaptureAccess()` before launching the macOS area-selection capture UI. If permission is unavailable to the current app identity, VYBE requests it with `CGRequestScreenCaptureAccess()` and explains that the app must be restarted after approval.
- Added `NSScreenCaptureUsageDescription` to the generated Info.plist.
- Debug and Release configurations now request the stable **Apple Development** signing identity with automatic signing. In Xcode, open **VYBE target → Signing & Capabilities**, enable **Automatically manage signing**, and select the same Team (a Personal Team is sufficient for local development) for every build. Keep `PRODUCT_BUNDLE_IDENTIFIER` as `com.vybe.desktop`. Do not use **Sign to Run Locally** / ad-hoc signing for repeated OCR builds: macOS can treat each ad-hoc build as a different app identity and the Screen Recording grant may not carry over.
- After selecting a stable signing identity, if the old VYBE row remains checked but OCR still fails, remove only the VYBE entry from Screen Recording, run this consistently signed build, grant VYBE once, quit and reopen it. Do not reset all TCC permissions or delete the login keychain.

A full Xcode build and live TCC permission test must be performed on macOS. This environment can validate source syntax and archive structure but cannot confirm the signing identity or actual Screen Recording grant.

## VYBE 2.0.7 update
See `PATCH-NOTES-2.0.7.md` for the calculator safety fix, Dictation Studio, Memory Cards, new illustrated wallpapers, and supported file-conversion matrix.

---

# VYBE 3.0 — Eight connected systems

VYBE 3.0 expands the existing native macOS app with a unified Systems hub. The original wallpaper engine, desktop widgets, VYBE Spaces, radial launcher, Command palette, AI assistant, dictation, screenshot analysis, converter and display integration remain part of the project.

## The eight systems

1. **VYBE Desktop** — Control the existing video/static wallpaper engine and choose which desktop widgets are enabled. Existing widget dragging and wallpaper library behaviour remain in the original desktop engine.
2. **VYBE Command** — Search and launch installed applications from the Systems hub. The existing global Command palette continues to expose VYBE actions, apps and Spaces (`⌘⌥ Space`).
3. **VYBE Intelligence** — Retains the configured OpenRouter and Gemini assistant. Adds a local Ollama connection test, installed-model discovery and a local chat panel using Ollama's `/api/tags` and `/api/chat` endpoints. Local prompts are sent to the endpoint shown in the panel; VYBE does not download models automatically.
4. **VYBE Control** — Shows connected display dimensions and opens the native macOS Display, Sound and Keyboard settings panes. Protected macOS controls remain managed by macOS.
5. **VYBE Flow** — Build and save a sequence of website-opening, application-launching and clipboard-copy actions. A flow runs only when the user presses **Run flow**. It does not run arbitrary shell commands or install background triggers.
6. **VYBE Workspace** — Brings the existing VYBE Spaces manager into the Systems hub. Spaces preserve their own widget selections and VYBE background preset. They are VYBE environments, not replacements for Apple's Mission Control Spaces.
7. **VYBE Studio** — Configure the Systems hub's accent colour, density preference and holographic glow. Existing legacy surfaces retain their established styling to avoid regressions.
8. **VYBE Utilities** — Manually capture text from the system clipboard, recopy saved entries, clear local clipboard history and maintain a locally stored quick note. Clipboard capture is manual; VYBE does not continuously monitor the clipboard.

## Local AI setup

1. Install and run Ollama separately if you want local inference.
2. Open VYBE Control Centre → VYBE Systems → Intelligence.
3. Confirm the endpoint, normally `http://127.0.0.1:11434`, then choose **Test local connection**.
4. Select an installed model and send a prompt. Model downloads are deliberately not automatic.

The local Ollama panel is an additional local chat surface; it does not silently replace the existing OpenRouter/Gemini voice assistant provider.

## Build and validation

Run `Scripts/validate-project.sh` for Swift syntax parsing and project-structure checks. On macOS, the script also runs an unsigned Debug build with `xcodebuild`. GitHub Actions runs the same Xcode target build on a macOS runner for pushes and pull requests.

An unsigned CI build verifies compilation, not Developer ID signing, notarization, runtime permissions or every interactive macOS workflow. Those still require testing on a real Mac.

## API key handling

The existing OpenRouter and Gemini integrations continue to use macOS Keychain. Do not put API keys in Swift source, committed configuration files, screenshots or issue reports. A client-side app cannot make a provider key impossible to extract from a distributed binary; a shared production key should be protected by a backend. Keep your local Xcode user data and local databases if you need them—the build workflow does not require deleting them.


## Building VYBE without code signing

This project is configured to build without an Apple Development certificate, Developer ID certificate, provisioning profile, or notarization. The Xcode Debug and Release configurations set code signing to disabled.

On a Mac with Xcode installed, run:

```bash
chmod +x Scripts/build-unsigned-release.sh
Scripts/build-unsigned-release.sh
```

The script performs a Release build with `CODE_SIGNING_ALLOWED=NO`, verifies that the resulting `.app` has no code signature, and creates `dist/VYBE-3.0.0-Unsigned-macOS.zip`. You can also open `VYBE.xcodeproj` and build/run the `VYBE` target directly; the project configurations are set up for unsigned builds.

### Important macOS distribution limitation

An unsigned app is suitable for local testing and direct sharing with people who understand the Gatekeeper warning. It is not notarized, is not suitable for Mac App Store submission, and macOS may block an app downloaded from the internet. On the recipient's Mac, they may need to Control-click the app and choose **Open**, then confirm the prompt. Only do this if they trust the source and have inspected the app. Do not instruct users to disable Gatekeeper globally.

Unsigned does not mean invisible or tamper-proof: macOS can still inspect the app, and removing its signature does not protect embedded API keys. Do not bundle private service credentials in the application.
