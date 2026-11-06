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
    private var headerButtons: HeaderButtons?
    private var loadingView: LoadingView?
    private var urlObservation: NSKeyValueObservation?
    private var systemAppearanceObservation: NSKeyValueObservation?
    /// The page's theme, from its last state message.
    private var pageIsDark: Bool?
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

    /// Hides the panel whenever it's visible (focused or not), otherwise shows it.
    func toggle() {
        if let panel, panel.isVisible {
            hide(restoreFocus: panel.isKeyWindow)
        } else {
            show()
        }
    }

    /// Builds the panel without showing it, so ChatGPT loads in the background and is ready
    /// when the panel first shows.
    func preload() {
        if panel == nil { _ = makePanel() }
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
        // The panel is non-activating: it takes key input, and the app in front stays active.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(webView)
        focusComposer()
    }

    /// `restoreFocus`: give focus back to the app that was frontmost before showing. That app
    /// usually stays active, as the panel does not activate Quick Chat; only a file dialog does.
    func hide(restoreFocus: Bool) {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        if restoreFocus && NSApp.isActive { previousApp?.activate() }
    }

    /// Closes the panel and releases the web view (the sign-in session stays in the data store).
    func tearDown() {
        panel?.orderOut(nil)
        webView?.stopLoading()
        panel?.contentView = nil
        panel = nil
        webView = nil
        headerButtons = nil
        loadingView = nil
        urlObservation = nil
        systemAppearanceObservation = nil
        pageIsDark = nil
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
        // As the window's content view, the mask also gives the window its rounded shape and
        // shadow; without it the shadow stays rectangular and the corners look light.
        background.maskImage = Self.roundedMask(radius: CGFloat(QuickChatPageStyle.windowCornerRadius))
        background.wantsLayer = true
        background.layer?.cornerRadius = CGFloat(QuickChatPageStyle.windowCornerRadius)
        background.layer?.masksToBounds = true
        let webView = makeWebView()
        webView.configuration.userContentController.add(PageMessageHandler(self), name: "quickChat")
        let headerButtons = HeaderButtons()
        headerButtons.onClose = { [weak self] in self?.hide(restoreFocus: true) }
        headerButtons.onOpenInBrowser = { [weak self] in self?.openInBrowser() }
        headerButtons.onTemporaryChat = { [weak self] in self?.toggleTemporaryChat() }
        headerButtons.onNewChat = { [weak self] in self?.newConversation() }
        let loadingView = LoadingView()
        for view in [webView, loadingView, headerButtons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            webView.topAnchor.constraint(equalTo: background.topAnchor),
            webView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            loadingView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            loadingView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            loadingView.topAnchor.constraint(equalTo: background.topAnchor),
            loadingView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            headerButtons.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            headerButtons.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            headerButtons.topAnchor.constraint(equalTo: background.topAnchor),
        ])
        panel.contentView = background

        restorePosition(of: panel)

        self.panel = panel
        self.webView = webView
        self.headerButtons = headerButtons
        self.loadingView = loadingView
        systemAppearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateAppearance() }
        }
        // The page changes its address without loading (single-page app); this follows each change.
        urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
            MainActor.assumeIsolated { self?.headerButtons?.update(for: webView.url) }
        }
        webView.load(URLRequest(url: Self.chatURL))
        return panel
    }

    /// A stretchable rounded rectangle; only its corners keep their size when resized.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
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
                                                                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari"),
           let version = Bundle(url: safariURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            config.applicationNameForUserAgent = "Version/\(version) Safari/605.1.15"
        }
        let webView = PanelWebView(frame: .zero, configuration: config)
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

    /// Starts a new chat the way the page does, without reloading: the title bar's new chat
    /// button (next to the sidebar button), else the page's Home link, else ChatGPT's own
    /// shortcut (⇧⌘O). Only structure is used, so it works in every language.
    private func newConversation() {
        guard let webView, QuickChatLocation(webView.url).isChatGPT else { return }
        webView.evaluateJavaScript("""
            (() => {
                const page = document.querySelector('[data-app-shell-active-page="true"]') || document;
                const button = page.querySelector('[data-app-shell-header-slot="start"] > :not([aria-hidden="true"]) button:not([aria-controls])')
                    || page.querySelector('a[href="/"]') || document.querySelector('a[href="/"]');
                if (button) { button.click(); return true; }
                const event = new KeyboardEvent('keydown', {
                    key: 'O', code: 'KeyO', keyCode: 79, which: 79,
                    metaKey: true, shiftKey: true, bubbles: true, cancelable: true
                });
                return !(document.activeElement || document.body).dispatchEvent(event);
            })();
            """) { [weak self] result, error in
                guard let self else { return }
                if error != nil || result as? Bool != true {
                    self.log.error("Could not invoke ChatGPT's New chat action; loading a new chat")
                    self.webView?.load(URLRequest(url: Self.chatURL))
                } else {
                    self.focusComposer()
                }
            }
    }

    /// Opens the current page (a conversation, or a new chat) in the default browser and hides the panel.
    private func openInBrowser() {
        let url = webView?.url
        NSWorkspace.shared.open(QuickChatLocation(url).isChatGPT ? url ?? Self.chatURL : Self.chatURL)
        hide(restoreFocus: false)
    }

    /// Starts or leaves a temporary chat with the page's own button, so the page stays loaded.
    /// The button is "Temporary chat", or "Turn off temporary chat" while one is on. Without that
    /// button (other languages, a changed page), loads the matching address.
    private func toggleTemporaryChat() {
        guard let webView else { return }
        let leave = QuickChatLocation(webView.url).isTemporary
        webView.evaluateJavaScript("""
            (() => {
                const button = [...document.querySelectorAll('header button[aria-label*="temporary chat" i], button[data-testid="temporary-chat-button"]')]
                    .find(element => element.getClientRects().length > 0);
                if (!button) return false;
                button.click();
                return true;
            })();
            """) { [weak self] result, _ in
                guard let self, let webView = self.webView else { return }
                if result as? Bool != true {
                    let address = leave ? "https://chatgpt.com/" : "https://chatgpt.com/?temporary-chat=true"
                    webView.load(URLRequest(url: URL(string: address)!))
                }
                self.focusComposer()
            }
    }

    fileprivate func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "drag":
            dragPanel()
        case "zoom":
            panel?.toggleMaximize()
        case "escape":
            hide(restoreFocus: true)
        case "state":
            // While the page loads, only Close shows; the page cannot use the other buttons yet.
            let ready = message["ready"] as? Bool == true
            if ready { loadingView?.stop() }
            headerButtons?.isCloseAllowed = message["close"] as? Bool ?? false
            headerButtons?.isAllowed = ready && message["buttons"] as? Bool == true
            pageIsDark = message["dark"] as? Bool
            updateAppearance()
        default:
            break
        }
    }

    /// The panel's material and buttons match the page's theme. When the page follows the system
    /// theme, so does the panel; this also keeps the page's "system" setting working, as the page
    /// takes its system theme from the panel.
    private func updateAppearance() {
        guard let panel, let pageIsDark else { return }
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        panel.appearance = pageIsDark == systemIsDark ? nil : NSAppearance(named: pageIsDark ? .darkAqua : .aqua)
    }

    /// Moves the panel with the mouse while the button that the page reported stays down.
    private func dragPanel() {
        guard let panel, let webView, NSEvent.pressedMouseButtons & 1 == 1,
              let down = NSEvent.mouseEvent(with: .leftMouseDown, location: panel.mouseLocationOutsideOfEventStream,
                                            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
                                            clickCount: 1, pressure: 1) else { return }
        panel.performDrag(with: down)
        // The page saw the press but the drag used the release; end the press in the page too.
        if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: panel.mouseLocationOutsideOfEventStream,
                                       modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
                                       clickCount: 1, pressure: 0) {
            webView.mouseUp(with: up)
        }
    }

    private func focusComposer() {
        webView?.evaluateJavaScript(QuickChatPageStyle.focusComposerScript)
    }

    /// chatgpt.com or a subdomain of it (not e.g. "notchatgpt.com").
    nonisolated static func isChatGPTHost(_ host: String) -> Bool {
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

    /// A new ChatGPT page shows a placeholder until its HTML loads; the loading view covers it
    /// until the page reports that it is ready. Other pages (such as sign-in) show as they load.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if QuickChatLocation(webView.url).isChatGPT { loadingView?.start() } else { loadingView?.stop() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        focusComposer()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingView?.stop()
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
        NSApp.activate() // a file dialog needs an active app
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
    /// Matches ChatGPT Classic's companion panel. Saved frames still take precedence;
    /// Reset Window Size (⌘O) applies these dimensions to an existing panel.
    static let defaultSize = NSSize(width: 440, height: 540)
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

/// Where the page is: an empty chat or a conversation, temporary or not.
struct QuickChatLocation {
    let isChatGPT: Bool
    let isConversation: Bool
    let isTemporary: Bool

    init(_ url: URL?) {
        let host = url?.host ?? ""
        isChatGPT = url?.scheme == "https" && QuickChatController.isChatGPTHost(host)
        let parts = url?.pathComponents ?? []
        // /c/<id>, also inside a project: /g/<project>/c/<id>
        isConversation = isChatGPT && parts.firstIndex(of: "c").map { $0 + 1 < parts.count } == true
        let query = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        isTemporary = isChatGPT && query.contains { $0.name == "temporary-chat" && $0.value == "true" }
    }
}

/// The panel's title bar buttons, in line with the page's sidebar button. Close is at the top
/// left, before the sidebar button. At the top right:
/// - Empty chat: Temporary Chat.
/// - Conversation: Open in Browser, New Chat.
/// - Temporary conversation: New Chat. The browser cannot show a temporary chat.
/// The view spans the title bar, but only its buttons take clicks; the rest goes to the page.
final class HeaderButtons: NSView {
    var onClose: (() -> Void)?
    var onOpenInBrowser: (() -> Void)?
    var onTemporaryChat: (() -> Void)?
    var onNewChat: (() -> Void)?
    /// Nothing (the sidebar, a menu, a dialog) covers the top left of the page's title bar.
    var isCloseAllowed = false { didSet { updateVisibility() } }
    /// The page has room for the buttons at the top right: it is a signed-in chat page, and
    /// nothing covers this corner.
    var isAllowed = false { didSet { updateVisibility() } }

    private(set) var close: HeaderButton!
    private(set) var openInBrowser: HeaderButton!
    private(set) var temporaryChat: HeaderButton!
    private(set) var newChat: HeaderButton!
    private let trailingButtons = NSStackView()
    private var location = QuickChatLocation(nil)

    init() {
        super.init(frame: .zero)
        close = HeaderButton(image: Self.symbol("xmark.circle"), label: "Close Quick Chat (Esc)") { [weak self] in self?.onClose?() }
        openInBrowser = HeaderButton(image: Self.openInBrowserImage, label: "Open in Browser") { [weak self] in self?.onOpenInBrowser?() }
        temporaryChat = HeaderButton(image: Self.temporaryChatImage, activeImage: Self.temporaryChatOnImage, label: "Temporary Chat") { [weak self] in self?.onTemporaryChat?() }
        newChat = HeaderButton(image: Self.newChatImage, label: "New Chat (⌘N)") { [weak self] in self?.onNewChat?() }
        trailingButtons.orientation = .horizontal
        trailingButtons.spacing = 8
        for button in [openInBrowser!, temporaryChat!, newChat!] { trailingButtons.addArrangedSubview(button) }
        for view in [close!, trailingButtons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let inset = CGFloat(QuickChatPageStyle.composerInset)
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            close.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            trailingButtons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            trailingButtons.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            heightAnchor.constraint(equalToConstant: CGFloat(QuickChatPageStyle.titleBarButtonSize) + inset * 2),
        ])
        update(for: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return view === self || view === trailingButtons ? nil : view
    }

    func update(for url: URL?) {
        location = QuickChatLocation(url)
        openInBrowser.isHidden = !location.isConversation || location.isTemporary
        temporaryChat.isHidden = location.isConversation
        temporaryChat.isActive = location.isTemporary
        newChat.isHidden = !location.isConversation
        updateVisibility()
    }

    private func updateVisibility() {
        close.isHidden = !location.isChatGPT || !isCloseAllowed
        trailingButtons.isHidden = !location.isChatGPT || !isAllowed
    }

    private static func symbol(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        return image.withSymbolConfiguration(.init(pointSize: 15, weight: .regular)) ?? image
    }

    private static func templateImage(_ draw: @escaping () -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func stroke(_ path: NSBezierPath) {
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// A window frame with a small window in its corner, like the companion window's
    /// "open in the main window" icon.
    private static let openInBrowserImage = templateImage {
        let frame = NSBezierPath()
        frame.move(to: NSPoint(x: 17, y: 8))
        frame.appendArc(withCenter: NSPoint(x: 13.5, y: 6.5), radius: 3.5, startAngle: 0, endAngle: -90, clockwise: true)
        frame.appendArc(withCenter: NSPoint(x: 6.5, y: 6.5), radius: 3.5, startAngle: -90, endAngle: -180, clockwise: true)
        frame.appendArc(withCenter: NSPoint(x: 6.5, y: 13.5), radius: 3.5, startAngle: 180, endAngle: 90, clockwise: true)
        frame.line(to: NSPoint(x: 8, y: 17))
        stroke(frame)
        let corner = NSBezierPath()
        corner.move(to: NSPoint(x: 6.5, y: 10))
        corner.appendArc(withCenter: NSPoint(x: 8, y: 8), radius: 1.5, startAngle: 180, endAngle: 270)
        corner.line(to: NSPoint(x: 10, y: 6.5))
        stroke(corner)
        stroke(NSBezierPath(roundedRect: NSRect(x: 10, y: 10, width: 7, height: 7), xRadius: 1.75, yRadius: 1.75))
    }

    /// A square, open at the top right, with a pencil, like the companion window's new chat icon.
    private static let newChatImage = templateImage {
        let square = NSBezierPath()
        square.move(to: NSPoint(x: 9.5, y: 3))
        square.appendArc(withCenter: NSPoint(x: 6.5, y: 6.5), radius: 3.5, startAngle: -90, endAngle: -180, clockwise: true)
        square.appendArc(withCenter: NSPoint(x: 6.5, y: 13.5), radius: 3.5, startAngle: 180, endAngle: 90, clockwise: true)
        square.appendArc(withCenter: NSPoint(x: 13.5, y: 13.5), radius: 3.5, startAngle: 90, endAngle: 0, clockwise: true)
        square.line(to: NSPoint(x: 17, y: 10.5))
        stroke(square)
        // The pencil points to the lower left; it is drawn along the x axis, then turned up 45°.
        let pencil = NSBezierPath()
        pencil.move(to: .zero)
        pencil.line(to: NSPoint(x: 2.4, y: -1.6))
        pencil.appendArc(withCenter: NSPoint(x: 9.6, y: 0), radius: 1.6, startAngle: -90, endAngle: 90)
        pencil.line(to: NSPoint(x: 2.4, y: 1.6))
        pencil.close()
        let place = AffineTransform(translationByX: 7, byY: 13)
        var turn = AffineTransform(rotationByDegrees: -45)
        turn.append(place)
        pencil.transform(using: turn)
        stroke(pencil)
    }

    /// A speech bubble with a dashed outline, like ChatGPT's temporary chat icon.
    private static let temporaryChatImage = templateImage {
        let bubble = NSBezierPath()
        bubble.appendArc(withCenter: NSPoint(x: 10.5, y: 9.5), radius: 7, startAngle: 140, endAngle: 470)
        bubble.lineWidth = 1.6
        bubble.lineCapStyle = .round
        bubble.setLineDash([3.1, 2.6], count: 2, phase: 0)
        bubble.stroke()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 5.2, y: 14.1))
        tail.line(to: NSPoint(x: 3.2, y: 17.2))
        tail.line(to: NSPoint(x: 7.2, y: 16.2))
        tail.lineWidth = 1.6
        tail.lineCapStyle = .round
        tail.lineJoinStyle = .round
        tail.stroke()
    }

    /// The same speech bubble, filled: a temporary chat is on.
    private static let temporaryChatOnImage = templateImage {
        NSBezierPath(ovalIn: NSRect(x: 2.7, y: 1.7, width: 15.6, height: 15.6)).fill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 5.2, y: 13.1))
        tail.line(to: NSPoint(x: 3.2, y: 17.2))
        tail.line(to: NSPoint(x: 8.2, y: 16.2))
        tail.close()
        tail.lineWidth = 1.6
        tail.lineJoinStyle = .round
        tail.fill()
        tail.stroke()
    }
}

