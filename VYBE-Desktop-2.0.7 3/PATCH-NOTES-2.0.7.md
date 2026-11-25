# VYBE 2.0.7 — Calculator, Dictation Studio, Memory Cards, Artwork & File Conversion

## Radial calculator stability
- Calculator rejects clipboard expressions longer than 120 characters before scanning/parsing them.
- Parenthesis nesting is limited to 24 levels and invalid/unbalanced expressions fail fast.
- The calculation still uses VYBE's arithmetic parser; it never evaluates clipboard text as code.

## Dictation Studio
- Dictation no longer injects keystrokes, edits the focused app, changes the clipboard, or requires Accessibility / keyboard-event permission.
- Recognized partial results update a dedicated VYBE panel live.
- The panel provides selectable text, Copy transcript, Stop, Done, and a close control that also stops microphone capture.
- Microphone and Speech Recognition permissions remain required.

## Memory Cards
- The old Quick Note action is migrated to Memory Card.
- Cards are written as Markdown files under `~/Library/Application Support/VYBE/Memory Cards/`.
- This is a VYBE-owned capture space, not Apple Notes.

## File Converter
- Convert File first checks the selected Finder item (when Finder was the app that launched the radial); otherwise it opens a file picker.
- Original files are preserved and generated files use collision-safe `-converted` names.
- Images: PNG, JPEG, HEIC, TIFF, GIF, BMP, WebP, JPEG 2000 and PDF where Image I/O on this Mac supports the destination format.
- PDFs: export each page to PNG or JPEG images.
- Video: MP4, MOV and M4V when the source and installed macOS codecs support the selected container.
- Audio extraction/conversion: M4A when AVFoundation supports the source.
- Pages: export to DOCX or PDF through Apple Pages.
- Keynote: export to PPTX or PDF through Apple Keynote.
- DOC/DOCX and PPT/PPTX: PDF export through Pages or Keynote respectively.
- Finder selection and document-app exports can trigger macOS Automation permission prompts. VYBE requests this only when the conversion action is used.
- PDF-to-editable-Pages is intentionally not presented as a lossless conversion. PDF is a fixed-layout format; the current PDF workflow exports page images. Reconstructing editable text/layout needs a separate OCR/document reconstruction workflow.

## New static artwork
- Added Mythic Forest, Neon Rain, Sakura District, Abyssal Bloom and Astral Cathedral.
- These are layered native vector illustrations with scene details, depth, lighting, foliage/coral/city architecture, and particle elements rather than a single centered gradient shape.
- Artwork cache moved to `Artwork-v3` so the updated illustrations regenerate instead of reusing old cached files.

## Project configuration
- Updated Speech Recognition, Screen Capture and Apple Events usage descriptions.
- Removed obsolete dictation keyboard-event permission status from AI Settings.
- Preserved the existing AnyDisplay installation logic and previous project features.

## Validation performed
- Swift frontend syntax parsing passed for the project Swift files.
- Xcode project plist syntax validation passed.
- ZIP integrity checked after packaging.
- A full macOS Xcode build, real microphone test, file conversion test and visual wallpaper test were not possible in this Linux environment.
