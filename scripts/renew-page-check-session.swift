// Signs in the daily page check's test account and writes its chatgpt.com cookies to a file (as
// JSON, for scripts/check-page-hooks.swift).
//
// renew-page-check-session OUTPUT.json [--cookies EXISTING.json]
//   Shows a small window. You sign in. scripts/renew-page-check-session.sh uses this mode and
//   stores the file as the CHATGPT_SESSION secret. --cookies starts with an existing session (to
//   test this tool without a new sign-in).
// renew-page-check-session OUTPUT.json --auto
//   Signs in without a person, with CHATGPT_TEST_ACCOUNT_EMAIL and CHATGPT_TEST_ACCOUNT_PASSWORD
//   from the environment. The page check workflow uses this mode when the session expired. It
//   stops when the sign-in needs a person: a bot check, a code or a second factor. It never
//   tries to get past a bot check.
//
// Exit status: 0 signed in, 5 the sign-in needs a person, 4 an error. The last line of the
// output tells why. The output never contains page text, so it cannot show the email address.
import AppKit
import WebKit

@main
@MainActor
enum RenewSession {
    static var window: NSWindow?

    static func main() {
        let auto = CommandLine.arguments.contains("--auto")
        NSApplication.shared.setActivationPolicy(auto ? .accessory : .regular)
        Task { await run(auto: auto) }
        NSApplication.shared.run()
    }

    static func run(auto: Bool) async {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else { print("usage: renew-page-check-session OUTPUT.json [--auto]"); exit(4) }
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
        let window = NSWindow(contentRect: web.frame, styleMask: auto ? .borderless : [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Sign in with the page check's test account"
        window.contentView = web
        Self.window = window
        if auto {
            window.orderFront(nil)
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        web.load(URLRequest(url: URL(string: "https://chatgpt.com/auth/login")!))

        if auto {
            let environment = ProcessInfo.processInfo.environment
            guard let email = environment["CHATGPT_TEST_ACCOUNT_EMAIL"], !email.isEmpty,
                  let password = environment["CHATGPT_TEST_ACCOUNT_PASSWORD"], !password.isEmpty else {
                print("CHATGPT_TEST_ACCOUNT_EMAIL and CHATGPT_TEST_ACCOUNT_PASSWORD must be set.")
                exit(4)
            }
            await signIn(web, email: email, password: password)
        } else {
            print("Sign in with the test account in the window. The window closes by itself after the sign-in.")
            let end = Date().addingTimeInterval(15 * 60)
            while Date() < end {
                try? await Task.sleep(for: .seconds(2))
                guard window.isVisible else { print("The window was closed before the sign-in."); exit(4) }
                if await signedIn(web) { await save(store, to: output) }
            }
            print("No sign-in after 15 minutes.")
            exit(4)
        }
        await save(store, to: output)
    }

    static func signedIn(_ web: WKWebView) async -> Bool {
        guard web.url?.host == "chatgpt.com" else { return false }
        let answer = try? await web.callAsyncJavaScript(
            "try { const s = await (await fetch('/api/auth/session', { cache: 'no-store' })).json(); return !!(s && s.user); } catch { return false; }",
            arguments: [:], in: nil, contentWorld: .page) as? Bool
        return answer == true
    }

    /// Looks at the sign-in page and does the next step: it presses Log in, or types the email or
    /// the password and continues. The values go in as arguments, never as script text.
    static let stepScript = """
        const shown = element => !!element && !element.disabled && element.getClientRects().length > 0;
        const text = (document.title + ' ' + (document.body ? document.body.innerText : '')).slice(0, 4000);
        if (document.querySelector('iframe[src*="challenges.cloudflare.com"], iframe[src*="arkoselabs"], iframe[src*="hcaptcha"], iframe[src*="recaptcha"], #challenge-form, #cf-challenge-running')
            || /just a moment|attention required|verify you are human/i.test(text)) return 'challenge';
        const code = document.querySelector('input[autocomplete="one-time-code"], input[name="code"], input[name="otp"]');
        if (shown(code) || /check your inbox|enter the code|verification code|authenticator/i.test(text)) return 'code';
        const type = (input, value) => {
            Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, value);
            input.dispatchEvent(new Event('input', { bubbles: true }));
            input.dispatchEvent(new Event('change', { bubbles: true }));
        };
        const send = input => {
            const form = input.closest('form');
            const button = (form && form.querySelector('button[type="submit"]'))
                || [...document.querySelectorAll('button')].find(b => shown(b) && /^continue$/i.test(b.textContent.trim()));
            if (button) button.click(); else if (form) form.requestSubmit();
        };
        const secret = document.querySelector('input[type="password"]');
        if (shown(secret)) { type(secret, password); send(secret); return 'password'; }
        const address = document.querySelector('input[type="email"], input[name="email"], input[name="username"], input[autocomplete="email"], input[autocomplete="username"]');
        if (shown(address)) { type(address, email); send(address); return 'email'; }
        const login = document.querySelector('[data-testid="login-button"]')
            || [...document.querySelectorAll('button, a')].find(b => shown(b) && /^log in$/i.test(b.textContent.trim()));
        if (location.hostname === 'chatgpt.com' && shown(login)) { login.click(); return 'login'; }
        return 'wait';
        """

    static func signIn(_ web: WKWebView, email: String, password: String) async {
        var done: [String: Int] = [:] // how many times each step was done
        var last = ""
        let end = Date().addingTimeInterval(3 * 60)
        while Date() < end {
            try? await Task.sleep(for: .seconds(3))
            if await signedIn(web) { print("Signed in."); return }
            if web.isLoading { continue }
            let step = (try? await web.callAsyncJavaScript(stepScript, arguments: ["email": email, "password": password],
                                                           in: nil, contentWorld: .page) as? String) ?? "wait"
            switch step {
            case "challenge":
                print("The sign-in stopped: OpenAI showed a bot check. A person must sign in.")
                exit(5)
            case "code":
                print("The sign-in stopped: OpenAI asked for a code (email or second factor). A person must sign in.")
                exit(5)
            case "wait":
                continue
            default:
                if step != last { print("Step: \(step)") }
                last = step
                done[step, default: 0] += 1
                // A step that the page does not accept stops the sign-in, so that a wrong
                // password is not sent many times.
                if done[step, default: 0] > 3 {
                    print("The sign-in stopped: the page did not accept the \(step) step. Possibly the email or the password is wrong.")
                    exit(5)
                }
                try? await Task.sleep(for: .seconds(4))
            }
        }
        print("The sign-in stopped: no signed-in page after 3 minutes.")
        exit(5)
    }

    static func save(_ store: WKWebsiteDataStore, to output: URL) async {
        // Cloudflare's cookies belong to this machine's address, so they stay out.
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
}
