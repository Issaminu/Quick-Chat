// Signs in the daily page check's test account in a small window and writes its chatgpt.com
// cookies to a file (as JSON, for scripts/check-page-hooks.swift). Run it through
// scripts/renew-page-check-session.sh, which stores the file as the CHATGPT_SESSION secret.
//
// renew-page-check-session OUTPUT.json [--cookies EXISTING.json]
// --cookies starts with an existing session (to test this tool without a new sign-in).
import AppKit
import WebKit

@main
@MainActor
enum RenewSession {
    static var window: NSWindow?

    static func main() {
        NSApplication.shared.setActivationPolicy(.regular)
        Task { await run() }
        NSApplication.shared.run()
    }

    static func run() async {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else { print("usage: renew-page-check-session OUTPUT.json"); exit(4) }
        let output = URL(fileURLWithPath: arguments[1])
        let store = WKWebsiteDataStore.nonPersistent()
        if let index = arguments.firstIndex(of: "--cookies"), index + 1 < arguments.count,
           let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[index + 1])),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for item in list {
                var properties: [HTTPCookiePropertyKey: Any] = [.name: item["name"] ?? "", .value: item["value"] ?? "",
                                                                .domain: item["domain"] ?? "", .path: item["path"] as? String ?? "/"]
                if item["secure"] as? Bool == true { properties[.secure] = "TRUE" }
                if let cookie = HTTPCookie(properties: properties) { await store.httpCookieStore.setCookie(cookie) }
            }
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 720), configuration: configuration)
        let window = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Sign in with the page check's test account"
        window.contentView = web
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        Self.window = window
        web.load(URLRequest(url: URL(string: "https://chatgpt.com/auth/login")!))
        print("Sign in with the test account in the window. The window closes by itself after the sign-in.")

        // Wait for a signed-in chatgpt.com page (at most 15 minutes).
        let end = Date().addingTimeInterval(15 * 60)
        while Date() < end {
            try? await Task.sleep(for: .seconds(2))
            guard window.isVisible else { print("The window was closed before the sign-in."); exit(4) }
            guard web.url?.host == "chatgpt.com" else { continue }
            let signedIn = try? await web.callAsyncJavaScript(
                "try { const s = await (await fetch('/api/auth/session')).json(); return !!(s && s.user); } catch { return false; }",
                arguments: [:], in: nil, contentWorld: .page) as? Bool
            guard signedIn == true else { continue }

            // Cloudflare's cookies belong to this Mac's address, so they stay out.
            let cookies = await store.httpCookieStore.allCookies().filter {
                ($0.domain.hasSuffix("chatgpt.com") || $0.domain.hasSuffix("openai.com")) &&
                    !["cf_clearance", "__cf_bm", "_cfuvid"].contains($0.name)
            }
            let list: [[String: Any]] = cookies.map { cookie in
                var item: [String: Any] = ["name": cookie.name, "value": cookie.value, "domain": cookie.domain,
                                           "path": cookie.path, "secure": cookie.isSecure, "httpOnly": cookie.isHTTPOnly]
                if let date = cookie.expiresDate { item["expires"] = date.timeIntervalSince1970 }
                if let policy = cookie.sameSitePolicy { item["sameSite"] = policy.rawValue.capitalized }
                return item
            }
            do {
                let data = try JSONSerialization.data(withJSONObject: list)
                FileManager.default.createFile(atPath: output.path, contents: data, attributes: [.posixPermissions: 0o600])
            } catch {
                print("Could not write the session: \(error.localizedDescription)")
                exit(4)
            }
            let session = cookies.first { $0.name.hasPrefix("__Secure-next-auth.session-token") }
            let expiry = session?.expiresDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "unknown"
            print("Signed in. Saved \(cookies.count) cookies. The session expires on \(expiry).")
            exit(0)
        }
        print("No sign-in after 15 minutes.")
        exit(4)
    }
}
