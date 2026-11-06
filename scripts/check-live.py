# Run with python3 scripts/check-live.py on macOS, after you sign in to Quick Chat once.
# Checks the panel on the real chatgpt.com with your Quick Chat session: the empty chat, a
# temporary chat, and your most recent conversation. It sends no messages. Run it when ChatGPT
# changes its page, to see which part of the style lost its hook. Quit Quick Chat first.
from pathlib import Path
import plistlib
import subprocess
import tempfile

repo=Path(__file__).resolve().parents[1]
root=Path(tempfile.mkdtemp(prefix='quickchat-live-check-'))
source=repo/'Sources/QuickChat/Features/QuickChat/QuickChatPanel.swift'
(root/'QuickChatPanel.swift').write_text(source.read_text().replace('private func makePanel()', 'func makePanel()'))
(root/'main.swift').write_text(r'''
import AppKit
import WebKit

@MainActor
enum Check {
    static var failures=0
    static func check(_ pass:Bool,_ label:String,_ detail:Any? = nil) {
        print("\(pass ? "PASS" : "FAIL") \(label)\(pass || detail == nil ? "" : " (\(detail!))")")
        if !pass { failures += 1 }
    }
    static func js(_ web:WKWebView,_ code:String) async -> Any? {
        try? await web.callAsyncJavaScript(code, arguments:[:], in:nil, contentWorld:.page)
    }
    static func wait(_ seconds:Double, _ condition:@escaping @MainActor () async ->Bool) async {
        let end=Date().addingTimeInterval(seconds)
        while Date()<end { if await condition() { return }; try? await Task.sleep(for:.milliseconds(100)) }
    }
    static func visible(_ buttons:HeaderButtons) -> [String] {
        [(buttons.close,"close"),(buttons.sidebar,"sidebar"),(buttons.openInBrowser,"open"),(buttons.temporaryChat,"temporary"),(buttons.newChat,"new")]
            .filter{!$0.0.isHiddenOrHasHiddenAncestor}.map{$0.1}
    }
    /// Layout facts about the rendered page (the page keeps hidden copies of earlier pages).
    static let measure = """
        const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true });
        const rendered = selector => [...document.querySelectorAll(selector)].find(e => e.getClientRects().length);
        const body = rendered('[data-composer-body]');
        if (!body) return null;
        const r = body.getBoundingClientRect();
        const scroller = rendered('[data-app-action-timeline-scroll]');
        const main = rendered('[role="main"]');
        const text = main ? [...main.querySelectorAll('*')].filter(e => e.children.length === 0 && e.textContent.trim() && shown(e) && !e.closest('form')) : [];
        const alpha = color => { const c = document.createElement('canvas').getContext('2d'); c.fillStyle = color; c.fillRect(0, 0, 1, 1); return c.getImageData(0, 0, 1, 1).data[3]; };
        return {
            styled: document.adoptedStyleSheets.some(s => [...s.cssRules].some(r => r.name === 'quick-chat-follow-scroll')),
            loading: document.readyState,
            insets: [r.left, innerWidth - r.right, innerHeight - r.bottom],
            radius: getComputedStyle(body).borderTopLeftRadius,
            composerAlpha: alpha(getComputedStyle(rendered('[data-composer-layout][data-composer-surface-variant]') || body).backgroundColor) + alpha(getComputedStyle(body).backgroundColor),
            pageAlpha: alpha(getComputedStyle(document.body).backgroundColor) + alpha(getComputedStyle(rendered('main[data-app-shell-main-surface]') || document.body).backgroundColor),
            headerButtons: [...document.querySelectorAll('header[data-app-shell-titlebar] button')].filter(shown).length,
            sidebarButton: rendered('header[data-app-shell-titlebar] button[aria-controls]')?.getBoundingClientRect().left ?? null,
            smoothing: getComputedStyle(body).webkitFontSmoothing,
            overscroll: getComputedStyle(scroller || document.documentElement).overscrollBehaviorY,
            textSize: scroller ? getComputedStyle(scroller.firstElementChild).getPropertyValue('--font-text-md-size').trim() : null,
            textOutsideComposer: text.map(e => e.textContent.trim().slice(0, 30)).slice(0, 5),
            gap: scroller ? Math.round(r.top - scroller.getBoundingClientRect().bottom) : null,
            mask: scroller ? getComputedStyle(scroller.firstElementChild).animationName : null,
            conversation: rendered('a[href*="/c/"]')?.getAttribute('href') || document.querySelector('a[href*="/c/"]')?.getAttribute('href') || null
        };
        """
    static func checkLayout(_ web:WKWebView,_ state:String,empty:Bool) async {
        // Until the HTML finishes loading, ChatGPT shows a placeholder page without its title bar.
        await wait(30) { (await js(web,"return document.readyState === 'complete' && !!document.querySelector('header[data-app-shell-titlebar]') && !!document.querySelector('form[data-chatgpt-composer]')")) as? Bool == true }
        try? await Task.sleep(for:.milliseconds(500))
        guard let m = await js(web,measure) as? [String:Any] else { return check(false,"\(state): composer is on the page") }
        check(m["styled"] as? Bool == true,"\(state): the panel style is on the page","page is \(m["loading"]!)")
        check((m["insets"] as? [Double])?.map{$0.rounded()} == [8,8,8],"\(state): composer insets are 8 points",m["insets"]!)
        check(m["radius"] as? String == "12px","\(state): composer corners are concentric with the window",m["radius"]!)
        let composerAlpha=m["composerAlpha"] as? Int ?? 0
        check(composerAlpha > 0 && composerAlpha < 80,"\(state): composer is translucent",composerAlpha)
        check(m["pageAlpha"] as? Int == 0,"\(state): page background is transparent",m["pageAlpha"]!)
        check(m["headerButtons"] as? Int == 0,"\(state): the page draws no title bar buttons (the panel draws them)",m["headerButtons"]!)
        check(m["sidebarButton"] as? Double == 52,"\(state): the page's sidebar button sits under the panel's sidebar button",m["sidebarButton"]!)
        check(m["smoothing"] as? String == "auto","\(state): text uses the system's font smoothing",m["smoothing"]!)
        check(m["overscroll"] as? String == "none","\(state): scrolling does not stretch at the ends",m["overscroll"]!)
        if empty {
            check((m["textOutsideComposer"] as? [String])?.isEmpty == true,"\(state): no greeting or notice text",m["textOutsideComposer"]!)
        } else {
            check(m["gap"] as? Int == 0,"\(state): messages end at the composer top",m["gap"]!)
            check(m["mask"] as? String == "quick-chat-follow-scroll","\(state): messages fade above the composer",m["mask"]!)
            check(m["textSize"] as? String == "15px","\(state): message text is 15 points",m["textSize"]!)
        }
    }
    static func run() async {
        let controller=QuickChatController()
        let panel=controller.makePanel()
        controller.show()
        let background=panel.contentView!
        let web=background.subviews.compactMap{$0 as? WKWebView}.first!
        let buttons=background.subviews.compactMap{$0 as? HeaderButtons}.first!
        await wait(30) { (await js(web,"return !!document.querySelector('[data-composer-body]')")) as? Bool == true }
        guard web.url?.host == "chatgpt.com", (await js(web,"return !!document.querySelector('header[data-app-shell-titlebar]')")) as? Bool == true else {
            print("FAIL the signed-in ChatGPT page did not load; sign in to Quick Chat first")
            exit(1)
        }
        controller.setPointerInside(true) // the title bar shows only while the pointer is over the panel
        // The checks use the default size; the saved frame is put back at the end.
        let savedFrame=panel.frame
        panel.setFrame(NSRect(origin:savedFrame.origin,size:QuickChatPanel.defaultSize),display:true)
        try? await Task.sleep(for:.seconds(1))
        await checkLayout(web,"empty chat",empty:true)
        check(visible(buttons)==["close","sidebar","temporary"],"empty chat: panel shows Close, Sidebar and Temporary Chat",await js(web,"return [document.elementFromPoint(innerWidth - 26, 26), document.elementFromPoint(innerWidth - 70, 26)].map(e => e?.outerHTML.slice(0, 160)).join(' | ') + ' active:' + !!document.querySelector('[data-app-shell-active-page=\"true\"] form[data-chatgpt-composer]')") as Any)
        // A wide window: the page centers its content and docks the sidebar rail. The panel's
        // own frame is put back afterwards, as this check uses Quick Chat's saved settings.
        let frame=panel.frame
        panel.setFrame(NSRect(x:frame.minX,y:frame.minY,width:700,height:780),display:true)
        try? await Task.sleep(for:.seconds(1.5))
        let wide=await js(web,"""
            const rendered = selector => [...document.querySelectorAll(selector)].find(e => e.getClientRects().length);
            const body = rendered('[data-composer-body]').getBoundingClientRect();
            const alpha = color => { const c = document.createElement('canvas').getContext('2d'); c.fillStyle = color; c.fillRect(0, 0, 1, 1); return c.getImageData(0, 0, 1, 1).data[3]; };
            const painted = [...document.querySelectorAll('body *')].filter(e => { const r = e.getBoundingClientRect(); return r.width > innerWidth / 2 && r.height > innerHeight / 2; })
                .flatMap(e => [getComputedStyle(e), getComputedStyle(e, '::before')]).filter(s => alpha(s.backgroundColor) === 255).length;
            return [Math.round(innerHeight - body.bottom), painted];
            """) as? [Int]
        panel.setFrame(frame,display:true)
        check(wide?[0]==8,"wide empty chat: composer stays at the bottom",wide as Any)
        check(wide?[1]==0,"wide empty chat: page background stays transparent",wide as Any)

        buttons.temporaryChat.performClick(nil)
        await wait(10) { QuickChatLocation(web.url).isTemporary }
        try? await Task.sleep(for:.seconds(1))
        check(QuickChatLocation(web.url).isTemporary,"Temporary Chat starts a temporary chat",web.url as Any)
        await checkLayout(web,"temporary chat",empty:true)
        check(visible(buttons)==["close","sidebar","temporary"],"temporary chat: panel shows Close, Sidebar and Temporary Chat",visible(buttons))
        buttons.temporaryChat.performClick(nil)
        await wait(10) { !QuickChatLocation(web.url).isTemporary }
        check(!QuickChatLocation(web.url).isTemporary,"Temporary Chat again leaves the temporary chat",web.url as Any)

        try? await Task.sleep(for:.seconds(1)) // the new page settles and takes focus
        // Opens the most recent conversation from the sidebar, which lists conversations only while open.
        let opened=await js(web,"""
            const rendered = () => [...document.querySelectorAll('a[href*="/c/"]')].find(e => e.getClientRects().length);
            const sidebarButton = () => [...document.querySelectorAll('header[data-app-shell-titlebar] button[aria-controls]')].find(e => e.getClientRects().length);
            // The list loads after the sidebar opens. A click during a page change can be lost, so click again.
            for (let i = 0; i < 150 && !rendered(); i++) {
                if (i % 30 === 0 && sidebarButton()?.getAttribute('aria-expanded') !== 'true') sidebarButton()?.click();
                await new Promise(resolve => setTimeout(resolve, 100));
            }
            await new Promise(resolve => setTimeout(resolve, 800)); // let the sidebar finish opening
            const link = rendered();
            link?.click();
            return link?.getAttribute('href') ?? null;
            """) as? String
        if let opened {
            print("Opened \(opened)")
            await wait(15) {
                let loaded=(await js(web,"return !!document.querySelector('[data-app-action-timeline-scroll]')")) as? Bool == true
                return loaded && QuickChatLocation(web.url).isConversation
            }
            try? await Task.sleep(for:.seconds(2))
            await checkLayout(web,"conversation",empty:false)
            check(visible(buttons)==["close","sidebar","open","new"],"conversation: panel shows Close, Sidebar, Open in Browser and New Chat",visible(buttons))
            panel.sendEvent(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:panel.windowNumber,context:nil,characters:"n",charactersIgnoringModifiers:"n",isARepeat:false,keyCode:45)!)
            await wait(10) { !QuickChatLocation(web.url).isConversation }
            check(!QuickChatLocation(web.url).isConversation,"Command-N starts a new chat",web.url as Any)
        } else {
            print("SKIP conversation checks: no conversation in the sidebar", await js(web,"return [document.querySelectorAll('a[href*=\"/c/\"]').length, [...document.querySelectorAll('[aria-controls]')].map(e => e.getAttribute('aria-expanded')).join(), location.href]") as Any)
        }
        panel.setFrame(savedFrame,display:true)
        panel.saveFrame(usingName:QuickChatPanel.autosaveName)
        controller.tearDown()
        print("\(failures) failed checks")
        fflush(nil)
        exit(failures==0 ? 0 : 1)
    }
}
MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    Task { await Check.run() }
    NSApplication.shared.run()
}
''')
app=root/'QuickChatLiveCheck.app'
(app/'Contents/MacOS').mkdir(parents=True)
sources=[str(p) for p in sorted((repo/'Sources/QuickChat').rglob('*.swift')) if p.name not in ('main.swift','QuickChatPanel.swift')]
subprocess.run(['swiftc','-swift-version','6','-warnings-as-errors','-o',str(app/'Contents/MacOS/QuickChat'),*sources,str(root/'QuickChatPanel.swift'),str(root/'main.swift')],check=True,timeout=120)
# Quick Chat's bundle identifier, so the check uses Quick Chat's signed-in session.
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'QuickChat','CFBundleIdentifier':'dev.shuaibird.quickchat','CFBundleName':'Quick Chat Live Check','CFBundlePackageType':'APPL','LSUIElement':True}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
result=subprocess.run([str(app/'Contents/MacOS/QuickChat')],timeout=180)
raise SystemExit(result.returncode)
