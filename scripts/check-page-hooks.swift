// The daily page check: opens the live chatgpt.com with a test account, in the same WebKit and
// with the same page style as the panel. On each page it runs:
// - the screen checks (scripts/PageVisualCheck.swift): the areas of the panel that must be empty
//   (the title bar, around the composer) show nothing from the page;
// - every check in PageHooks for that page.
// A page with a failed check loads again for a second try; a check is broken only when it fails
// both times. Run from the repository root:
//
// swiftc -swift-version 6 -parse-as-library Sources/QuickChat/Features/QuickChat/QuickChatPageStyle.swift \
//     Sources/QuickChat/Features/QuickChat/PageHooks.swift scripts/PageVisualCheck.swift scripts/check-page-hooks.swift \
//     -o /tmp/check-page-hooks
// /tmp/check-page-hooks --cookies session.json --conversation https://chatgpt.com/c/... --out page-check
//
// --cookies: the test account's chatgpt.com cookies, as a JSON list of {name, value, domain,
//   path, expires, secure, httpOnly, sameSite} (scripts/renew-page-check-session.swift makes it).
// --conversation: a conversation of the test account to open (read only). Without it, the check
//   opens the newest conversation that the page links to.
// --previous, --previous-url: result.json of the last passing run, and a link to that run. The
//   report then lists the page's data-* attribute names that are gone or new since then.
// --out: a folder for report.md, result.json, an image of each page as the panel shows it, and a
//   marked image of each failed screen check.
//
// Exit status: 0 all hooks work, 1 some hooks are broken, 2 the site blocked the check (for
// example a Cloudflare challenge), 3 the session is not signed in (renew the session secret),
// 4 the check could not run.
import AppKit
import WebKit

@MainActor
final class PageMessages: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var state: [String: Any] = [:]
    var safeMode: String?
    var status = 0
    var finished = false

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
        switch body["type"] as? String {
        case "state": state = body
        case "safeMode": safeMode = body["reason"] as? String ?? "unknown"
        default: break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse {
            status = response.statusCode
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finished = true }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { finished = true }
}

enum Outcome: String {
    case ok, broken, blocked, session, failed
    var exitCode: Int32 { [.ok: 0, .broken: 1, .blocked: 2, .session: 3, .failed: 4][self]! }
}

