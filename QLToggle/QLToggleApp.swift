import SwiftUI

@main
struct QLToggleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var isEnabled = true
    private let bundleID = "com.local.PreviewMarkdown.Previewer"
    private let thumbBundleID = "com.local.PreviewMarkdown.Thumbnailer"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        isEnabled = checkEnabled()
        updateIcon()
        buildMenu()
    }

    private func checkEnabled() -> Bool {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        proc.arguments = ["-m", "-p", "com.apple.quicklook.preview"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains(bundleID)
    }

    private func toggle() {
        let action = isEnabled ? "ignore" : "use"
        pluginkit(action, bundleID)
        pluginkit(action, thumbBundleID)
        isEnabled.toggle()
        updateIcon()
        buildMenu()
    }

    private func pluginkit(_ action: String, _ identifier: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        proc.arguments = ["-e", action, "-i", identifier]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbolName = isEnabled ? "text.document.fill" : "text.document"
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "QL Markdown Toggle") {
            img.isTemplate = true
            button.image = img
        }
        button.toolTip = isEnabled ? "Markdown QL: Rendered" : "Markdown QL: Plain text"
    }

    private func buildMenu() {
        let menu = NSMenu()

        let stateTitle = isEnabled ? "✓ Rendered Markdown" : "✓ Plain Text"
        let stateItem = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        menu.addItem(.separator())

        let toggleTitle = isEnabled ? "Switch to Plain Text" : "Switch to Rendered"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(didTapToggle), keyEquivalent: "t")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let settingsItem = NSMenuItem(title: "PreviewMarkdown Settings…", action: #selector(didTapSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(didTapQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func didTapToggle() { toggle() }
    @objc private func didTapSettings() { NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/ruslan/Applications/PreviewMarkdown.app")) }
    @objc private func didTapQuit() { NSApp.terminate(nil) }
}
