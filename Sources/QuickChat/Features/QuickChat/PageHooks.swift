import Foundation

/// Every part of chatgpt.com that Quick Chat depends on: the page's attributes, CSS variables,
/// controls, shortcuts and storage that the page style (`QuickChatPageStyle`) and the panel use.
///
/// ChatGPT can change any of them without notice. Three things guard against that:
/// - The page style keys only on these hooks. A renamed hook makes its part of the style stop,
///   and the page shows ChatGPT's own look there.
/// - Safe mode (in `QuickChatPageStyle.script`): if the style hides the composer or the messages,
///   it turns itself off for that page.
/// - The daily page check (`scripts/check-page-hooks.swift`, run by
///   `.github/workflows/page-check.yml`) runs each `check` on the live site with a test account.
///   It opens a GitHub issue that lists each broken hook with `usedFor` and `ifBroken`.
///
/// The page style check fails when the style uses a `data-*` attribute or a CSS variable that no
/// check here names, so this list stays complete.
enum PageHooks {
    /// The pages that the daily check opens: the empty chat, a temporary chat, a conversation
    /// (read only), and the empty chat in a wide panel (900 points).
    enum Page: String, CaseIterable, Sendable {
        case home, temporary, conversation, wide
    }

    struct Hook: Sendable {
        let id: String
        let pages: [Page]
        /// A JavaScript expression (it can use `await` and the `helpers`) that is true while the
        /// hook works.
        let check: String
        let usedFor: String
        let ifBroken: String
    }

