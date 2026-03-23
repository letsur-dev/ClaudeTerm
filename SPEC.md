# ClaudeTerm Spec

> SwiftTerm 터미널 에뮬레이터 + 네이티브 NSTextView composer. Claude CLI를 PTY로 실행하고 한글 IME 완벽 지원.

---

## 1. 프로젝트 구조

```
ClaudeTerm/
├── Package.swift
├── AGENTS.md
├── SPEC.md
└── Sources/ClaudeTerm/
    ├── main.swift
    └── WorkspaceView.swift
```

---

## 2. Package.swift

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeTerm",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeTerm", targets: ["ClaudeTerm"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeTerm",
            dependencies: ["SwiftTerm"],
            path: "Sources/ClaudeTerm"
        ),
    ]
)
```

---

## 3. main.swift

### 3.1 AppDelegate

CCT의 `macos.swift`에서 복사. 변경점:
- `ClaudeWorkspaceView` → `WorkspaceView` (새 클래스)
- 메뉴 타이틀 "Claude Code" → "ClaudeTerm"

```swift
import AppKit

@MainActor
@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [WorkspaceWindowController] = []
    private static var retainedDelegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenuBar()
        NSApp.activate(ignoringOtherApps: true)

        let args = CommandLine.arguments
        if args.count > 1 {
            var isDir: ObjCBool = false
            let path = args[1]
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                openWorkspace(path: path)
                return
            }
        }
        showSessionPicker()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
```

#### buildMenuBar

CCT와 동일. Edit 메뉴 필수 (Cmd+C/V/A 라우팅에 필요).

```swift
    private func buildMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ClaudeTerm", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ClaudeTerm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // File menu
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Workspace", action: #selector(newWorkspaceTapped), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open Folder…", action: #selector(openFolderTapped), keyEquivalent: "o")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // Edit menu — Cmd+C/V/A 라우팅에 필수
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut",        action: #selector(NSText.cut(_:)),       keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",       action: #selector(NSText.copy(_:)),      keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",      action: #selector(NSText.paste(_:)),     keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // Window menu
        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        winItem.submenu = winMenu
        mainMenu.addItem(winItem)

        NSApp.mainMenu = mainMenu
    }
```

#### Window Management

CCT와 동일.

```swift
    func openWorkspace(path: String) {
        let wc = WorkspaceWindowController(workspacePath: path)
        windowControllers.append(wc)
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func newWorkspaceTapped() { showSessionPicker() }
    @objc private func openFolderTapped() { showOpenFolderPanel(thenOpenWorkspace: true) }

    func showSessionPicker() {
        let sessions = listTmuxSessions()
        if sessions.isEmpty { showOpenFolderPanel(thenOpenWorkspace: true); return }
        showTmuxPicker(sessions: sessions)
    }
```

#### Tmux Session Picker

CCT `listTmuxSessions()`, `showTmuxPicker(sessions:)`, `showOpenFolderPanel(thenOpenWorkspace:)` 그대로 복사.
PickerRow 클래스도 동일.

### 3.2 WorkspaceWindowController

CCT와 동일하되 `ClaudeWorkspaceView` → `WorkspaceView`.

```swift
@MainActor
final class WorkspaceWindowController: NSWindowController {

    private let workspacePath: String
    private var workspaceView: WorkspaceView!

    init(workspacePath: String) {
        self.workspacePath = workspacePath

        let name = URL(fileURLWithPath: workspacePath).lastPathComponent
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = name
        window.backgroundColor = NSColor(calibratedRed: 0.067, green: 0.067, blue: 0.075, alpha: 1)
        window.minSize = NSSize(width: 800, height: 560)
        window.isRestorable = false
        window.collectionBehavior.insert(.moveToActiveSpace)

        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let wx = sf.minX + (sf.width  - 1200) / 2
            let wy = sf.minY + (sf.height - 800)  / 2
            window.setFrame(NSRect(x: wx, y: wy, width: 1200, height: 800), display: false)
        }

        super.init(window: window)

        workspaceView = WorkspaceView(frame: window.contentView!.bounds, workspacePath: workspacePath)
        workspaceView.autoresizingMask = [.width, .height]
        window.contentView = workspaceView
    }

    required init?(coder: NSCoder) { fatalError() }
}
```

---

## 4. WorkspaceView.swift

### 4.1 Design Tokens

CCT에서 복사. 동일.

```swift
import AppKit
import SwiftTerm

