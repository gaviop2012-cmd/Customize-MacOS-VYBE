import AppKit
import Carbon.HIToolbox

enum VYBEHotKey: UInt32 {
    case mute = 1
    case loop = 2
    case restart = 3
    case playPause = 4
    case assistant = 5
    case toggleDock = 6
    case commandPalette = 7
    case radialLauncher = 8
}

final class HotKeyManager {
    static let shared = HotKeyManager()
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    private init() {}

    func registerShortcuts() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerProcPtr = { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, let shortcut = VYBEHotKey(rawValue: hotKeyID.id) else {
                return noErr
            }
            DispatchQueue.main.async {
                Task { @MainActor in
                    switch shortcut {
                    case .assistant:
                        VYBEAssistantWindow.shared.toggleAndListen()
                    case .toggleDock:
                        DesktopEnvironment.shared.toggleDockVisibility()
                    case .commandPalette:
                        VYBEOverlayController.shared.toggleCommand()
                    case .radialLauncher:
                        VYBEOverlayController.shared.toggleRadial()
                    default:
                        WallpaperEngine.shared.handleShortcut(shortcut)
                    }
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &handler
        )

        // Option + M: mute, Option + L: loop, Option + R: restart,
        // Option + P: play/pause, Option + Space: VYBE AI. Carbon hotkeys work globally.
        register(id: .mute, keyCode: 46)
        register(id: .loop, keyCode: 37)
        register(id: .restart, keyCode: 15)
        register(id: .playPause, keyCode: 35)
        register(id: .assistant, keyCode: 49) // Option + Space: voice assistant
        register(id: .toggleDock, keyCode: 2) // Option + D: toggle VYBE Dock
        register(id: .commandPalette, keyCode: 49, modifiers: UInt32(optionKey | cmdKey)) // Option + Command + Space avoids Spotlight
        register(id: .radialLauncher, keyCode: 5, modifiers: UInt32(controlKey | optionKey)) // Control + Option + G: radial launcher
    }

    private func register(id: VYBEHotKey, keyCode: UInt32, modifiers: UInt32 = UInt32(optionKey)) {
        var hotKeyID = EventHotKeyID(signature: fourCharCode("VYBE"), id: id.rawValue)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            references.append(reference)
        }
    }

    func unregisterShortcuts() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    private func fourCharCode(_ value: String) -> OSType {
        value.utf16.reduce(0) { ($0 << 8) + OSType($1) }
    }
}
