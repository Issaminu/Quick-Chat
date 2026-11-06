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
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 440, height: 540), configuration: configuration)
        let window = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web
        window.orderFront(nil)
        let fixture = """
        <!doctype html><html style="color-scheme:dark"><head><style>
        :root { --bg-primary:#000; --main-surface-primary:#000; --app-color-background-surface-under:#000; }
        .control-wrapper { display:inline-block; width:36px; height:36px; transform:translateZ(0); }
        header { height:44px; } body { margin:0; } main { height:340px; background:var(--bg-primary); }
        .surface { background:var(--bg-primary); }
        #bottom-wash { background:var(--app-color-background-surface-under); height:20px; }
        #composer-gradient::before { content:''; background:linear-gradient(transparent,var(--bg-primary)); }
        #thread-bottom-container { position:absolute; bottom:0; width:100%; padding:0 24px 24px; box-sizing:border-box; }
        .composer-offset { padding-inline:12px; padding-bottom:8px; }
        form { margin:0; background:var(--bg-primary); }
        #composer-surface { height:88px; border-radius:28px; background:#212121; }
        #composer-inner { height:100%; background:#212121; }
        [data-testid] { background:#000; }
        </style></head><body><div id="root">
        <header id="page-header"><span class="control-wrapper"><button data-testid="open-sidebar-button" aria-label="Open sidebar">Sidebar</button></span>
        <span class="control-wrapper"><button data-testid="create-new-chat-button" aria-label="New chat">New chat</button></span><span id="conversation-title">Test response</span>
        <button id="share-chat">Share</button></header>
        <main><h1 id="welcome-heading">What's on the agenda today?</h1><article id="message-warning"><h1 id="message-heading">A message heading</h1>ChatGPT can make mistakes.</article></main>
        <div id="thread-bottom-container"><div id="composer-shell" class="composer-offset"><div id="disclaimer" class="surface">ChatGPT can make mistakes.</div>
        <div id="bottom-wash"></div><div id="composer-gradient"><form><div id="composer-surface"><div id="composer-inner"><div id="prompt-textarea" contenteditable="true"></div></div></div></form></div>
        </div></div>
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
                        'bottom wash stays transparent': alpha('#bottom-wash') === 0,
                        'composer gradient has no black stop': !getComputedStyle(document.querySelector('#composer-gradient'),'::before').backgroundImage.includes('rgb(0, 0, 0)'),
                        'composer has a light translucent fill': alpha('#composer-surface') > 0 && alpha('#composer-surface') < 30,
                        'composer inner layer has no opaque fill': alpha('#composer-inner') === 0,
                        'composer side and bottom insets are 12 points': (() => { const r=document.querySelector('#composer-surface').getBoundingClientRect(); return r.left === 12 && r.right === innerWidth - 12 && r.bottom === innerHeight - 12; })(),
                        'empty-chat greeting is hidden': !document.querySelector('#welcome-heading') || getComputedStyle(document.querySelector('#welcome-heading')).display === 'none',
                        'headings inside messages remain visible': document.querySelector('#message-heading').checkVisibility(),
                        'sidebar and its rows stay opaque': alpha('aside') === 255 && alpha('#sidebar-row') === 255,
                        'menu and its rows stay opaque': alpha('[role="menu"]') === 255 && alpha('#menu-row') === 255,
                        'original sidebar button stays hidden inside a transformed wrapper': !document.querySelector('[data-testid="open-sidebar-button"]').checkVisibility({visibilityProperty:true}),
                        'original new chat button stays hidden inside a transformed wrapper': !document.querySelector('[data-testid="create-new-chat-button"]').checkVisibility({visibilityProperty:true})
                    };
                })();
                """) as! [String: Bool]
            for name in result.keys.sorted() {
                let passed = result[name]!
                print("\(passed ? "PASS" : "FAIL") \(state): \(name)")
                if !passed { failures += 1 }
            }
            _ = try await web.evaluateJavaScript("(() => { document.querySelector('main').outerHTML='<main id=\"thread\"><article id=\"message-warning\"><h1 id=\"message-heading\">A message heading</h1>ChatGPT can make mistakes.</article></main>';const footer=document.querySelector('#composer-shell');const replacement=footer.cloneNode(true);replacement.querySelectorAll('[data-quick-chat-disclaimer]').forEach(e=>e.removeAttribute('data-quick-chat-disclaimer'));footer.replaceWith(replacement); })()")
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
