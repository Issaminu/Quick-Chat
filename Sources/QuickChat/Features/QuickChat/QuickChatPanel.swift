import AppKit
import WebKit

/// Floating Quick Chat in the spirit of ChatGPT Classic's companion chat: chatgpt.com in a
/// web view, which uses its compact layout at this width.
@MainActor
final class QuickChatController: NSObject {
    private static let chatURL = URL(string: "https://chatgpt.com/")!
    /// Hosts that stay inside the panel (chat + sign-in flows); other links open in the browser.
    private static let inPanelHosts = ["chatgpt.com", "openai.com", "auth0.com", "google.com", "apple.com",
                                       "microsoftonline.com", "live.com", "microsoft.com"]

    private let log = Log.make("QuickChat")
    private var panel: QuickChatPanel?
    private var webView: WKWebView?
    private weak var dragRegion: DraggableView?
    private var previousApp: NSRunningApplication?
    /// Where each in-flight download is being written, for "reveal in Finder" when it finishes.
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    /// Recent automatic reloads after the web content process died, to stop a crash loop.
    private var crashReloads: [Date] = []
    /// Set when crash reloads were given up; the page reloads the next time the panel shows.
    private var reloadOnShow = false

    var isVisible: Bool { panel?.isVisible == true }

    /// Local shortcut (only while the panel is key) that triggers `resetSize()`.
    var resetSizeShortcut = Shortcut.loadResetSize() {
        didSet { panel?.resetSizeShortcut = resetSizeShortcut }
    }

    /// Local shortcut (only while the panel is key) that toggles maximize.
    var maximizeShortcut = Shortcut.loadMaximize() {
        didSet { panel?.maximizeShortcut = maximizeShortcut }
    }

    /// Resizes the panel back to `QuickChatPanel.defaultSize` (no-op if it was never built).
    func resetSize() { panel?.resetSize() }