private enum C {
    static let bg          = NSColor(hex: "#111113")!
    static let sidebar     = NSColor(hex: "#141416")!
    static let border      = NSColor(hex: "#262628")!
    static let inputBg     = NSColor(hex: "#1c1c1f")!
    static let inputBorder = NSColor(hex: "#2e2e32")!
    static let text        = NSColor(hex: "#d4d4dc")!
    static let textDim     = NSColor(hex: "#606068")!
    static let textBright  = NSColor(hex: "#ececf4")!
    static let accent      = NSColor(hex: "#8b7cf8")!
    static let red         = NSColor(hex: "#f87171")!
    static let green       = NSColor(hex: "#34d399")!

    static let sidebarW: CGFloat  = 220
    static let statusH: CGFloat   = 26
    static let inputMinH: CGFloat = 44
    static let inputMaxH: CGFloat = 160
    static let radius: CGFloat    = 10
}
```

### 4.2 FileNode

CCT에서 복사. 동일.

```swift
private final class FileNode {
    let url: URL
    var children: [FileNode]?
    var isDirectory: Bool { (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    var name: String { url.lastPathComponent }
    init(_ url: URL) { self.url = url }

    func loadChildren() {
        guard isDirectory, children == nil else { return }
        children = ((try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? [])
        .filter { !$0.lastPathComponent.hasPrefix(".") }
        .sorted {
            let ad = (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let bd = (try? $1.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return ad != bd ? ad : $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
        .map { FileNode($0) }
    }
}
```

### 4.3 ComposerView

CCT에서 복사하되 MVP 범위에 맞게 축소.
포함: 텍스트 입력, IME composition, Enter 제출, 높이 자동 조정.
제외: 이미지 attachment/badge 삽입, 별도 업로드 플로우.

```swift
private final class ComposerView: NSTextView {
    var onSubmit: (() -> Void)?
    var onHeightChange: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        // Enter (Shift 없이, 조합 중 아닐 때) → 전송
        if isReturn && !event.modifierFlags.contains(.shift) && !hasMarkedText() {
            onSubmit?(); return
        }
        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        onHeightChange?()
    }

}
```

> 이미지 파일 붙여넣기는 MVP에서 별도 처리하지 않는다. 기본 paste 동작에 맡기며, Claude CLI의 네이티브 이미지 입력 UX는 후속 범위다.

### 4.4 Input Routing

SwiftTerm의 `LocalProcessTerminalView`를 직접 사용한다.
macOS용 `keyDown` 오버라이드는 외부 모듈에서 열려 있지 않으므로, 입력 라우팅은 두 단계로 처리한다.

- 기본 포커스는 `ComposerView`에 둔다.
- `ComposerView.onTerminalKey`로 Ctrl/Option/Esc 같은 제어 키를 터미널에 직접 전달한다.
- 사용자가 터미널을 클릭한 뒤 일반 텍스트를 입력하면 `NSEvent.addLocalMonitorForEvents`로 가로채 composer로 되돌린다.

```swift
private func forwardTerminalKeyIfNeeded(_ event: NSEvent) -> Bool {
    guard shouldHandleInTerminal(event) else { return false }
    terminalView.keyDown(with: event)
    return true
}

private func installKeyMonitorIfNeeded() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
        guard let self,
              let window = self.window,
              window.firstResponder === self.terminalView,
              self.shouldRedirectTerminalText(event) else {
            return event
        }

        window.makeFirstResponder(self.composer)
        self.composer?.keyDown(with: event)
        return nil
    }
}
```

### 4.5 WorkspaceView (메인 뷰)

#### 프로퍼티

```swift
@MainActor
final class WorkspaceView: NSView {

    var workspacePath: String { didSet { refreshTree(); pathLabel?.stringValue = shortPath } }

    // Layout refs
    private var terminalView: LocalProcessTerminalView!
    private weak var composer: ComposerView!
    private weak var composerHeightConstraint: NSLayoutConstraint!
    private weak var statusDot: NSView!
    private weak var statusLabel: NSTextField!
    private weak var pathLabel: NSTextField!
    private weak var outlineView: NSOutlineView!
    private var rootNode: FileNode?
    private var isProcessRunning = false
    private var keyMonitor: Any?
```

#### init

```swift
    init(frame: NSRect, workspacePath: String) {
        self.workspacePath = workspacePath
        super.init(frame: frame)
        buildUI()
        refreshTree()
        launchClaude()
    }
    required init?(coder: NSCoder) { fatalError() }
```

#### buildUI

레이아웃: `sidebar(220px) | divider(1px) | mainArea | statusBar(26px)`

mainArea 내부: `terminalView | composerArea`

```swift
    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = C.bg.cgColor

        let sidebar   = makeSidebar()    // CCT에서 복사 — FileNode + NSOutlineView
        let divider   = makeDivider()
        let mainArea  = makeMainArea()   // 터미널 + composer
        let statusBar = makeStatusBar()  // 경로 + 상태 dot

        [sidebar, divider, mainArea, statusBar].forEach { addSubview($0) }

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: C.sidebarW),

            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            mainArea.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            mainArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainArea.topAnchor.constraint(equalTo: topAnchor),
            mainArea.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: C.statusH),
        ])
    }
