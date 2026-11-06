// Run from the repository root:
// swiftc -swift-version 6 Sources/QuickChat/Features/QuickChat/QuickChatPageStyle.swift scripts/check-page-style.swift -o /tmp/quickchat-page-style-check
// /tmp/quickchat-page-style-check
//
// Checks the page style against a small page that has the same hooks as chatgpt.com: the
// empty chat first, then the conversation layout that the page switches to (without loading)
// after the first message. scripts/check-live.py checks the real page.
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

    static let fixture = """
        <!doctype html><html data-theme="dark" style="color-scheme:dark"><head><style>
        :root { --color-surface:#0e0e0e; --thread-composer-bottom-inset:24px; }
        * { box-sizing:border-box; } html, body { margin:0; height:100%; background:#0e0e0e; color:#fff; }
        .bg-surface { background-color:var(--color-surface); }
        main { position:relative; height:100vh; display:flex; flex-direction:column; background:#0e0e0e; }
        header { position:fixed; inset:0 0 auto 0; height:52px; display:flex; z-index:30; pointer-events:none; }
        header button { width:36px; height:36px; pointer-events:auto; }
        [data-app-shell-header-slot-content] { display:flex; gap:8px; padding:8px; }
        [data-app-shell-main-titlebar] { flex:1; display:flex; justify-content:flex-end; padding:8px; }
        .root { --composer-layout-surface-background:#212121; --composer-layout-surface-shadow:inset 0 0 1px #fff3;
                --composer-border-radius:28px; --color-background-composer-primary:#2c67c5; --color-text-composer-primary:#fff; }
        [data-composer-body] { position:relative; height:88px; background-color:var(--composer-layout-surface-background);
                               box-shadow:var(--composer-layout-surface-shadow); border-radius:var(--composer-border-radius); }
        .send { position:absolute; right:8px; bottom:8px; width:36px; height:36px; border-radius:50%;
                background-color:var(--color-background-composer-primary); color:var(--color-text-composer-primary); }
        [role="main"] { flex:1; display:flex; flex-direction:column; padding:76px 16px 24px; }
        #page { flex:1; min-height:0; display:flex; flex-direction:column; }
        #hero { flex:1; } .contents { display:contents; }
        #thread { position:relative; flex:1; min-height:0; }
        [data-app-action-timeline-scroll] { --thread-content-top-inset:32px; height:100%; overflow-y:auto; padding-top:32px; display:flex; flex-direction:column; }
        .content { min-height:100%; flex-shrink:0; display:flex; flex-direction:column; }
        .content p { height:40px; margin:0; }
        .spacer { position:sticky; bottom:0; flex-shrink:0; height:calc(var(--thread-scroll-padding-bottom) - 1rem); }
        .footer { position:absolute; inset:auto 0 0 0; }
        [data-thread-scroll-footer]::after { content:""; display:block; height:var(--thread-composer-bottom-inset); }
        [data-thread-scroll-footer] > [aria-hidden] { position:absolute; inset:0; }
        [data-pip-obstacle] { position:relative; padding:0 16px; }
        #scroll-down { position:absolute; left:50%; bottom:100%; width:32px; height:32px; }
        .disclaimer { visibility:var(--thread-composer-disclaimer-visibility, inherit); }
        [role="menu"] { position:fixed; top:200px; left:100px; width:100px; height:40px; }
        </style></head><body><div data-app-shell-active-page="true"><main data-app-shell-main-surface>
        <header data-app-shell-titlebar>
          <div data-app-shell-header-slot="start"><div data-app-shell-header-slot-content>
            <div class="bg-surface"><button id="sidebar-button" aria-controls="sidebar">S</button></div>
            <div class="bg-surface"><button id="header-new-chat">N</button></div>
          </div></div>
          <div data-app-shell-main-titlebar><span id="title">Title</span><button id="temporary">T</button></div>
        </header>
        <div id="page"></div>
        </main></div><div role="menu" class="bg-surface">Menu</div>
        <div><div id="ask-toolbar" style="position:fixed; top:100px; transform:translateX(0%) translateY(-100%)"><div role="presentation"><button>Ask</button><div aria-hidden="true"></div></div></div></div>
        <div data-radix-popper-content-wrapper id="format-toolbar"><div role="dialog"><div role="presentation"><button aria-label="Link">L</button></div></div></div>
        <div data-radix-popper-content-wrapper id="model-menu"><div role="menu"><div role="group">Model</div></div></div>
        <template id="home"><div role="main">
          <div id="hero"><h1 id="greeting">Any greeting</h1><p>Any description</p></div>
          <div id="composer-block"><div data-home-feed-composer class="contents">
            <form data-chatgpt-composer data-composer-placement="home"><div class="root"><div data-composer-body>
              <div data-rich-text-layout style="max-height:40px; overflow-y:auto"><div contenteditable="true"></div></div><div data-composer-expansion-control><button class="expand" data-composer-expand-toggle>E</button></div><button class="send">↑</button></div></div></form>
          </div><div id="notice">Any notice</div></div>
        </div></template>
        <template id="conversation"><div id="thread">
          <div data-app-action-timeline-scroll>
            <div class="content"><div id="code" style="overflow-y:auto; height:40px"><div style="height:200px">code</div></div><div id="messages"></div>
              <div><div class="disclaimer" id="disclaimer" data-markdown-copy="exclude">Any disclaimer</div></div><div class="spacer" aria-hidden="true"></div></div>
            <div class="footer"><div data-thread-scroll-footer>
              <div aria-hidden="true" class="bg-surface"></div>
              <div data-pip-obstacle><button id="scroll-down" class="bg-surface">↓</button>
                <form data-chatgpt-composer data-composer-placement="thread"><div class="root"><div data-composer-body>
                  <div data-rich-text-layout style="max-height:40px; overflow-y:auto"><div contenteditable="true"></div></div><div data-composer-expansion-control><button class="expand" data-composer-expand-toggle>E</button></div><button class="send">↑</button></div></div></form></div>
            </div></div>
          </div>
        </div></template>
        <script>
        // Like ChatGPT: render a page from a template and track the composer area's height.
        window.show = (name, messages = 40) => {
            document.querySelector('#page').replaceChildren(document.querySelector('#' + name).content.cloneNode(true));
            const scroller = document.querySelector('[data-app-action-timeline-scroll]');
            if (!scroller) return;
            document.querySelector('#messages').innerHTML = '<p>Message</p>'.repeat(messages);
            const footer = document.querySelector('[data-thread-scroll-footer]');
            new ResizeObserver(() => scroller.style.setProperty('--thread-scroll-padding-bottom', footer.offsetHeight + 16 + 'px')).observe(footer);
        };
        show('home');
        </script></body></html>
        """

    static let checks = """
        (() => {
            const $ = selector => document.querySelector(selector);
            const style = selector => getComputedStyle($(selector));
            const alpha = color => {
                const context = document.createElement('canvas').getContext('2d');
                context.fillStyle = color;
                context.fillRect(0, 0, 1, 1);
                return context.getImageData(0, 0, 1, 1).data[3];
            };
            const shown = element => element.checkVisibility({ visibilityProperty: true, opacityProperty: true });
            const composer = [...document.querySelectorAll('[data-composer-body]')].find(shown);
            const rect = composer.getBoundingClientRect();
            const send = composer.querySelector('.send');
            const result = {
                'page surfaces are transparent': ['html', 'body', 'main'].every(s => alpha(style(s).backgroundColor) === 0),
                'page sidebar button is not drawn and sits under the panel one': !shown($('#sidebar-button')) && $('#sidebar-button').getBoundingClientRect().x === 52,
                'text uses the system font smoothing': getComputedStyle(composer).webkitFontSmoothing === 'auto',
                'scrolling does not stretch at the ends': getComputedStyle(document.documentElement).overscrollBehaviorY === 'none',
                'header has no other page buttons': !shown($('#header-new-chat')) && !shown($('#temporary')) && !shown($('#title')),
                'header buttons have no fill': alpha(getComputedStyle($('#sidebar-button').parentElement).backgroundColor) === 0,
                'composer is translucent': alpha(getComputedStyle(composer).backgroundColor) > 0 && alpha(getComputedStyle(composer).backgroundColor) < 40,
                'composer has one 1-point border': getComputedStyle(composer).boxShadow.includes('inset') && getComputedStyle(composer).borderTopWidth === '0px',
                'composer corners are concentric with the window': getComputedStyle(composer).borderTopLeftRadius === '12px',
                'composer insets are 8 points': rect.left === 8 && innerWidth - rect.right === 8 && innerHeight - rect.bottom === 8,
                'primary button is white with a black icon': getComputedStyle(send).backgroundColor === 'rgb(255, 255, 255)' && getComputedStyle(send).color === 'rgb(0, 0, 0)',
                'menus keep their fill': alpha(style('[role="menu"]').backgroundColor) === 255,
                'composer has no Expand control of its own': !shown(composer.querySelector('[data-composer-expand-toggle]')),
                'composer text does not stretch at its ends': getComputedStyle(composer.querySelector('[data-rich-text-layout]')).overscrollBehaviorY === 'none',
                'selection toolbars are hidden, menus are not': !shown($('#ask-toolbar')) && !shown($('#format-toolbar')) && shown($('#model-menu'))
            };
            if ($('#hero')) {
                result['greeting and notices are hidden'] = !shown($('#hero')) && !shown($('#greeting')) && !shown($('#notice'));
            } else {
                const scroller = $('[data-app-action-timeline-scroll]');
                const content = scroller.firstElementChild;
                result['messages end at the composer top'] = Math.abs(scroller.getBoundingClientRect().bottom - rect.top) < 1;
                result['messages fade with the scroll position'] = getComputedStyle(content).maskImage.includes('gradient') &&
                    getComputedStyle(content).animationName === 'quick-chat-follow-scroll';
                result['a code block passes the scroll on at its ends'] = getComputedStyle($('#code')).overscrollBehaviorY === 'auto';
                result['message list has a thin scroll bar while it can scroll'] =
                    scroller.offsetWidth - scroller.clientWidth === (scroller.scrollHeight > scroller.clientHeight ? 10 : 0);
                result['scroll-to-bottom button keeps its fill'] = alpha(style('#scroll-down').backgroundColor) === 255;
                if (scroller.scrollHeight <= scroller.clientHeight) {
                    result['mask starts at the top of the visible area'] = getComputedStyle(content).maskPosition.endsWith('-32px');
                }
                result['message text is 15 points'] = getComputedStyle(content).getPropertyValue('--font-text-md-size').trim() === '15px';
                result['disclaimer is hidden and takes no space'] = $('#disclaimer').getClientRects().length === 0;
                result['opaque composer backdrop is hidden'] = !shown($('[data-thread-scroll-footer] > [aria-hidden]'));
            }
            return result;
        })();
        """

    static func check() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: QuickChatPageStyle.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 440, height: 540), configuration: configuration)
        let window = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web
        window.orderFront(nil)
        web.loadHTMLString(fixture, baseURL: URL(string: "https://chatgpt.com/"))
        var ready = false
        for _ in 0..<200 where !ready {
            ready = (try? await web.evaluateJavaScript("document.readyState === 'complete' && document.adoptedStyleSheets.some(s => [...s.cssRules].some(r => r.name === 'quick-chat-follow-scroll'))")) as? Bool == true
            try await Task.sleep(for: .milliseconds(25))
        }
        guard ready else { print("FAIL: fixture did not load"); exit(1) }
        var failures = 0
        let states = ["empty chat": "", "conversation (after the first message)": "show('conversation')",
                      "short conversation (it cannot scroll)": "show('conversation', 1)"]
        for state in ["empty chat", "conversation (after the first message)", "short conversation (it cannot scroll)"] {
            if !states[state]!.isEmpty {
                _ = try await web.evaluateJavaScript(states[state]!)
                try await Task.sleep(for: .milliseconds(200))
            }
            let result = try await web.evaluateJavaScript(checks) as! [String: Bool]
            for name in result.keys.sorted() {
                print("\(result[name]! ? "PASS" : "FAIL") \(state): \(name)")
                if !result[name]! { failures += 1 }
            }
        }
        _ = try await web.evaluateJavaScript("document.documentElement.dataset.quickChatPointer = 'outside'")
        try await Task.sleep(for: .milliseconds(400))
        let hidden = try await web.evaluateJavaScript("""
            getComputedStyle(document.querySelector('header')).opacity === '0' &&
            getComputedStyle(document.documentElement).getPropertyValue('--quick-chat-title-bar-shown').trim() === '0'
            """) as? Bool == true
        print("\(hidden ? "PASS" : "FAIL") pointer outside the panel: the title bar is hidden and messages may use its space")
        if !hidden { failures += 1 }
        window.orderOut(nil)
        print("\(failures) failed checks")
        exit(failures == 0 ? 0 : 1)
    }
}