    /// Hides the panel whenever it's visible (focused or not), otherwise shows it. Focus goes
    /// back to the previous app only if the panel had it.
    func toggle() {
        if let panel, panel.isVisible {
            hide(restoreFocus: panel.isKeyWindow && NSApp.isActive)
        } else {
            show()
        }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        if reloadOnShow, let webView {
            reloadOnShow = false
            crashReloads = []
            reload(webView)
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(webView)
        focusComposer()
    }

    /// `restoreFocus`: give focus back to the app that was frontmost before showing.
    func hide(restoreFocus: Bool) {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        if restoreFocus { previousApp?.activate() }
    }

    /// Closes the panel and releases the web view (the sign-in session stays in the data store).
    func tearDown() {
        panel?.orderOut(nil)
        webView?.stopLoading()
        panel?.contentView = nil
        panel = nil
        webView = nil
        crashReloads = []
        reloadOnShow = false
    }

    /// Signs out by clearing the panel's website data (cookies, storage).
    func signOut() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            MainActor.assumeIsolated {
                self?.log.info("Cleared Quick Chat website data")
                self?.webView?.load(URLRequest(url: Self.chatURL))
            }
        }
    }

    // MARK: Building

    private func makePanel() -> QuickChatPanel {
        let panel = QuickChatPanel(contentRect: NSRect(origin: .zero, size: QuickChatPanel.defaultSize))
        panel.onCancel = { [weak self] in self?.hide(restoreFocus: true) }
        panel.onNewConversation = { [weak self] in self?.newConversation() }
        panel.resetSizeShortcut = resetSizeShortcut
        panel.maximizeShortcut = maximizeShortcut

        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 20
        background.layer?.masksToBounds = true
        let webView = makeWebView()
        let dragRegion = DraggableView()
        dragRegion.isHidden = true
        webView.configuration.userContentController.add(HeaderControlsHandler(dragRegion), name: "quickChatHeaderControls")
        for view in [webView, dragRegion] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            webView.topAnchor.constraint(equalTo: background.topAnchor),
            webView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            dragRegion.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            dragRegion.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            dragRegion.topAnchor.constraint(equalTo: background.topAnchor),
            dragRegion.heightAnchor.constraint(equalToConstant: 44),
        ])
        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Quick Chat")!,
                                   target: panel, action: #selector(QuickChatPanel.cancelOperation(_:)))
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        closeButton.toolTip = "Close Quick Chat (Esc)"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 10),
            closeButton.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
        ])
        panel.contentView = background

        restorePosition(of: panel)

        self.panel = panel
        self.webView = webView
        self.dragRegion = dragRegion
        webView.load(URLRequest(url: Self.chatURL))
        return panel
    }

    private func restorePosition(of panel: NSPanel) {
        let saved = UserDefaults.standard.string(forKey: "NSWindow Frame \(QuickChatPanel.autosaveName)")?
            .split(separator: " ").prefix(4).compactMap { Double($0) }
        panel.setFrameAutosaveName(QuickChatPanel.autosaveName)
        guard saved != nil, panel.setFrameUsingName(QuickChatPanel.autosaveName) else {
            placeInitially(panel)
            return
        }
        // AppKit can remap an external display's saved frame to the main display. Keep the
        // original coordinates when they still fit; otherwise use AppKit's adjusted frame.
        if let saved, saved.count == 4, saved.allSatisfy({ $0.isFinite }),
           saved[2] >= panel.minSize.width, saved[3] >= panel.minSize.height {
            let frame = NSRect(x: saved[0], y: saved[1], width: saved[2], height: saved[3])
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(frame) }) {
                panel.setFrame(frame, display: false)
            }
        }
    }

    private func placeInitially(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.minY + 32))
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(WKUserScript(source: QuickChatPageStyle.script,
                                                                injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        if let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari"),
           let version = Bundle(url: safariURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            config.applicationNameForUserAgent = "Version/\(version) Safari/605.1.15"
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.underPageBackgroundColor = .clear
        // WKWebView has no public macOS switch for transparent page compositing.
        if webView.responds(to: NSSelectorFromString("_setDrawsBackground:")) {
            webView.setValue(false, forKey: "drawsBackground")
        }
        return webView
    }

    private func newConversation() {
        guard let webView, let url = webView.url, url.scheme == "https",
              let host = url.host, Self.isChatGPTHost(host) else { return }
        webView.evaluateJavaScript("""
            (() => {
                const button = document.querySelector('[data-testid="create-new-chat-button"], [data-testid="new-chat-button"], [aria-label^="New chat" i]')
                    || [...document.querySelectorAll('button, a, [role="button"]')].find(element =>
                        /^new chat(?:$|\\s)/i.test((element.getAttribute('aria-label') || element.textContent || '').trim()));
                if (button) { button.click(); return true; }
                // The compact page may unmount the sidebar button; use the site's own shortcut then.
                const event = new KeyboardEvent('keydown', {
                    key: 'O', code: 'KeyO', keyCode: 79, which: 79,
                    metaKey: true, shiftKey: true, bubbles: true, cancelable: true
                });
                return !(document.activeElement || document.body).dispatchEvent(event);
            })();
            """) { [weak self] result, error in
                if error != nil || result as? Bool != true {
                    self?.log.error("Could not invoke ChatGPT's New chat action")
                    NSSound.beep()
                } else {
                    self?.focusComposer()
                }
            }
    }

    private func focusComposer() {
        // The compact and desktop pages use different composer IDs.
        webView?.evaluateJavaScript("document.querySelector('#prompt-textarea, #mobile-composer-prompt')?.focus()")
    }

    /// chatgpt.com or a subdomain of it (not e.g. "notchatgpt.com").
    fileprivate static func isChatGPTHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")
    }

    /// blob: and data: URLs are page-generated files (exports, images); they're saved, never shown.
    private static func isGeneratedFile(_ url: URL?) -> Bool {
        url?.scheme == "blob" || url?.scheme == "data"
    }

    /// ~/Downloads/<name>, or "<name> 2", "<name> 3", … if that already exists (Finder-style).
    private static func uniqueDownloadURL(suggestedFilename: String) -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var name = (suggestedFilename as NSString).lastPathComponent
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.hasPrefix(".") { name = "download" + name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = downloads.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = "\(base) \(n)" + (ext.isEmpty ? "" : ".\(ext)")
            candidate = downloads.appendingPathComponent(numbered)
            n += 1
        }
        return candidate
    }

    private static func staysInPanel(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return true } // about:blank, data:, etc.
        return inPanelHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

