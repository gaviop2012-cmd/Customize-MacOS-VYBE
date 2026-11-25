import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FolderIconManager: ObservableObject {
    @Published private(set) var status = "Choose an image and one or more folders."

    func applyCustomIcon() {
        let imagePicker = NSOpenPanel()
        imagePicker.title = "Choose a folder icon image"
        imagePicker.allowedContentTypes = [.png, .jpeg, .tiff, .icns]
        imagePicker.allowsMultipleSelection = false
        guard imagePicker.runModal() == .OK, let imageURL = imagePicker.url,
              let image = NSImage(contentsOf: imageURL) else {
            status = "No icon image selected."
            return
        }

        let folderPicker = NSOpenPanel()
        folderPicker.title = "Choose folders to customise"
        folderPicker.prompt = "Apply Icon"
        folderPicker.canChooseFiles = false
        folderPicker.canChooseDirectories = true
        folderPicker.allowsMultipleSelection = true
        guard folderPicker.runModal() == .OK, !folderPicker.urls.isEmpty else {
            status = "No folders selected."
            return
        }

        let failures = folderPicker.urls.filter {
            !NSWorkspace.shared.setIcon(image, forFile: $0.path, options: [])
        }
        let applied = folderPicker.urls.count - failures.count
        status = failures.isEmpty
            ? "Applied the icon to \(applied) folder(s)."
            : "Applied to \(applied); macOS rejected \(failures.count)."
    }

    func restoreDefaultIcons() {
        let folderPicker = NSOpenPanel()
        folderPicker.title = "Choose folders to restore"
        folderPicker.prompt = "Restore Icons"
        folderPicker.canChooseFiles = false
        folderPicker.canChooseDirectories = true
        folderPicker.allowsMultipleSelection = true
        guard folderPicker.runModal() == .OK, !folderPicker.urls.isEmpty else { return }

        let failures = folderPicker.urls.filter {
            !NSWorkspace.shared.setIcon(nil, forFile: $0.path, options: [])
        }
        let restored = folderPicker.urls.count - failures.count
        status = failures.isEmpty
            ? "Restored \(restored) folder icon(s)."
            : "Restored \(restored); macOS rejected \(failures.count)."
    }
}

struct FolderIconSection: View {
    @StateObject private var manager = FolderIconManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundStyle(Color.accentColor)
                Text("DESKTOP ICONS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                Spacer()
            }
            HStack(spacing: 9) {
                Button("Apply folder icon…") { manager.applyCustomIcon() }
                    .buttonStyle(.borderedProminent)
                Button("Restore originals…") { manager.restoreDefaultIcons() }
                    .buttonStyle(.bordered)
            }
            HStack(spacing: 9) {
                Button("Show macOS Desktop Icons") { FinderDesktopVisibility.setHidden(false) }
                    .buttonStyle(.bordered)
                Button("Hide macOS Desktop Icons") { FinderDesktopVisibility.setHidden(true) }
                    .buttonStyle(.bordered)
            }
            Text(manager.status)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("Applies to folders you select. macOS does not provide a supported way to replace every protected app and file icon globally.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}
