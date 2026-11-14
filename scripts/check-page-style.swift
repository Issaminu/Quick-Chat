// Run from the repository root:
// swiftc -swift-version 6 Sources/QuickChat/Features/QuickChat/QuickChatPageStyle.swift Sources/QuickChat/Features/QuickChat/PageHooks.swift scripts/PageVisualCheck.swift scripts/check-page-style.swift -o /tmp/quickchat-page-style-check
// /tmp/quickchat-page-style-check
//
// Checks the page style against a small page that has the same hooks as chatgpt.com: the
// empty chat first, then the conversation layout that the page switches to (without loading)
// after the first message. It also checks that PageHooks names every hook of the style, and
// that safe mode turns the style off when the style hides the composer.
// scripts/check-page-hooks.swift checks the real page every day.
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
        [data-app-shell-header-slot="start"] > div > div { display:flex; gap:8px; padding:8px; }
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
        .footer::before { content:""; position:absolute; inset:0; background-image:linear-gradient(transparent, #0e0e0e); }
        .footer::after { content:""; position:absolute; inset:auto 0 0 0; height:24px; background-color:#0e0e0e; }
        [data-thread-scroll-footer]::after { content:""; display:block; height:var(--thread-composer-bottom-inset); }
        [data-thread-scroll-footer] > [aria-hidden] { position:absolute; inset:0; }
        [data-pip-obstacle] { position:relative; padding:0 16px; }
        #scroll-down { position:absolute; left:50%; bottom:100%; width:32px; height:32px; }
        .disclaimer { visibility:var(--thread-composer-disclaimer-visibility, inherit); }
        [role="menu"] { position:fixed; top:200px; left:100px; width:100px; height:40px; }
        </style></head><body><div data-app-shell-active-page="true"><main data-app-shell-main-surface>
        <header data-app-shell-titlebar>
          <div data-app-shell-header-slot="start"><div><div>
            <div class="bg-surface"><div><button id="sidebar-button" aria-controls="sidebar">S</button></div></div>
            <div class="bg-surface"><div><button id="header-new-chat">N</button></div></div>
          </div></div></div>
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
                'page sidebar button is not drawn and sits under the panel one': !shown($('#sidebar-button')) && $('#sidebar-button').getBoundingClientRect().x === 8,
                'text uses the system font smoothing': getComputedStyle(composer).webkitFontSmoothing === 'auto',
                'scrolling does not stretch at the ends': getComputedStyle(document.documentElement).overscrollBehaviorY === 'none',
                'header has no other page buttons': !shown($('#header-new-chat')) && !shown($('#temporary')) && !shown($('#title')),
                'header buttons have no fill': alpha(getComputedStyle($('#sidebar-button').closest('.bg-surface')).backgroundColor) === 0,
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
                result['messages fade above the composer'] = getComputedStyle(content).maskImage.includes('gradient');
                result['a code block passes the scroll on at its ends'] = getComputedStyle($('#code')).overscrollBehaviorY === 'auto';
                const select = e => getComputedStyle(e).webkitUserSelect || getComputedStyle(e).userSelect;
                result['only message text, the composer and fields can be selected'] = select(document.body) === 'none' &&
                    select($('#messages p')) === 'text' && select($('#scroll-down')) === 'none' &&
                    select(composer.querySelector('[contenteditable="true"]')) === 'text' && select($('#sidebar-button')) === 'none';
                result['message list has a thin scroll bar while it can scroll'] =
                    scroller.offsetWidth - scroller.clientWidth === (scroller.scrollHeight > scroller.clientHeight ? 10 : 0);
                result['scroll-to-bottom button keeps its fill'] = alpha(style('#scroll-down').backgroundColor) === 255;
                if (scroller.scrollHeight <= scroller.clientHeight) {
                    result['mask starts at the top of the visible area'] = getComputedStyle(content).maskPosition.endsWith('-32px');
                }
                result['message text is 15 points'] = getComputedStyle(content).getPropertyValue('--font-text-md-size').trim() === '15px';
                result['disclaimer is hidden and takes no space'] = $('#disclaimer').getClientRects().length === 0;
                result['opaque composer backdrop is hidden'] = !shown($('[data-thread-scroll-footer] > [aria-hidden]'));
                result['the footer draws no backdrop'] = ['::before', '::after'].every(p => { const s = getComputedStyle($('.footer'), p); return alpha(s.backgroundColor) === 0 && s.backgroundImage === 'none'; });
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
        PageVisualCheck.prepare(web)
        let window = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web
        window.orderFront(nil)
        web.loadHTMLString(fixture, baseURL: URL(string: "https://chatgpt.com/"))
        var ready = false
        for _ in 0..<200 where !ready {
            ready = (try? await web.evaluateJavaScript("document.readyState === 'complete' && document.adoptedStyleSheets.some(s => [...s.cssRules].some(r => r.name === '--quick-chat-title-bar-shown'))")) as? Bool == true
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
        // The screen checks of the daily page check (scripts/PageVisualCheck.swift): the styled page
        // draws nothing in the panel's empty areas, and a new title bar button and a band behind
        // the composer are found, with the elements that draw them.
        // The test page's own menus stay out of these checks. Like ChatGPT, the messages start
        // below the title bar.
        let screenState = """
            document.head.insertAdjacentHTML('beforeend', '<style id="screen-test">[role="menu"], [data-radix-popper-content-wrapper], #ask-toolbar { display:none !important; } [data-app-action-timeline-scroll] { --thread-content-top-inset:52px; padding-top:52px; }</style>');
            """
        for (state, script) in [("empty chat", "show('home')"), ("conversation", "show('conversation')")] {
            _ = try await web.evaluateJavaScript(script + ";" + screenState)
            try await Task.sleep(for: .milliseconds(300))
            let findings = await PageVisualCheck.check(web, prefix: "check", folder: nil)
            let pass = findings.isEmpty
            print("\(pass ? "PASS" : "FAIL") screen: the \(state) draws nothing in the empty areas\(pass ? "" : " (\(findings.map { "\($0.area.id): \($0.drawnPixels) pixels, \($0.painters)" }))")")
            if !pass { failures += 1 }
        }
        _ = try await web.evaluateJavaScript("""
            document.body.insertAdjacentHTML('beforeend', '<div id="new-title-button" style="position:fixed; top:10px; left:120px; width:30px; height:30px; background:#888"></div>');
            document.querySelector('.footer').insertAdjacentHTML('beforeend', '<div id="band" style="position:absolute; inset:auto 0 0 0; height:60px; background:#0e0e0e; z-index:-1"></div>');
            """)
        try await Task.sleep(for: .milliseconds(300))
        let findings = await PageVisualCheck.check(web, prefix: "check", folder: nil)
        let found = Dictionary(findings.map { ($0.area.id, $0.painters.joined(separator: "\n")) }, uniquingKeysWith: { a, _ in a })
        for (area, element) in [("title-bar", "new-title-button"), ("below-composer", "band")] {
            let pass = found[area]?.contains(element) == true
            print("\(pass ? "PASS" : "FAIL") screen: finds what draws in the area \(area) (\(element))\(pass ? "" : " (\(found))")")
            if !pass { failures += 1 }
        }
        _ = try await web.evaluateJavaScript("document.querySelectorAll('#new-title-button, #band, #screen-test').forEach(e => e.remove())")

        // The mask covers the visible part of the message list in each of these cases.
        _ = try await web.evaluateJavaScript("show('conversation')")
        try await Task.sleep(for: .milliseconds(200))
        let maskCases = try await web.callAsyncJavaScript("""
            const frames = () => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
            const scroller = document.querySelector('[data-app-action-timeline-scroll]');
            const aligned = () => {
                const content = scroller.firstElementChild, style = getComputedStyle(content);
                const y = parseFloat(style.maskPosition.split(' ')[1]), height = parseFloat(style.maskSize.split(' ')[1]);
                const top = scroller.getBoundingClientRect().top + scroller.clientTop - content.getBoundingClientRect().top;
                return Math.abs(y - top) < 1 && Math.abs(height - scroller.clientHeight) < 1;
            };
            const result = {};
            scroller.scrollTop = (scroller.scrollHeight - scroller.clientHeight) / 2; await frames();
            result['after a scroll'] = scroller.scrollTop > 0 && aligned();
            const extra = document.createElement('p'); extra.style.height = '600px';
            scroller.firstElementChild.prepend(extra); await frames();
            result['after the content grows with no scroll'] = aligned();
            scroller.firstElementChild.replaceWith(scroller.firstElementChild.cloneNode(true)); await frames();
            result['after the page renders the list again'] = aligned();
            scroller.firstElementChild.style.cssText = ''; await frames();
            result['after the page changes the inline style of the list'] = aligned();
            scroller.firstElementChild.querySelector('p').remove(); scroller.scrollTop = 0; await frames();
            return result;
            """, arguments: [:], in: nil, contentWorld: .page) as! [String: Bool]
        for name in maskCases.keys.sorted() {
            print("\(maskCases[name]! ? "PASS" : "FAIL") the mask covers the visible messages \(name)")
            if !maskCases[name]! { failures += 1 }
        }

        // A press on the background moves the panel; a press on content or a control does not.
        _ = try await web.evaluateJavaScript("show('conversation')")
        try await Task.sleep(for: .milliseconds(200))
        let presses = try await web.callAsyncJavaScript("""
            const posts = [];
            window.webkit = { messageHandlers: { quickChat: { postMessage: m => { if (m.type !== 'state') posts.push(m.type); } } } };
            document.querySelector('#messages').insertAdjacentHTML('afterbegin',
                '<div id="user-row"><div data-user-message-bubble id="bubble">Question</div></div>' +
                '<div data-dil-response id="answer"><p id="answer-text">Answer</p></div>');
            const press = (element, detail = 1, y = 300) => {
                posts.length = 0;
                element.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0, detail, clientX: 10, clientY: y }));
                return posts.join(',') || 'none';
            };
            const $ = s => document.querySelector(s);
            const composer = [...document.querySelectorAll('[data-composer-body]')].find(e => e.checkVisibility());
            const range = document.createRange(); range.selectNodeContents($('#answer-text')); getSelection().addRange(range);
            const result = {
                'beside your message': press($('#user-row')) === 'drag',
                'between messages': press($('#messages')) === 'drag',
                'in the composer around its field': press(composer) === 'drag',
                'on the title bar': press($('header'), 1, 20) === 'drag',
                'double press on the title bar zooms': press($('header'), 2, 20) === 'zoom',
                'double press on the background only drags': press($('#user-row'), 2) === 'drag',
                'not on your message': press($('#bubble')) === 'none',
                'not on an answer, also beside its text': press($('#answer')) === 'none' && press($('#answer-text')) === 'none',
                'not on message text': press($('#messages p:last-child')) === 'none',
                'not on the composer field or a button': press(composer.querySelector('[contenteditable]')) === 'none' && press(composer.querySelector('.send')) === 'none',
                'not on a menu outside the page': press($('[role="menu"]')) === 'none'
            };
            press($('#user-row'));
            result['a press on the background ends a text selection'] = getSelection().toString() === '';
            delete window.webkit;
            return result;
            """, arguments: [:], in: nil, contentWorld: .page) as! [String: Bool]
        for name in presses.keys.sorted() {
            print("\(presses[name]! ? "PASS" : "FAIL") a press moves the panel: \(name)")
            if !presses[name]! { failures += 1 }
        }

        // Focus rings: outside keyboard mode, the style removes outlines and Tailwind's ring
        // shadows from focused controls (also when a menu gives the focus back after Esc). The
        // check window is not the key window, so it reads the rule instead of a focused element.
        let rings = try await web.evaluateJavaScript("""
            (() => {
                const rule = document.adoptedStyleSheets.flatMap(s => [...s.cssRules])
                    .find(r => r.selectorText?.includes(':not([data-quick-chat-keyboard])') && r.selectorText.includes(':focus-visible') && r.selectorText.includes('button'));
                if (!rule) return false;
                const none = name => rule.style.getPropertyValue(name).replace(/\\s+/g, ' ').trim() === '0 0 #0000' && rule.style.getPropertyPriority(name) === 'important';
                return rule.style.outlineStyle === 'none' && none('--tw-ring-shadow') && none('--tw-ring-offset-shadow') &&
                    rule.selectorText.includes('button') && rule.selectorText.includes(':focus)');
            })()
            """) as? Bool == true
        print("\(rings ? "PASS" : "FAIL") focus rings: outside keyboard mode, no outline and no ring shadow on focused controls")
        if !rings { failures += 1 }
        // The sidebar's arrow keys, on a sidebar that the check adds for a moment (docked: no dialog).
        let sidebarKeys = try await web.callAsyncJavaScript("""
            const nav = document.createElement('nav');
            nav.style.cssText = 'position:fixed; left:0; top:60px; width:200px; z-index:5';
            nav.innerHTML = `<div data-sidebar-navigation-root>
                <div data-sidebar-cycle-item role="group"><a data-interactive-row-link href="#one">One</a></div>
                <div data-sidebar-cycle-item role="group" aria-current="page"><a data-interactive-row-link href="#two">Two</a></div>
                <div data-sidebar-cycle-item role="group"><a data-interactive-row-link href="#three">Three</a></div></div>`;
            document.body.append(nav);
            const links = [...nav.querySelectorAll('a')];
            const key = name => { const event = new KeyboardEvent('keydown', { key: name, bubbles: true, cancelable: true }); (document.activeElement ?? document.body).dispatchEvent(event); return event.defaultPrevented; };
            const focused = () => links.indexOf(document.activeElement);
            const result = {};
            document.activeElement?.blur?.();
            result['without a press in the sidebar, the arrows stay with the page'] = !key('ArrowDown') && focused() === -1;
            nav.querySelector('[data-sidebar-navigation-root]').dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
            result['after a press in the sidebar, ↓ selects the row after the open conversation'] = key('ArrowDown') && focused() === 2;
            result['↓ stays on the last row'] = key('ArrowDown') && focused() === 2;
            result['↑ moves up'] = key('ArrowUp') && key('ArrowUp') && focused() === 0;
            // The check window is not the key window, so :focus does not match here: read the rule.
            result['the selected row has the hover color'] = document.adoptedStyleSheets.flatMap(s => [...s.cssRules]).some(r =>
                r.selectorText?.includes('[data-sidebar-cycle-item]:has(a[data-interactive-row-link]:focus)') &&
                r.style.backgroundColor.includes('--color-background-secondary-ghost-hover'));
            result['Space opens the selected conversation'] = key(' ') && location.hash === '#one' && focused() === 0;
            history.replaceState(null, '', location.pathname);
            key('a');
            document.activeElement?.blur?.();
            result['Space in another place stays with the page'] = !key(' ');
            result['after typing, the arrows stay with the page'] = !key('ArrowDown') && focused() === -1;
            nav.remove();
            return result;
            """, arguments: [:], in: nil, contentWorld: .page) as? [String: Bool] ?? [:]
        for (name, pass) in sidebarKeys.sorted(by: { $0.key < $1.key }) {
            print("\(pass ? "PASS" : "FAIL") sidebar keys: \(name)")
            if !pass { failures += 1 }
        }
        if sidebarKeys.isEmpty { print("FAIL sidebar keys: the check did not run"); failures += 1 }
        let pseudoRings = try await web.evaluateJavaScript("""
            document.adoptedStyleSheets.flatMap(s => [...s.cssRules]).some(r => r.style?.outlineStyle === 'none' &&
                ['::before', '::after'].every(p => r.selectorText?.split(',').some(part => part.trim() === 'html:not([data-quick-chat-keyboard]) :focus-visible' + p)))
            """) as? Bool == true
        print("\(pseudoRings ? "PASS" : "FAIL") focus rings: outside keyboard mode, no outline on ::before or ::after of a focused element (sidebar rows)")
        if !pseudoRings { failures += 1 }

        // Light mode: the primary button turns black with a white icon.
        let lightButton = try await web.evaluateJavaScript("""
            (() => {
                document.documentElement.style.colorScheme = 'light';
                const send = [...document.querySelectorAll('.send')].find(e => e.checkVisibility());
                const ok = getComputedStyle(send).backgroundColor === 'rgb(0, 0, 0)' && getComputedStyle(send).color === 'rgb(255, 255, 255)';
                document.documentElement.style.colorScheme = 'dark';
                return ok;
            })()
            """) as? Bool == true
        print("\(lightButton ? "PASS" : "FAIL") light mode: the primary button is black with a white icon")
        if !lightButton { failures += 1 }

        // Saved drafts: the script removes only the draft entries, once per session.
        let draftsCleared = try await web.callAsyncJavaScript("""
            const db = await new Promise(resolve => { const r = indexedDB.open("codex-browser-host", 1); r.onupgradeneeded = () => r.result.createObjectStore("records"); r.onsuccess = () => resolve(r.result); });
            await new Promise(resolve => { const tx = db.transaction("records", "readwrite"); tx.objectStore("records").put({ "composer-prompt-drafts-v2": { text: "draft" }, "chatgpt-conversation-prompt-drafts-v2": { c1: "draft" }, "chatgpt-sidebar-state-v2": { open: true } }, "codex.browser.persistedAtomState"); tx.oncomplete = resolve; });
            db.close();
            localStorage.setItem("oai/apps/conversationDrafts", "draft");
            sessionStorage.removeItem("quick-chat-drafts-cleared");
            eval(script);
            await new Promise(resolve => setTimeout(resolve, 300));
            const read = await new Promise(resolve => { const r = indexedDB.open("codex-browser-host"); r.onsuccess = () => { const q = r.result.transaction("records").objectStore("records").get("codex.browser.persistedAtomState"); q.onsuccess = () => { r.result.close(); resolve(q.result); }; }; });
            const once = sessionStorage.getItem("quick-chat-drafts-cleared") === "1";
            return Object.keys(read).join(",") === "chatgpt-sidebar-state-v2" && localStorage.getItem("oai/apps/conversationDrafts") === null && once;
            """, arguments: ["script": QuickChatPageStyle.clearDraftsScript], in: nil, contentWorld: .page) as? Bool == true
        print("\(draftsCleared ? "PASS" : "FAIL") a clean start removes only the saved drafts, once per session")
        if !draftsCleared { failures += 1 }

        _ = try await web.evaluateJavaScript("document.documentElement.dataset.quickChatPointer = 'outside'")
        try await Task.sleep(for: .milliseconds(400))
        let hidden = try await web.evaluateJavaScript("""
            getComputedStyle(document.querySelector('header')).opacity === '0' &&
            getComputedStyle(document.querySelector('header')).getPropertyValue('--quick-chat-title-bar-shown').trim() === '0'
            """) as? Bool == true
        print("\(hidden ? "PASS" : "FAIL") pointer outside the panel: the title bar is hidden and messages may use its space")
        if !hidden { failures += 1 }
        let shownAtOnce = try await web.callAsyncJavaScript("""
            document.documentElement.dataset.quickChatPointer = 'inside';
            await new Promise(resolve => requestAnimationFrame(resolve));
            return getComputedStyle(document.querySelector('header')).opacity === '1' &&
                getComputedStyle(document.querySelector('header')).getPropertyValue('--quick-chat-title-bar-shown').trim() === '1';
            """, arguments: [:], in: nil, contentWorld: .page) as? Bool == true
        print("\(shownAtOnce ? "PASS" : "FAIL") pointer back over the panel: the title bar shows at once, without a fade")
        if !shownAtOnce { failures += 1 }
        let onTop = try await web.callAsyncJavaScript("""
            const header = document.querySelector('header');
            const scroller = document.querySelector('[data-app-action-timeline-scroll]');
            scroller.scrollTop = 0;
            const hit = document.elementFromPoint(innerWidth / 2, 20);
            const wheel = new WheelEvent('wheel', { bubbles: true, cancelable: true, clientX: innerWidth / 2, clientY: 20, deltaY: 40 });
            hit.dispatchEvent(wheel);
            return [header.contains(hit) ? 'header' : hit?.tagName ?? 'none', getComputedStyle(hit).cursor, scroller.scrollTop, wheel.defaultPrevented];
            """, arguments: [:], in: nil, contentWorld: .page) as? [Any] ?? []
        let titleBarOnTop = onTop.count == 4 && onTop[0] as? String == "header" && onTop[1] as? String == "default"
        print("\(titleBarOnTop ? "PASS" : "FAIL") the title bar takes the pointer and shows the normal pointer over text under it \(titleBarOnTop ? "" : "(\(onTop))")")
        if !titleBarOnTop { failures += 1 }
        let wheelThrough = onTop.count == 4 && onTop[2] as? Double == 40 && onTop[3] as? Bool == true
        print("\(wheelThrough ? "PASS" : "FAIL") the scroll wheel on the title bar scrolls the messages under it \(wheelThrough ? "" : "(\(onTop))")")
        if !wheelThrough { failures += 1 }
        _ = try await web.evaluateJavaScript("document.documentElement.dataset.quickChatPointer = 'outside'")
        try await Task.sleep(for: .milliseconds(60))
        let fadesOut = try await web.evaluateJavaScript("(v => v > 0 && v < 1)(+getComputedStyle(document.querySelector('header')).getPropertyValue('--quick-chat-title-bar-shown'))") as? Bool == true
        print("\(fadesOut ? "PASS" : "FAIL") pointer outside the panel again: the title bar fades out")
        if !fadesOut { failures += 1 }
        try await Task.sleep(for: .milliseconds(300))
        // The normal page did not start safe mode (its checks ran 1.5 and 5 seconds after load).
        try await Task.sleep(for: .seconds(1))
        let styleOn = try await web.evaluateJavaScript("!document.documentElement.hasAttribute('data-quick-chat-safe-mode') && document.adoptedStyleSheets.some(s => !s.disabled && [...s.cssRules].some(r => r.name === '--quick-chat-title-bar-shown'))") as? Bool == true
        print("\(styleOn ? "PASS" : "FAIL") safe mode: the style stays on for a page that it does not harm")
        if !styleOn { failures += 1 }
        window.orderOut(nil)

        // Safe mode: a page change that puts the composer next to its wrapper (so the style hides
        // it) turns the style off, and the composer shows again.
        let changed = WKWebView(frame: NSRect(x: 0, y: 0, width: 440, height: 540), configuration: configuration)
        let changedWindow = NSWindow(contentRect: changed.frame, styleMask: .borderless, backing: .buffered, defer: false)
        changedWindow.contentView = changed
        changedWindow.orderFront(nil)
        changed.loadHTMLString("""
            <!doctype html><html><body><div data-app-shell-active-page="true"><main data-app-shell-main-surface>
            <header data-app-shell-titlebar></header>
            <div role="main"><div><div data-home-feed-composer></div>
            <form data-chatgpt-composer><div data-composer-body><div contenteditable="true">Draft</div></div></form></div></div>
            </main></div></body></html>
            """, baseURL: URL(string: "https://chatgpt.com/"))
        try await Task.sleep(for: .seconds(3))
        let safe = try await changed.evaluateJavaScript("""
            (() => {
                const editor = document.querySelector('[contenteditable="true"]');
                const style = document.adoptedStyleSheets.find(s => [...s.cssRules].some(r => r.name === '--quick-chat-title-bar-shown'));
                return document.documentElement.dataset.quickChatSafeMode === 'composer' && !!style && style.disabled &&
                    editor.checkVisibility({ opacityProperty: true, visibilityProperty: true });
            })()
            """) as? Bool == true
        print("\(safe ? "PASS" : "FAIL") safe mode: the style turns itself off when it hides the composer")
        if !safe { failures += 1 }
        changedWindow.orderOut(nil)

        // PageHooks names every data attribute and CSS variable of the page that the style and
        // the panel's scripts use, so the daily page check covers them. Attributes that only
        // start a new page report (data-state, data-theme) need no check.
        let used = [QuickChatPageStyle.css, QuickChatPageStyle.script, QuickChatPageStyle.newChatScript,
                    QuickChatPageStyle.toggleSidebarScript, QuickChatPageStyle.temporaryChatButtons,
                    QuickChatPageStyle.focusComposerScript].joined(separator: "\n")
        let checked = PageHooks.Page.allCases.map(PageHooks.checkScript(for:)).joined(separator: "\n")
        let pattern = try NSRegularExpression(pattern: #"(?<![\w-])(data-[a-z0-9-]+|--[a-z][a-z0-9-]+)"#)
        let names = Set(pattern.matches(in: used, range: NSRange(used.startIndex..., in: used)).map { String(used[Range($0.range, in: used)!]) })
            .filter { !$0.hasPrefix("data-quick-chat") && !$0.hasPrefix("--quick-chat") && !["data-state", "data-theme"].contains($0) }
        let missing = names.filter { !checked.contains($0) }.sorted()
        print("\(missing.isEmpty ? "PASS" : "FAIL") PageHooks checks every page hook that the style uses\(missing.isEmpty ? "" : " (missing: \(missing.joined(separator: ", ")))")")
        if !missing.isEmpty { failures += 1 }

        print("\(failures) failed checks")
        exit(failures == 0 ? 0 : 1)
    }
}
