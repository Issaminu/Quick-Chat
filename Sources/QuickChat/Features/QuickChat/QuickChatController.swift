import AppKit
import WebKit

/// Floating Quick Chat in the spirit of ChatGPT Classic's companion chat: chatgpt.com in a
/// web view, which uses its compact layout at this width.
@MainActor
final class QuickChatController: NSObject {
    private static let chatURL = URL(string: "https://chatgpt.com/")!
    /// The app starts with empty drafts after a normal quit. After a crash, ChatGPT's drafts stay,
    /// so that a crash does not lose a long message. The answer is read once per launch.
    private static let startsClean: Bool = {
        let defaults = UserDefaults.standard
        let key = "QuickChat.QuitNormally"
        let quitNormally = defaults.object(forKey: key) as? Bool ?? true
        defaults.set(false, forKey: key)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            UserDefaults.standard.set(true, forKey: key)
        }
        return quitNormally
    }()
    /// Hosts that stay inside the panel (chat + sign-in flows); other links open in the browser.
    private static let inPanelHosts = ["chatgpt.com", "openai.com", "auth0.com", "google.com", "apple.com",
                                       "microsoftonline.com", "live.com", "microsoft.com"]

    private let log = Log.make("QuickChat")
    private var panel: QuickChatPanel?
    private var webView: WKWebView?
    private var headerButtons: HeaderButtons?
    private var loadingView: LoadingView?
    private var pointerWatcher: PointerWatcher?
    /// The title bar shows while the pointer is over the panel, and for a moment after it leaves.
    private(set) var isTitleBarShown = true
    /// Set while the page style is off for the current page (safe mode): what it hid.
    private(set) var pageStyleOffReason: String?
    private var hideTitleBar: Task<Void, Never>?
    /// Counts the title bar changes, so only the newest change starts its fade.
    private var titleBarChange = 0
    private var titleBarFadeStarted = 0
    private var urlObservation: NSKeyValueObservation?
    private var systemAppearanceObservation: NSKeyValueObservation?
    /// The page's theme, from its last state message.
    private var pageIsDark: Bool?
    private var previousApp: NSRunningApplication?
    /// The panel showed since the app started; the first show places it at the default position.
    private var hasShown = false
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
        if !hasShown {
            hasShown = true
            placeInitially(panel)
        }
        // The panel is non-activating: it takes key input, and the app in front stays active.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(webView)
        // No "entered" event comes when the panel appears under the pointer.
        setPointerInside(panel.frame.contains(NSEvent.mouseLocation), immediately: true)
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
        pointerWatcher = nil
        hideTitleBar?.cancel()
        hideTitleBar = nil
        isTitleBarShown = true
        urlObservation = nil
        systemAppearanceObservation = nil
        pageIsDark = nil
        crashReloads = []
        reloadOnShow = false
        hasShown = false
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
        panel.onToggleSidebar = { [weak self] in self?.toggleSidebar() }
        panel.onMaximizedChange = { [weak self] _ in self?.updateLargeState() }
        panel.waitForContent = { [weak self] width in await self?.waitForPageLayout(width: width) }
        panel.resetSizeShortcut = resetSizeShortcut
        panel.maximizeShortcut = maximizeShortcut

        let background = PanelMaterialView()
        // As the window's content view, the mask also gives the window its rounded shape and
        // shadow; without it the shadow stays rectangular and the corners look light.
        background.maskImage = Self.roundedMask(radius: CGFloat(QuickChatPageStyle.windowCornerRadius))
        background.wantsLayer = true
        background.layer?.cornerRadius = CGFloat(QuickChatPageStyle.windowCornerRadius)
        background.layer?.masksToBounds = true
        let pointerWatcher = PointerWatcher { [weak self] inside in self?.setPointerInside(inside) }
        background.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                  owner: pointerWatcher))
        self.pointerWatcher = pointerWatcher
        let webView = makeWebView()
        webView.configuration.userContentController.add(PageMessageHandler(self), name: "quickChat")
        let headerButtons = HeaderButtons()
        headerButtons.onClose = { [weak self] in self?.hide(restoreFocus: true) }
        headerButtons.onSidebar = { [weak self] in self?.toggleSidebar() }
        headerButtons.onExpand = { [weak self] in self?.panel?.expandOrShrink() }
        headerButtons.onTemporaryChat = { [weak self] in self?.toggleTemporaryChat() }
        headerButtons.onNewChat = { [weak self] in self?.newConversation() }
        let loadingView = LoadingView()
        let cover = ResizeCover()
        panel.cover = cover
        for view in [webView, cover, loadingView, headerButtons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            webView.topAnchor.constraint(equalTo: background.topAnchor),
            webView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            cover.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            cover.topAnchor.constraint(equalTo: background.topAnchor),
            cover.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            loadingView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            loadingView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            loadingView.topAnchor.constraint(equalTo: background.topAnchor),
            loadingView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            headerButtons.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            headerButtons.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            headerButtons.topAnchor.constraint(equalTo: background.topAnchor),
        ])
        panel.contentView = background

        restoreSize(of: panel)

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

    /// Keeps the saved size. The position is not kept: the first show after launch places the
    /// panel (see `show()`).
    private func restoreSize(of panel: NSPanel) {
        let saved = UserDefaults.standard.string(forKey: "NSWindow Frame \(QuickChatPanel.autosaveName)")?
            .split(separator: " ").prefix(4).compactMap { Double($0) }
        panel.setFrameAutosaveName(QuickChatPanel.autosaveName) // this can apply the saved frame
        if let saved, saved.count == 4, saved.allSatisfy({ $0.isFinite }),
           saved[2] >= panel.minSize.width, saved[3] >= panel.minSize.height {
            panel.setFrame(NSRect(origin: panel.frame.origin, size: NSSize(width: saved[2], height: saved[3])), display: false)
        }
    }

    /// The default position: centered near the bottom of the screen under the pointer.
    private func placeInitially(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = NSSize(width: min(panel.frame.width, visible.width), height: min(panel.frame.height, visible.height - 32))
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.minY + 32, width: size.width, height: size.height),
                       display: false)
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(WKUserScript(source: QuickChatPageStyle.script,
                                                                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.addUserScript(WKUserScript(source: QuickChatPageStyle.sandboxFrameScript,
                                                                injectionTime: .atDocumentStart, forMainFrameOnly: false))
        if Self.startsClean {
            config.userContentController.addUserScript(WKUserScript(source: QuickChatPageStyle.clearDraftsScript,
                                                                    injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
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
        webView.evaluateJavaScript(QuickChatPageStyle.newChatScript) { [weak self] result, error in
                guard let self else { return }
                if error != nil || result as? Bool != true {
                    self.log.error("Could not invoke ChatGPT's New chat action; loading a new chat")
                    self.webView?.load(URLRequest(url: Self.chatURL))
                } else {
                    self.focusComposer()
                }
            }
    }

    /// Opens or closes the page's sidebar with the page's own (hidden) sidebar button. The page
    /// then moves the focus to a sidebar button, which opens that button's tooltip; the panel
    /// takes the focus off it again, as a click on the page would leave no focused button.
    /// The small layout has a sidebar button in the page's title bar. The wide layout has none
    /// (its sidebar is a docked row of icons), so the page then gets its own sidebar shortcut, ⌘⇧S.
    private func toggleSidebar() {
        webView?.evaluateJavaScript(QuickChatPageStyle.toggleSidebarScript)
    }

    /// Waits until the page drew its first frame at `width`, at most 1 second: the second frame
    /// at that width starts only after the first one is drawn. A long conversation needs a few
    /// hundred milliseconds to render again at a new width.
    private func waitForPageLayout(width: CGFloat) async {
        guard let webView else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            var finished = false
            let finish = { if !finished { finished = true; done.resume() } }
            webView.callAsyncJavaScript("""
                for (let frames = 0, i = 0; i < 60 && frames < 2; i++) {
                    await new Promise(resolve => requestAnimationFrame(resolve));
                    if (Math.abs(innerWidth - width) <= 1) frames++;
                }
                """, arguments: ["width": Double(width)], in: nil, in: .page) { _ in finish() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { finish() }
        }
    }

    /// Starts or leaves a temporary chat with the page's own button, so the page stays loaded.
    /// The button shows a dashed chat bubble (with a checkmark while a temporary chat is on), in
    /// every language; its English label is a second way to find it. Without that button (a
    /// changed page), loads the matching address.
    private func toggleTemporaryChat() {
        guard let webView else { return }
        let leave = QuickChatLocation(webView.url).isTemporary
        webView.evaluateJavaScript(QuickChatPageStyle.temporaryChatScript) { [weak self] result, _ in
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
            panel?.expandOrShrink()
        case "escape":
            hide(restoreFocus: true)
        case "safeMode":
            // The page style hid the composer or the messages, so it turned itself off for this
            // page (ChatGPT changed its page). The daily page check reports the broken hooks.
            pageStyleOffReason = message["reason"] as? String ?? "unknown"
            log.error("Page style turned off: it hid the \(self.pageStyleOffReason ?? "", privacy: .public). ChatGPT changed its page.")
        case "state":
            // While the page loads, only Close shows; the page cannot use the other buttons yet.
            let ready = message["ready"] as? Bool == true
            if ready {
                loadingView?.stop()
                applyPointerState() // the page may render its document element again while it loads
            }
            headerButtons?.isLeadingAllowed = message["close"] as? Bool ?? false
            headerButtons?.isChatPage = message["chat"] as? Bool ?? false
            let left = message["left"] as? Double ?? 0
            headerButtons?.leadingInset = CGFloat(left)
            // The main area starts to the right of a docked sidebar: the page shows its wide layout.
            if let panel, panel.isPageWide != (left > 0) {
                panel.isPageWide = left > 0
                updateLargeState()
            }
            headerButtons?.hasSidebarToggle = message["sidebar"] as? Bool ?? true
            headerButtons?.isAllowed = ready && message["buttons"] as? Bool == true
            pageIsDark = message["dark"] as? Bool
            updateAppearance()
        default:
            break
        }
    }

    /// A large panel (maximized, or as wide as the page's wide layout) shows Shrink, and it
    /// always shows its title bar. A small panel shows Expand, and it hides the title bar again
    /// when the pointer is not over it.
    private func updateLargeState() {
        guard let panel else { return }
        headerButtons?.isExpanded = panel.isLarge
        setPointerInside(panel.frame.contains(NSEvent.mouseLocation))
    }

    /// In the small panel, the title bar shows while the pointer is over the panel. It hides 0.5
    /// seconds after the pointer leaves, unless the pointer comes back first. `immediately` skips
    /// that delay. In a large panel, it always shows.
    func setPointerInside(_ inside: Bool, immediately: Bool = false) {
        hideTitleBar?.cancel()
        hideTitleBar = nil
        // A large panel has room for the title bar, so it always shows there.
        if panel?.isLarge == true { return showTitleBar(true) }
        if inside || immediately { return showTitleBar(inside) }
        hideTitleBar = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { self?.showTitleBar(false) }
        }
    }

    /// All the title bar buttons are the panel's own, so one fade shows or hides all of them.
    /// The page fades the messages under the title bar with the same duration and curve. Its fade
    /// starts when the page gets the new state, so the buttons' fade starts then too. A busy page
    /// can take longer; the buttons then wait at most 0.15 seconds.
    private func showTitleBar(_ shown: Bool) {
        guard shown != isTitleBarShown else { return }
        isTitleBarShown = shown
        titleBarChange += 1
        let change = titleBarChange
        applyPointerState { [weak self] in self?.fadeTitleBar(change) }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.fadeTitleBar(change)
        }
    }

    private func fadeTitleBar(_ change: Int) {
        guard change == titleBarChange, change != titleBarFadeStarted else { return }
        titleBarFadeStarted = change
        let shown = isTitleBarShown
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            headerButtons?.animator().alphaValue = shown ? 1 : 0
        }
    }

    /// `applied` runs when the page has the new state (or could not get it).
    private func applyPointerState(applied: (@MainActor () -> Void)? = nil) {
        let value = isTitleBarShown ? "inside" : "outside"
        guard let webView else { applied?(); return }
        webView.evaluateJavaScript("document.documentElement.dataset.quickChatPointer = '\(value)'") { _, _ in applied?() }
    }

    /// The panel's material and buttons match the page's theme. When the page follows the system
    /// theme, so does the panel; this also keeps the page's "system" setting working, as the page
    /// takes its system theme from the panel.
    private func updateAppearance() {
        guard let panel, let pageIsDark else { return }
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        panel.appearance = pageIsDark == systemIsDark ? nil : NSAppearance(named: pageIsDark ? .darkAqua : .aqua)
        // The loading view and the resize cover match the panel's background.
        for case let view as PanelMaterialView in [panel.contentView] + (panel.contentView?.subviews ?? []) {
            view.isLight = !pageIsDark
        }
    }

    /// Moves the panel with the mouse while the button that the page reported stays down. A fast
    /// drag throws the panel to a side of the screen (see PanelThrow).
    private func dragPanel() {
        guard let panel, let webView else { return }
        // The page saw the press but the drag used the release; end the press in the page too.
        if let up = panel.trackDrag() { webView.mouseUp(with: up) }
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
        pageStyleOffReason = nil // a new page starts with the style on
        applyPointerState()
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
