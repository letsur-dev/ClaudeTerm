import AppKit
import QuickLookUI
import SwiftTerm

private enum C {
    static let bg = NSColor(hex: "#111113")!
    static let sidebar = NSColor(hex: "#141416")!
    static let border = NSColor(hex: "#262628")!
    static let inputBg = NSColor(hex: "#1c1c1f")!
    static let inputBorder = NSColor(hex: "#2e2e32")!
    static let text = NSColor(hex: "#d4d4dc")!
    static let textDim = NSColor(hex: "#606068")!
    static let textBright = NSColor(hex: "#ececf4")!
    static let accent = NSColor(hex: "#8b7cf8")!
    static let red = NSColor(hex: "#f87171")!
    static let green = NSColor(hex: "#34d399")!
    static let sidebarWidth: CGFloat = 220
    static let statusHeight: CGFloat = 26
    static let inputMinHeight: CGFloat = 44
    static let inputMaxHeight: CGFloat = 160
    static let radius: CGFloat = 10
}

private final class FileNode {
    let url: URL
    var children: [FileNode]?

    init(_ url: URL) {
        self.url = url
    }

    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    var name: String {
        url.lastPathComponent
    }

    func loadChildren() {
        guard isDirectory, children == nil else { return }

        children = ((try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? [])
        .filter { !$0.lastPathComponent.hasPrefix(".") }
        .sorted { lhs, rhs in
            let lhsIsDirectory = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let rhsIsDirectory = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if lhsIsDirectory != rhsIsDirectory {
                return lhsIsDirectory && !rhsIsDirectory
            }
            return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }
        .map(FileNode.init)
    }
}

private final class ComposerView: NSTextView {
    var onSubmit: (() -> Void)?
    var onHeightChange: (() -> Void)?
    var onTerminalKey: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onTerminalKey?(event) == true {
            return
        }

        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, !event.modifierFlags.contains(.shift), !hasMarkedText() {
            onSubmit?()
            return
        }

        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        onHeightChange?()
    }
}

private enum TerminalFontResolver {
    static func preferredFont() -> NSFont? {
        if isRunning(bundleIdentifier: "com.apple.Terminal"), let font = terminalAppFont() {
            return font
        }
        if isRunning(bundleIdentifier: "com.googlecode.iterm2"), let font = iTermFont() {
            return font
        }
        return terminalAppFont() ?? iTermFont()
    }

    private static func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    private static func terminalAppFont() -> NSFont? {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Preferences/com.apple.Terminal.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let defaultProfile = plist["Default Window Settings"] as? String,
              let settings = plist["Window Settings"] as? [String: Any],
              let profile = settings[defaultProfile] as? [String: Any],
              let fontData = profile["Font"] as? Data,
              let font = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSFont.self, from: fontData) else {
            return nil
        }
        return font
    }

    private static func iTermFont() -> NSFont? {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Preferences/com.googlecode.iterm2.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bookmarks = plist["New Bookmarks"] as? [[String: Any]] else {
            return nil
        }

        let defaultGuid = plist["Default Bookmark Guid"] as? String
        let bookmark = bookmarks.first { ($0["Guid"] as? String) == defaultGuid } ?? bookmarks.first
        guard let normalFont = bookmark?["Normal Font"] as? String else {
            return nil
        }
        return parseITermFont(normalFont)
    }

    private static func parseITermFont(_ value: String) -> NSFont? {
        guard let split = value.lastIndex(of: " ") else { return nil }
        let name = String(value[..<split])
        let sizeText = String(value[value.index(after: split)...])
        guard let size = Double(sizeText) else { return nil }
        return NSFont(name: name, size: size)
    }
}

private final class InterceptingTerminalView: LocalProcessTerminalView {
    var shouldInterceptTextInput: (() -> Bool)?
    var onInterceptedTextInput: ((String) -> Void)?
    var onInterceptedMarkedText: ((Any, NSRange, NSRange) -> Void)?
    private var allowsProgrammaticTextInput = false

