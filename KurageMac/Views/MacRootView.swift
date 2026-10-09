import AppKit
import SwiftUI
import KurageCore

struct MacRootView: View {
    let model: AppModel
    @State private var restored = false
    @State private var awake = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.isSignedIn {
                MacWorkspaceView(model: model, isAwake: awake && scenePhase != .background)
                    .id(model.workspaceGeneration)
            } else if restored {
                MacSignInView(model: model)
            } else {
                ProgressView("Restoring account…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await model.adoptExistingAccount()
            restored = true
        }
        // Losing keyboard focus is not a mobile background transition.
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.setApplicationActive(awake && phase != .background)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            awake = false
            model.setApplicationActive(false)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            awake = true
            model.setApplicationActive(scenePhase != .background)
        }
    }
}

/// Workspace menu and Settings, pinned under the session list.
/// The plate is opaque so a scrolling title cannot show through the controls.
private struct MacSidebarFooter: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack {
            Menu {
                ForEach(model.workspaces) { workspace in
                    Button(workspace.name) { Task { await model.selectWorkspace(workspace.id) } }
                }
            } label: {
                Label(model.workspaceLabel, systemImage: "square.grid.2x2")
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("workspace-menu")
            Button("Settings", systemImage: "gearshape") { openWindow(id: MacSettingsWindow.id) }
                .labelStyle(.iconOnly)
                .help("Settings")
                .accessibilityIdentifier("open-settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            // Solid sidebar plate. A clear bar lets the session list show through.
            MacSidebarPlate()
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Opaque sidebar plate drawn above the session list.
/// The list's scroll view paints over a normal SwiftUI background, so titles stay visible until this view is lifted.
private struct MacSidebarPlate: NSViewRepresentable {
    func makeNSView(context: Context) -> MacSidebarPlateView { MacSidebarPlateView() }
    func updateNSView(_ view: MacSidebarPlateView, context: Context) {}
}

private final class MacSidebarPlateView: NSView {
    override var isOpaque: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        layer?.backgroundColor = plateColor.cgColor
        liftAboveOverlappingScrollView()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = plateColor.cgColor
    }

    private var plateColor: NSColor {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return MacChrome.sidebar(dark: dark)
    }

}

private extension NSView {
    /// The sidebar list's scroll view is composited above ordinary SwiftUI backgrounds.
    /// `searchOutset` widens a hairline so it still counts as overlapping that list.
    func liftAboveOverlappingScrollView(searchOutset: CGFloat = 0) {
        guard let content = window?.contentView else { return }
        let mine = convert(bounds, to: nil).insetBy(dx: -searchOutset, dy: 0)
        guard let scroll = content.firstScrollView(overlapping: mine),
              let common = commonAncestor(with: scroll),
              let ours = common.child(containing: self),
              let theirs = common.child(containing: scroll),
              ours !== theirs else { return }
        ours.wantsLayer = true
        theirs.wantsLayer = true
        let above = (theirs.layer?.zPosition ?? 0) + 1
        if ours.layer?.zPosition != above { ours.layer?.zPosition = above }
    }

    func commonAncestor(with other: NSView) -> NSView? {
        var ancestors = Set<NSView>()
        var view: NSView? = self
        while let current = view {
            ancestors.insert(current)
            view = current.superview
        }
        view = other
        while let current = view {
            if ancestors.contains(current) { return current }
            view = current.superview
        }
        return nil
    }
}

private extension NSView {
    func firstScrollView(overlapping rect: NSRect) -> NSScrollView? {
        if let scroll = self as? NSScrollView, convert(bounds, to: nil).intersects(rect) { return scroll }
        for subview in subviews {
            if let found = subview.firstScrollView(overlapping: rect) { return found }
        }
        return nil
    }

    func child(containing descendant: NSView) -> NSView? {
        var view: NSView? = descendant
        while let current = view {
            if current.superview === self { return current }
            view = current.superview
        }
        return nil
    }
}

/// Solid sidebar and conversation fills. The system sidebar material is a warm gray
/// that does not match these values, so both columns paint over it.
enum MacChrome {
    static func sidebar(dark: Bool) -> NSColor {
        if dark { return NSColor(srgbRed: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1) }
        return NSColor(srgbRed: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF7 / 255, alpha: 1)
    }

    static func main(dark: Bool) -> NSColor {
        if dark { return NSColor(srgbRed: 0x07 / 255, green: 0x07 / 255, blue: 0x07 / 255, alpha: 1) }
        return NSColor(srgbRed: 0xFC / 255, green: 0xFC / 255, blue: 0xFC / 255, alpha: 1)
    }

    static func sidebar(_ scheme: ColorScheme) -> Color {
        Color(nsColor: sidebar(dark: scheme == .dark))
    }

    static func main(_ scheme: ColorScheme) -> Color {
        Color(nsColor: main(dark: scheme == .dark))
    }

    static func divider(dark: Bool) -> NSColor {
        if dark { return NSColor(srgbRed: 0x2A / 255, green: 0x2A / 255, blue: 0x2A / 255, alpha: 1) }
        return NSColor(srgbRed: 0xE4 / 255, green: 0xE4 / 255, blue: 0xE4 / 255, alpha: 1)
    }
}

/// Hairline on the sidebar's trailing edge. The session list draws above a SwiftUI
/// overlay, so this view lifts its own layer the same way the footer plate does.
private struct MacColumnDivider: NSViewRepresentable {
    func makeNSView(context: Context) -> MacColumnDividerView { MacColumnDividerView() }
    func updateNSView(_ view: MacColumnDividerView, context: Context) {}
}

private final class MacColumnDividerView: NSView {
    override var isOpaque: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        layer?.backgroundColor = dividerColor.cgColor
        liftAboveOverlappingScrollView(searchOutset: 8)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = dividerColor.cgColor
    }

    private var dividerColor: NSColor {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return MacChrome.divider(dark: dark)
    }
}

/// Paints the title bar in two columns. The unified toolbar is one material across
/// the window, so the traffic-light side would otherwise stay the conversation color.
private struct MacTitlebarSplit: NSViewRepresentable {
    func makeNSView(context: Context) -> MacTitlebarSplitView { MacTitlebarSplitView() }
    func updateNSView(_ view: MacTitlebarSplitView, context: Context) {}

