# VYBE Display setup

VYBE Display uses the MIT-licensed AnyDisplay host and Android receiver as its display transport.
The VYBE Control Centre provides installation, launch, download and permission shortcuts.

## Mac

1. Open VYBE Control Centre and find **VYBE Display**.
2. Choose **Install Display Engine**. VYBE downloads the upstream AnyDisplay macOS release from its official GitHub release URL and installs it under `~/Library/Application Support/VYBE/Display/`.
3. Choose **Launch Host**.
4. Approve Screen Recording and Accessibility permissions for **AnyDisplay** in macOS Privacy & Security when requested.

The upstream macOS host requires macOS 14 or newer. It uses a virtual display on macOS, ScreenCaptureKit, VideoToolbox and a menu-bar controller.

## Android tablet

1. Choose **Android App** in VYBE Display to download the official AnyDisplay APK.
2. Install the APK on the tablet and open it.
3. For Wi-Fi, keep the Mac and tablet on the same local network. The tablet advertises itself using Bonjour/mDNS.
4. For USB, enable Developer options and USB debugging on Android, connect a data-capable USB cable, and ensure Android Platform-Tools (`adb`) is installed on the Mac.
5. Use the AnyDisplay menu-bar icon on the Mac to select the tablet. Compare the six-digit pairing code on both devices and approve only if they match.

Once connected, AnyDisplay creates a real extended display (not merely a VYBE-rendered mirror). You can arrange it in macOS System Settings > Displays and drag application windows onto it.

## Important implementation boundary

The VYBE code in this project is the branded management surface and installer/launcher. The display transport, virtual-display implementation, pairing, encryption, capture, encoding, decoding and Android receiver are upstream AnyDisplay components. VYBE does not claim to have rewritten or embedded those systems.

Upstream project: https://github.com/efekurucay/anydisplay  
Upstream setup guide: https://efekurucay.com/anydisplay/  
Upstream license: `ThirdPartyLicenses/AnyDisplay-MIT-LICENSE.txt`
