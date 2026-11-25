# VYBE

### Your Mac. Your Environment. Your Rules.

VYBE is a native macOS desktop customization and productivity environment designed to transform the traditional Mac desktop into a more personal, interactive and intelligent workspace.

Instead of being just another launcher or wallpaper application, VYBE brings desktop customization, productivity utilities, AI assistance and interactive controls together in one environment.

## Features

### Immersive Desktop
- Static and video wallpapers.
- Full-scene illustrated wallpaper artwork.
- Customizable desktop widgets.
- Application and folder shortcuts.
- Desktop appearance controls.

### VYBE Radial Launcher
A keyboard-accessible circular launcher for frequently used actions.

- Navigate with arrow keys.
- Launch actions with Return.
- Close with Escape.
- Custom application and URL shortcuts.
- Built-in productivity utilities.

### Productivity Tools
- Dictation Studio with a live transcript and copy functionality.
- Screenshot AI for sending a selected screen capture to a compatible AI model.
- Calculator.
- QR code generation.
- Memory Cards for personal notes and saved information.
- File conversion utilities.
- Clipboard-related actions and web search.

### AI Integration
- Google Gemini integration.
- OpenRouter integration.
- User-configured API keys stored in macOS Keychain.
- Model selection and AI settings.

### Desktop Controls
- Custom VYBE Dock.
- Global keyboard shortcuts.
- VYBE Command palette.
- VYBE Spaces for organizing workspace configurations.
- Menu-bar Control Centre.

### VYBE Display
Optional integration with AnyDisplay for extending a Mac display to a compatible Android device.

AnyDisplay is a separate third-party project. See its included license and setup documentation.

## Requirements

- macOS 13 or later for the VYBE project.
- Xcode with a compatible macOS SDK.
- Apple Development signing for consistent Screen Recording permissions.
- Internet access for online AI providers.
- API key for the AI provider you choose.

The AnyDisplay host has its own macOS requirements.

## Getting Started

1. Clone this repository.
2. Open `VYBE.xcodeproj` in Xcode.
3. Select the VYBE target.
4. Configure Signing & Capabilities with your Apple Development Team.
5. Build and run the VYBE scheme.

Grant permissions only when you use the corresponding feature, such as microphone access for dictation or Screen Recording for Screenshot AI.

## AI Configuration

VYBE supports Google Gemini and OpenRouter.

You must provide your own API key through VYBE's settings. Never commit API keys or credentials to the repository.

## Privacy

VYBE uses native macOS permissions for features such as microphone capture, speech recognition, screen capture and Apple application automation.

Screenshot AI sends the screenshot you explicitly select to your configured AI provider. Review that provider's privacy and data-handling terms before sharing sensitive information.

## Third-Party Software

VYBE uses native Apple frameworks and integrates with the separately distributed AnyDisplay project.

Third-party license notices are provided in `ThirdPartyLicenses/`.

## Project Status

VYBE is an actively developed personal macOS project. Some functionality depends on macOS permissions, installed Apple applications, available codecs and external AI providers.

Not every feature has been independently tested across all macOS versions and hardware configurations.

## License

The VYBE project license is to be selected by its author before publication. AnyDisplay retains its separate third-party license.

---

**VYBE — Work. Create. Explore.**
