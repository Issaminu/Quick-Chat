# Run with python3 scripts/check-panel.py on macOS.
# Builds the real panel in an isolated app; only its initial page is replaced by a local fixture
# with the same hooks as chatgpt.com.
from pathlib import Path
import plistlib
import subprocess
import tempfile

repo=Path(__file__).resolve().parents[1]
root=Path(tempfile.mkdtemp(prefix='quickchat-panel-check-'))
source=repo/'Sources/QuickChat/Features/QuickChat/QuickChatPanel.swift'
s=source.read_text().replace('private func makePanel()', 'func makePanel()')
a='\n        webView.load(URLRequest(url: Self.chatURL))\n'
assert s.count(a)==1
s=s.replace(a,'\n        webView.loadHTMLString(Check.fixture, baseURL: URL(string:"https://chatgpt.com/c/previous")!)\n')
s=s.replace('config.websiteDataStore = .default()','config.websiteDataStore = .nonPersistent()')
(root/'QuickChatPanel.swift').write_text(s)
(root/'main.swift').write_text(r'''
import AppKit
import WebKit

@MainActor
final class NavigationSpy: NSObject, WKNavigationDelegate {
    var requests=0
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,
                 decisionHandler:@escaping @MainActor (WKNavigationActionPolicy)->Void) {
        requests += 1
        decisionHandler(.cancel)
    }
}
@MainActor
enum Check {
    static var failures=0
    static let fixture="""
    <!doctype html><html style="color-scheme:dark"><head><style>
    *{box-sizing:border-box}body{margin:0;color:white}main{height:100vh}
    header{position:fixed;top:0;left:0;right:0;height:52px;display:flex;pointer-events:none}
    header button{pointer-events:auto;width:36px;height:36px}
    form{position:absolute;bottom:8px;left:8px;right:8px}
    </style></head><body><div data-app-shell-active-page="true"><main data-app-shell-main-surface>
    <header data-app-shell-titlebar><div data-app-shell-header-slot="start"><div data-app-shell-header-slot-content>
    <div><button aria-controls="sidebar" id="sidebar">Sidebar</button></div><div><button id="new-chat">New</button></div></div></div>
    <div data-app-shell-main-titlebar><button id="temporary" aria-label="Temporary chat">Temporary</button></div></header>
    <article id="previous-conversation">Previous conversation</article>
    <form data-chatgpt-composer><div id="draft" contenteditable="true">Draft</div></form></main></div>
    <a href="/" id="home">Home</a>
    <script>
    window.clicks={temporary:0,newChat:0,home:0,sidebar:0};
    document.querySelector('#sidebar').onclick=()=>clicks.sidebar++;
    document.querySelector('#temporary').onclick=()=>clicks.temporary++;
    document.querySelector('#new-chat').onclick=()=>{clicks.newChat++;document.querySelector('#previous-conversation')?.remove();document.querySelector('#draft').textContent=''};
    document.querySelector('#home').onclick=event=>{event.preventDefault();clicks.home++};
    </script></body></html>
    """
    static func check(_ pass:Bool,_ label:String,_ detail:Any? = nil) {
        print("\(pass ? "PASS" : "FAIL") \(label)\(pass || detail == nil ? "" : " (\(detail!))")")
        if !pass { failures += 1 }
    }
    static func wait(_ condition:@escaping @MainActor () async ->Bool) async {
        for _ in 0..<100 { if await condition() { return }; try? await Task.sleep(for:.milliseconds(50)) }
    }
    static func js(_ web:WKWebView,_ code:String) async -> Any? { try? await web.evaluateJavaScript(code) }
    static func visible(_ buttons:HeaderButtons) -> [String] {
        [(buttons.close,"close"),(buttons.sidebar,"sidebar"),(buttons.openInBrowser,"open"),(buttons.temporaryChat,"temporary"),(buttons.newChat,"new")]
            .filter{!$0.0.isHiddenOrHasHiddenAncestor}.map{$0.1}
    }
    static func run() async {
        let controller=QuickChatController()
        let panel=controller.makePanel()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        let background=panel.contentView as! NSVisualEffectView
        let web=background.subviews.compactMap{$0 as? WKWebView}.first!
        let buttons=background.subviews.compactMap{$0 as? HeaderButtons}.first!
        let loading=background.subviews.compactMap{$0 as? LoadingView}.first!
        let screen=NSScreen.screens.first{$0.frame.intersects(panel.frame)}!
        check(abs(panel.frame.minX-(screen.visibleFrame.midX-panel.frame.width/2))<1 && abs(panel.frame.minY-(screen.visibleFrame.minY+32))<1,"fresh panel opens bottom-center")
        check(panel.frame.size==NSSize(width:440,height:540),"default dimensions match the reference popup")
        check(background.maskImage != nil,"window has a rounded shape, so its shadow follows the corners")
        check(web.acceptsFirstMouse(for:nil) && buttons.close.acceptsFirstMouse(for:nil),"the first click on a panel that is not key reaches the page and the buttons")

        let locations:[(String,Bool,Bool)]=[("https://chatgpt.com/",false,false),("https://chatgpt.com/?temporary-chat=true",false,true),
            ("https://chatgpt.com/c/abc",true,false),("https://chatgpt.com/c/abc?temporary-chat=true",true,true),
            ("https://chatgpt.com/g/g-p-1/c/abc",true,false),("https://chatgpt.com/c/",false,false)]
        check(locations.allSatisfy{let l=QuickChatLocation(URL(string:$0.0)); return l.isChatGPT && l.isConversation==$0.1 && l.isTemporary==$0.2},"addresses are read as empty chat or conversation, temporary or not")
        check(!QuickChatLocation(URL(string:"https://auth.openai.com/log-in")).isChatGPT,"other sites are not ChatGPT")

        await wait { visible(buttons).count==4 && !loading.isLoading }
        check(!loading.isLoading,"the loading view hides when the page is ready")
        check(visible(buttons)==["close","sidebar","open","new"],"conversation shows Close, Sidebar, Open in Browser and New Chat",visible(buttons))
        buttons.update(for:URL(string:"https://chatgpt.com/"))
        check(visible(buttons)==["close","sidebar","temporary"],"empty chat shows Close, Sidebar and Temporary Chat",visible(buttons))
        let offImage=buttons.temporaryChat.image
        buttons.update(for:URL(string:"https://chatgpt.com/?temporary-chat=true"))
        check(visible(buttons)==["close","sidebar","temporary"] && buttons.temporaryChat.isActive,"temporary empty chat shows Close, Sidebar and an active Temporary Chat")
        check(buttons.temporaryChat.image !== offImage,"an active Temporary Chat shows its filled icon")
        buttons.update(for:URL(string:"https://chatgpt.com/c/abc?temporary-chat=true"))
        check(visible(buttons)==["close","sidebar","new"],"temporary conversation shows Close, Sidebar and New Chat")
        buttons.update(for:URL(string:"https://auth.openai.com/log-in"))
        check(visible(buttons).isEmpty,"buttons hide on other sites")
        check(buttons.hitTest(NSPoint(x:200,y:20)) == nil,"the title bar between the buttons belongs to the page")
        buttons.update(for:web.url)

        _=await js(web,"document.body.insertAdjacentHTML('beforeend','<div id=\"dialog\" role=\"dialog\" style=\"position:fixed;inset:0;background:#000\"></div>')")
        await wait { visible(buttons).isEmpty }
        check(visible(buttons).isEmpty,"buttons hide while a dialog or the sidebar covers their corner")
        _=await js(web,"document.querySelector('#dialog').remove()")
        await wait { visible(buttons).count==4 }
        check(visible(buttons).count==4,"buttons come back when the corner is clear")

        let spy=NavigationSpy()
        web.navigationDelegate=spy
        buttons.update(for:URL(string:"https://chatgpt.com/"))
        buttons.temporaryChat.performClick(nil)
        await wait { (await js(web,"clicks.temporary")) as? Int == 1 }
        check((await js(web,"clicks.temporary")) as? Int == 1 && spy.requests==0,"Temporary Chat uses the page's own button without loading")
        _=await js(web,"document.querySelector('#temporary').setAttribute('aria-label','Turn off temporary chat')")
        buttons.update(for:URL(string:"https://chatgpt.com/?temporary-chat=true"))
        buttons.temporaryChat.performClick(nil)
        await wait { (await js(web,"clicks.temporary")) as? Int == 2 }
        check((await js(web,"clicks.temporary")) as? Int == 2 && spy.requests==0,"leaving a temporary chat uses the page's own button without loading")
        buttons.update(for:web.url)
        buttons.newChat.performClick(nil)
        await wait { (await js(web,"clicks.newChat")) as? Int == 1 }
        check((await js(web,"clicks.newChat")) as? Int == 1 && spy.requests==0,"New Chat uses the page's own button without loading")
        check((await js(web,"!document.querySelector('#previous-conversation') && document.querySelector('#draft').textContent===''")) as? Bool == true,"New Chat clears the conversation and draft")
        let commandN=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:panel.windowNumber,context:nil,characters:"n",charactersIgnoringModifiers:"n",isARepeat:false,keyCode:45)!
        panel.sendEvent(commandN)
        await wait { (await js(web,"clicks.newChat")) as? Int == 2 }
        check((await js(web,"clicks.newChat")) as? Int == 2,"Command-N does the same as New Chat")
        _=await js(web,"document.querySelector('#new-chat').remove()")
        panel.sendEvent(commandN)
        await wait { (await js(web,"clicks.home")) as? Int == 1 }
        check((await js(web,"clicks.home")) as? Int == 1 && spy.requests==0,"without that button, New Chat uses the page's Home link")

        buttons.sidebar.performClick(nil)
        await wait { (await js(web,"clicks.sidebar")) as? Int == 1 }
        check((await js(web,"clicks.sidebar")) as? Int == 1,"the panel's sidebar button uses the page's sidebar button")
        controller.setPointerInside(false)
        try? await Task.sleep(for:.milliseconds(250))
        controller.setPointerInside(true)
        try? await Task.sleep(for:.milliseconds(1000))
        check(buttons.alphaValue == 1,"the title bar stays when the pointer comes back within 0.5 seconds")
        controller.setPointerInside(false)
        try? await Task.sleep(for:.milliseconds(250))
        check(buttons.alphaValue == 1,"the title bar waits before it hides")
        await wait { buttons.alphaValue == 0 }
        let pointerOutside=(await js(web,"document.documentElement.dataset.quickChatPointer")) as? String
        check(buttons.alphaValue == 0 && pointerOutside == "outside","the title bar hides while the pointer is outside the panel")
        controller.setPointerInside(true)
        await wait { buttons.alphaValue == 1 }
        let pointerInside=(await js(web,"document.documentElement.dataset.quickChatPointer")) as? String
        check(buttons.alphaValue == 1 && pointerInside == "inside","the title bar shows again when the pointer comes back")

        let frame=panel.frame
        _=await js(web,"webkit.messageHandlers.quickChat.postMessage({type:'drag'})")
        try? await Task.sleep(for:.milliseconds(200))
        check(panel.frame==frame,"a drag message without a pressed mouse button does nothing")
        _=await js(web,"webkit.messageHandlers.quickChat.postMessage({type:'zoom'})")
        await wait { panel.isMaximized }
        check(panel.isMaximized,"double press on the title bar maximizes")
        _=await js(web,"webkit.messageHandlers.quickChat.postMessage({type:'zoom'})")
        await wait { !panel.isMaximized && panel.frame==frame }
        check(!panel.isMaximized && panel.frame==frame,"another double press restores the frame","\(panel.isMaximized) \(panel.frame) expected \(frame)")

        buttons.close.performClick(nil)
        check(!panel.isVisible,"Close hides the panel")
        controller.show()
        panel.cancelOperation(nil)
        check(!panel.isVisible,"Escape action hides the panel")
        controller.show()
        _=await js(web,"document.querySelector('#draft').addEventListener('keydown', e => e.preventDefault()); document.querySelector('#draft').dispatchEvent(new KeyboardEvent('keydown', {key:'Escape', bubbles:true}))")
        await wait { !panel.isVisible }
        check(!panel.isVisible,"Esc in the composer hides the panel, although the composer claims the key")
        controller.show()
        _=await js(web,"document.body.insertAdjacentHTML('beforeend','<div id=\"menu\" role=\"menu\">Menu</div>'); document.querySelector('#draft').dispatchEvent(new KeyboardEvent('keydown', {key:'Escape', bubbles:true}))")
        try? await Task.sleep(for:.milliseconds(300))
        check(panel.isVisible,"while a menu is open, Esc goes to the menu and the panel stays")
        _=await js(web,"document.querySelector('#menu').remove()")
        controller.show()
        check(panel.isVisible && background.subviews.contains(web),"showing after hide keeps the same web view")

        let saved=NSPoint(x:screen.visibleFrame.minX+80,y:screen.visibleFrame.minY+100)
        panel.setFrame(NSRect(origin:saved,size:NSSize(width:500,height:640)),display:false)
        panel.saveFrame(usingName:QuickChatPanel.autosaveName)
        controller.tearDown()
        panel.setFrameAutosaveName("") // release the first window's name, as a closed app would
        let restored=QuickChatController()
        let restoredPanel=restored.makePanel()
        check(restoredPanel.frame.origin==saved && restoredPanel.frame.size==NSSize(width:500,height:640),"saved position and size are restored instead of recentered")
        restored.tearDown()
        print("\(failures) failed checks")
        fflush(nil)
        exit(failures==0 ? 0 : 1)
    }
}
MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    // Isolated preferences: the check must not move the real panel's saved position.
    UserDefaults.standard.removePersistentDomain(forName:Bundle.main.bundleIdentifier!)
    Task { await Check.run() }
    NSApplication.shared.run()
}
''')
app=root/'QuickChatPanelCheck.app'
(app/'Contents/MacOS').mkdir(parents=True)
sources=[str(p) for p in sorted((repo/'Sources/QuickChat').rglob('*.swift')) if p.name not in ('main.swift','QuickChatPanel.swift')]
subprocess.run(['swiftc','-swift-version','6','-warnings-as-errors','-o',str(app/'Contents/MacOS/Check'),*sources,str(root/'QuickChatPanel.swift'),str(root/'main.swift')],check=True,timeout=120)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'Check','CFBundleIdentifier':'local.quickchat.panelcheck','CFBundleName':'Quick Chat Panel Check','CFBundlePackageType':'APPL','LSUIElement':True}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print('Check directory: '+str(root),flush=True)
result=subprocess.run([str(app/'Contents/MacOS/Check')],timeout=60)
raise SystemExit(result.returncode)
