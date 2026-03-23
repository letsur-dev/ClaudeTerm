import AppKit

private struct TmuxSession {
    let name: String
    let path: String
}

private enum WorkspaceSessionResolver {
    static func resolveSessionName(for path: String, sessions: [TmuxSession]) -> String {
        if let existing = sessions.first(where: { $0.path == path }) {
            return existing.name
        }
        return generatedSessionName(for: path)
    }

    private static func generatedSessionName(for path: String) -> String {
        let base = URL(fileURLWithPath: path).lastPathComponent
        let slug = sanitize(base.isEmpty ? "workspace" : base)
        let hash = stableHash(path)
        return "claudeterm-\(slug)-\(hash)"
    }

    private static func sanitize(_ value: String) -> String {
        let lowered = value.lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(scalars).replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(24).description
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowControllers: [WorkspaceWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenuBar()
        NSApp.activate(ignoringOtherApps: true)

        let args = CommandLine.arguments
        if args.count > 1 {
            let candidate = NSString(string: args[1]).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory), isDirectory.boolValue {
                openWorkspace(path: candidate)
                return
            }
        }

        showSessionPicker()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func openWorkspace(path: String, sessionName: String? = nil) {
        let resolvedSession = sessionName ?? WorkspaceSessionResolver.resolveSessionName(for: path, sessions: listTmuxSessions())
        let controller = WorkspaceWindowController(workspacePath: path, tmuxSessionName: resolvedSession)
        windowControllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func newWorkspaceTapped() {
        showSessionPicker()
    }

    @objc private func openFolderTapped() {
        showOpenFolderPanel(thenOpenWorkspace: true)
    }

    private func buildMenuBar() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ClaudeTerm", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ClaudeTerm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Workspace", action: #selector(newWorkspaceTapped), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open Folder…", action: #selector(openFolderTapped), keyEquivalent: "o")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    private func showSessionPicker() {
        let sessions = listTmuxSessions()
        guard !sessions.isEmpty else {
            showOpenFolderPanel(thenOpenWorkspace: true)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Open Workspace"
        alert.informativeText = "Select a tmux session or choose a folder."
        alert.addButton(withTitle: "Open Session")
        alert.addButton(withTitle: "Choose Folder…")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 28), pullsDown: false)
        for session in sessions {
            popup.addItem(withTitle: "\(session.name)  •  \(session.path)")
        }
        popup.selectItem(at: 0)
        alert.accessoryView = popup

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let selected = sessions[max(0, popup.indexOfSelectedItem)]
            openWorkspace(path: selected.path, sessionName: selected.name)
        case .alertSecondButtonReturn:
            showOpenFolderPanel(thenOpenWorkspace: true)
        default:
            break
        }
    }

    private func showOpenFolderPanel(thenOpenWorkspace: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if thenOpenWorkspace {
            openWorkspace(path: url.path)
        }
    }

    private static let tmuxCandidates = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/usr/bin/tmux",
    ]

    private func resolveTmuxPath() -> String? {
        Self.tmuxCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private func listTmuxSessions() -> [TmuxSession] {
        guard let tmux = resolveTmuxPath(),
              let raw = runCommand(tmux, ["list-sessions", "-F", "#{session_name}"]) else {
            return []
        }

        return raw
            .split(separator: "\n")
            .compactMap { line in
                let name = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, let path = tmuxPath(for: name) else { return nil }
                return TmuxSession(name: name, path: path)
            }
    }

    private func tmuxPath(for session: String) -> String? {
        guard let tmux = resolveTmuxPath(),
              let raw = runCommand(tmux, ["display-message", "-p", "-t", "\(session):0.0", "#{pane_current_path}"]) else {
            return nil
        }
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return path
    }

    private func runCommand(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

@MainActor
final class WorkspaceWindowController: NSWindowController {
    private let workspacePath: String
    private let tmuxSessionName: String
    private let workspaceView: WorkspaceView

    init(workspacePath: String, tmuxSessionName: String) {
        self.workspacePath = workspacePath
        self.tmuxSessionName = tmuxSessionName

        let name = URL(fileURLWithPath: workspacePath).lastPathComponent
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = name.isEmpty ? workspacePath : name
        window.backgroundColor = NSColor(calibratedRed: 0.067, green: 0.067, blue: 0.075, alpha: 1)
        window.minSize = NSSize(width: 800, height: 560)
        window.isRestorable = false
        window.collectionBehavior.insert(.moveToActiveSpace)

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let originX = visible.minX + (visible.width - 1200) / 2
            let originY = visible.minY + (visible.height - 800) / 2
            window.setFrame(NSRect(x: originX, y: originY, width: 1200, height: 800), display: false)
        }

        workspaceView = WorkspaceView(
            frame: window.contentView?.bounds ?? .zero,
            workspacePath: workspacePath,
            tmuxSessionName: tmuxSessionName
        )
        workspaceView.autoresizingMask = [.width, .height]
        window.contentView = workspaceView

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