```

#### makeMainArea (터미널 + composer)

CCT의 `makeMainArea()`에서 `ConversationView`를 `LocalProcessTerminalView`로 교체. 세션 헤더 제거.

```swift
    private func makeMainArea() -> NSView {
        let v = tinted(C.bg)

        // SwiftTerm 터미널 뷰
        let tv = LocalProcessTerminalView(frame: .zero)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.getTerminal().backgroundColor = .init(red: 0x11, green: 0x11, blue: 0x13)
        tv.getTerminal().foregroundColor = .init(red: 0xd4, green: 0xd4, blue: 0xdc)
        // 폰트 설정
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        v.addSubview(tv)
        terminalView = tv

        let composerArea = makeComposerArea()
        v.addSubview(composerArea)

        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            tv.topAnchor.constraint(equalTo: v.topAnchor),
            tv.bottomAnchor.constraint(equalTo: composerArea.topAnchor),

            composerArea.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            composerArea.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            composerArea.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        return v
    }
```

#### makeComposerArea

CCT에서 복사. 제거: permission mode 버튼, slash 메뉴 버튼, 이미지 badge, stop 버튼.
유지: 텍스트 입력, send 버튼, placeholder.

```swift
    private func makeComposerArea() -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = C.bg.cgColor

        let topLine = makeDivider()
        wrapper.addSubview(topLine)

        let box = tinted(C.inputBg)
        box.layer?.cornerRadius = C.radius
        box.layer?.borderWidth  = 1
        box.layer?.borderColor  = C.inputBorder.cgColor
        wrapper.addSubview(box)

        let tv = ComposerView(frame: .zero)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.font = .systemFont(ofSize: 14)
        tv.textColor = C.textBright
        tv.insertionPointColor = C.accent
        tv.drawsBackground = false
        tv.isRichText = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.textContainerInset = NSSize(width: 4, height: 0)
        if let tc = tv.textContainer { tc.lineFragmentPadding = 0; tc.widthTracksTextView = true }
        tv.onSubmit = { [weak self] in self?.submit() }
        box.addSubview(tv)
        composer = tv

        let ph = label("Message Claude…", size: 14, color: C.textDim)
        ph.isEnabled = false
        box.addSubview(ph)

        tv.onHeightChange = { [weak self, weak ph, weak tv] in
            ph?.isHidden = !(tv?.string.isEmpty ?? true)
            self?.updateComposerHeight()
        }

        // Send 버튼
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let sendBg = roundBtn(color: C.accent)
        box.addSubview(sendBg)

        let btn = NSButton(title: "", target: self, action: #selector(sendTapped))
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
        btn.contentTintColor = .white
        box.addSubview(btn)

        let hc = box.heightAnchor.constraint(equalToConstant: C.inputMinH)
        hc.priority = .defaultHigh
        hc.isActive = true
        composerHeightConstraint = hc

        NSLayoutConstraint.activate([
            topLine.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            topLine.topAnchor.constraint(equalTo: wrapper.topAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 1),

            box.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            box.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            box.topAnchor.constraint(equalTo: topLine.bottomAnchor, constant: 12),
            box.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -12),

            tv.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            tv.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -40),
            tv.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            tv.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),

            ph.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            ph.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),

            sendBg.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            sendBg.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
            sendBg.widthAnchor.constraint(equalToConstant: 26),
            sendBg.heightAnchor.constraint(equalToConstant: 26),

            btn.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            btn.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
            btn.widthAnchor.constraint(equalToConstant: 26),
            btn.heightAnchor.constraint(equalToConstant: 26),
        ])
        return wrapper
    }
