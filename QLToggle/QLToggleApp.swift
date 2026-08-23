import SwiftUI
import ServiceManagement

@main
struct QLToggleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let previewerID = "com.local.PreviewMarkdown.Previewer"
    private let thumbnailerID = "com.local.PreviewMarkdown.Thumbnailer"

    /// Transient error surfaced in the menu (e.g. SMAppService failures).
    private var menuError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    // MARK: - Process helpers

    private func run(_ path: String, _ args: [String]) -> String {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return ""
        }
        // Read to EOF before waiting: safe for any output size
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - pluginkit state (re-queried on every menu open)

    /// pluginkit -m lines look like `+    com.local.PreviewMarkdown.Previewer(2.4.3)`
    /// where the leading marker is `+` (active) or `-` (ignored).
    private func extensionEnabled(_ bundleID: String, in listing: String) -> Bool {
        for rawLine in listing.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("+") || line.hasPrefix("-") else { continue }
            let rest = line.dropFirst().trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix(bundleID) {
                return line.hasPrefix("+")
            }
        }
        return false
    }

    private var previewerEnabled: Bool {
        let listing = run("/usr/bin/pluginkit", ["-m", "-p", "com.apple.quicklook.preview"])
        return extensionEnabled(previewerID, in: listing)
    }

    /// The Thumbnailer does not appear under `-p com.apple.quicklook.thumbnail`,
    /// so query the full listing for it.
    private var thumbnailerEnabled: Bool {
        let listing = run("/usr/bin/pluginkit", ["-m"])
        return extensionEnabled(thumbnailerID, in: listing)
    }

    // MARK: - Menu (rebuilt from live state whenever it opens)

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        let previewOn = previewerEnabled
        let thumbOn = thumbnailerEnabled
        let enabled = previewOn || thumbOn

        if let button = statusItem.button {
            let symbolName = enabled ? "text.document.fill" : "text.document"
            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "QL Markdown Toggle") {
                img.isTemplate = true
                button.image = img
            }
            button.toolTip = enabled ? "Markdown QL: Rendered" : "Markdown QL: Plain text"
        }

        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        func disabled(_ title: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        func action(_ title: String, _ sel: Selector, _ key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            item.target = self
            return item
        }

        if let err = menuError {
            menu.addItem(disabled("⚠︎ \(err)"))
            menu.addItem(.separator())
            menuError = nil
        }

        // Per-extension status lines (display only)
        menu.addItem(disabled("Previewer: \(previewOn ? "✓ active" : "✗ ignored")"))
        menu.addItem(disabled("Thumbnailer: \(thumbOn ? "✓ active" : "✗ ignored")"))
        menu.addItem(.separator())

        menu.addItem(action(enabled ? "Switch to Plain Text" : "Switch to Rendered",
                            #selector(didTapToggle), "t"))
        menu.addItem(action("PreviewMarkdown Settings…", #selector(didTapSettings), ","))
        menu.addItem(.separator())
        menu.addItem(action("Launch at Login: \(loginItemEnabled ? "✓" : "✗")", #selector(didTapLoginItem)))
        menu.addItem(action("Restart Quick Look", #selector(didTapRestartQL)))
        menu.addItem(.separator())
        menu.addItem(action("Quit", #selector(didTapQuit), "q"))
    }

    // MARK: - Actions

    /// Single toggle: acts on both extensions together, direction from the
    /// Previewer's current state.
    @objc private func didTapToggle() {
        let enable = !previewerEnabled
        let act = enable ? "use" : "ignore"
        _ = run("/usr/bin/pluginkit", ["-e", act, "-i", previewerID])
        _ = run("/usr/bin/pluginkit", ["-e", act, "-i", thumbnailerID])
        rebuildMenu()
    }

    /// Open the host app by bundle ID — no paths, works from any account.
    @objc private func didTapSettings() {
        _ = run("/usr/bin/open", ["-b", "com.local.PreviewMarkdown"])
    }

    @objc private func didTapLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            menuError = "Login item: \(error.localizedDescription)"
        }
        rebuildMenu()
    }

    private var loginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func didTapRestartQL() {
        _ = run("/usr/bin/qlmanage", ["-r"])
        _ = run("/usr/bin/qlmanage", ["-r", "cache"])
        menuError = "Quick Look restarted"
        rebuildMenu()
    }

    @objc private func didTapQuit() { NSApp.terminate(nil) }
}