    func sendProgrammaticText(_ text: String) {
        allowsProgrammaticTextInput = true
        insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        allowsProgrammaticTextInput = false
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if !allowsProgrammaticTextInput,
           shouldInterceptTextInput?() == true,
           let text = normalizedText(from: string),
           !text.isEmpty {
            onInterceptedTextInput?(text)
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if !allowsProgrammaticTextInput,
           shouldInterceptTextInput?() == true {
            onInterceptedMarkedText?(string, selectedRange, replacementRange)
            return
        }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    override func copy(_ sender: Any) {
        guard selection.active else {
            super.copy(sender)
            return
        }

        let start = selection.start
        let end = selection.end
        let (minPos, maxPos) = SwiftTerm.Position.compare(start, end) == .before
            ? (start, end) : (end, start)

        var result = ""
        for row in minPos.row...maxPos.row {
            guard let bufferLine = terminal.getLine(row: row) else { continue }

            let startCol = row == minPos.row ? minPos.col : 0
            let endCol = row == maxPos.row ? maxPos.col : -1
            let text = bufferLine.translateToString(trimRight: true, startCol: startCol, endCol: endCol)

            result += text

            if row < maxPos.row, let nextLine = terminal.getLine(row: row + 1) {
                if !nextLine.isWrapped {
                    result += "\n"
                }
            }
        }

        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        clipboard.setString(result, forType: .string)
    }

    private func normalizedText(from value: Any) -> String? {
        if let text = value as? String {
            return text
        }
        if let text = value as? NSString {
            return text as String
        }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        return nil
    }
}

@MainActor
final class WorkspaceView: NSView {
    var workspacePath: String {
        didSet {
            pathLabel?.stringValue = shortPath
            sidebarTitleLabel?.stringValue = workspaceName
            refreshTree()
        }
    }

    private let tmuxSessionName: String
    private var terminalView: InterceptingTerminalView!
    private weak var composer: ComposerView?
    private weak var composerPlaceholder: NSTextField?
    private weak var composerHeightConstraint: NSLayoutConstraint?
    private weak var statusDot: NSView?
    private weak var statusLabel: NSTextField?
    private weak var pathLabel: NSTextField?
    private weak var helpLabel: NSTextField?
    private weak var outlineView: NSOutlineView?
    private weak var sidebarTitleLabel: NSTextField?
    private var rootNode: FileNode?
    private static let historyLimit = 500
    private static let historyTruncateThreshold = 200
    private var submissionHistory: [String] = []
    private var historyIndex: Int?
    private var historyDraft = ""
    private var isProcessRunning = false
    private var didTerminateProcess = false
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var mouseDownMonitor: Any?
    private var mouseDragMonitor: Any?
    private var mouseUpMonitor: Any?
    private var scrollMonitor: Any?
    private var isTrackingTerminalClick = false
    private var didDragInTerminal = false
    private var pendingComposerRestore: DispatchWorkItem?
    private var previewPopover: NSPopover?

    init(frame: NSRect, workspacePath: String, tmuxSessionName: String) {
        self.workspacePath = workspacePath
        self.tmuxSessionName = tmuxSessionName
        super.init(frame: frame)
        buildUI()
        refreshTree()
        launchClaude()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            previewPopover?.performClose(nil)
            removeEventMonitors()
            cleanupProcess()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installKeyMonitorIfNeeded()
        installFlagsMonitorIfNeeded()
        installMouseMonitorsIfNeeded()
        installScrollMonitorIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.composer)
        }
    }

    private var workspaceName: String {
        let name = URL(fileURLWithPath: workspacePath).lastPathComponent
        return name.isEmpty ? workspacePath : name
    }

    private var shortPath: String {
        let home = NSHomeDirectory()
        if workspacePath.hasPrefix(home) {
            return "~" + workspacePath.dropFirst(home.count)
        }
        return workspacePath
    }

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = C.bg.cgColor

        let sidebar = makeSidebar()
        let divider = makeDivider()
        let mainArea = makeMainArea()
        let statusBar = makeStatusBar()