```

#### launchClaude — Claude CLI를 PTY로 실행

```swift
    private func launchClaude() {
        // 환경변수 구성
        var env: [String] = []
        for (k, v) in ProcessInfo.processInfo.environment {
            // 중첩 실행 방지: CLAUDECODE, CLAUDE_CODE_ENTRYPOINT 제거
            if k == "CLAUDECODE" || k == "CLAUDE_CODE_ENTRYPOINT" { continue }
            env.append("\(k)=\(v)")
        }
        // TERM 설정
        env.removeAll { $0.hasPrefix("TERM=") }
        env.append("TERM=xterm-256color")
        // PATH 보강 (GUI 앱에서 node/claude 찾기 위함)
        if !env.contains(where: { $0.contains("/opt/homebrew/bin") }) {
            if let idx = env.firstIndex(where: { $0.hasPrefix("PATH=") }) {
                env[idx] = env[idx] + ":/opt/homebrew/bin:/usr/local/bin"
            }
        }

        // Claude CLI 실행 정보 해석
        let launch = resolveClaudeLaunch()

        terminalView.startProcess(
            executable: launch.executable,
            args: launch.args,
            environment: env,
            execName: nil
        )
        isProcessRunning = true
        updateStatus()

        // 프로세스 종료 감지
        terminalView.processDelegate = self  // TerminalViewDelegate에서 처리
    }

    private struct LaunchSpec {
        let executable: String
        let args: [String]
    }

    private func resolveClaudeLaunch() -> LaunchSpec {
        // 일반적인 설치 경로들
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            NSHomeDirectory() + "/.npm-global/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return LaunchSpec(executable: path, args: [])
            }
        }
        // fallback: PATH에서 claude 탐색
        return LaunchSpec(executable: "/usr/bin/env", args: ["claude"])
    }
```

#### submit — Composer 텍스트를 PTY stdin으로 전달

```swift
    private func submit() {
        guard let tv = composer else { return }
        let text = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        tv.string = ""
        updateComposerHeight()

        // PTY stdin으로 전달 (텍스트 + 줄바꿈)
        let data = Array((text + "\n").utf8)
        terminalView.send(data)
    }

    @objc private func sendTapped() { submit() }
```

#### 프로세스 종료 처리

```swift
    // LocalProcessTerminalView의 프로세스 종료 콜백
    func processTerminated(_ source: TerminalView, exitCode: Int32?) {
        isProcessRunning = false
        updateStatus()
        statusLabel?.stringValue = "Exited (\(exitCode ?? -1))"
        statusDot?.layer?.backgroundColor = C.red.cgColor
    }