/// The panel's web view. The panel does not activate the app, so it is often not the key window
/// when you click it. The first click then goes to the page, as in a key window, so a single
/// press on the title bar starts a drag and a single click works.
final class PanelWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A borderless icon button like the page's title bar buttons: 36 pt, 8 pt corners, a light
/// fill on hover. While active, it shows its active image (such as a filled icon).
final class HeaderButton: NSButton {
    private let onPress: () -> Void
    private let normalImage: NSImage
    private let activeImage: NSImage?
    private var isHovered = false { didSet { updateFill() } }
    var isActive = false {
        didSet {
            image = isActive ? activeImage ?? normalImage : normalImage
            updateFill()
        }
    }

    init(image: NSImage, activeImage: NSImage? = nil, label: String, onPress: @escaping () -> Void) {
        self.onPress = onPress
        normalImage = image
        self.activeImage = activeImage
        super.init(frame: .zero)
        self.image = image
        imagePosition = .imageOnly
        isBordered = false
        contentTintColor = .secondaryLabelColor
        toolTip = label
        setAccessibilityLabel(label)
        target = self
        action = #selector(press)
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false
        let size = CGFloat(QuickChatPageStyle.titleBarButtonSize)
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func press() { onPress() }

    /// One click works also while the panel is not the key window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFill()
    }

