import WebKit

/// The search of the find bar (⌘F). The script runs in the app's own script world, so the page
/// cannot see it or change it. It marks the matches with the CSS Custom Highlight API: it does not
/// change the page's text, selection or focus.
@MainActor
enum PageFind {
    static let world = WKContentWorld.world(name: "QuickChatFind")
    /// The name of the message handler that receives new results while the page changes.
    static let messageName = "quickChatFind"

    /// Defines `quickChatFind` with these functions. Each returns `{ index, count, limited }`;
    /// `index` is -1 when there is no match.
    /// - `find(text, inset)`: searches for `text` and shows the first match at or after the
    ///   current match (or the first match in the window or below it). It scrolls the match to
    ///   the area between `inset` points from the top of the window and the composer.
    /// - `step(backwards, inset)`: shows the next or the previous match.
    /// - `clear()`: removes the marks.
    /// While a search is active, a page change searches again (at most every 0.3 seconds) and
    /// posts the new result to `messageName`.
    static let script = #"""
        (() => {
            if (globalThis.quickChatFind) return;
            const allName = "quick-chat-find", currentName = "quick-chat-find-current";
            const limit = 1000;
            // Between the text of two blocks: the search cannot match across it (it is not \s).
            const blockBreak = "￿";
            const skipped = new Set(["script", "style", "noscript", "template", "textarea", "select", "svg"]);
            const style = new CSSStyleSheet();
            style.replaceSync(`
                ::highlight(${allName}) { background-color: #ffe066; color: #000; }
                ::highlight(${currentName}) { background-color: #ff9f0a; color: #000; }`);
            let query = "", matches = [], index = -1, inset = 0, timer = 0;

            const post = message => {
                try { webkit.messageHandlers.quickChatFind.postMessage(message); } catch {}
            };
            const state = () => ({ index, count: matches.length, limited: matches.length >= limit });

            // Only text that shows on the page: no hidden elements, and no text for screen readers
            // only (such text is in a box of 1 × 1 pixel).
            const accept = element => {
                if (skipped.has(element.localName)) return NodeFilter.FILTER_REJECT;
                const display = getComputedStyle(element).display;
                if (display === "contents") return NodeFilter.FILTER_SKIP;
                if (display === "none") return NodeFilter.FILTER_REJECT;
                const shows = element.checkVisibility
                    ? element.checkVisibility({ visibilityProperty: true, opacityProperty: true })
                    : element.getClientRects().length > 0;
                if (!shows) return NodeFilter.FILTER_REJECT;
                const rect = element.getBoundingClientRect();
                return rect.width > 1 || rect.height > 1 ? NodeFilter.FILTER_SKIP : NodeFilter.FILTER_REJECT;
            };

            // The text of the page as one string, with a block break between blocks.
            const collect = () => {
                const nodes = [], starts = [];
                let text = "", lastBlock = null;
                if (!document.body) return { nodes, starts, text };
                const blocks = new Map();
                const blockOf = element => {
                    for (let node = element; node && node !== document.body; node = node.parentElement) {
                        let block = blocks.get(node);
                        if (block === undefined) {
                            const display = getComputedStyle(node).display;
                            block = display.startsWith("inline") || display === "contents" ? null : node;
                            blocks.set(node, block);
                        }
                        if (block) return block;
                    }
                    return document.body;
                };
                const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
                    acceptNode: node => node.nodeType === Node.TEXT_NODE ? NodeFilter.FILTER_ACCEPT : accept(node),
                });
                for (let node = walker.nextNode(); node; node = walker.nextNode()) {
                    if (node.nodeType !== Node.TEXT_NODE || !node.data) continue;
                    const block = blockOf(node.parentElement);
                    if (block !== lastBlock && text) text += blockBreak;
                    lastBlock = block;
                    nodes.push(node);
                    starts.push(text.length);
                    text += node.data;
                }
                return { nodes, starts, text };
            };

            // The node and the offset in it for a position in the collected text.
            const position = (data, offset, isEnd) => {
                const target = isEnd ? offset - 1 : offset;
                let low = 0, high = data.starts.length - 1;
                while (low < high) {
                    const middle = (low + high + 1) >> 1;
                    if (data.starts[middle] <= target) low = middle; else high = middle - 1;
                }
                return [data.nodes[low], offset - data.starts[low]];
            };