// MARK: - WebKit delegates

extension QuickChatController: WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate {
    /// `window.open` / target=_blank: sign-in pages stay in the panel, everything else goes to the browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if Self.isGeneratedFile(url) {
            // window.open(blob:/data:) would otherwise replace the chat in the panel.
            webView.startDownload(using: navigationAction.request) { $0.delegate = self }
        } else if Self.staysInPanel(url) {
            webView.load(navigationAction.request)
        } else {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        // <a download>, blob:/data: links: save the file instead of navigating (checked first, as
        // download links often point at file hosts that would otherwise open in the browser).
        if navigationAction.shouldPerformDownload || (navigationAction.targetFrame?.isMainFrame == true && Self.isGeneratedFile(url)) {
            decisionHandler(.download)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true, navigationAction.navigationType == .linkActivated,
           !Self.staysInPanel(url), let url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// Responses the web view can't display, or that the server marks as attachments, are saved.
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased()
        let isAttachment = disposition?.hasPrefix("attachment") == true
        decisionHandler(!navigationResponse.canShowMIMEType || isAttachment ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        dragRegion?.isHidden = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        focusComposer()
    }

    /// macOS may kill the web content process (often while hidden, under memory pressure), which
    /// leaves the view blank; reload right away so it's ready before the panel is shown again.
    /// A page that keeps crashing it (3 times in a minute) is left until the panel is next shown.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let now = Date()
        crashReloads.removeAll { now.timeIntervalSince($0) > 60 }
        guard crashReloads.count < 3 else {
            log.error("Web content process keeps terminating; reloading when the panel is next shown")
            reloadOnShow = true
            return
        }
        crashReloads.append(now)
        log.info("Web content process terminated; reloading")
        reload(webView)
    }

    private func reload(_ webView: WKWebView) {
        if webView.url != nil { webView.reload() } else { webView.load(URLRequest(url: Self.chatURL)) }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        guard let panel else { return completionHandler(nil) }
        let open = NSOpenPanel()
        open.allowsMultipleSelection = parameters.allowsMultipleSelection
        open.canChooseDirectories = parameters.allowsDirectories
        open.beginSheetModal(for: panel) { response in
            completionHandler(response == .OK ? open.urls : nil)
        }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        // Camera and microphone alike: WebKit asks the user (per page load) on chatgpt.com only.
        // macOS's own TCC prompt also appears once per app (NSCamera/NSMicrophoneUsageDescription).
        decisionHandler(origin.protocol == "https" && Self.isChatGPTHost(origin.host) ? .prompt : .deny)
    }

    // MARK: Downloads (WKDownloadDelegate)

    /// Saves straight to ~/Downloads under a unique name (like Safari): no modal sheet on the
    /// floating panel, which may be hidden by the time a slow download asks for a destination.
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        let destination = Self.uniqueDownloadURL(suggestedFilename: suggestedFilename)
        downloadDestinations[ObjectIdentifier(download)] = destination
        log.info("Downloading to \(destination.path, privacy: .public)")
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destination = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        log.error("Download failed: \(error.localizedDescription, privacy: .public)")
        NSSound.beep()
    }
}

// MARK: - Panel

final class QuickChatPanel: NSPanel {
    static let autosaveName = "MiniChat.Panel" // pre-rename name; keeps the saved frame
    /// Default content size (also the "reset size" target): a 3:4 portrait panel. Anything under
    /// 640 wide gets chatgpt.com's compact (mobile) layout; 420 sits between Classic's 440-wide
    /// companion chat and `minSize` (400), so the thread reads as a narrow column without the
    /// squat look of the new app's 470-wide window cut down to 560 tall.
    static let defaultSize = NSSize(width: 420, height: 560)
    var onCancel: (() -> Void)?
    var onNewConversation: (() -> Void)?
    /// Local key combo that calls `resetSize()` while the panel is key (default ⌘O).
    var resetSizeShortcut: Shortcut? = .commandO
    /// Local key combo that calls `toggleMaximize()` while the panel is key (default ⌘F).
    var maximizeShortcut: Shortcut? = .commandF