@main
@MainActor
enum PageHookCheck {
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Task {
            let outcome = await run()
            exit(outcome.exitCode)
        }
        NSApplication.shared.run()
    }

    static func argument(_ name: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// What one look at a page found.
    struct PageRun {
        var results: [String: Bool] = [:]
        var errors: [String: String] = [:]
        var findings: [PageVisualCheck.Finding] = []
        /// The names of the page's data-* attributes.
        var attributes: [String] = []
        var safeMode: String?

        /// The failed hooks, and `screen:<area>` for each failed screen check.
        var failures: Set<String> {
            Set(results.filter { !$0.value }.map(\.key)).union(findings.map { "screen:\($0.area.id)" })
        }
    }

    /// The names of the page's data-* attributes (not Quick Chat's own).
    static let attributesScript = """
        return JSON.stringify([...new Set([...document.querySelectorAll("*")].flatMap(e => e.getAttributeNames()
            .filter(n => n.startsWith("data-") && !n.startsWith("data-quick-chat"))))].sort());
        """

    /// The screen checks first (the hook checks open and close the sidebar and scroll), then the
    /// page's attributes, then the hook checks.
    static func examine(_ page: PageHooks.Page, web: WKWebView, messages: PageMessages, folder: URL) async -> PageRun {
        var run = PageRun()
        run.findings = await PageVisualCheck.check(web, prefix: "\(page.rawValue)-screen", folder: folder)
        let names = try? await web.callAsyncJavaScript(attributesScript, arguments: [:], in: nil, contentWorld: .page) as? String
        run.attributes = (names.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String]) ?? []
        let raw = try? await web.callAsyncJavaScript(PageHooks.checkScript(for: page), arguments: [:], in: nil, contentWorld: .page) as? String
        let parsed = (raw.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]) ?? [:]
        run.results = parsed["result"] as? [String: Bool] ?? [:]
        run.errors = parsed["errors"] as? [String: String] ?? [:]
        run.safeMode = messages.safeMode
        return run
    }

    static func run() async -> Outcome {
        guard let cookiesPath = argument("--cookies"), let out = argument("--out") else {
            print("usage: check-page-hooks --cookies FILE [--conversation URL] [--previous FILE --previous-url URL] --out FOLDER")
            return .failed
        }
        let folder = URL(fileURLWithPath: out, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let messages = PageMessages()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: QuickChatPageStyle.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(
            source: QuickChatPageStyle.sandboxFrameScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        configuration.userContentController.add(messages, name: "quickChat")
        // The page loads several hundred files; the browser's resource list keeps 250 by default.
        configuration.userContentController.addUserScript(WKUserScript(
            source: "performance.setResourceTimingBufferSize(100000);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 440, height: 540), configuration: configuration)
        web.navigationDelegate = messages
        // Transparent like the panel, for the screen checks.
        PageVisualCheck.prepare(web)
        let window = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = web
        window.orderFront(nil)

        // The session. The values are never printed.
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: cookiesPath))
            let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            for item in list {
                guard let name = item["name"] as? String, let value = item["value"] as? String,
                      let domain = item["domain"] as? String else { continue }
                var properties: [HTTPCookiePropertyKey: Any] = [
                    .name: name, .value: value, .domain: domain, .path: item["path"] as? String ?? "/",
                ]
                if item["secure"] as? Bool == true { properties[.secure] = "TRUE" }
                if let expires = item["expires"] as? Double, expires > 0 { properties[.expires] = Date(timeIntervalSince1970: expires) }
                if let sameSite = item["sameSite"] as? String { properties[.sameSitePolicy] = sameSite.lowercased() }
                if item["httpOnly"] as? Bool == true { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
                if let cookie = HTTPCookie(properties: properties) {
                    await configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                }
            }
            print("Loaded \(list.count) cookies")
        } catch {
            print("Could not read the cookies: \(error.localizedDescription)")
            return .failed
        }

        var pages: [String: [String: Any]] = [:]
        var runs: [PageHooks.Page: PageRun] = [:]
        /// Checks that failed on one try and passed on the other: page → ids.
        var unsteady: [PageHooks.Page: [String]] = [:]
        var outcome = Outcome.ok
        var conversation = argument("--conversation")
        for page in PageHooks.Page.allCases {
            let size = page == .wide ? NSSize(width: 900, height: 540) : NSSize(width: 440, height: 540)
            window.setContentSize(size)
            web.frame = NSRect(origin: .zero, size: size)
            let address: String
            switch page {
            case .home, .wide: address = "https://chatgpt.com/"
            case .temporary: address = "https://chatgpt.com/?temporary-chat=true"
            case .conversation:
                guard let conversation else {
                    pages[page.rawValue] = ["status": "skipped", "note": "The test account has no conversation to open."]
                    continue
                }
                address = conversation
            }
            print("Opening the \(page.rawValue) page")
            var loaded = await load(address, in: web, messages: messages, chatPage: true)
            if let png = await PageVisualCheck.panelImage(web) { try? png.write(to: folder.appendingPathComponent("\(page.rawValue).png")) }
            switch loaded {
            case .blocked(let note):
                pages[page.rawValue] = ["status": "blocked", "note": note]
                outcome = .blocked
            case .signedOut:
                pages[page.rawValue] = ["status": "signed out", "note": "The page is not signed in."]
                outcome = .session
            case .ready, .notReady:
                if page == .home, conversation == nil {
                    conversation = try? await web.evaluateJavaScript(
                        "document.querySelector('a[href^=\"/c/\"]')?.href ?? null") as? String
                }
                var run = await examine(page, web: web, messages: messages, folder: folder)
                // A second try before a failure counts: a slow load or a short test of ChatGPT
                // can fail a check once. A check is broken only when it fails both times.
                if !run.failures.isEmpty {
                    print("Some checks failed on the \(page.rawValue) page: \(run.failures.sorted().joined(separator: ", ")). Loading it again for a second try.")
                    loaded = await load(address, in: web, messages: messages, chatPage: true)
                    if loaded == .ready || loaded == .notReady {
                        let second = await examine(page, web: web, messages: messages, folder: folder)
                        let both = run.failures.intersection(second.failures)
                        unsteady[page] = run.failures.symmetricDifference(second.failures).sorted()
                        var merged = second
                        for (id, works) in run.results { merged.results[id] = works || second.results[id] == true }
                        merged.findings = second.findings.filter { both.contains("screen:\($0.area.id)") }
                        merged.errors = second.errors.filter { both.contains($0.key) }
                        run = merged
                    }
                }
                runs[page] = run
                pages[page.rawValue] = [
                    "status": loaded == .ready ? "checked" : "checked (the page did not report ready)",
                    "results": run.results, "errors": run.errors,
                    "screen": run.findings.map { ["area": $0.area.id, "pixels": $0.drawnPixels, "share": $0.share, "painters": $0.painters, "image": $0.image as Any] },
                    "attributes": run.attributes,
                    "unsteady": unsteady[page] ?? [],
                    "safeMode": run.safeMode as Any,
                ]
                for (id, works) in run.results.sorted(by: { $0.key < $1.key }) {
                    print("\(works ? "PASS" : "FAIL") \(page.rawValue): \(id)")
                }
                for finding in run.findings {
                    print("FAIL \(page.rawValue): screen: the page draws \(finding.area.name) (\(finding.drawnPixels) pixels)")
                    for painter in finding.painters { print("    \(painter)") }
                }
                for id in unsteady[page] ?? [] { print("NOTE \(page.rawValue): \(id) failed on one try only") }
                if run.results.isEmpty { print("FAIL \(page.rawValue): the checks did not run") }
            }
            if outcome == .blocked || outcome == .session { break }
        }

        // A hook is broken when its check fails on any page where it ran (both tries).
        var broken: [PageHooks.Hook: [String]] = [:]
        if outcome == .ok {
            for (page, run) in runs {
                if run.results.isEmpty { // the checks themselves did not run
                    pages[page.rawValue]?["note"] = "The checks did not run on this page."
                    outcome = .failed
                }
                for (id, works) in run.results where !works {
                    if let hook = PageHooks.all.first(where: { $0.id == id }) { broken[hook, default: []].append(page.rawValue) }
                }
            }
            if outcome == .ok, !broken.isEmpty || runs.values.contains(where: { !$0.findings.isEmpty }) { outcome = .broken }
        }

        let previous = argument("--previous").flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let changes = attributeChanges(runs: runs, previous: previous)
        let report = markdown(outcome: outcome, broken: broken, runs: runs, pages: pages, unsteady: unsteady,
                              changes: changes, previousURL: argument("--previous-url"))
        try? report.write(to: folder.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
        let screen = runs.flatMap { page, run in run.findings.map { "screen:\(page.rawValue)/\($0.area.id)" } }
        let summary: [String: Any] = [
            "outcome": outcome.rawValue,
            "broken": (broken.keys.map(\.id) + screen).sorted(),
            "pages": pages,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("result.json"))
        }
        print("Outcome: \(outcome.rawValue)")
        return outcome
    }

    enum Loaded: Equatable { case ready, notReady, signedOut, blocked(String) }

    /// Loads `address` and waits until the page reports a ready chat page (at most 45 seconds),
    /// then 6 seconds more: the page style's safe mode checks the page 1.5 and 5 seconds after it
    /// loads.
    static func load(_ address: String, in web: WKWebView, messages: PageMessages, chatPage: Bool) async -> Loaded {
        messages.state = [:]
        messages.safeMode = nil
        messages.status = 0
        messages.finished = false
        web.load(URLRequest(url: URL(string: address)!))
        let end = Date().addingTimeInterval(45)
        while Date() < end {
            if messages.state["ready"] as? Bool == true, messages.state["chat"] as? Bool == true || messages.safeMode != nil { break }
            if messages.finished, let blocked = await blockedNote(web, status: messages.status) { return .blocked(blocked) }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if let blocked = await blockedNote(web, status: messages.status) { return .blocked(blocked) }
        try? await Task.sleep(for: .seconds(6))
        let signedIn = try? await web.callAsyncJavaScript(
            "try { const session = await (await fetch('/api/auth/session')).json(); return !!(session && session.user); } catch { return null; }",
            arguments: [:], in: nil, contentWorld: .page) as? Bool
        if signedIn == false { return .signedOut }
        return messages.state["ready"] as? Bool == true ? .ready : .notReady
    }

    /// A note when the page is a block or a challenge page instead of ChatGPT.
    static func blockedNote(_ web: WKWebView, status: Int) async -> String? {
        let page = try? await web.evaluateJavaScript("""
            JSON.stringify({ title: document.title, challenge: !!document.querySelector('#challenge-form, #challenge-running, #cf-challenge-running, .cf-browser-verification, iframe[src*="challenges.cloudflare.com"]') })
            """) as? String
        let info = (page.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]) ?? [:]
        let title = info["title"] as? String ?? ""
        if info["challenge"] as? Bool == true || title.range(of: "just a moment|attention required|access denied", options: [.regularExpression, .caseInsensitive]) != nil {
            return "The site showed a challenge page (\"\(title)\", HTTP \(status))."
        }
        if status == 403 || status == 429 { return "The site answered HTTP \(status)." }
        return nil
    }

    /// The data-* attribute names that are gone or new on each page since the last passing run.
    struct Changes {
        var gone: [String: [String]] = [:]
        var added: [String: [String]] = [:]
        var known = false
        var isEmpty: Bool { gone.values.allSatisfy(\.isEmpty) && added.values.allSatisfy(\.isEmpty) }
    }

    static func attributeChanges(runs: [PageHooks.Page: PageRun], previous: [String: Any]?) -> Changes {
        var changes = Changes()
        guard let pages = previous?["pages"] as? [String: [String: Any]] else { return changes }
        for (page, run) in runs where !run.attributes.isEmpty {
            guard let before = pages[page.rawValue]?["attributes"] as? [String] else { continue }
            changes.known = true
            let old = Set(before), new = Set(run.attributes)
            changes.gone[page.rawValue] = old.subtracting(new).sorted()
            changes.added[page.rawValue] = new.subtracting(old).sorted()
        }
        return changes
    }

    /// The style, the page script and the hook checks: the text where Quick Chat names the
    /// page's attributes.
    static let quickChatSource = QuickChatPageStyle.css + QuickChatPageStyle.script + QuickChatPageStyle.newChatScript
        + QuickChatPageStyle.toggleSidebarScript + PageHooks.all.map(\.check).joined(separator: "\n")

    /// True when Quick Chat names `attribute` (as a whole name).
    static func quickChatUses(_ attribute: String) -> Bool {
        var start = quickChatSource.startIndex
        while let range = quickChatSource.range(of: attribute, range: start..<quickChatSource.endIndex) {
            let next = range.upperBound < quickChatSource.endIndex ? quickChatSource[range.upperBound] : " "
            if !(next.isLetter || next.isNumber || next == "-" || next == "_") { return true }
            start = range.upperBound
        }
        return false
    }

    /// What users see when the page draws in an area that must be empty.
    static func screenEffect(_ area: String) -> String {
        switch area {
        case "title-bar": "Something from the page shows in the title bar, next to or under the panel's own buttons."
        case "above-composer": "Something shows above the composer in the empty chat (for example a greeting or a notice)."
        default: "Something from the page shows around the composer (for example a dark band), where only the panel's material must show."
        }
    }

    static func markdown(outcome: Outcome, broken: [PageHooks.Hook: [String]], runs: [PageHooks.Page: PageRun],
                         pages: [String: [String: Any]], unsteady: [PageHooks.Page: [String]],
                         changes: Changes, previousURL: String?) -> String {
        var lines: [String] = []
        let screen = PageHooks.Page.allCases.flatMap { page in (runs[page]?.findings ?? []).map { (page, $0) } }
        switch outcome {
        case .ok:
            lines.append("All \(PageHooks.all.count) page hooks work on the live chatgpt.com, and the screen checks pass.")
        case .broken:
            var parts: [String] = []
            if !broken.isEmpty { parts.append("\(broken.count) of the \(PageHooks.all.count) page hooks that Quick Chat uses no longer work") }
            if !screen.isEmpty { parts.append("\(screen.count) screen \(screen.count == 1 ? "check fails" : "checks fail")") }
            lines.append("**ChatGPT changed its page.** " + parts.joined(separator: ", and ") + ".")
            lines.append("")
            lines.append("### What users see")
            lines.append("")
            for (hook, onPages) in broken.sorted(by: { $0.key.id < $1.key.id }) {
                lines.append("- \(hook.ifBroken) (hook `\(hook.id)`, on \(onPages.sorted().joined(separator: ", ")))")
            }
            for (page, finding) in screen {
                lines.append("- \(screenEffect(finding.area.id)) (screen check, \(page.rawValue): \(finding.area.name))")
            }
            if !broken.isEmpty {
                lines.append("")
                lines.append("### Broken hooks")
                lines.append("")
                lines.append("| Hook | Pages | Used for |")
                lines.append("|---|---|---|")
                for (hook, onPages) in broken.sorted(by: { $0.key.id < $1.key.id }) {
                    lines.append("| `\(hook.id)` | \(onPages.sorted().joined(separator: ", ")) | \(hook.usedFor) |")
                }
                let errors = runs.flatMap { page, run in run.errors.map { "- `\($0.key)` on \(page.rawValue): \($0.value)" } }.sorted()
                if !errors.isEmpty {
                    lines.append("")
                    lines.append("Errors from the checks:")
                    lines.append(contentsOf: errors)
                }
            }
            if !screen.isEmpty {
                lines.append("")
                lines.append("### Screen checks that fail")
                lines.append("")
                lines.append("These areas must show only the panel's material, but the page draws in them.")
                for (page, finding) in screen {
                    lines.append("")
                    lines.append("**\(page.rawValue): \(finding.area.name)**: \(finding.drawnPixels) drawn pixels (\(Int((finding.share * 100).rounded())) % of the area)."
                                 + (finding.image.map { " The artifact has a marked image: `\($0)` (drawn pixels in red)." } ?? ""))
                    if finding.painters.isEmpty {
                        lines.append("No element draws there by itself: look at the image.")
                    } else {
                        lines.append("Elements that can draw there (the first is often the cause):")
                        lines.append(contentsOf: finding.painters.map { "- \($0)" })
                    }
                }
            }
        case .blocked:
            lines.append("The page check could not reach ChatGPT: the site blocked it. Nothing is known about the page hooks today.")
        case .session:
            lines.append("The page check's test account is not signed in: its session expired. To renew it, run `scripts/renew-page-check-session.sh` on a Mac and sign in with the test account.")
        case .failed:
            lines.append("The page check could not run.")
        }

        if changes.known, !changes.isEmpty {
            lines.append("")
            lines.append(outcome == .ok ? "### Early warning: the page changed" : "### Changes in the page since the last passing check")
            lines.append("")
            lines.append("The `data-*` attribute names that are gone or new since \(previousURL.map { "[the last passing run](\($0))" } ?? "the last passing run"). **Bold** names are in Quick Chat's style or checks.")
            lines.append("")
            lines.append("| Page | Gone | New |")
            lines.append("|---|---|---|")
            let format: ([String]) -> String = { names in
                guard !names.isEmpty else { return "" }
                let shown = names.prefix(30).map { quickChatUses($0) ? "**`\($0)`**" : "`\($0)`" }.joined(separator: " ")
                return names.count > 30 ? shown + " and \(names.count - 30) more" : shown
            }
            for page in PageHooks.Page.allCases {
                let gone = changes.gone[page.rawValue] ?? [], added = changes.added[page.rawValue] ?? []
                if gone.isEmpty, added.isEmpty { continue }
                lines.append("| \(page.rawValue) | \(format(gone)) | \(format(added)) |")
            }
        }

        let retried = PageHooks.Page.allCases.flatMap { page in (unsteady[page] ?? []).map { "`\($0)` on \(page.rawValue)" } }
        if !retried.isEmpty {
            lines.append("")
            lines.append("Failed on one of two tries only (not counted as broken): \(retried.joined(separator: ", ")).")
        }

        lines.append("")
        lines.append("| Page | Hooks | Screen checks |")
        lines.append("|---|---|---|")
        for page in PageHooks.Page.allCases {
            guard let info = pages[page.rawValue] else { continue }
            guard let run = runs[page] else {
                lines.append("| \(page.rawValue) | \(info["note"] as? String ?? info["status"] as? String ?? "") | |")
                continue
            }
            let hooks = run.results.isEmpty ? (info["note"] as? String ?? "did not run") :
                "\(run.results.values.filter { $0 }.count) of \(run.results.count) pass" + (run.safeMode.map { "; safe mode turned the style off (it hid the \($0))" } ?? "")
            let areas = run.findings.isEmpty ? "pass" : "fail: " + run.findings.map(\.area.name).joined(separator: ", ")
            lines.append("| \(page.rawValue) | \(hooks) | \(areas) |")
        }
        if outcome == .broken {
            lines.append("")
            lines.append("### To fix")
            lines.append("")
            lines.append("1. Download the run's artifact. It has an image of each page as the panel shows it, and the marked images of the failed screen checks.")
            lines.append("2. Use the changed attribute names and the elements above to find what ChatGPT changed.")
            lines.append("3. Update the hook in `Sources/QuickChat/Features/QuickChat/PageHooks.swift` and the style in `QuickChatPageStyle.swift`. Prefer a rule that keeps only what the panel needs, so that new page elements stay hidden.")
            lines.append("4. Add the new page structure to `scripts/check-page-style.swift`, and run `python3 scripts/check-live.py` to check the real page.")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension PageHooks.Hook: Hashable {
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
