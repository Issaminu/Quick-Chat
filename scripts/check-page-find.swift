// Run from the repository root:
// swiftc -swift-version 6 -parse-as-library Sources/QuickChat/Features/QuickChat/PageFind.swift scripts/check-page-find.swift -o /tmp/quickchat-page-find-check
// /tmp/quickchat-page-find-check
//
// Checks the search of the find bar (⌘F) on a small local page: what it finds, the marks, the
// scroll to the current match, and a new search when the page changes.
import AppKit
import WebKit

@main
@MainActor
enum PageFindCheck {
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Task {
            do { try await check() }
            catch { print("FAIL: \(error)"); exit(1) }
        }
        NSApplication.shared.run()
    }

    static let fixture = """
        <!doctype html><html><head><style>
        html, body { margin:0; height:100%; background:#fff; color:#000; font:16px/24px -apple-system; }
        #scroll { position:absolute; inset:0 0 120px 0; overflow-y:auto; padding:0 16px; }
        .gap { height:900px; }
        .sr-only { position:absolute; width:1px; height:1px; overflow:hidden; clip:rect(0,0,0,0); }
        form { position:fixed; inset:auto 0 0 0; height:100px; background:#eee; }
        </style></head><body>
        <div id="scroll">
          <p id="first">Apple one</p>
          <p>foo <b>bar</b> and apple two</p>
          <p>the end</p><p>start of the next block</p>
          <div style="display:contents"><p>apple three in contents</p></div>
          <p style="display:none">apple hidden</p>
          <p style="visibility:hidden">apple invisible</p>
          <p style="opacity:0">apple transparent</p>
          <span class="sr-only">apple for screen readers</span>
          <p style="-webkit-user-select:none">apple that cannot be selected</p>
          <textarea>apple in a text area</textarea>
          <script>/* apple in a script */</script>
          <div id="spacer"></div><p id="low">lowword</p>
          <div class="gap"></div>
          <p id="far">far APPLE four</p>
          <div class="gap"></div>
        </div>
        <form data-chatgpt-composer style="display:none"><div>hidden copy of an earlier page</div></form>
        <form data-chatgpt-composer><div contenteditable="true">draft</div></form>
        </body></html>
        """

    final class Results: NSObject, WKScriptMessageHandler {
        var messages: [[String: Any]] = []
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any] { messages.append(body) }
        }
    }

    static func check() async throws {
        let config = WKWebViewConfiguration()
        let results = Results()
        config.userContentController.add(results, contentWorld: PageFind.world, name: PageFind.messageName)
        config.userContentController.addUserScript(WKUserScript(source: PageFind.script, injectionTime: .atDocumentStart,
                                                                forMainFrameOnly: true, in: PageFind.world))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 540), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        let webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        window.contentView!.addSubview(webView)
        window.orderFrontRegardless()
        webView.loadHTMLString(fixture, baseURL: URL(string: "https://chatgpt.com/"))
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(50))
            if !webView.isLoading { break }
        }
        try await Task.sleep(for: .milliseconds(200))

        var failures = 0
        func expect(_ name: String, _ pass: Bool, _ detail: Any = "") {
            print("\(pass ? "PASS" : "FAIL") find: \(name)\(pass ? "" : " (\(detail))")")
            if !pass { failures += 1 }
        }
        func find(_ script: String, _ arguments: [String: Any] = [:]) async throws -> [String: Any] {
            let value = try await webView.callAsyncJavaScript(script, arguments: arguments.merging(["inset": 96]) { $1 },
                                                              in: nil, contentWorld: PageFind.world)
            return value as? [String: Any] ?? [:]
        }
        func marks(_ script: String) async throws -> Any? {
            try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: PageFind.world)
        }
        func page(_ script: String) async throws -> Any? {
            try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        }

        expect("the page cannot see the search", try await page("return typeof quickChatFind") as? String == "undefined")

        var result = try await find("return quickChatFind.find('apple', inset)")
        expect("finds only the text that shows and can be selected, in any case", result["count"] as? Int == 4, result)
        expect("starts at the first match on screen", result["index"] as? Int == 0, result)
        // Each script world has its own view of the marks, so the check reads them in the find world.
        expect("marks all matches and the current match",
               try await marks("return [CSS.highlights.get('quick-chat-find')?.size, CSS.highlights.get('quick-chat-find-current')?.size].join()") as? String == "4,1")
        expect("does not change the selection", try await page("return getSelection().rangeCount") as? Int == 0)

        // The color of the current match on screen.
        let snapshot = try await webView.takeSnapshot(configuration: nil)
        let rect = try await page("const r = quickChatFindRect(); return [r.left, r.top, r.width, r.height]".replacingOccurrences(
            of: "quickChatFindRect()", with: "(() => { const p = document.getElementById('first'); const r = document.createRange(); r.setStart(p.firstChild, 0); r.setEnd(p.firstChild, 5); return r.getBoundingClientRect(); })()")) as? [Double] ?? [0, 0, 0, 0]
        let bitmap = NSBitmapImageRep(data: snapshot.tiffRepresentation!)!
        let scale = Double(bitmap.pixelsWide) / snapshot.size.width
        // Most of the match's box is orange (the rest is the text).
        var orange = 0, all = 0
        for x in stride(from: rect[0] * scale, to: (rect[0] + rect[2]) * scale, by: 2) {
            for y in stride(from: rect[1] * scale, to: (rect[1] + rect[3]) * scale, by: 2) {
                guard let c = bitmap.colorAt(x: Int(x), y: Int(y))?.usingColorSpace(.sRGB) else { continue }
                all += 1
                if c.redComponent > 0.9, c.greenComponent > 0.5, c.greenComponent < 0.75, c.blueComponent < 0.2 { orange += 1 }
            }
        }
        let isOrange = all > 0 && Double(orange) / Double(all) > 0.5
        let color = "\(orange) of \(all) pixels"
        expect("the current match shows in orange", isOrange, color as Any)

        result = try await find("return quickChatFind.find('foo bar', inset)")
        expect("finds text across inline elements", result["count"] as? Int == 1, result)
        result = try await find("return quickChatFind.find('end start', inset)")
        expect("does not find text across blocks", result["count"] as? Int == 0, result)
        result = try await find("return quickChatFind.find('draft', inset)")
        expect("finds the composer's text", result["count"] as? Int == 1, result)

        _ = try await find("return quickChatFind.find('apple', inset)")
        _ = try await find("return quickChatFind.step(false, inset)")
        _ = try await find("return quickChatFind.step(false, inset)")
        result = try await find("return quickChatFind.step(false, inset)")
        expect("goes to the next match", result["index"] as? Int == 3, result)
        let far = try await page("""
            const r = document.getElementById('far').getBoundingClientRect();
            const c = document.querySelectorAll('form')[1].getBoundingClientRect();
            return r.top >= 96 && r.bottom <= c.top;
            """) as? Bool
        expect("scrolls the current match between the find bar and the composer", far == true)
        result = try await find("return quickChatFind.step(false, inset)")
        expect("goes from the last match to the first", result["index"] as? Int == 0, result)
        result = try await find("return quickChatFind.step(true, inset)")
        expect("goes from the first match to the last", result["index"] as? Int == 3, result)

        // A match under the composer (the page also has a hidden composer of an earlier page).
        let low = try await page("""
            document.getElementById('scroll').scrollTop = 0;
            const spacer = document.getElementById('spacer');
            spacer.style.height = (470 - document.getElementById('low').getBoundingClientRect().top) + 'px';
            return document.getElementById('low').getBoundingClientRect().top;
            """) as? Double
        _ = try await find("return quickChatFind.find('lowword', inset)")
        let lowShows = try await page("""
            const r = document.getElementById('low').getBoundingClientRect();
            return r.top >= 96 && r.bottom <= document.querySelectorAll('form')[1].getBoundingClientRect().top;
            """) as? Bool
        expect("scrolls a match from under the composer", low == 470 && lowShows == true, [low as Any, lowShows as Any])
        _ = try await page("document.getElementById('spacer').style.height = '0px'")
        // The current match is the first one after "lowword": the far one.
        _ = try await find("return quickChatFind.find('apple', inset)")

        result = try await find("return quickChatFind.find('appl', inset)")
        expect("a changed text keeps the current match", result["index"] as? Int == 3, result)

        _ = try await page("document.getElementById('first').insertAdjacentHTML('afterend', '<p>new apple</p>')")
        // The search runs again 0.3 seconds after the change. A slow machine can need more time.
        for _ in 0..<100 where results.messages.last?["count"] as? Int != 5 {
            try await Task.sleep(for: .milliseconds(50))
        }
        let message = results.messages.last
        expect("a page change searches again", message?["type"] as? String == "findResult" && message?["count"] as? Int == 5,
               message as Any)

        _ = try await find("return quickChatFind.clear()")
        expect("close removes the marks",
               try await marks("return (CSS.highlights.get('quick-chat-find')?.size ?? 0) + (CSS.highlights.get('quick-chat-find-current')?.size ?? 0)") as? Int == 0)

        print(failures == 0 ? "All find checks passed" : "\(failures) find checks failed")
        exit(failures == 0 ? 0 : 1)
    }
}