    /// The user's frame from before maximizing; non-nil while maximized. Hiding and showing
    /// keep the panel maximized; a relaunch doesn't, as the maximized frame is never autosaved.
    private var restoreFrame: NSRect?
    var isMaximized: Bool { restoreFrame != nil }
    /// Set while the panel changes its own frame, so only user moves/resizes end the maximize.
    private var isSettingFrame = false

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .resizable],
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
    override var canBecomeMain: Bool { true }

    /// Window ▸ Zoom uses the same maximize behavior as the drag region and shortcut.
    override func zoom(_ sender: Any?) { toggleMaximize() }

    /// Esc (when the page doesn't handle it) hides the panel.
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// Fills the screen's visible frame (menu bar and Dock stay visible), or goes back to the
    /// user's frame from before. The panel stays resizable while maximized.
    func toggleMaximize() {
        if let restoreFrame {
            setOwnFrame(restoreFrame)
            endMaximize()
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
        setOwnFrame(frame)
        if isMaximized { endMaximize() }
    }

    /// Animated frame change that doesn't count as the user moving or resizing the panel.
    private func setOwnFrame(_ frame: NSRect) {
        isSettingFrame = true
        defer { isSettingFrame = false }
        setFrame(frame, display: true, animate: true)
    }

    /// Leaves the maximized state as is (frame-wise) and resumes autosaving the current frame.
    private func endMaximize() {
        restoreFrame = nil
        setFrameAutosaveName(Self.autosaveName)
        saveFrame(usingName: Self.autosaveName)
    }

    /// The user moved or resized the maximized panel: that frame becomes their own.
    @objc private func frameDidChange() {
        if isMaximized, !isSettingFrame { endMaximize() }
    }

    /// Runs the Reset Window Size or Maximize action if `event` is its shortcut. Key repeats
    /// are swallowed, so holding the shortcut doesn't toggle maximize over and over.
    private func handleLocalShortcut(_ event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "n" {
            if !event.isARepeat { onNewConversation?() }
            return true
        }
        guard let pressed = Shortcut(event: event) else { return false }
        guard pressed == resetSizeShortcut || pressed == maximizeShortcut else { return false }
        if event.isARepeat { return true }
        if pressed == resetSizeShortcut {
            resetSize()
        } else if pressed == maximizeShortcut {
            toggleMaximize()
        } else {
            return false
        }
        return true
    }

    /// Catches the panel's local shortcuts before the web view sees them. Done here rather
    /// than in `performKeyEquivalent` so combos without ⌘ (e.g. ⌥R, F5) work too.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleLocalShortcut(event) { return }
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

/// Drag the empty middle of the web header without covering its buttons or adding a bar.
private final class DraggableView: NSView {
    var controls: [NSRect] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let webPoint = NSPoint(x: local.x + frame.minX, y: bounds.height - local.y)
        if controls.contains(where: { $0.contains(webPoint) }) { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            (window as? QuickChatPanel)?.toggleMaximize()
        } else {
            window?.performDrag(with: event)
        }
    }
}

/// Only control rectangles cross this bridge; the handler does not retain the panel or controller.
@MainActor
private final class HeaderControlsHandler: NSObject, WKScriptMessageHandler {
    private weak var dragRegion: DraggableView?

    init(_ dragRegion: DraggableView) { self.dragRegion = dragRegion }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, origin.protocol == "https",
              QuickChatController.isChatGPTHost(origin.host),
              let rectangles = message.body as? [[Double]], let dragRegion else { return }
        dragRegion.controls = rectangles.prefix(256).compactMap { rect in
            guard rect.count == 4, rect.allSatisfy({ $0.isFinite }), rect[2] > 0, rect[3] > 0 else { return nil }
            return NSRect(x: CGFloat(rect[0]), y: CGFloat(rect[1]), width: CGFloat(rect[2]), height: CGFloat(rect[3]))
        }
        dragRegion.isHidden = false
    }
}