    private func updateFill() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let alpha: CGFloat = isHovered ? 0.08 : 0
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
            contentTintColor = isActive ? .labelColor : .secondaryLabelColor
        }
    }
}

/// Covers the page with the panel's material and a spinner while a page loads. It stops when
/// the page is ready, or after 15 seconds. A drag on it moves the panel.
final class LoadingView: NSVisualEffectView {
    private let spinner = NSProgressIndicator()
    private var timeout: Task<Void, Never>?

    init() {
        super.init(frame: .zero)
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .active
        isHidden = true
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var isLoading: Bool { !isHidden }

    func start() {
        alphaValue = 1
        isHidden = false
        spinner.startAnimation(nil)
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            if !Task.isCancelled { self?.stop() }
        }
    }

    func stop() {
        timeout?.cancel()
        timeout = nil
        guard isLoading else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.isHidden = true
                self.spinner.stopAnimation(nil)
            }
        })
    }

    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Page messages go to the controller; the handler does not retain it.
@MainActor
private final class PageMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var controller: QuickChatController?

    init(_ controller: QuickChatController) { self.controller = controller }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, origin.protocol == "https",
              QuickChatController.isChatGPTHost(origin.host),
              let body = message.body as? [String: Any] else { return }
        controller?.handle(body)
    }
}