        [sidebar, divider, mainArea, statusBar].forEach(addSubview(_:))

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: C.sidebarWidth),

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
            statusBar.heightAnchor.constraint(equalToConstant: C.statusHeight),
        ])
    }

    private func makeSidebar() -> NSView {
        let container = tinted(C.sidebar)

        let header = label(workspaceName, size: 12, weight: .semibold, color: C.textBright)
        header.lineBreakMode = .byTruncatingTail
        container.addSubview(header)
        sidebarTitleLabel = header

        let divider = makeDivider()
        container.addSubview(divider)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        container.addSubview(scrollView)

        let outline = NSOutlineView()
        outline.translatesAutoresizingMaskIntoConstraints = false
        outline.headerView = nil
        outline.rowSizeStyle = .default
        outline.rowHeight = 24
        outline.indentationPerLevel = 14
        outline.style = .sourceList
        outline.backgroundColor = .clear
        outline.focusRingType = .none
        outline.delegate = self
        outline.dataSource = self
        outline.target = self
        outline.action = #selector(ovClicked)
        outline.doubleAction = #selector(ovDoubleClicked)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("files"))
        column.isEditable = false
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        scrollView.documentView = outline
        outlineView = outline

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),

            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            divider.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            divider.heightAnchor.constraint(equalToConstant: 1),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func makeMainArea() -> NSView {
        let container = tinted(C.bg)

        let tv = InterceptingTerminalView(frame: .zero)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.nativeBackgroundColor = C.bg
        tv.nativeForegroundColor = C.text
        tv.font = resolvedTerminalFont()
        tv.allowMouseReporting = true
        tv.shouldInterceptTextInput = { [weak self] in
            self?.shouldInterceptTerminalTextInput() ?? false
        }
        tv.onInterceptedTextInput = { [weak self] text in
            self?.redirectTerminalTextInputToComposer(text)
        }
        tv.onInterceptedMarkedText = { [weak self] string, selectedRange, replacementRange in
            self?.redirectTerminalMarkedTextToComposer(string, selectedRange: selectedRange, replacementRange: replacementRange)
        }
        container.addSubview(tv)
        terminalView = tv

        let composerArea = makeComposerArea()
        container.addSubview(composerArea)

        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tv.topAnchor.constraint(equalTo: container.topAnchor),
            tv.bottomAnchor.constraint(equalTo: composerArea.topAnchor),

            composerArea.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            composerArea.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            composerArea.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func makeComposerArea() -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = C.bg.cgColor

        let topLine = makeDivider()
        wrapper.addSubview(topLine)

        let box = tinted(C.inputBg)
        box.layer?.cornerRadius = C.radius
        box.layer?.borderWidth = 1
        box.layer?.borderColor = C.inputBorder.cgColor
        wrapper.addSubview(box)

        let textView = ComposerView(frame: .zero)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = resolvedComposerFont()
        textView.textColor = C.textBright
        textView.insertionPointColor = C.accent
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 4, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.onSubmit = { [weak self] in
            self?.submit()
        }
        textView.onTerminalKey = { [weak self] event in
            self?.forwardTerminalKeyIfNeeded(event) ?? false
        }
        textView.onHeightChange = { [weak self, weak textView] in
            self?.composerPlaceholder?.isHidden = !(textView?.string.isEmpty ?? true)
            self?.updateComposerHeight()
        }
        box.addSubview(textView)
        composer = textView

        let placeholder = label("Message Claude…", size: 14, color: C.textDim)
        placeholder.isEnabled = false
        box.addSubview(placeholder)
        composerPlaceholder = placeholder

        let sendButton = NSButton(title: "", target: self, action: #selector(sendTapped))
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.isBordered = false
        sendButton.wantsLayer = true
        sendButton.layer?.cornerRadius = 13
        sendButton.layer?.backgroundColor = C.accent.cgColor
        sendButton.image = NSImage(
            systemSymbolName: "arrow.up",
            accessibilityDescription: "Send"
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        sendButton.contentTintColor = .white
        box.addSubview(sendButton)

        let heightConstraint = box.heightAnchor.constraint(equalToConstant: C.inputMinHeight)
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
        composerHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            topLine.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            topLine.topAnchor.constraint(equalTo: wrapper.topAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 1),

            box.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            box.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            box.topAnchor.constraint(equalTo: topLine.bottomAnchor, constant: 12),
            box.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -12),

            textView.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            textView.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -42),
            textView.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            textView.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),

            placeholder.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            placeholder.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),

            sendButton.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            sendButton.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 26),
            sendButton.heightAnchor.constraint(equalToConstant: 26),
        ])

        return wrapper
    }

    private func makeStatusBar() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(hex: "#0d0d0f")?.cgColor

        let topLine = makeDivider()
        container.addSubview(topLine)

        let dot = NSView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = C.green.cgColor
        container.addSubview(dot)
        statusDot = dot

        let status = label("Running", size: 10, weight: .medium, color: C.textDim)
        container.addSubview(status)
        statusLabel = status

        let path = label(shortPath, size: 10, color: NSColor(hex: "#404048")!)
        path.lineBreakMode = .byTruncatingHead
        container.addSubview(path)
        pathLabel = path

        let help = label(
            "Enter send  Shift+Enter newline  Up history  Ctrl+C stop  Option+Drag copy",
            size: 10,
            color: NSColor(hex: "#6b6b76")!
        )
        help.lineBreakMode = .byTruncatingTail
        container.addSubview(help)
        helpLabel = help

        let brand = label("ClaudeTerm", size: 10, weight: .medium, color: NSColor(hex: "#505060")!)
        container.addSubview(brand)

        NSLayoutConstraint.activate([
            topLine.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topLine.topAnchor.constraint(equalTo: container.topAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 1),

            dot.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),

            status.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            status.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            path.leadingAnchor.constraint(equalTo: status.trailingAnchor, constant: 8),
            path.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            help.leadingAnchor.constraint(equalTo: path.trailingAnchor, constant: 12),
            help.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            help.trailingAnchor.constraint(lessThanOrEqualTo: brand.leadingAnchor, constant: -12),

            brand.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            brand.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    @objc private func sendTapped() {
        submit()
    }

    @objc private func ovDoubleClicked() {
        guard let outlineView, outlineView.clickedRow >= 0,
              let item = outlineView.item(atRow: outlineView.clickedRow) as? FileNode,
              !item.isDirectory else {
            return
        }

        showPreview(for: item.url, from: outlineView, row: outlineView.clickedRow)
    }

    @objc private func ovClicked() {
        guard let outlineView, outlineView.clickedRow >= 0,
              let item = outlineView.item(atRow: outlineView.clickedRow) as? FileNode else {
            return
        }

        if item.isDirectory {
            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else {
                outlineView.expandItem(item)
            }
            return
        }

        let prefix = workspacePath.hasSuffix("/") ? workspacePath : workspacePath + "/"
        let rel = item.url.path.replacingOccurrences(of: prefix, with: "")
        let current = composer?.string ?? ""
        composer?.string = current.isEmpty ? "@\(rel) " : current + " @\(rel) "
        composerPlaceholder?.isHidden = true
        updateComposerHeight()
        window?.makeFirstResponder(composer)
    }

    private func showPreview(for url: URL, from outlineView: NSOutlineView, row: Int) {
        previewPopover?.performClose(nil)

        let controller = NSViewController()
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        controller.view = root

        let title = label(url.lastPathComponent, size: 12, weight: .semibold, color: C.textBright)
        root.addSubview(title)

        let divider = makeDivider()
        root.addSubview(divider)

        guard let preview = QLPreviewView(frame: .zero, style: .normal) else { return }
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.previewItem = url as NSURL
        root.addSubview(preview)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 720),
            root.heightAnchor.constraint(equalToConstant: 560),

            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),

            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            divider.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            divider.heightAnchor.constraint(equalToConstant: 1),

            preview.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            preview.topAnchor.constraint(equalTo: divider.bottomAnchor),
            preview.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .semitransient
        popover.animates = false
        previewPopover = popover

        let anchorView = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) ?? outlineView
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxX)
    }

    private func refreshTree() {
        rootNode = FileNode(URL(fileURLWithPath: workspacePath))
        rootNode?.loadChildren()
        outlineView?.reloadData()
        outlineView?.expandItem(nil, expandChildren: false)
    }

    private func resolvedTerminalFont() -> NSFont {
        TerminalFontResolver.preferredFont() ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    private func resolvedComposerFont() -> NSFont {
        let font = TerminalFontResolver.preferredFont() ?? NSFont.systemFont(ofSize: 14)
        return NSFont(name: font.fontName, size: max(font.pointSize, 14)) ?? font
    }

    private func composerShouldConsume(_ event: NSEvent) -> Bool {
        guard let composer else { return false }
        if composer.hasMarkedText() {
            return true
        }

        let hasDraft = !composer.string.isEmpty || composer.selectedRange().length > 0
        guard hasDraft else { return false }
        return isNavigationKey(event)
    }

    private func shouldHandleInTerminal(_ event: NSEvent) -> Bool {
        if composerShouldConsume(event) {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            return false
        }
        if flags.contains(.control) || flags.contains(.option) {
            return true
        }

        switch event.keyCode {
        case 53, 115, 116, 119, 121, 123, 124, 125, 126:
            return true
        default:
            return false
        }
    }

    private func isNavigationKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 115, 116, 119, 121, 123, 124, 125, 126:
            return true
        default:
            return false
        }
    }

    private func forwardTerminalKeyIfNeeded(_ event: NSEvent) -> Bool {
        if handleComposerHistoryKeyIfNeeded(event) {
            return true
        }
        guard shouldHandleInTerminal(event) else { return false }
        forwardComposerEventToTerminal(event)
        return true
    }

    private func shouldRedirectTerminalText(_ event: NSEvent) -> Bool {
        if shouldHandleInTerminal(event) {
            return false
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return !flags.contains(.command)
    }

    private func shouldInterceptTerminalTextInput() -> Bool {
        guard let window else { return false }
        return window.firstResponder === terminalView
    }

    private func redirectTerminalTextInputToComposer(_ text: String) {
        guard let window, let composer else { return }
        window.makeFirstResponder(composer)
        composer.insertText(text, replacementRange: composer.selectedRange())
        composerPlaceholder?.isHidden = !composer.string.isEmpty || composer.hasMarkedText()
        updateComposerHeight()
    }

    private func redirectTerminalMarkedTextToComposer(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let window, let composer else { return }
        window.makeFirstResponder(composer)
        composer.setMarkedText(string, selectedRange: selectedRange, replacementRange: composer.selectedRange())
        composerPlaceholder?.isHidden = !composer.string.isEmpty || composer.hasMarkedText()
        updateComposerHeight()
    }

    private func handleComposerHistoryKeyIfNeeded(_ event: NSEvent) -> Bool {
        guard let composer, !composer.hasMarkedText() else { return false }

        switch event.keyCode {
        case 126:
            guard !submissionHistory.isEmpty else { return false }
            if historyIndex == nil {
                guard composer.string.isEmpty else { return false }
                historyDraft = ""
                historyIndex = submissionHistory.count - 1
            } else if let index = historyIndex, index > 0 {
                historyIndex = index - 1
            }
        case 125:
            guard let index = historyIndex else { return false }
            if index < submissionHistory.count - 1 {
                historyIndex = index + 1
            } else {
                historyIndex = nil
                setComposerText(historyDraft)
                return true
            }
        default:
            return false
        }

        if let index = historyIndex {
            setComposerText(submissionHistory[index])
        }
        return true
    }

    private func setComposerText(_ text: String) {
        composer?.string = text
        composerPlaceholder?.isHidden = !text.isEmpty
        updateComposerHeight()
        composer?.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
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

    private func installFlagsMonitorIfNeeded() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            self.terminalView.allowMouseReporting = !flags.contains(.option)
            return event
        }
    }

    private func installMouseMonitorsIfNeeded() {
        guard mouseDownMonitor == nil, mouseDragMonitor == nil, mouseUpMonitor == nil else { return }

        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.trackTerminalMouseDown(event)
            return event
        }

        mouseDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.trackTerminalMouseDragged(event)
            return event
        }

        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.trackTerminalMouseUp(event)
            return event
        }
    }

    private func installScrollMonitorIfNeeded() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self else { return event }
            return self.handleTerminalScrollEvent(event) ? nil : event
        }
    }

    private func handleTerminalScrollEvent(_ event: NSEvent) -> Bool {
        guard event.window === window,
              isPointInsideTerminal(event.locationInWindow),
              terminalView.allowMouseReporting,
              terminalView.terminal.mouseMode != .off else {
            return false
        }

        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
        guard delta != 0 else { return false }

        let hit = approximateTerminalMouseHit(for: event.locationInWindow)
        let buttonFlags = wheelButtonFlags(for: event, deltaY: delta)
        terminalView.terminal.sendEvent(
            buttonFlags: buttonFlags,
            x: hit.grid.col,
            y: hit.grid.row,
            pixelX: hit.pixels.col,
            pixelY: hit.pixels.row
        )
        return true
    }

    private func wheelButtonFlags(for event: NSEvent, deltaY: CGFloat) -> Int {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var value = deltaY > 0 ? 64 : 65
        if flags.contains(.shift) { value += 4 }
        if flags.contains(.option) { value += 8 }
        if flags.contains(.control) { value += 16 }
        return value
    }

    private func approximateTerminalMouseHit(for locationInWindow: NSPoint) -> (grid: (col: Int, row: Int), pixels: (col: Int, row: Int)) {
        let point = terminalView.convert(locationInWindow, from: nil)
        let width = max(terminalView.bounds.width, 1)
        let height = max(terminalView.bounds.height, 1)
        let clampedX = min(max(point.x, 0), width)
        let clampedY = min(max(point.y, 0), height)
        let col = min(max(Int(clampedX / width * CGFloat(max(terminalView.terminal.cols, 1))), 0), max(terminalView.terminal.cols - 1, 0))
        let rowFromTop = Int((height - clampedY) / height * CGFloat(max(terminalView.terminal.rows, 1)))
        let row = min(max(rowFromTop, 0), max(terminalView.terminal.rows - 1, 0))
        return (
            grid: (col, row),
            pixels: (Int(clampedX), Int(height - clampedY))
        )
    }

    private func trackTerminalMouseDown(_ event: NSEvent) {
        pendingComposerRestore?.cancel()
        pendingComposerRestore = nil

        guard let window, event.window === window, isPointInsideTerminal(event.locationInWindow) else {
            isTrackingTerminalClick = false
            didDragInTerminal = false
            return
        }
        isTrackingTerminalClick = true
        didDragInTerminal = false
        if event.modifierFlags.contains(.option) {
            return
        }
        guard event.clickCount == 1 else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isTrackingTerminalClick, !self.didDragInTerminal else { return }
            self.window?.makeFirstResponder(self.composer)
        }
        pendingComposerRestore = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30), execute: workItem)
    }

    private func trackTerminalMouseDragged(_ event: NSEvent) {
        guard isTrackingTerminalClick, let window, event.window === window else { return }
        didDragInTerminal = true
        pendingComposerRestore?.cancel()
        pendingComposerRestore = nil
    }

    private func trackTerminalMouseUp(_ event: NSEvent) {
        defer {
            isTrackingTerminalClick = false
            didDragInTerminal = false
        }

        guard isTrackingTerminalClick, event.clickCount == 1 else { return }
    }

    private func isPointInsideTerminal(_ point: NSPoint) -> Bool {
        guard window != nil else { return false }
        let pointInTerminal = terminalView.convert(point, from: nil)
        return terminalView.bounds.contains(pointInTerminal)
    }

    private func forwardComposerEventToTerminal(_ event: NSEvent) {
        guard let window else { return }
        window.makeFirstResponder(terminalView)

        if let control = controlCharacter(for: event) {
            terminalView.send([control])
        } else if let selector = terminalSelector(for: event) {
            terminalView.doCommand(by: selector)
        } else {
            terminalView.keyDown(with: event)
            terminalView.keyUp(with: event)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.firstResponder === self.terminalView else { return }
            self.window?.makeFirstResponder(self.composer)
        }
    }

    private func controlCharacter(for event: NSEvent) -> UInt8? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.control), !flags.contains(.command), !flags.contains(.option) else {
            return nil
        }

        if let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first {
            switch scalar.value {
            case 32:
                return 0
            case 64...95:
                return UInt8(scalar.value - 64)
            case 97...122:
                return UInt8(scalar.value - 96)
            default:
                break
            }
        }

        switch event.keyCode {
        case 0: return 1
        case 11: return 2
        case 8: return 3
        case 2: return 4
        case 14: return 5
        case 3: return 6
        case 5: return 7
        case 4: return 8
        case 34: return 9
        case 38: return 10
        case 40: return 11
        case 37: return 12
        case 46: return 13
        case 45: return 14
        case 31: return 15
        case 35: return 16
        case 12: return 17
        case 15: return 18
        case 1: return 19
        case 17: return 20
        case 32: return 21
        case 9: return 22
        case 13: return 23
        case 7: return 24
        case 16: return 25
        case 6: return 26
        default:
            return nil
        }
    }

    private func terminalSelector(for event: NSEvent) -> Selector? {
        switch event.keyCode {
        case 48:
            return event.modifierFlags.contains(.shift)
                ? #selector(NSResponder.insertBacktab(_:))
                : #selector(NSResponder.insertTab(_:))
        case 53:
            return #selector(NSResponder.cancelOperation(_:))
        case 115:
            return #selector(NSResponder.moveToBeginningOfLine(_:))
        case 116:
            return #selector(NSResponder.pageUp(_:))
        case 119:
            return #selector(NSResponder.moveToEndOfLine(_:))
        case 121:
            return #selector(NSResponder.pageDown(_:))
        case 123:
            return #selector(NSResponder.moveLeft(_:))
        case 124:
            return #selector(NSResponder.moveRight(_:))
        case 125:
            return #selector(NSResponder.moveDown(_:))
        case 126:
            return #selector(NSResponder.moveUp(_:))
        default:
            return nil
        }
    }

    private func removeEventMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }
        if let mouseDragMonitor {
            NSEvent.removeMonitor(mouseDragMonitor)
            self.mouseDragMonitor = nil
        }
        if let mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
            self.mouseUpMonitor = nil
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        pendingComposerRestore?.cancel()
        pendingComposerRestore = nil
    }

    private struct LaunchSpec {
        let executable: String
        let args: [String]
    }

    private func resolveClaudeLaunch() -> LaunchSpec {
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            NSHomeDirectory() + "/.npm-global/bin/claude",
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return LaunchSpec(executable: path, args: [])
        }

        return LaunchSpec(executable: "/usr/bin/env", args: ["claude"])
    }

    private func resolveTmuxLaunch(tmuxPath: String) -> LaunchSpec {
        let command = shellCommand(for: resolveClaudeLaunch())
        return LaunchSpec(
            executable: tmuxPath,
            args: [
                "new-session",
                "-A",
                "-s", tmuxSessionName,
                "-c", workspacePath,
                command
            ]
        )
    }

    private func shellCommand(for launch: LaunchSpec) -> String {
        let parts = [launch.executable] + launch.args
        return "exec " + parts.map(shellEscape).joined(separator: " ")
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static let tmuxCandidates = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/usr/bin/tmux",
    ]

    private func resolveTmuxPath() -> String? {
        Self.tmuxCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private func launchClaude() {
        guard let tmuxPath = resolveTmuxPath() else {
            statusDot?.layer?.backgroundColor = C.red.cgColor
            statusLabel?.stringValue = "tmux not found"
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "tmux is required"
            alert.informativeText = "brew install tmux"
            alert.addButton(withTitle: "Copy Command")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew install tmux", forType: .string)
            }
            return
        }

        var environment: [String] = []
        for (key, value) in ProcessInfo.processInfo.environment {
            if key == "CLAUDECODE" || key == "CLAUDE_CODE_ENTRYPOINT" {
                continue
            }
            environment.append("\(key)=\(value)")
        }

        if let pathIndex = environment.firstIndex(where: { $0.hasPrefix("PATH=") }) {
            let extra = ["/opt/homebrew/bin", "/usr/local/bin"]
            let current = environment[pathIndex].dropFirst("PATH=".count).split(separator: ":").map(String.init)
            let merged = Array(NSOrderedSet(array: current + extra)) as? [String] ?? (current + extra)
            environment[pathIndex] = "PATH=" + merged.joined(separator: ":")
        } else {
            environment.append("PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        }

        environment.removeAll { $0.hasPrefix("TERM=") }
        environment.append("TERM=xterm-256color")

        if !environment.contains(where: { $0.hasPrefix("LANG=") }) {
            environment.append("LANG=en_US.UTF-8")
        }

        let launch = resolveTmuxLaunch(tmuxPath: tmuxPath)
        terminalView.processDelegate = self
        terminalView.startProcess(
            executable: launch.executable,
            args: launch.args,
            environment: environment,
            execName: nil,
            currentDirectory: workspacePath
        )
        isProcessRunning = true
        updateStatus()
    }

    private func submit() {
        guard let composer else { return }
        let text = composer.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sendReturnToTerminal()
            return
        }

        submissionHistory.append(historyEntry(for: text))
        if submissionHistory.count > Self.historyLimit {
            submissionHistory.removeFirst(submissionHistory.count - Self.historyLimit)
        }
        historyIndex = nil
        historyDraft = ""

        composer.string = ""
        composerPlaceholder?.isHidden = false
        updateComposerHeight()

        window?.makeFirstResponder(terminalView)
        terminalView.sendProgrammaticText(text + "\n")
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.composer)
        }
    }

    private func historyEntry(for text: String) -> String {
        let lineCount = text.components(separatedBy: .newlines).count
        guard lineCount > Self.historyTruncateThreshold else { return text }
        let firstLines = text.components(separatedBy: .newlines).prefix(3).joined(separator: "\n")
        return "\(firstLines)\n[pasted \(lineCount) lines]"
    }

    private func sendReturnToTerminal() {
        window?.makeFirstResponder(terminalView)
        terminalView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.composer)
        }
    }

    private func updateComposerHeight() {
        guard let composer,
              let layoutManager = composer.layoutManager,
              let textContainer = composer.textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let textHeight = layoutManager.usedRect(for: textContainer).height
        let newHeight = max(C.inputMinHeight, min(C.inputMaxHeight, ceil(textHeight + 26)))
        if abs((composerHeightConstraint?.constant ?? 0) - newHeight) > 1 {
            composerHeightConstraint?.constant = newHeight
        }
    }

    private func updateStatus() {
        statusDot?.layer?.backgroundColor = (isProcessRunning ? C.green : C.red).cgColor
        statusLabel?.stringValue = isProcessRunning ? "Running" : "Stopped"
    }

    private func cleanupProcess() {
        guard !didTerminateProcess else { return }
        didTerminateProcess = true

        if terminalView != nil, terminalView.process.running {
            terminalView.terminate()
        }
    }

    private func tinted(_ color: NSColor) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        return view
    }

    private func makeDivider() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = C.border.cgColor
        return view
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.backgroundColor = .clear
        return label
    }
}