    /// Functions that the checks use. `rendered` skips the hidden copies of earlier pages that
    /// ChatGPT keeps. `uses` searches the page's HTML, scripts and style sheets.
    static let helpers = #"""
        const rendered = selector => [...document.querySelectorAll(selector)].find(e => e.getClientRects().length > 0) ?? null;
        const has = selector => !!rendered(selector);
        const exists = selector => !!document.querySelector(selector);
        const shows = element => !!element && element.checkVisibility({ opacityProperty: true, visibilityProperty: true });
        const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
        const mainLeft = () => Math.round(rendered("main[data-app-shell-main-surface]")?.getBoundingClientRect().left ?? -1);
        const alpha = color => { const c = document.createElement("canvas").getContext("2d"); c.fillStyle = color; c.fillRect(0, 0, 1, 1); return c.getImageData(0, 0, 1, 1).data[3]; };
        // The page's HTML, and every script and style sheet that it loaded or links: from the
        // resource timing list (its buffer can be full) and from the page's own tags.
        window.__quickChatSource ??= null;
        const source = async () => {
            if (window.__quickChatSource) return window.__quickChatSource;
            let text = document.documentElement.outerHTML;
            const urls = new Set(performance.getEntriesByType("resource").map(e => e.name).filter(u => /\.(m?js|css)(\?|$)/.test(u)));
            for (const e of document.querySelectorAll('script[src], link[rel~="stylesheet"][href], link[rel~="modulepreload"][href], link[rel~="preload"][href]')) urls.add(e.src || e.href);
            for (const sheet of document.styleSheets) { try { text += [...sheet.cssRules].map(r => r.cssText).join("\n"); } catch {} }
            let read = 0;
            for (const url of urls) { try { const response = await fetch(url); if (response.ok) { text += await response.text(); read++; } } catch {} }
            window.__quickChatSourceInfo = `${read} of ${urls.size} files, ${Math.round(text.length / 1024)} KB`;
            return window.__quickChatSource = text;
        };
        const uses = async name => (await source()).includes(name);
        """#

    static let all: [Hook] = [
        // The app shell
        Hook(id: "main-surface", pages: [.home, .conversation],
             check: #"has("main[data-app-shell-main-surface]")"#,
             usedFor: "The transparent page background, and finding the wide layout.",
             ifBroken: "The page background is opaque; a wide panel does not show Shrink."),
        Hook(id: "wide-frame", pages: [.wide],
             check: #"exists("[data-app-shell-frame]") && exists("[data-app-shell-workspace]")"#,
             usedFor: "The transparent background of the wide layout.",
             ifBroken: "A wide panel has an opaque background around the chat."),
        Hook(id: "active-page", pages: [.home, .conversation],
             check: #"exists('[data-app-shell-active-page="true"]')"#,
             usedFor: "Finding chat pages, for the panel's buttons.",
             ifBroken: "The panel shows none of its buttons."),
        Hook(id: "title-bar", pages: [.home, .conversation],
             check: #"has("header[data-app-shell-titlebar]")"#,
             usedFor: "The page's title bar: hidden under the panel's buttons, and faded with them.",
             ifBroken: "The panel's buttons are gone, and the page's own title bar shows."),
        Hook(id: "title-bar-start-slot", pages: [.home, .conversation],
             check: #"exists('header[data-app-shell-titlebar] [data-app-shell-header-slot="start"] button[aria-controls]')"#,
             usedFor: "Keeping only the sidebar button in the page's title bar, and New Chat.",
             ifBroken: "Page buttons show under the panel's buttons, or New Chat does nothing."),
        Hook(id: "title-bar-hidden", pages: [.home, .conversation],
             check: #"(() => { const header = rendered("header[data-app-shell-titlebar]"); return !!header && [...header.querySelectorAll("button, a")].filter(shows).length === 0; })()"#,
             usedFor: "No page buttons under the panel's own title bar buttons.",
             ifBroken: "Page buttons show in the title bar, under or next to the panel's buttons."),
        Hook(id: "sidebar-button", pages: [.home],
             check: #"await (async () => { const toggle = () => rendered("header[data-app-shell-titlebar] button[aria-controls]"); if (!toggle()) return false; toggleSidebar(); await sleep(700); const opened = toggle()?.getAttribute("aria-expanded") === "true"; toggleSidebar(); await sleep(700); return opened && toggle()?.getAttribute("aria-expanded") === "false"; })()"#,
             usedFor: "The Sidebar button and ⌘B in the small panel.",
             ifBroken: "Sidebar and ⌘B do nothing in the small panel."),
        Hook(id: "wide-layout", pages: [.wide],
             check: #"mainLeft() > 0"#,
             usedFor: "A panel of 768 points or more counts as large (Shrink, title bar always shown).",
             ifBroken: "A wide panel shows Expand, and its title bar hides."),
        Hook(id: "wide-sidebar-shortcut", pages: [.wide],
             check: #"await (async () => { const before = mainLeft(); toggleSidebar(); await sleep(900); const opened = mainLeft(); toggleSidebar(); await sleep(900); return opened !== before && mainLeft() === before; })()"#,
             usedFor: "⌘B in a wide panel (ChatGPT's own sidebar shortcut, ⌘⇧S).",
             ifBroken: "⌘B does nothing in a wide panel."),

        // The sidebar
        Hook(id: "sidebar-rows", pages: [.conversation],
             check: #"await (async () => { toggleSidebar(); await sleep(900); const root = rendered("[data-sidebar-navigation-root]"); const links = root ? [...root.querySelectorAll("[data-sidebar-cycle-item] a[data-interactive-row-link]")].filter(e => e.getClientRects().length) : []; const current = links.some(a => a.getAttribute("href") === location.pathname && a.closest('[data-sidebar-cycle-item][aria-current="page"]')); toggleSidebar(); await sleep(900); return links.length > 0 && current; })()"#,
             usedFor: "↑ and ↓ move through the sidebar's conversations, from the open conversation.",
             ifBroken: "The arrow keys do not move through the sidebar's conversations."),
        Hook(id: "sidebar-row-color", pages: [.home],
             check: #"await uses("--color-background-secondary-ghost-hover")"#,
             usedFor: "The sidebar row that the arrow keys selected looks like a row under the pointer.",
             ifBroken: "The selected sidebar row has no background."),

        // The composer
        Hook(id: "composer", pages: [.home, .conversation],
             check: #"has("form[data-chatgpt-composer]")"#,
             usedFor: "The composer's look, the panel's buttons, and focusing the composer.",
             ifBroken: "The composer has ChatGPT's own look, and the panel shows no buttons."),
        Hook(id: "composer-usable", pages: [.home, .conversation],
             check: #"(() => { const editor = rendered('form[data-chatgpt-composer] [contenteditable="true"]'); if (!shows(editor)) return false; const r = editor.getBoundingClientRect(); const hit = document.elementFromPoint(r.left + Math.min(20, r.width / 2), r.top + r.height / 2); return !!hit && !!hit.closest("form[data-chatgpt-composer]"); })()"#,
             usedFor: "You can see and type in the composer.",
             ifBroken: "The composer is hidden or covered."),
        Hook(id: "composer-home", pages: [.home],
             check: #"has('form[data-chatgpt-composer][data-composer-placement="home"]')"#,
             usedFor: "The composer's small inset in the empty chat.",
             ifBroken: "The empty chat's composer has ChatGPT's wide margins."),
        Hook(id: "composer-body", pages: [.home, .conversation],
             check: #"has("form[data-chatgpt-composer] [data-composer-body]")"#,
             usedFor: "The composer's rounded corners, concentric with the window's corners.",
             ifBroken: "The composer's corners do not match the window's corners."),
        Hook(id: "composer-surface", pages: [.home],
             check: #"(() => { const surface = rendered("form[data-chatgpt-composer] [data-composer-surface-variant]") ?? rendered("form[data-chatgpt-composer] [data-composer-body]"); return !!surface && alpha(getComputedStyle(surface).backgroundColor) < 255; })()"#,
             usedFor: "The composer's translucent surface (ChatGPT's composer tokens).",
             ifBroken: "The composer has an opaque surface."),
        Hook(id: "composer-text", pages: [.home],
             check: #"has("form[data-chatgpt-composer] [data-rich-text-layout]") && await uses("data-overflowing") && await uses("data-composer-expansion-control")"#,
             usedFor: "The composer's scroll bar and margins, and hiding its own Expand control.",
             ifBroken: "A long draft has a wide scroll bar or uneven margins, or an extra Expand control shows."),
        Hook(id: "home-feed", pages: [.home],
             check: #"exists("[data-home-feed-composer]")"#,
             usedFor: "Showing only the composer in the empty chat.",
             ifBroken: "The empty chat shows ChatGPT's greeting and suggestions."),
        Hook(id: "home-only-composer", pages: [.home],
             check: #"(() => { const main = rendered('[role="main"]') ?? rendered("main"); return !!main && [...main.querySelectorAll("h1, h2, h3, p, button, a")].filter(e => shows(e) && !e.closest("form, header")).length === 0; })()"#,
             usedFor: "The empty chat shows nothing but the composer.",
             ifBroken: "Greetings, suggestions or notices show above the composer."),

        // Conversations
        Hook(id: "conversation-address", pages: [.conversation],
             check: #"location.pathname.startsWith("/c/")"#,
             usedFor: "Telling a conversation from the empty chat (New Chat or Temporary Chat).",
             ifBroken: "The panel shows the wrong button next to Close."),
        Hook(id: "message-list", pages: [.conversation],
             check: #"has("[data-app-action-timeline-scroll]")"#,
             usedFor: "The message list: its mask under the title bar, its thin scroll bar, text selection, 15-point text, and its end at the composer.",
             ifBroken: "Messages show behind the title bar or the composer, the scroll bar is wide, or message text cannot be selected."),
        Hook(id: "messages-show", pages: [.conversation],
             check: #"shows(rendered("[data-user-message-bubble]")) && shows(rendered("[data-dil-response]"))"#,
             usedFor: "You can see the messages and the answers.",
             ifBroken: "Messages or answers are hidden."),
        Hook(id: "message-mask", pages: [.conversation],
             check: #"await (async () => { const scroller = rendered("[data-app-action-timeline-scroll]"); if (!scroller) return false; const before = scroller.scrollTop; scroller.scrollTop = (scroller.scrollHeight - scroller.clientHeight) / 2; await sleep(300); const content = scroller.firstElementChild, style = getComputedStyle(content); const y = parseFloat(style.maskPosition.split(" ")[1]); const top = scroller.getBoundingClientRect().top + scroller.clientTop - content.getBoundingClientRect().top; scroller.scrollTop = before; return style.maskImage.includes("gradient") && Math.abs(y - top) < 1; })()"#,
             usedFor: "The message fade under the title bar and above the composer follows the scroll.",
             ifBroken: "Messages are cut at the wrong place, or text is hidden at the top of the panel."),
        Hook(id: "messages-end-at-composer", pages: [.conversation],
             check: #"(() => { const body = rendered("[data-composer-body]"), scroller = rendered("[data-app-action-timeline-scroll]"); return !!body && !!scroller && Math.abs(body.getBoundingClientRect().top - scroller.getBoundingClientRect().bottom) <= 1; })()"#,
             usedFor: "Messages end at the composer's top edge (ChatGPT's --thread-scroll-padding-bottom).",
             ifBroken: "Messages show beside or through the composer, or there is a gap."),
        Hook(id: "thread-footer", pages: [.conversation],
             check: #"has("[data-thread-scroll-footer] > [data-pip-obstacle]")"#,
             usedFor: "The composer's inset in a conversation, and hiding the page's opaque backdrop behind it.",
             ifBroken: "The conversation's composer has wide margins or an opaque band behind it."),
        Hook(id: "composer-backdrop", pages: [.conversation],
             check: #"(() => { const body = rendered("[data-composer-body]"); if (!body) return false; const b = body.getBoundingClientRect(), y = (b.bottom + innerHeight) / 2; const covers = e => { const r = e.getBoundingClientRect(); return r.top <= y && r.bottom >= y && r.left <= b.left && r.right >= b.right; }; return [...document.querySelectorAll("body *")].filter(e => !e.closest("form") && e.getClientRects().length && covers(e)).every(e => [null, "::before", "::after"].every(p => { const s = getComputedStyle(e, p); return (p && s.content === "none") || (alpha(s.backgroundColor) < 255 && !s.backgroundImage.includes("gradient")); })); })()"#,
             usedFor: "No opaque band behind the conversation's composer (the backdrop of [data-thread-scroll-footer]).",
             ifBroken: "A dark band shows behind and below the composer in a conversation."),
        Hook(id: "message-parts", pages: [.conversation],
             check: #"has("[data-user-message-bubble]") && has("[data-markdown-text-style]") && has("[data-dil-response] [data-client-defined-widget]")"#,
             usedFor: "Dragging the panel by empty space: your messages, answers and code blocks keep the press.",
             ifBroken: "A press on a message, an answer or a code block moves the panel."),
        Hook(id: "disclaimer", pages: [.conversation],
             check: #"await uses("data-markdown-copy") && await uses("--thread-composer-disclaimer-visibility")"#,
             usedFor: "Hiding the disclaimer below the messages.",
             ifBroken: "The disclaimer shows below the messages."),
        Hook(id: "new-chat-button", pages: [.conversation],
             check: #"!!(document.querySelector('[data-app-shell-active-page="true"]')?.querySelector('[data-app-shell-header-slot="start"] > :not([aria-hidden="true"]) button:not([aria-controls])') || document.querySelector('a[href="/"]'))"#,
             usedFor: "New Chat and ⌘N.",
             ifBroken: "New Chat and ⌘N load the start page instead (slower)."),

        // Temporary chats
        Hook(id: "temporary-chat-button", pages: [.home, .temporary],
             check: #"[...document.querySelectorAll(temporaryChatButtons)].some(e => e.getClientRects().length > 0)"#,
             usedFor: "The Temporary Chat button.",
             ifBroken: "Temporary Chat loads the temporary chat address instead (slower)."),
        Hook(id: "temporary-chat-address", pages: [.temporary],
             check: #"new URLSearchParams(location.search).get("temporary-chat") === "true""#,
             usedFor: "Showing the filled Temporary Chat icon while a temporary chat is on.",
             ifBroken: "The Temporary Chat icon does not show when a temporary chat is on."),

        // ChatGPT's CSS variables and tokens
        Hook(id: "thread-variables", pages: [.conversation],
             check: #"await uses("--thread-content-top-inset") && await uses("--thread-scroll-padding-bottom") && await uses("--thread-composer-bottom-inset") && await uses("--app-shell-titlebar-height")"#,
             usedFor: "Placing the message mask, the end of the messages, and the composer's inset.",
             ifBroken: "Messages are cut at the wrong place, or the composer's inset is wrong."),
        Hook(id: "composer-tokens", pages: [.home],
             check: #"await uses("--composer-layout-surface-background") && await uses("--composer-layout-surface-shadow") && await uses("--composer-layout-surface-backdrop-filter") && await uses("--composer-border-radius") && await uses("--radius-token-composer-single-line") && await uses("--color-background-composer-primary") && await uses("--color-text-composer-primary")"#,
             usedFor: "The composer's surface, border, radius and send button colors.",
             ifBroken: "The composer or its send button has ChatGPT's own look."),
        Hook(id: "text-size", pages: [.conversation],
             check: #"await uses("--font-text-md-size")"#,
             usedFor: "15-point message text, like ChatGPT's companion window.",
             ifBroken: "Message text has ChatGPT's web size."),
        Hook(id: "focus-rings", pages: [.home],
             check: #"await uses("--tw-ring-shadow") && await uses("--tw-ring-offset-shadow") && await uses("--tw-inset-ring-shadow")"#,
             usedFor: "No focus rings after a click, or after a menu closes.",
             ifBroken: "Blue focus rings show after clicks."),
        Hook(id: "popups", pages: [.home],
             check: #"await uses("data-radix-popper-content-wrapper")"#,
             usedFor: "Hiding the toolbars on selected text, and Esc (it closes a menu before it hides the panel).",
             ifBroken: "Toolbars show on selected text, or Esc hides the panel while a menu is open."),

        // Storage and other sites
        Hook(id: "drafts-storage", pages: [.home],
             check: #"await uses("codex-browser-host") && await uses("persistedAtomState") && await uses("prompt-drafts")"#,
             usedFor: "Empty drafts after a quit.",
             ifBroken: "Drafts from before a quit come back."),
        Hook(id: "sandbox-frames", pages: [.home],
             check: #"await uses("web-sandbox.oaiusercontent.com")"#,
             usedFor: "Interactive answers (diagrams, simulations) on the panel's material.",
             ifBroken: "Interactive answers show on a black background."),

        // The guard itself
        Hook(id: "safe-mode-off", pages: [.home, .conversation, .wide],
             check: #"!document.documentElement.hasAttribute("data-quick-chat-safe-mode")"#,
             usedFor: "The page style stays on (safe mode turns it off when it hides the composer or the messages).",
             ifBroken: "The panel shows ChatGPT without its style and without its own buttons."),
    ]

    /// The checks of `page` as one async function body that returns `{ id: true/false }`. A check
    /// that throws, or that does not finish in 30 seconds, counts as broken. It can call the page style's sidebar script as
    /// `toggleSidebar()`.
    static func checkScript(for page: Page) -> String {
        let checks = all.filter { $0.pages.contains(page) }.map { hook in
            "try { result[\(javaScriptString(hook.id))] = !!(await within((async () => (\(hook.check)))())); } catch (error) { result[\(javaScriptString(hook.id))] = false; errors[\(javaScriptString(hook.id))] = String(error); }" +
            (hook.check.contains("uses(") ? " if (!result[\(javaScriptString(hook.id))] && window.__quickChatSourceInfo) errors[\(javaScriptString(hook.id))] ??= `not in the page's source (${window.__quickChatSourceInfo})`;" : "")
        }
        return """
            const toggleSidebar = () => \(expression(QuickChatPageStyle.toggleSidebarScript));
            const temporaryChatButtons = \(QuickChatPageStyle.temporaryChatButtons);
            \(helpers)
            // A check that does not finish in 30 seconds counts as broken.
            const within = check => Promise.race([check, new Promise((_, reject) => setTimeout(() => reject(new Error("the check did not finish in 30 seconds")), 30000))]);
            const result = {}, errors = {};
            \(checks.joined(separator: "\n"))
            return JSON.stringify({ result, errors });
            """
    }

    /// A script of the page style (an expression and a semicolon) as an expression: the page's
    /// security policy does not allow `eval`.
    private static func expression(_ script: String) -> String {
        var text = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix(";") { text.removeLast() }
        return text
    }

    private static func javaScriptString(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}
