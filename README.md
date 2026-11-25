# VYBE — A More Personal Mac Experience

**VYBE is a native macOS desktop customisation environment designed to transform the way your Mac looks, feels and works.**

Instead of being limited to changing your wallpaper or rearranging a few icons, VYBE brings together desktop personalisation, custom launchers, intelligent shortcuts, AI-assisted tools and a collection of utilities in one cohesive experience.

Built primarily with **Swift, SwiftUI and AppKit**, VYBE is designed to work with macOS rather than imitate it through a web interface.

---

## Contents

- [What is VYBE?](#what-is-vybe)
- [1. Wallpaper Studio](#1-wallpaper-studio)
- [2. Desktop Widgets](#2-desktop-widgets)
- [3. VYBE Dock](#3-vybe-dock)
- [4. Control Centre](#4-control-centre)
- [5. VYBE Radial Launcher](#5-vybe-radial-launcher)
- [6. Dictation Studio](#6-dictation-studio)
- [7. AI Assistant](#7-ai-assistant)
- [8. Screenshot AI](#8-screenshot-ai)
- [9. Memory Cards](#9-memory-cards)
- [10. File Converter](#10-file-converter)
- [11. App Visual Customisation](#11-app-visual-customisation)
- [12. VYBE Display](#12-vybe-display)
- [13. Keyboard Shortcuts](#13-keyboard-shortcuts)
- [14. Themes and Appearance](#14-themes-and-appearance)
- [Technical Architecture](#technical-architecture)
- [Installation](#installation)
- [Permissions and Privacy](#permissions-and-privacy)
- [Known Limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

---

## What is VYBE?

VYBE is an attempt to make the Mac desktop feel like a personalised computing environment.

It combines several ideas:

- A custom wallpaper experience.
- A desktop with useful visual elements.
- A dedicated application launcher.
- Keyboard-driven actions.
- AI-powered assistance.
- Small utilities that reduce the need to switch between applications.
- Native macOS integrations.

The goal is to make common actions easier to access while giving the desktop its own visual identity.

## 1. Wallpaper Studio

Wallpaper Studio is the foundation of VYBE.

It allows users to build a personal wallpaper library and use both static images and videos as desktop backgrounds.

### Static wallpapers

Choose an image and use it as the desktop background. VYBE also includes a collection of designed wallpaper scenes intended to make the desktop feel more atmospheric and expressive.

### Video wallpapers

Import local video files and use them as animated desktop backgrounds.

The playback system supports:

- Continuous looping.
- Play and pause controls.
- Audio mute and unmute.
- Restarting playback.
- A persistent local wallpaper library.
- Restoring the previously selected wallpaper after reopening VYBE.
- Wallpaper playback across connected displays.
- Recovery after sleep and wake events.

### Wallpaper library

Imported videos are stored in VYBE's application-support directory so the library can persist between launches.

Users can manage their saved wallpapers and remove videos they no longer want.

### Automatic wallpaper rotation

Where enabled, VYBE can automatically change wallpapers at a configured interval.

Rotation can use sequential or random selection. At least two saved videos are needed for rotation.

## 2. Desktop Widgets

VYBE includes a desktop-personalisation area for useful information and quick access.

The intended widget experience includes:

- Clock.
- Date.
- Quick notes.
- Timer and stopwatch.
- Custom text.
- System information.

Widget preferences can be stored so the desktop configuration remains consistent.

**Important:** Widget preferences and in-app previews should not be confused with independent desktop-overlay windows. Whether widgets are independently draggable on the actual desktop depends on the implementation in the particular release.

## 3. VYBE Dock

VYBE Dock is an independent application launcher.

It provides an alternative way to access frequently used Mac applications without relying exclusively on the standard Dock.

### How it works

1. Open the VYBE Dock interface.
2. Add an application using the application picker.
3. Select an application from your favourites.
4. VYBE asks macOS to launch that application.
5. Remove applications from your favourites when they are no longer needed.

The Dock is designed around a floating, minimal appearance, with custom icon presentation and visual effects.

**macOS distinction:** VYBE Dock is a separate launcher. It does not replace or modify Apple's protected Dock or Finder components.

## 4. Control Centre

The VYBE Control Centre brings important controls into one place.

Instead of opening several separate windows, users can access relevant VYBE controls through the application's control interface and menu-bar integration.

Depending on the release, these controls can include:

- Wallpaper controls.
- Playback controls.
- Quick access to VYBE modules.
- Appearance settings.
- Application shortcuts.
- Desktop customisation settings.

The idea is to make VYBE's most frequently used functions accessible without navigating through the entire application.

## 5. VYBE Radial Launcher

The radial launcher provides a circular way to access actions and shortcuts.

Rather than presenting everything as a conventional list, it arranges available actions around a central interaction point.

### Interaction

The launcher is designed to support:

- Opening the radial interface.
- Selecting an action.
- Navigating between actions using arrow keys.
- Confirming a selection with Return.
- Closing the interface with Escape.
- Displaying the selected action and its description.

The keyboard-navigation model is:

| Key | Action |
|---|---|
| Left / Up | Previous action |
| Right / Down | Next action |
| Return | Launch selected action |
| Escape | Close launcher |

The radial launcher is intended to make frequently used actions feel immediate and accessible.

## 6. Dictation Studio

Dictation Studio provides a speech-to-text workflow within VYBE.

### How it works

1. Open Dictation Studio.
2. Start dictation.
3. Allow macOS microphone access when requested.
4. Speak into the microphone.
5. View the recognised speech in the transcript area.
6. Copy the resulting text when ready.

The newer panel-based workflow is intended to show the transcript live instead of silently attempting to type into whichever application happens to be active.

This makes it useful for preparing messages, notes, search queries and longer passages of text.

Recognition quality and language support depend on the speech-recognition services available to the application and macOS.

## 7. AI Assistant

VYBE includes an AI-assisted experience that can connect to supported remote AI providers.

The provider architecture has included OpenRouter and Gemini.

### How it works

1. Configure a supported AI provider.
2. Supply the required credentials through the application's supported credential-storage flow.
3. Enter a prompt.
4. VYBE sends the request to the configured provider.
5. The response is displayed inside the application.

The AI functionality is intended to provide assistance without requiring a local language model to run on the Mac.

Provider availability, model access, rate limits and costs are determined by the selected provider and account.

## 8. Screenshot AI

Screenshot AI is designed to let users ask questions about something visible on their screen.

### Workflow

1. Open Screenshot AI.
2. Capture or select a screenshot.
3. Enter a question or instruction about the image.
4. Send the screenshot and prompt to the configured AI model.
5. Review the model's response.

Examples:

- Explain this error message.
- Summarise the information in this screenshot.
- Help me understand this application interface.
- Explain what this chart is showing.

The intended workflow is based on a user-selected screenshot, rather than continuous screen monitoring.

Image understanding depends on the capabilities of the configured model.

## 9. Memory Cards

Memory Cards provide a place to keep useful information inside VYBE.

The concept is to make important information easier to save and revisit without having to open a separate note-taking application.

Cards can be used for things such as:

- Important reminders.
- Useful snippets.
- Ideas.
- Information worth keeping.
- Short reference notes.

The exact storage, editing and retrieval behaviour should be checked against the release being distributed.

## 10. File Converter

The File Converter is intended to make common file conversions accessible from VYBE.

Rather than opening a dedicated conversion application for every small task, users can select a supported file and choose an output format.

Examples of conversion workflows include:

- PNG to JPG.
- JPG to PNG.
- Supported image-format conversions.
- Supported document conversions.
- Supported video conversions.

### How it works

1. Select a file.
2. Choose a supported output format.
3. Select an output location where required.
4. Start the conversion.
5. Review the resulting file.

Not every format is interchangeable. For example, converting a PDF into an editable Pages document requires document reconstruction or an appropriate conversion engine; simply changing the file extension does not perform that conversion.

Actual supported formats depend on the conversion engines included in the release.

## 11. App Visual Customisation

VYBE also explores giving commonly used applications a more consistent visual identity.

The aim is to make the Mac feel less like a collection of unrelated interfaces and more like one personalised environment.

This includes custom presentation for application shortcuts and icons where supported.

VYBE does not need to modify the original applications themselves to provide its own launcher and visual presentation.

## 12. VYBE Display

VYBE Display is an optional integration intended to extend the desktop experience to compatible Android devices.

The integration uses the third-party AnyDisplay project.

### General setup

1. Install the compatible AnyDisplay macOS host.
2. Install the Android receiver application on the Android device.
3. Connect both devices to the same Wi-Fi network.
4. Open the host application.
5. Select the Android device.
6. Complete the pairing process using the displayed verification code.

USB-based connection may require Android debugging and the appropriate ADB tools.

VYBE's integration provides access to the external project; the actual display and streaming behaviour is provided by AnyDisplay.

Third-party licensing and attribution must be retained.

## 13. Keyboard Shortcuts

VYBE uses keyboard shortcuts to make common actions quicker.

A documented shortcut from the project is:

| Shortcut | Function |
|---|---|
| Option + D | Open the VYBE Dock |

The radial launcher also supports keyboard navigation:

- Arrow keys to move between actions.
- Return to confirm.
- Escape to close.

Other shortcuts depend on the configured actions in the particular release.

---

## Technical Architecture

VYBE is built primarily using native Apple technologies.

| Technology | Purpose |
|---|---|
| Swift | Application logic |
| SwiftUI | Interface construction |
| AppKit | macOS windows and desktop integration |
| AVFoundation | Video playback |
| Speech framework | Speech recognition where integrated |
| UserDefaults | Persistent preferences |
| Keychain | Secure credential storage where integrated |
| NSWorkspace | Application launching |
| Core Graphics | Screen and graphics-related functionality |

The application is designed to use supported macOS APIs rather than modifying protected system components.

## Installation

### Requirements

- A compatible Mac.
- macOS version supported by the particular VYBE release.
- Xcode if building from source.
- Internet access for remote AI features and downloading optional integrations.

### Build from source

1. Download and extract the VYBE project.
2. Open `VYBE.xcodeproj` in Xcode.
3. Select the **VYBE** scheme.
4. Select **My Mac** as the run destination.
5. Build using `Command + B`.
6. Run using `Command + R`.

Check the project's deployment target before building. Requirements may differ between releases.

## Permissions and Privacy

Some functionality may require access to macOS resources.

Depending on the features enabled, this can include:

- Microphone access for dictation.
- Network access for remote AI requests.
- User-selected file access for importing wallpapers and converting files.
- Screen Recording or Accessibility permissions for optional third-party display functionality.

VYBE should only access resources needed for the action being performed.

AI requests sent to external providers are subject to those providers' privacy policies and data-handling practices. Avoid sending confidential screenshots or files unless you are comfortable with the selected provider's policies.

API credentials should be stored securely and must never be committed to a public repository.

## Known Limitations

VYBE works alongside macOS, not as a replacement for the operating system.

Some limitations are important to understand:

- VYBE Dock is not a replacement for Apple's Dock.
- Desktop widget behaviour depends on the desktop-window implementation in the release.
- System monitoring is limited to information exposed through supported APIs.
- Apple Silicon temperature and fan-speed readings are not guaranteed to be available through public APIs.
- AI functionality depends on the selected provider, model and network connection.
- File conversion is limited to the formats and engines actually supported.
- Third-party display functionality depends on AnyDisplay and its compatibility requirements.

Features should be considered available only when they are present and working in the specific release being used.

## Contributing

Contributions, bug reports and suggestions are welcome.

When reporting a bug, include:

- macOS version.
- Mac model.
- VYBE version.
- Steps to reproduce the issue.
- Relevant screenshots or crash logs.

For code contributions:

1. Fork the repository.
2. Create a feature branch.
3. Keep changes modular.
4. Preserve existing working functionality.
5. Test changes on macOS.
6. Submit a pull request with a clear description.

## License

The VYBE project's license should be specified in the repository's root `LICENSE` file.

Third-party components retain their respective licenses. In particular, the AnyDisplay integration must retain its required MIT license notice and attribution.

---

## The Idea Behind VYBE

VYBE is built around a simple idea:

**Your desktop should feel like yours.**

It should be more than a background behind your windows. It should be a space that reflects your style, gives you access to the tools you use, and makes everyday interactions feel more natural.

VYBE brings personalisation and utility together in one native Mac experience.

**Make your Mac feel different. Make it feel like VYBE.**
