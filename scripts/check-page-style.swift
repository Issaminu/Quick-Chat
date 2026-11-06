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
        * { box-sizing:border-box; } body { margin:0; } #root, main { height:100vh; }
        header { position:absolute; top:0; left:0; width:100%; height:52px; display:flex; }
        .toolbar-branch { display:flex; margin-left:auto; transform:translateZ(0); contain:layout paint; }
        header button { width:36px; height:36px; }
        #welcome-region { height:340px; }
        .surface { background:var(--bg-primary); }
        #fixture-dock { position:absolute; bottom:0; width:100%; padding:6px 0 24px; }
        .composer-offset { padding-inline:16px; padding-bottom:0; }
        .contents { display:contents; }
        form { margin:0; background:var(--bg-primary); }
        #composer-surface { position:relative; height:88px; border-radius:28px; background:#212121; }
        #composer-inner { height:100%; background:#212121; }
        .bg-composer-primary { background:#2c67c5; color:white; position:absolute; right:8px; bottom:8px; width:36px; height:36px; border-radius:50%; }
        .bg-composer-primary svg { color:white; }
        </style></head><body><div id="root"><main class="group/home-composer-layout">
        <header data-app-shell-titlebar><button aria-label="Show sidebar">Sidebar</button>
        <button aria-label="New chat">New chat</button><span id="conversation-title">Test response</span>
        <div class="toolbar-branch"><button id="share-chat">Share</button><div class="contents"><button aria-label="Temporary chat"><svg width="20" height="20"></svg></button></div></div></header>
        <section id="welcome-region"><h1 id="welcome-heading">Arbitrary greeting variant</h1><div class="heading-xl">Another animated greeting layer</div></section>
        <article id="message-warning"><h1 id="message-heading">A message heading</h1>ChatGPT can make mistakes.</article>
        <div id="fixture-dock"><div id="composer-shell" class="composer-offset"><div id="disclaimer" class="surface">ChatGPT can make mistakes.</div>
        <div class="contents"><div class="contents"><form data-composer-placement="home"><div id="composer-surface" data-composer-body><div id="composer-inner"><div role="textbox" data-composer-markdown contenteditable="true"></div></div>
        <button aria-label="Send" class="bg-composer-primary"><svg><path fill="currentColor" d="M1 1h10v10z"></path></svg></button></div></form></div></div>
        </div></div></main>
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
        for state in ["empty chat", "client-side greeting and composer rerender"] {
            let result = try await web.evaluateJavaScript("""
                (() => {
                    const alpha = selector => {
                        const context = document.createElement('canvas').getContext('2d');
                        context.fillStyle = getComputedStyle(document.querySelector(selector)).backgroundColor;
                        context.fillRect(0,0,1,1);
                        return context.getImageData(0,0,1,1).data[3];
                    };
                    const temporary = document.querySelector('button[aria-label="Temporary chat"]');
                    const card = document.querySelector('#composer-surface');
                    const rect = card.getBoundingClientRect();
                    const send = document.querySelector('button[aria-label="Send"]');
                    const shown = element => element.checkVisibility({visibilityProperty:true});
                    return {
                        'chat surface stays transparent': alpha('main') === 0,
                        'disclaimer is hidden': !shown(document.querySelector('#disclaimer')),
                        'composer remains visible': shown(card),
                        'matching message text remains visible': shown(document.querySelector('#message-warning')),
                        'only Temporary Chat remains in the header': [...document.querySelectorAll('header button')].filter(shown).length === 1 && shown(temporary),
                        'Temporary Chat is at the top left': temporary.getBoundingClientRect().x === 8 && temporary.getBoundingClientRect().y === 8,
                        'conversation title is hidden': !shown(document.querySelector('#conversation-title')),
                        'composer has a light translucent fill': alpha('#composer-surface') > 0 && alpha('#composer-surface') < 30,
                        'composer inner layer has no opaque fill': alpha('#composer-inner') === 0,
                        'composer side and bottom insets are 8 points': rect.left === 8 && rect.right === innerWidth - 8 && rect.bottom === innerHeight - 8,
                        'inner corners equal outer radius minus inset': parseFloat(getComputedStyle(card).borderRadius) === 20 - 8,
                        'every greeting layer is hidden': [...document.querySelectorAll('#welcome-region, #welcome-region *')].every(e=>!shown(e)),
                        'headings inside messages remain visible': shown(document.querySelector('#message-heading')),
                        'primary action is white with a black icon': getComputedStyle(send).backgroundColor === 'rgb(255, 255, 255)' && getComputedStyle(send.querySelector('svg')).color === 'rgb(0, 0, 0)',
                        'sidebar and its rows stay opaque': alpha('aside') === 255 && alpha('#sidebar-row') === 255,
                        'menu and its rows stay opaque': alpha('[role="menu"]') === 255 && alpha('#menu-row') === 255
                    };
                })();
                """) as! [String: Bool]
            for name in result.keys.sorted() {
                let passed = result[name]!
                print("\(passed ? "PASS" : "FAIL") \(state): \(name)")
                if !passed { failures += 1 }
            }
            _ = try await web.evaluateJavaScript("(() => { document.querySelector('#welcome-region').innerHTML='<div class=\"heading-xl\">A completely different greeting with no matched words</div>';const footer=document.querySelector('#composer-shell');const replacement=footer.cloneNode(true);replacement.querySelectorAll('[data-quick-chat-disclaimer]').forEach(e=>e.removeAttribute('data-quick-chat-disclaimer'));footer.replaceWith(replacement); })()")
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