```

MVP에서는 자동 재시작 UI를 제공하지 않는다. 종료 상태만 보여주고, 재실행은 새 워크스페이스를 열어 처리한다.

#### makeSidebar

CCT에서 그대로 복사: `makeSidebar()`, `sidebarHeader()`, 파일 트리 OutlineView, `refreshTree()`, `ovClicked()`.

`ovClicked()`에서 파일 클릭 시 `@filepath`를 composer에 삽입하는 동작도 동일.

```swift
    // CCT와 동일
    @objc private func ovClicked() {
        guard let item = outlineView?.item(atRow: outlineView?.clickedRow ?? -1) as? FileNode else { return }
        if item.isDirectory {
            if outlineView?.isItemExpanded(item) == true { outlineView?.collapseItem(item) }
            else { outlineView?.expandItem(item) }
        } else {
            let rel = item.url.path.replacingOccurrences(of: workspacePath + "/", with: "")
            let current = composer?.string ?? ""
            composer?.string = current.isEmpty ? "@\(rel) " : current + " @\(rel) "
            updateComposerHeight()
            window?.makeFirstResponder(composer)
        }
    }
```

#### makeStatusBar

CCT에서 복사. 단순화: cooking indicator 제거, spinner 제거. dot + label + path + brand만 유지.

```swift
    private func makeStatusBar() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(hex: "#0d0d0f")?.cgColor

        let topLine = makeDivider()
        v.addSubview(topLine)

        let dot = NSView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = C.green.cgColor
        v.addSubview(dot)
        statusDot = dot

        let sl = label("Running", size: 10, weight: .medium, color: C.textDim)
        v.addSubview(sl)
        statusLabel = sl

        let pl = label(shortPath, size: 10, color: NSColor(hex: "#404048")!)
        pl.lineBreakMode = .byTruncatingHead
        v.addSubview(pl)
        pathLabel = pl

        let brand = label("✦ ClaudeTerm", size: 10, weight: .medium, color: NSColor(hex: "#505060")!)
        v.addSubview(brand)

        NSLayoutConstraint.activate([
            topLine.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            topLine.topAnchor.constraint(equalTo: v.topAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 1),

            dot.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),

            sl.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            sl.centerYAnchor.constraint(equalTo: v.centerYAnchor),

            pl.leadingAnchor.constraint(equalTo: sl.trailingAnchor, constant: 8),
            pl.centerYAnchor.constraint(equalTo: v.centerYAnchor),

            brand.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            brand.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    private func updateStatus() {
        statusDot?.layer?.backgroundColor = (isProcessRunning ? C.green : C.red).cgColor
        statusLabel?.stringValue = isProcessRunning ? "Running" : "Stopped"
    }
```

#### Composer Height

CCT와 동일.

```swift
    private func updateComposerHeight() {
        guard let tv = composer,
              let lm = tv.layoutManager,
              let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let textH = lm.usedRect(for: tc).height
        let newH = max(C.inputMinH, min(C.inputMaxH, ceil(textH + 26)))
        if abs((composerHeightConstraint?.constant ?? 0) - newH) > 1 {
            composerHeightConstraint?.constant = newH
        }
    }
```

#### Focus

```swift
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.composer)
        }
    }
```

#### Helpers

CCT와 동일: `shortPath`, `tinted(_:)`, `makeDivider()`, `roundBtn(color:)`, `label(_:size:weight:color:)`, `iconButton(symbol:target:action:)`.

### 4.6 OutlineView DataSource/Delegate

CCT에서 복사. `ClaudeWorkspaceView` → `WorkspaceView`로 이름만 변경.

```swift
extension WorkspaceView: NSOutlineViewDataSource {
    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return rootNode?.children?.count ?? 0 }
        let n = item as! FileNode
        if n.isDirectory && n.children == nil { n.loadChildren() }
        return n.children?.count ?? 0
    }
    func outlineView(_ ov: NSOutlineView, child i: Int, ofItem item: Any?) -> Any {
        item == nil ? rootNode!.children![i] : (item as! FileNode).children![i]
    }
    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as! FileNode).isDirectory
    }
}

