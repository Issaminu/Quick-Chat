// The daily page check: opens the live chatgpt.com with a test account, in the same WebKit and
// with the same page style as the panel, and runs every check in PageHooks on the pages that it
// names. Run from the repository root:
//
// swiftc -swift-version 6 -parse-as-library Sources/QuickChat/Features/QuickChat/QuickChatPageStyle.swift \
//     Sources/QuickChat/Features/QuickChat/PageHooks.swift scripts/check-page-hooks.swift -o /tmp/check-page-hooks
// /tmp/check-page-hooks --cookies session.json --conversation https://chatgpt.com/c/... --out page-check
//
// --cookies: the test account's chatgpt.com cookies, as a JSON list of {name, value, domain,
//   path, expires, secure, httpOnly, sameSite} (scripts/renew-page-check-session.swift makes it).
// --conversation: a conversation of the test account to open (read only). Without it, the check
//   opens the newest conversation that the page links to.
// --out: a folder for report.md, result.json and a screenshot of each page.
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

    static func run() async -> Outcome {
        guard let cookiesPath = argument("--cookies"), let out = argument("--out") else {
            print("usage: check-page-hooks --cookies FILE [--conversation URL] --out FOLDER")
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
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 440, height: 540), configuration: configuration)
        web.navigationDelegate = messages
        let window = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
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
            let loaded = await load(address, in: web, messages: messages, chatPage: true)
            await screenshot(web, to: folder.appendingPathComponent("\(page.rawValue).png"))
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
                let script = PageHooks.checkScript(for: page)
                let raw = try? await web.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page) as? String
                let parsed = (raw.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]) ?? [:]
                let results = parsed["result"] as? [String: Bool] ?? [:]
                pages[page.rawValue] = [
                    "status": loaded == .ready ? "checked" : "checked (the page did not report ready)",
                    "results": results, "errors": parsed["errors"] as? [String: String] ?? [:],
                    "safeMode": messages.safeMode as Any,
                ]
                for (id, works) in results.sorted(by: { $0.key < $1.key }) {
                    print("\(works ? "PASS" : "FAIL") \(page.rawValue): \(id)")
                }
                if results.isEmpty { print("FAIL \(page.rawValue): the checks did not run") }
            }
            if outcome == .blocked || outcome == .session { break }
        }

        // A hook is broken when its check fails on any page where it ran.
        var broken: [PageHooks.Hook: [String]] = [:]
        if outcome == .ok {
            for (page, info) in pages {
                guard let results = info["results"] as? [String: Bool] else { continue }
                if results.isEmpty { // the checks themselves did not run
                    pages[page]?["note"] = "The checks did not run on this page."
                    outcome = .failed
                }
                for (id, works) in results where !works {
                    if let hook = PageHooks.all.first(where: { $0.id == id }) { broken[hook, default: []].append(page) }
                }
            }
            if !broken.isEmpty, outcome == .ok { outcome = .broken }
        }

        let report = markdown(outcome: outcome, broken: broken, pages: pages)
        try? report.write(to: folder.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
        let summary: [String: Any] = [
            "outcome": outcome.rawValue,
            "broken": broken.keys.map(\.id).sorted(),
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

    static func screenshot(_ web: WKWebView, to url: URL) async {
        guard let image = try? await web.takeSnapshot(configuration: nil), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    static func markdown(outcome: Outcome, broken: [PageHooks.Hook: [String]], pages: [String: [String: Any]]) -> String {
        var lines: [String] = []
        switch outcome {
        case .ok:
            lines.append("All \(PageHooks.all.count) page hooks work on the live chatgpt.com.")
        case .broken:
            lines.append("ChatGPT changed its page. \(broken.count) of the \(PageHooks.all.count) page hooks that Quick Chat uses no longer work.")
            lines.append("")
            lines.append("| Hook | Page | Used for | What users see |")
            lines.append("|---|---|---|---|")
            for (hook, onPages) in broken.sorted(by: { $0.key.id < $1.key.id }) {
                lines.append("| `\(hook.id)` | \(onPages.sorted().joined(separator: ", ")) | \(hook.usedFor) | \(hook.ifBroken) |")
            }
            let errors = pages.flatMap { page, info in
                ((info["errors"] as? [String: String]) ?? [:]).map { "- `\($0.key)` on \(page): \($0.value)" }
            }.sorted()
            if !errors.isEmpty {
                lines.append("")
                lines.append("Errors from the checks:")
                lines.append(contentsOf: errors)
            }
            lines.append("")
            lines.append("To fix: compare each hook's check in `Sources/QuickChat/Features/QuickChat/PageHooks.swift` with the live page, and update the hook there and in `QuickChatPageStyle.swift`. The run's artifact has a screenshot of each page.")
        case .blocked:
            lines.append("The page check could not reach ChatGPT: the site blocked it. Nothing is known about the page hooks today.")
        case .session:
            lines.append("The page check's test account is not signed in: its session expired. To renew it, run `scripts/renew-page-check-session.sh` on a Mac and sign in with the test account.")
        case .failed:
            lines.append("The page check could not run.")
        }
        lines.append("")
        lines.append("| Page | Result |")
        lines.append("|---|---|")
        for page in PageHooks.Page.allCases {
            guard let info = pages[page.rawValue] else { continue }
            let results = info["results"] as? [String: Bool] ?? [:]
            let note = info["note"] as? String
            let summary = results.isEmpty ? (note ?? info["status"] as? String ?? "") :
                "\(results.values.filter { $0 }.count) of \(results.count) checks pass" + ((info["safeMode"] as? String).map { "; safe mode turned the style off (it hid the \($0))" } ?? "")
            lines.append("| \(page.rawValue) | \(summary) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension PageHooks.Hook: Hashable {
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
