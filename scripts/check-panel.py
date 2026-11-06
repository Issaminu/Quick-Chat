# Run with python3 scripts/check-panel.py on macOS.
# Builds the real panel in an isolated app; only its initial page is replaced by a local fixture.
from pathlib import Path
import plistlib
import subprocess
import tempfile

repo=Path(__file__).resolve().parents[1]
root=Path(tempfile.mkdtemp(prefix='quickchat-navigation-check-'))
source=repo/'Sources/QuickChat/Features/QuickChat/QuickChatPanel.swift'
s=source.read_text().replace('private func makePanel()', 'func makePanel()').replace('private func makeWebView()', 'func makeWebView()')
a='\n        webView.load(URLRequest(url: Self.chatURL))\n'
assert s.count(a)==1
s=s.replace(a,'\n        webView.loadHTMLString(Check.fixture, baseURL: URL(string:"https://chatgpt.com/c/previous")!)\n')
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
    <!doctype html><html style="color-scheme:dark;--bg-primary:#202020;--main-surface-primary:#202020"><head><style>
    *{box-sizing:border-box}body{margin:0;color:white}#root,main{background:var(--bg-primary);height:100vh}
    #sidebar{position:absolute;top:0;left:0;width:320px;height:100vh;background:var(--bg-primary);z-index:10}
    #search{position:absolute;top:8px;left:100px;width:160px;height:28px}#new-chat{position:absolute;top:60px;left:75px}
    #modes{position:absolute;top:80px;right:0}#other-tabs{position:absolute;top:150px;right:0}
    form{position:absolute;bottom:10px;left:12px;right:12px}#prompt-textarea{height:50px}
    </style></head><body><div id="root"><header data-app-shell-titlebar style="position:absolute;top:0;z-index:30;height:52px;width:100%"><button aria-label="Show sidebar">Sidebar</button><button id="temporary" aria-label="Temporary chat">Temporary</button></header><main><article id="previous-conversation">Previous conversation</article>
    <form><div id="prompt-textarea" contenteditable="true">Draft</div></form></main>
    <aside id="sidebar" role="dialog"><input id="search" aria-label="Search chats"><button id="new-chat" data-testid="create-new-chat-button">New chat</button></aside>
    <div id="modes"><button role="switch" aria-label="Chat">Chat</button><button role="switch" aria-label="Work">Work</button></div>
    <div id="other-tabs" role="tablist"><button role="tab">Chat</button><button role="tab">Settings</button></div></div>
    <script>window.temporaryClicks=0;document.querySelector('#temporary').onclick=()=>{window.temporaryClicks++};window.newChatClicks=0;document.querySelector('#new-chat').onclick=()=>{window.newChatClicks++;document.querySelector('#previous-conversation')?.remove();document.querySelector('#prompt-textarea').textContent='';document.querySelector('#sidebar').style.display='none'};</script>
    </body></html>
    """
    static func check(_ pass:Bool,_ label:String) { print("\(pass ? "PASS" : "FAIL") \(label)"); if !pass { failures += 1 } }
    static func wait(_ condition:@escaping @MainActor () async ->Bool) async {
        for _ in 0..<100 { if await condition() { return }; try? await Task.sleep(for:.milliseconds(50)) }
        fatalError("Fixture timeout")
    }
    static func run() async {
        let controller=QuickChatController()
        let panel=controller.makePanel()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        let background=panel.contentView!
        let web=background.subviews.compactMap{$0 as? WKWebView}.first!
        let screen=NSScreen.screens.first{$0.frame.intersects(panel.frame)}!
        check(abs(panel.frame.minX-(screen.visibleFrame.midX-panel.frame.width/2))<1 && abs(panel.frame.minY-(screen.visibleFrame.minY+32))<1,"fresh panel opens bottom-center")
        check(panel.frame.size==NSSize(width:440,height:540),"default dimensions match the reference popup")
        check(background.subviews.compactMap{$0 as? NSButton}.isEmpty,"no native header buttons can overlap website controls")
        panel.setContentSize(QuickChatPanel.defaultSize)
        background.layoutSubtreeIfNeeded()
        await wait { (try? await web.evaluateJavaScript("!!document.getElementById('quick-chat-page-style')")) as? Bool == true }
        let style=try! await web.evaluateJavaScript("({sidebar:getComputedStyle(document.querySelector('#sidebar')).backgroundColor,mode:getComputedStyle(document.querySelector('#modes')).display,other:getComputedStyle(document.querySelector('#other-tabs')).display})") as! [String:String]
        check(style["sidebar"] != "rgba(0, 0, 0, 0)","sidebar stays opaque over conversation")
        check(style["mode"] == "none","Chat/Work switch hidden")
        check(style["other"] != "none","unrelated tabs remain visible")
        let drag=background.subviews.first{!($0 is WKWebView)}!
        await wait { !drag.isHidden }
        check(!drag.isHidden,"drag area becomes available on the chat page")
        let nativePoint=NSPoint(x:180,y:background.bounds.maxY-22)
        check(drag.isHidden || drag.hitTest(nativePoint)==nil,"sidebar search is not intercepted by window dragging")
        let temporaryPoint=NSPoint(x:22,y:background.bounds.maxY-22)
        check(drag.hitTest(temporaryPoint)==nil,"Temporary Chat is not intercepted by window dragging")
        _=try! await web.evaluateJavaScript("document.querySelector('#temporary').click()")
        check((try! await web.evaluateJavaScript("window.temporaryClicks")) as? Int == 1,"original Temporary Chat click handler is retained")
        check((try! await web.evaluateJavaScript("document.elementFromPoint(22,22)?.closest('button')?.id==='temporary'")) as? Bool == true,"Temporary Chat is the actual click target at the top left")
        panel.cancelOperation(nil)
        check(!panel.isVisible,"Escape action hides the panel")
        controller.show()
        check(panel.isVisible && background.subviews.contains(web),"showing after hide keeps the same web view")
        let spy=NavigationSpy()
        web.navigationDelegate=spy
        let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:panel.windowNumber,context:nil,characters:"n",charactersIgnoringModifiers:"n",isARepeat:false,keyCode:45)!
        panel.sendEvent(event)
        try? await Task.sleep(for:.milliseconds(200))
        let clicks=(try! await web.evaluateJavaScript("window.newChatClicks")) as! Int
        check(clicks==1 && spy.requests==0,"Command-N clicks New chat without navigating or reloading")
        let clean=(try! await web.evaluateJavaScript("!document.querySelector('#previous-conversation') && document.querySelector('#prompt-textarea').textContent===''") ) as! Bool
        if !clean { print(try! await web.evaluateJavaScript("JSON.stringify({previous:!!document.querySelector('#previous-conversation'),draft:document.querySelector('#prompt-textarea').textContent})") as Any) }
        check(clean,"New chat clears the current conversation and draft")
        _=try! await web.evaluateJavaScript("document.querySelector('#new-chat').remove();window.shortcutNewChats=0;document.addEventListener('keydown',event=>{if(event.metaKey&&event.shiftKey&&event.code==='KeyO'){event.preventDefault();window.shortcutNewChats++}})")
        panel.sendEvent(event)
        try? await Task.sleep(for:.milliseconds(150))
        check((try! await web.evaluateJavaScript("window.shortcutNewChats")) as? Int == 1 && spy.requests==0,"compact page falls back to ChatGPT's shortcut without reloading")
        _=try! await web.evaluateJavaScript("document.querySelector('#modes').replaceWith(Object.assign(document.createElement('div'),{id:'modes',innerHTML:'<button role=\\\"switch\\\" aria-label=\\\"Chat\\\">Chat</button><button role=\\\"switch\\\" aria-label=\\\"Work\\\">Work</button>'}))")
        try? await Task.sleep(for:.milliseconds(150))
        check((try! await web.evaluateJavaScript("getComputedStyle(document.querySelector('#modes')).display")) as? String == "none","mode switch remains hidden after client-side rendering")
        let saved=NSPoint(x:screen.visibleFrame.minX+80,y:screen.visibleFrame.minY+100)
        panel.setFrame(NSRect(origin:saved,size:NSSize(width:500,height:640)),display:false)
        panel.saveFrame(usingName:QuickChatPanel.autosaveName)
        controller.tearDown()
        panel.setFrameAutosaveName("") // release the first window's name, as a closed app would
        let restored=QuickChatController()
        let restoredPanel=restored.makePanel()
        print("Position restoration: saved=\(saved), restored=\(restoredPanel.frame.origin); preference=\(String(describing:UserDefaults.standard.string(forKey:"NSWindow Frame MiniChat.Panel")))")
        check(restoredPanel.frame.origin==saved && restoredPanel.frame.size==NSSize(width:500,height:640),"saved position and size are restored instead of recentered")
        restored.tearDown()
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
app=root/'QuickChatNavigationCheck.app'
(app/'Contents/MacOS').mkdir(parents=True)
sources=[str(p) for p in sorted((repo/'Sources/QuickChat').rglob('*.swift')) if p.name not in ('main.swift','QuickChatPanel.swift')]
subprocess.run(['swiftc','-swift-version','6','-warnings-as-errors','-o',str(app/'Contents/MacOS/Check'),*sources,str(root/'QuickChatPanel.swift'),str(root/'main.swift')],check=True,timeout=90)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'Check','CFBundleIdentifier':'local.quickchat.navigationcheck.'+root.name.rsplit('-',1)[-1],'CFBundleName':'Quick Chat Navigation Check','CFBundlePackageType':'APPL','LSUIElement':True}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print('Check directory: '+str(root),flush=True)
result=subprocess.run([str(app/'Contents/MacOS/Check')],timeout=30)
raise SystemExit(result.returncode)