extension WorkspaceView: NSOutlineViewDelegate {
    func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let node = item as! FileNode
        let cell = FileCell()
        cell.configure(node)
        return cell
    }
    func outlineView(_ ov: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        FileRowView()
    }
}
```

### 4.7 FileCell, FileRowView

CCT에서 복사. 동일.

### 4.8 NSColor(hex:) Extension

CCT에서 복사. 동일.

```swift
extension NSColor {
    convenience init?(hex: String) {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 6 { s += "ff" }
        guard s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        self.init(calibratedRed: CGFloat((v>>24)&0xff)/255,
                  green: CGFloat((v>>16)&0xff)/255,
                  blue:  CGFloat((v>>8)&0xff)/255,
                  alpha: CGFloat(v&0xff)/255)
    }
}
```

---

## 5. CCT 코드 재사용 맵

| CCT 소스 | 재사용 대상 | 범위 |
|---------|-----------|------|
| `macos.swift` — AppDelegate | `main.swift` | 전체 복사 (타이틀만 변경) |
| `macos.swift` — PickerRow | `main.swift` | 전체 복사 |
| `macos.swift` — WorkspaceWindowController | `main.swift` | 복사 후 `ClaudeWorkspaceView` → `WorkspaceView` |
| `ClaudeWorkspaceView.swift` — enum C | `WorkspaceView.swift` | 전체 복사 |
| `ClaudeWorkspaceView.swift` — FileNode | `WorkspaceView.swift` | 전체 복사 |
| `ClaudeWorkspaceView.swift` — ComposerView | `WorkspaceView.swift` | 복사, 이미지 attachment 기능 제거 |
| `ClaudeWorkspaceView.swift` — makeSidebar | `WorkspaceView.swift` | 전체 복사 |
| `ClaudeWorkspaceView.swift` — makeStatusBar | `WorkspaceView.swift` | 복사, cooking indicator 제거 |
| `ClaudeWorkspaceView.swift` — Helpers | `WorkspaceView.swift` | 전체 복사 |
| `ClaudeWorkspaceView.swift` — OutlineView ext | `WorkspaceView.swift` | 복사 후 타입명 변경 |
| `ClaudeWorkspaceView.swift` — FileCell/FileRowView | `WorkspaceView.swift` | 전체 복사 |
| `ClaudeWorkspaceView.swift` — NSColor(hex:) | `WorkspaceView.swift` | 전체 복사 |

### 사용하지 않는 CCT 소스

| 파일 | 이유 |
|------|------|
| `ClaudeService.swift` | PTY 직접 통신으로 대체 |
| `ConversationView.swift` | SwiftTerm이 렌더링 담당 |
| `ConversationWebView.swift` | 불필요 |
| `PermissionServer.swift` | CLI 자체 처리 |
| `TerminalBridge.h` | 불필요 |
| `TerminalGridView.swift` | SwiftTerm 대체 |
| `TerminalService.swift` | PTY 직접 통신으로 대체 |

---

## 6. 기능 요구사항 요약

| # | 기능 | 구현 위치 | 핵심 |
|---|------|----------|------|
| FR-1 | 한글 입력 | `ComposerView` | NSTextView IME composition. `hasMarkedText()` 체크 |
| FR-2 | CLI TUI 렌더링 | `LocalProcessTerminalView` | SwiftTerm 기본 터미널 렌더링. ANSI 색상, 커서 이동 |
| FR-3 | 입력 전달 | `submit()` | `terminalView.send(Array((text + "\n").utf8))` |
| FR-4 | 제어 키 전달 | `ComposerView.onTerminalKey` | Ctrl/Option/Esc 등 제어 키를 터미널로 직접 전달 |
| FR-5 | 파일 트리 | `makeSidebar()` | FileNode + NSOutlineView. 클릭 → `@filepath` 삽입 |
| FR-6 | 워크스페이스 선택 | `showSessionPicker()` | tmux 세션 목록 + 폴더 선택 |
| FR-7 | 프로세스 생명주기 | `processTerminated()` | 상태바 표시, 자동 재시작 없음 |
| FR-9 | 환경 설정 | `launchClaude()` | CLAUDECODE unset, PATH 보강, TERM=xterm-256color |
| FR-10 | 텍스트 선택/복사 | SwiftTerm 기본 | 마우스 드래그 선택, Cmd+C 복사 |
| FR-11 | 포커스 관리 | `installKeyMonitorIfNeeded()` | 터미널 포커스에서 일반 키는 composer로 복귀, 제어 키는 터미널 유지 |
| FR-13 | 스크롤 | SwiftTerm 기본 | 자동 스크롤 + 수동 스크롤 |

---

## 7. 리스크 & 검증

| 리스크 | 영향 | 대응 |
|-------|------|------|
| CLI PTY stdin 일괄 수신 | 입력 깨짐 가능 | 문자 단위 전송 폴백: `for byte in data { send([byte]) }` |
| 입력 에코 이중 표시 | composer + TUI 둘 다 표시 | CLI raw mode는 보통 echo off. 문제 시 composer 즉시 비움 |
| SwiftTerm React Ink 렌더링 | thinking/tool box 깨짐 | xterm-256color 호환이면 대부분 OK |
| PTY 크기 작음 | TUI 레이아웃 깨짐 | 최소 윈도우 800x560 (80열 이상) |

### 빌드 후 검증 체크리스트

1. `swift build` 성공
2. 앱 실행 → 세션 피커 표시 → 폴더 선택 → 윈도우 열림
3. 터미널 뷰에 Claude CLI TUI 표시
4. composer에서 한글 조합 정상 → Enter → Claude에 전달
5. composer에서 영문 입력 → Enter → Claude에 전달
6. Ctrl+C → Claude 응답 중단
7. 사이드바 파일 트리 표시, 클릭 → @filepath 삽입
8. Claude 종료 시 상태바에 표시
9. 앱 닫기 시 PTY 하위 프로세스 정리
10. 윈도우 크기 변경 시 TUI 레이아웃 재조정

### 종료 시 정리 정책

- `WorkspaceView`가 윈도우에서 분리되거나 해제될 때 실행 중인 PTY 프로세스를 종료한다.
- 앱 전체 종료 시에는 각 워크스페이스 뷰가 자신의 하위 프로세스를 정리한다.
- orphan `claude` 프로세스를 남기지 않는 것이 목표다.

---

## 8. SwiftTerm API 참고

### LocalProcessTerminalView 주요 API

```swift
// 프로세스 실행
func startProcess(executable: String, args: [String], environment: [String]?, execName: String?)

// 데이터 전송 (PTY stdin)
func send(_ data: [UInt8])
func send(txt: String)

// 터미널 설정
func getTerminal() -> Terminal
var font: NSFont { get set }

// 프로세스 종료 콜백
// LocalProcessTerminalViewDelegate 또는 TerminalViewDelegate로 수신
```

### 프로세스 종료 감지 방법

`LocalProcessTerminalView`는 프로세스 종료 시 delegate 콜백을 호출한다.
`processTerminated(_ source: TerminalView, exitCode: Int32?)` 메서드를 구현하면 된다.

---

## 9. 구현 순서 (Codex용)

1. `Package.swift` 생성
2. `Sources/ClaudeTerm/main.swift` — AppDelegate + PickerRow + WorkspaceWindowController
3. `Sources/ClaudeTerm/WorkspaceView.swift` — 전체 (이 파일이 핵심)
4. `swift build`로 컴파일 오류 해결
5. 빌드 성공 확인