            const search = () => {
                matches = [];
                const words = query.trim().split(/\s+/).filter(Boolean)
                    .map(word => word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
                if (!words.length) return;
                const data = collect();
                for (const match of data.text.matchAll(new RegExp(words.join("\\s+"), "giu"))) {
                    const range = new Range();
                    range.setStart(...position(data, match.index, false));
                    range.setEnd(...position(data, match.index + match[0].length, true));
                    matches.push(range);
                    if (matches.length >= limit) break;
                }
            };

            // The first match at or after `previous`, else the first match that shows in the window
            // or below it.
            const startIndex = previous => {
                if (!matches.length) return -1;
                if (previous?.startContainer.isConnected) {
                    const next = matches.findIndex(range => {
                        try { return range.compareBoundaryPoints(Range.START_TO_START, previous) >= 0; }
                        catch { return false; }
                    });
                    return Math.max(next, 0);
                }
                const next = matches.findIndex(range => range.getBoundingClientRect().bottom > 0);
                return Math.max(next, 0);
            };

            const paint = () => {
                if (!globalThis.Highlight || !CSS.highlights) return;
                if (!document.adoptedStyleSheets.includes(style)) {
                    document.adoptedStyleSheets = [...document.adoptedStyleSheets, style];
                }
                CSS.highlights.set(allName, new Highlight(...matches));
                const current = matches[index];
                if (!current) return CSS.highlights.delete(currentName);
                const highlight = new Highlight(current);
                highlight.priority = 1;
                CSS.highlights.set(currentName, highlight);
            };

            const scroller = element => {
                for (let node = element; node; node = node.parentElement) {
                    const style = getComputedStyle(node);
                    if (/auto|scroll/.test(style.overflowY) && node.scrollHeight > node.clientHeight) return node;
                }
                return document.scrollingElement;
            };

            // Scrolls the current match to the middle of the free area (between the find bar and
            // the composer), if it is not fully in that area.
            const reveal = () => {
                const range = matches[index];
                const element = range?.startContainer.parentElement;
                if (!element) return;
                // The page keeps hidden copies of earlier pages: use the composer that shows.
                const composer = [...document.querySelectorAll("form[data-chatgpt-composer]")]
                    .find(form => form.getClientRects().length)?.getBoundingClientRect();
                const top = inset;
                const bottom = (composer && composer.top > top + 40 ? composer.top : innerHeight) - 8;
                let rect = range.getBoundingClientRect();
                if (rect.height && rect.top >= top && rect.bottom <= bottom && rect.left >= 0 && rect.right <= innerWidth) return;
                element.scrollIntoView({ block: "center", inline: "nearest", behavior: "instant" });
                rect = range.getBoundingClientRect();
                scroller(element)?.scrollBy({ top: rect.top + rect.height / 2 - (top + bottom) / 2, behavior: "instant" });
            };

            // While a search is active, a page change searches again: at most every 0.3 seconds,
            // so that an answer that ChatGPT writes does not search at each word.
            const observer = new MutationObserver(() => {
                if (timer) return;
                timer = setTimeout(() => {
                    timer = 0;
                    if (!query) return;
                    const previous = matches[index];
                    search();
                    index = startIndex(previous);
                    paint();
                    post({ type: "findResult", ...state() });
                }, 300);
            });

            globalThis.quickChatFind = {
                find(text, topInset) {
                    inset = topInset;
                    const previous = query ? matches[index] : null;
                    query = text;
                    if (!query.trim()) { this.clear(); query = text; return state(); }
                    search();
                    index = startIndex(previous);
                    paint();
                    reveal();
                    observer.disconnect();
                    observer.observe(document.body ?? document.documentElement,
                                     { subtree: true, childList: true, characterData: true });
                    return state();
                },
                step(backwards, topInset) {
                    inset = topInset;
                    if (!matches.length) return state();
                    index = (index + (backwards ? -1 : 1) + matches.length) % matches.length;
                    paint();
                    reveal();
                    return state();
                },
                clear() {
                    query = "";
                    matches = [];
                    index = -1;
                    observer.disconnect();
                    clearTimeout(timer);
                    timer = 0;
                    CSS.highlights?.delete(allName);
                    CSS.highlights?.delete(currentName);
                    return state();
                },
            };
        })();
        """#
}
