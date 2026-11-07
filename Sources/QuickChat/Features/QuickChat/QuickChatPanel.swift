import AppKit

/// The floating panel window: borderless, non-activating, resizable, and maximizable.
final class QuickChatPanel: NSPanel {
    static let autosaveName = "MiniChat.Panel" // pre-rename name; keeps the saved frame
    /// Matches ChatGPT Classic's companion panel. Saved frames still take precedence;
    /// Reset Window Size (⌘O) applies these dimensions to an existing panel.
    static let defaultSize = NSSize(width: 440, height: 540)
    var onCancel: (() -> Void)?
    var onNewConversation: (() -> Void)?
    /// ⌘B: opens or closes the page's sidebar.
    var onToggleSidebar: (() -> Void)?
    /// ⌘F: opens the find bar.
    var onFind: (() -> Void)?
    /// ⌘G and ⇧⌘G: the next or the previous match (`true`: the previous match).
    var onFindNext: ((Bool) -> Void)?
    /// Called when the panel becomes large (maximized) or goes back to its own frame.
    var onMaximizedChange: ((Bool) -> Void)?
    /// Covers the content while the panel changes its size (the controller adds it).
    var cover: NSView?
    /// Waits until the content is laid out at the given width (with a time limit).
    var waitForContent: ((CGFloat) async -> Void)?
    /// Local key combo that calls `resetSize()` while the panel is key (default ⌘O).
    var resetSizeShortcut: Shortcut? = .commandO
    /// Local key combo that calls `expandOrShrink()` while the panel is key (default ⌃⌘F).
    var maximizeShortcut: Shortcut? = .controlCommandF

    /// The user's frame from before maximizing; non-nil while maximized. Hiding and showing
    /// keep the panel maximized; a relaunch doesn't, as the maximized frame is never autosaved.
    private var restoreFrame: NSRect? {
        didSet { if (oldValue == nil) != (restoreFrame == nil) { onMaximizedChange?(isMaximized) } }
    }
    var isMaximized: Bool { restoreFrame != nil }
    /// The page shows its wide layout: it docks its sidebar on the left. The page does this from
    /// a width of 768 points. The controller sets it from the page's state.
    var isPageWide = false
    /// A maximized panel, or a panel that the user made as wide as the page's wide layout.
    var isLarge: Bool { isMaximized || isPageWide }
    private var frameTransition: Task<Void, Never>?
    /// A throw in progress (see PanelThrow).
    var throwMotion: ThrowMotion?
    /// The left button's press while it is down: where and when it started.
    var leftPress: PanelThrow.Sample?
    /// Set while the panel changes its own frame, so only user moves/resizes end the maximize.
    private var isSettingFrame = false

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   // Non-activating: the panel takes key input, but the app in front stays
                   // active, so its window keeps focus (like Spotlight).
                   styleMask: [.borderless, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "ChatGPT"
        // Join full-screen spaces without becoming a full-screen tile.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        minSize = NSSize(width: 400, height: 400)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(frameDidChange),
                                                   name: name, object: self)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Window ▸ Zoom does the same as Expand, a double-click on the title bar, and ⌃⌘F.
    override func zoom(_ sender: Any?) { expandOrShrink() }

    /// Expand or Shrink: a small panel fills the screen, and a maximized panel goes back to its
    /// frame from before. A panel that the user made large (the page shows its wide layout)
    /// goes to the default size.
    func expandOrShrink() {
        if isMaximized || !isPageWide { toggleMaximize() } else { resetSize() }
    }

    /// Esc (when the page doesn't handle it) hides the panel.
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// Fills the screen's visible frame (menu bar and Dock stay visible), or goes back to the
    /// user's frame from before. The panel stays resizable while maximized.
    func toggleMaximize() {
        if let restoreFrame {
            setOwnFrame(restoreFrame) { $0.endMaximize() }
        } else {
            guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
            restoreFrame = frame
            setFrameAutosaveName("") // keep the user's frame as the one restored on relaunch
            setOwnFrame(visible)
        }
    }

    /// Resizes to `defaultSize`, keeping the top-left corner put (the pre-maximize one if
    /// maximized) but staying on the visible part of the screen. The frame autosave then
    /// persists the new size.
    func resetSize() {
        let anchor = restoreFrame ?? frame
        let size = frameRect(forContentRect: NSRect(origin: .zero, size: Self.defaultSize)).size
        var frame = NSRect(x: anchor.minX, y: anchor.maxY - size.height,
                           width: size.width, height: size.height)
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        setOwnFrame(frame) { panel in
            if panel.isMaximized { panel.endMaximize() }
        }
    }