    static func dismantleNSView(_ view: MacTitlebarSplitView, coordinator: ()) {
        view.uninstall()
    }
}

final class MacTitlebarSplitView: NSView {
    private var chrome: MacTitlebarChromeView?
    private weak var installedWindow: NSWindow?
    private var originalTitlebar: (transparent: Bool, separator: NSTitlebarSeparatorStyle)?
    private var hiddenFills: [NSView] = []

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if installedWindow !== newWindow { uninstall() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        install()
    }

    override func layout() {
        super.layout()
        install()
    }

    func uninstall() {
        chrome?.removeFromSuperview()
        chrome = nil
        for fill in hiddenFills { fill.isHidden = false }
        hiddenFills = []
        if let window = installedWindow, let originalTitlebar {
            window.titlebarAppearsTransparent = originalTitlebar.transparent
            window.titlebarSeparatorStyle = originalTitlebar.separator
        }
        installedWindow = nil
        originalTitlebar = nil
    }

    private func install() {
        guard let window, let titlebar = window.titlebarContainer() else { return }
        if installedWindow !== window {
            uninstall()
            installedWindow = window
            originalTitlebar = (window.titlebarAppearsTransparent, window.titlebarSeparatorStyle)
        }
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        if chrome?.superview !== titlebar {
            chrome?.removeFromSuperview()
            let view = MacTitlebarChromeView()
            view.autoresizingMask = [.width, .height]
            titlebar.addSubview(view, positioned: .below, relativeTo: nil)
            chrome = view
        }
        guard let chrome else { return }
        if let host = titlebar.subviews.first(where: { !($0 is MacTitlebarChromeView) }) {
            titlebar.addSubview(chrome, positioned: .below, relativeTo: host)
        }
        chrome.frame = titlebar.bounds
        titlebar.neutralizeTitlebarFill(hiddenFills: &hiddenFills)
        chrome.needsDisplay = true
    }
}

/// Sidebar color behind the traffic lights, conversation color behind the title.
private final class MacTitlebarChromeView: NSView {
    override var isOpaque: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard window != nil else { return }
        NotificationCenter.default.addObserver(
            self, selector: #selector(redraw),
            name: NSSplitView.didResizeSubviewsNotification, object: nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    @objc private func redraw(_ note: Notification) {
        guard let source = note.object as? NSView, source.window === window else { return }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let splitX = sidebarEdge()
        MacChrome.sidebar(dark: dark).setFill()
        NSRect(x: 0, y: 0, width: max(splitX, 0), height: bounds.height).fill()
        MacChrome.main(dark: dark).setFill()
        NSRect(x: splitX, y: 0, width: max(bounds.width - splitX, 0), height: bounds.height).fill()
        guard splitX > 1, splitX < bounds.width - 1 else { return }
        MacChrome.divider(dark: dark).setFill()
        NSRect(x: splitX, y: 0, width: 1, height: bounds.height).fill()
    }

    /// The visible sidebar's trailing x, in this view.
    /// A collapsed column keeps its last frame and only clips the hairline, so a
    /// stale divider x would leave a sidebar-colored titlebar with nothing below it.
    private func sidebarEdge() -> CGFloat {
        guard let window, let theme = window.contentView?.superview else {
            retryDraw()
            return 0
        }
        if let split = mainColumnSplit(in: theme, window: window),
           let sidebar = split.arrangedSubviews.first,
           split.isSubviewCollapsed(sidebar) {
            return 0
        }
        guard let divider = theme.firstView(where: { $0 is MacColumnDividerView }) else {
            retryDraw()
            return 0
        }
        if divider.isHidden || divider.hasHiddenAncestor || divider.visibleRect.isEmpty {
            retryDraw()
            return 0
        }
        let frame = divider.convert(divider.bounds, to: nil)
        guard frame.midX > 8 else { return 0 }
        return convert(NSPoint(x: frame.midX, y: 0), from: nil).x
    }

    private func retryDraw() {
        if redraws < 20 {
            redraws += 1
            DispatchQueue.main.async { [weak self] in self?.needsDisplay = true }
        }
    }

    /// The full-height vertical split that owns the sidebar column.
    private func mainColumnSplit(in theme: NSView, window: NSWindow) -> NSSplitView? {
        if let splitView, splitView.window === window { return splitView }
        var best: NSSplitView?
        var bestArea: CGFloat = 0
        func walk(_ view: NSView) {
            if let split = view as? NSSplitView, split.isVertical, split.arrangedSubviews.count >= 2 {
                let frame = split.convert(split.bounds, to: nil)
                let area = frame.width * frame.height
                if frame.height > window.frame.height * 0.7, area > bestArea {
                    best = split
                    bestArea = area
                }
            }
            for subview in view.subviews { walk(subview) }
        }
        walk(theme)
        splitView = best
        return best
    }

    private var redraws = 0
    private weak var splitView: NSSplitView?
}

private extension NSWindow {
    func titlebarContainer() -> NSView? {
        guard let content = contentView, let theme = content.superview else { return nil }
        let chrome = theme.subviews.filter { $0 !== content }
        return chrome.lazy.compactMap { view in
            view.firstView { String(describing: type(of: $0)).contains("TitlebarContainer") }
        }.first ?? chrome.lazy.compactMap { view in
            view.firstView { String(describing: type(of: $0)).contains("Titlebar") }
        }.first
    }
}

private extension NSView {
    func firstView(where matches: (NSView) -> Bool) -> NSView? {
        if matches(self) { return self }
        for subview in subviews {
            if let found = subview.firstView(where: matches) { return found }
        }
        return nil
    }

