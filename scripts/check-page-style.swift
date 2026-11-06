// Run from the repository root:
// swiftc -swift-version 6 Sources/QuickChat/Features/QuickChat/QuickChatPageStyle.swift scripts/check-page-style.swift -o /tmp/quickchat-page-style-check
// /tmp/quickchat-page-style-check
import AppKit
import WebKit

@main
@MainActor
enum PageStyleCheck {
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Task {
            do { try await check() }
            catch { print("FAIL: \(error)"); exit(1) }
        }
        NSApplication.shared.run()
    }

    static func check() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: QuickChatPageStyle.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 420, height: 560), configuration: configuration)
        let window = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web
        window.orderFront(nil)
        let fixture = """
        <!doctype html><html style="color-scheme:dark"><head><style>
        :root { --bg-primary:#000; --main-surface-primary:#000; --app-color-background-surface-under:#000; }
        header { height:44px; } body { margin:0; } main { height:340px; background:var(--bg-primary); }
        .surface { background:var(--bg-primary); }
        #bottom-wash { background:var(--app-color-background-surface-under); height:20px; }
        #composer-gradient::before { content:''; background:linear-gradient(transparent,var(--bg-primary)); }
        form { height:80px; border-radius:24px; background:var(--bg-primary); }
        [data-testid] { background:#000; }
        </style></head><body><div id="root">
        <header id="page-header"><button data-testid="open-sidebar-button" aria-label="Open sidebar">Sidebar</button>
        <button data-testid="create-new-chat-button" aria-label="New chat">New chat</button><span id="conversation-title">Test response</span>
        <button id="share-chat">Share</button></header>
        <main><h1>What's on the agenda today?</h1><article id="message-warning">ChatGPT can make mistakes.</article></main>
        <div id="composer-shell"><div id="disclaimer" class="surface">ChatGPT can make mistakes.</div>
        <div id="composer-gradient"><form><div id="prompt-textarea" contenteditable="true"></div></form></div>
        <div id="bottom-wash"></div></div>
        <aside role="dialog"><div id="sidebar-row" class="surface">Recent chat</div></aside>
        <div role="menu"><div id="menu-row" class="surface">Settings</div></div>
        </div></body></html>
        """
        web.loadHTMLString(fixture, baseURL: URL(string: "https://chatgpt.com/"))
        var ready = false
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("!!document.getElementById('quick-chat-page-style')")) as? Bool == true {
                ready = true
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        guard ready else { print("FAIL: fixture did not load"); exit(1) }
        var failures = 0
        for state in ["empty chat", "conversation after client-side navigation"] {
            let result = try await web.evaluateJavaScript("""
                (() => {
                    const alpha = selector => {
                        const context = document.createElement('canvas').getContext('2d');
                        context.fillStyle = getComputedStyle(document.querySelector(selector)).backgroundColor;
                        context.fillRect(0,0,1,1);
                        return context.getImageData(0,0,1,1).data[3];
                    };
                    return {
                        'chat surface stays transparent': alpha('main') === 0,
                        'disclaimer is hidden': getComputedStyle(document.querySelector('#disclaimer')).display === 'none',
                        'composer remains visible': document.querySelector('form').checkVisibility(),
                        'matching message text remains visible': document.querySelector('#message-warning').checkVisibility(),
                        'conversation title is hidden': getComputedStyle(document.querySelector('#conversation-title')).visibility === 'hidden',
                        'old share control is hidden': getComputedStyle(document.querySelector('#share-chat')).visibility === 'hidden',
                        'sidebar is visible beside native close button': document.querySelector('[data-testid="open-sidebar-button"]').checkVisibility({visibilityProperty:true}) && document.querySelector('[data-testid="open-sidebar-button"]').getBoundingClientRect().left === 40,
                        'new chat is visible at the top right': document.querySelector('[data-testid="create-new-chat-button"]').checkVisibility({visibilityProperty:true}) && document.querySelector('[data-testid="create-new-chat-button"]').getBoundingClientRect().right === innerWidth - 10,
                        'bottom wash stays transparent': alpha('#bottom-wash') === 0,
                        'composer gradient has no black stop': !getComputedStyle(document.querySelector('#composer-gradient'),'::before').backgroundImage.includes('rgb(0, 0, 0)'),
                        'composer retains its translucent fill': alpha('form') > 0 && alpha('form') < 255,
                        'sidebar and its rows stay opaque': alpha('aside') === 255 && alpha('#sidebar-row') === 255,
                        'menu and its rows stay opaque': alpha('[role="menu"]') === 255 && alpha('#menu-row') === 255,
                        'sidebar button has no background': alpha('[data-testid="open-sidebar-button"]') === 0,
                        'new chat button has no background': alpha('[data-testid="create-new-chat-button"]') === 0
                    };
                })();
                """) as! [String: Bool]
            for name in result.keys.sorted() {
                let passed = result[name]!
                print("\(passed ? "PASS" : "FAIL") \(state): \(name)")
                if !passed { failures += 1 }
            }
            _ = try await web.evaluateJavaScript("(() => { document.querySelector('main').outerHTML='<main id=\"thread\"><article id=\"message-warning\">ChatGPT can make mistakes.</article></main>';const footer=document.querySelector('#composer-shell');const replacement=footer.cloneNode(true);replacement.querySelectorAll('[data-quick-chat-disclaimer]').forEach(e=>e.removeAttribute('data-quick-chat-disclaimer'));footer.replaceWith(replacement); })()")
            for _ in 0..<100 {
                if (try await web.evaluateJavaScript("getComputedStyle(document.querySelector('#disclaimer')).display === 'none'")) as? Bool == true { break }
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        window.orderOut(nil)
        print("\(failures) failed checks")
        exit(failures == 0 ? 0 : 1)
    }
}