    /// A frame change that doesn't count as the user moving or resizing the panel. The page
    /// lays itself out again at every step of a resize, and it switches layouts at some widths.
    /// So a cover with the panel's material fades in over the page, the panel resizes, and the
    /// cover fades out when the page is laid out at the new size. The title bar buttons stay.
    /// `then` runs right after the frame changes.
    private func setOwnFrame(_ frame: NSRect, then: @escaping (QuickChatPanel) -> Void = { _ in }) {
        stopThrow()
        frameTransition?.cancel()
        guard isVisible, let cover else {
            applyOwnFrame(frame, animate: false)
            then(self)
            return
        }
        // A newer size change cancels this one: it then stops at its next step, and the newer one
        // sets its own frame and keeps the cover until its own frame is drawn.
        frameTransition = Task { [weak self] in
            guard let self else { return }
            await Self.fade(cover, to: 1, duration: 0.1)
            guard !Task.isCancelled else { return }
            self.applyOwnFrame(frame, animate: true)
            then(self)
            await self.waitForContent?(frame.width)
            guard !Task.isCancelled else { return }
            await Self.fade(cover, to: 0, duration: 0.2)
            if !Task.isCancelled { self.frameTransition = nil }
        }
    }

    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.2 }

    private func applyOwnFrame(_ frame: NSRect, animate: Bool) {
        isSettingFrame = true
        defer { isSettingFrame = false }
        setFrame(frame, display: true, animate: animate)
    }

    private static func fade(_ view: NSView, to alpha: CGFloat, duration: TimeInterval) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                view.animator().alphaValue = alpha
            }, completionHandler: { done.resume() })
        }
    }

    /// A hide during a size change must not leave the cover on the page for the next show.
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        stopThrow()
        frameTransition?.cancel()
        frameTransition = nil
        cover?.alphaValue = 0
    }

    /// Leaves the maximized state as is (frame-wise) and resumes autosaving the current frame.
    /// Setting the autosave name applies the frame saved under it. That frame can be from other
    /// screen bounds (for example, before the Dock moved), so the current frame is saved first and
    /// kept.
    private func endMaximize() {
        restoreFrame = nil
        let current = frame
        saveFrame(usingName: Self.autosaveName)
        setFrameAutosaveName(Self.autosaveName)
        if frame != current {
            isSettingFrame = true
            setFrame(current, display: true)
            isSettingFrame = false
            saveFrame(usingName: Self.autosaveName)
        }
    }

    /// The user moved or resized the maximized panel: that frame becomes their own.
    @objc private func frameDidChange() {
        if isMaximized, !isSettingFrame { endMaximize() }
    }

    /// Runs Find, New Chat, Sidebar, Reset Window Size or Maximize if `event` is its shortcut. Key repeats
    /// are swallowed, so holding the shortcut doesn't toggle maximize over and over.
    private func handleLocalShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "g" {
            if !event.isARepeat { onFindNext?(true) }
            return true
        }
        if modifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f":
                if !event.isARepeat { onFind?() }
                return true
            case "g":
                // Held down, it goes through the matches, as in Safari.
                onFindNext?(false)
                return true
            case "n":
                if !event.isARepeat { onNewConversation?() }
                return true
            case "b":
                if !event.isARepeat { onToggleSidebar?() }
                return true
            default:
                break
            }
        }
        guard let pressed = Shortcut(event: event) else { return false }
        guard pressed == resetSizeShortcut || pressed == maximizeShortcut else { return false }
        if event.isARepeat { return true }
        if pressed == resetSizeShortcut {
            resetSize()
        } else if pressed == maximizeShortcut {
            expandOrShrink()
        } else {
            return false
        }
        return true
    }

    /// Catches the panel's local shortcuts before the web view sees them. Done here rather
    /// than in `performKeyEquivalent` so combos without ⌘ (e.g. ⌥R, F5) work too.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleLocalShortcut(event) { return }
        if event.type == .leftMouseDown {
            leftPress = PanelThrow.Sample(time: event.timestamp, point: Self.screenPoint(of: event) ?? NSEvent.mouseLocation)
        } else if event.type == .leftMouseUp {
            leftPress = nil
        }
        super.sendEvent(event)
    }

    override func close() { onCancel?() }

    /// ⌘W hides; the local shortcuts are caught here too, ahead of the web view (which
    /// otherwise claims ⌘ combos).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleLocalShortcut(event) { return true }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            onCancel?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
