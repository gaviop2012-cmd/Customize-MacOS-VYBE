# VYBE 3.0 — Systems expansion

## Added
- Unified eight-system hub integrated into the existing Control Centre.
- Desktop panel for the existing wallpaper engine and widget selection.
- Installed-app search and launch panel.
- Local Ollama endpoint validation, model discovery and chat.
- Display inventory and native macOS settings shortcuts.
- Saved manual Flow sequences with website, app and clipboard actions.
- Existing VYBE Spaces manager surfaced as Workspace profiles.
- Persistent accent, density and glow preferences for the new hub.
- Manual clipboard history and persistent local quick note.
- macOS GitHub Actions build workflow and local validation script.

## Safety and compatibility
- Existing OpenRouter and Gemini Keychain storage is unchanged.
- Clipboard capture is manual; no background clipboard polling is introduced.
- Flow supports only explicit allowlisted actions; no arbitrary shell execution.
- Ollama prompts go to the configured endpoint; no automatic model downloads.
- Existing wallpaper, Dock, radial, dictation, screenshot, converter and display implementations are retained rather than rewritten.

## Validation boundary
- Swift parser and project-file checks can run on non-macOS hosts.
- A real Xcode/macOS SDK build is delegated to the included macOS CI workflow and must be observed passing before release.
- Signing, notarization, permission prompts and interactive regression tests require the user's Mac.