    /// Record only visible fills hidden by this installation, so teardown restores them.
    func neutralizeTitlebarFill(hiddenFills: inout [NSView]) {
        for subview in subviews where !(subview is MacTitlebarChromeView) && !subview.isHidden {
            let coversWidth = subview.frame.width > bounds.width * 0.8 && subview.frame.height > 12
            let name = String(describing: type(of: subview))
            let isFill = subview is NSVisualEffectView || name.contains("Decoration") || name.contains("Background")
            if coversWidth && isFill && !subview.containsControl() {
                hiddenFills.append(subview)
                subview.isHidden = true
            } else {
                subview.neutralizeTitlebarFill(hiddenFills: &hiddenFills)
            }
        }
    }

    func containsControl() -> Bool {
        if self is NSControl { return true }
        return subviews.contains { $0.containsControl() }
    }

    var hasHiddenAncestor: Bool {
        var view = superview
        while let current = view {
            if current.isHidden { return true }
            view = current.superview
        }
        return false
    }
}

private struct MacWorkspaceView: View {
    let model: AppModel
    let isAwake: Bool
    @State private var window = MacWindowState()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var window = window
        NavigationSplitView {
            VStack(spacing: 0) {
                MacSidebar(model: model, window: window)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                MacSidebarFooter(model: model)
                    .layoutPriority(1)
                    .zIndex(1)
            }
            .background(MacChrome.sidebar(colorScheme).ignoresSafeArea())
            .overlay(alignment: .trailing) {
                MacColumnDivider()
                    .frame(width: 1)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            Group {
                if let rootID = window.selectedRootID, let root = model.sessionSummary(rootID) {
                    MacSessionView(model: model, window: window, root: root, isAwake: isAwake)
                        .id(root.id)
                } else {
                    ContentUnavailableView("Select a conversation", systemImage: "bubble.left.and.bubble.right",
                        description: Text("Choose a session from the sidebar, or start one in a project."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MacChrome.main(colorScheme).ignoresSafeArea())
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background { MacTitlebarSplit() }
        .overlay {
            if window.showsSessionSearch {
                MacSessionSearchOverlay(model: model, window: window)
            }
        }
        .sheet(item: $window.newSession) { destination in
            MacNewSessionView(model: model, destination: destination, isAwake: isAwake) { id in
                window.open(id, rootID: destination.isTab ? destination.template.id : nil)
            }
        }
        .task(id: isAwake) {
            guard isAwake else { return }
            while !Task.isCancelled {
                await model.refreshSessions()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }
}