extension WorkspaceView: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isProcessRunning = false
            self.updateStatus()
            self.statusLabel?.stringValue = "Exited (\(exitCode ?? -1))"
            self.statusDot?.layer?.backgroundColor = C.red.cgColor
        }
    }
}

extension WorkspaceView: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return rootNode?.children?.count ?? 0
        }

        guard let node = item as? FileNode else { return 0 }
        if node.isDirectory, node.children == nil {
            node.loadChildren()
        }
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? FileNode, let children = node.children, index < children.count {
            return children[index]
        }
        if let children = rootNode?.children, index < children.count {
            return children[index]
        }
        return FileNode(URL(fileURLWithPath: workspacePath))
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isDirectory == true
    }
}

extension WorkspaceView: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("FileCell")
        let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? FileCell) ?? FileCell()
        cell.identifier = identifier
        cell.configure(node)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        FileRowView()
    }
}

private final class FileCell: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentTintColor = C.textDim
        addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = C.text
        titleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ node: FileNode) {
        titleLabel.stringValue = node.name
        let symbolName = node.isDirectory ? "folder.fill" : "doc.text"
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }
}

private final class FileRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }

        let selectionRect = bounds.insetBy(dx: 4, dy: 2)
        NSColor(hex: "#202024")?.setFill()
        NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6).fill()
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        var string = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if string.count == 6 {
            string += "ff"
        }
        guard string.count == 8, let value = UInt64(string, radix: 16) else {
            return nil
        }

        self.init(
            calibratedRed: CGFloat((value >> 24) & 0xff) / 255,
            green: CGFloat((value >> 16) & 0xff) / 255,
            blue: CGFloat((value >> 8) & 0xff) / 255,
            alpha: CGFloat(value & 0xff) / 255
        )
    }
}
