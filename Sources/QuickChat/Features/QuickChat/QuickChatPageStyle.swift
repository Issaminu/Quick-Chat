import Foundation

/// How chatgpt.com looks and behaves inside the panel. Account-provider pages keep their own styling.
///
/// The style keys only on ChatGPT's semantic attributes (`data-app-shell-*`, `data-composer-*`,
/// `data-thread-*`) and design tokens (`--composer-*`), never on text or generated class names.
/// CSS applies to every re-render without scripts that tag elements. If ChatGPT renames a hook,
/// that part of the page falls back to ChatGPT's own look; it does not break the page.
enum QuickChatPageStyle {
    static let windowCornerRadius = 20
    static let composerInset = 8
    /// The panel's own title bar buttons: 36 pt, 8 pt from the window edges, like the page's buttons.
    static let titleBarButtonSize = 36
    /// Focuses the rendered message editor (the page keeps hidden copies of earlier pages).
    static let focusComposerScript = """
        [...document.querySelectorAll('form[data-chatgpt-composer] [contenteditable="true"], #prompt-textarea')]
            .find(element => element.getClientRects().length > 0)?.focus()
        """

    static let css = #"""
        :root {
            --quick-chat-inset: \#(composerInset)px;
            --quick-chat-composer-radius: \#(windowCornerRadius - composerInset)px;
            --quick-chat-fade: 32px;
        }

        /* Transparent page surfaces show the panel's material. Only the surfaces change, not the
           shared color tokens, so menus, the sidebar, and floating buttons keep their backgrounds. */
        html, body, main[data-app-shell-main-surface] { background: transparent !important; }
        /* In a wide window, the page docks its sidebar rail and paints the frame and the workspace. */
        [data-app-shell-frame], [data-app-shell-workspace]::before { background-color: transparent !important; }
        :is([role="main"], [role="main"] *):has(form[data-chatgpt-composer]) { background-color: transparent !important; }
        [data-thread-scroll-footer] > [aria-hidden="true"] { display: none !important; }

        /* Chat pages' title bar: only the sidebar button. The panel adds its own buttons on the right.
           The rest stays in the layout (hidden), because the page measures it to place the
           conversation. Other pages (such as plugins or scheduled tasks) keep their title bar. */
        [data-app-shell-active-page="true"]:has(form[data-chatgpt-composer]) {
            & header[data-app-shell-titlebar] > :not([data-app-shell-header-slot="start"]) {
                visibility: hidden !important;
                pointer-events: none !important;
            }
            & [data-app-shell-header-slot="start"] [data-app-shell-header-slot-content] > :not(:has([aria-controls])) { display: none !important; }
        }
        header[data-app-shell-titlebar] .bg-surface { background-color: transparent !important; }
        /* The panel's close button sits at the top left, so the sidebar button moves to its right. */
        header[data-app-shell-titlebar] [data-app-shell-header-slot="start"] [data-app-shell-header-slot-content] {
            margin-inline-start: \#(titleBarButtonSize + composerInset)px !important;
        }

        /* Empty chat: only the composer. This hides every greeting, suggestion, and notice around it.
           Content before the composer keeps its space, so the composer stays at the bottom; content
           after it takes no space, so nothing invisible sits below the composer. */
        :is([role="main"], [role="main"] *):has([data-home-feed-composer]) > :not([data-home-feed-composer]):not(:has([data-home-feed-composer])) {
            visibility: hidden !important;
            opacity: 0 !important;
            pointer-events: none !important;
        }
        :is([role="main"] *):has([data-home-feed-composer]) ~ *, [data-home-feed-composer] ~ * { display: none !important; }
        /* In a wide window, the page centers the composer in a grid of three rows (space,
           composer, space). The space goes above it instead, so the composer stays at the bottom.
           Elements that are not grids ignore this. */
        :is([role="main"] *):has([data-home-feed-composer]) { grid-template-rows: 1fr auto 0px !important; }
        /* Conversation: the disclaimer below the messages (between the messages and the page's
           bottom spacer) takes no space. A block there with a control in it stays. */
        [data-app-action-timeline-scroll] { --thread-composer-disclaimer-visibility: hidden !important; }
        [data-app-action-timeline-scroll] > :first-child > :not(:first-child):not(:last-child):has([data-markdown-copy="exclude"]):not(:has(button, input, textarea, [role="button"])) {
            display: none !important;
        }

        /* Composer: ChatGPT's own surface tokens. They are set on every layer, because the page sets
           them on several layers. The radius is concentric with the window corners. */
        form[data-chatgpt-composer], form[data-chatgpt-composer] * {
            --composer-layout-surface-background: color-mix(in srgb, CanvasText 7%, transparent) !important;
            --composer-layout-surface-shadow: inset 0 0 0 1px color-mix(in srgb, CanvasText 12%, transparent) !important;
            --composer-layout-surface-backdrop-filter: none !important;
            --composer-border-radius: var(--quick-chat-composer-radius) !important;
            --radius-token-composer-single-line: var(--quick-chat-composer-radius) !important;
            --color-background-composer-primary: #fff !important;
            --color-text-composer-primary: #000 !important;
        }
        form[data-chatgpt-composer] [data-composer-body] { border-radius: var(--quick-chat-composer-radius) !important; }

        /* The same small inset left, right, and below the composer, before and after the first message. */
        :is([role="main"], [role="main"] *):has(form[data-composer-placement="home"]) {
            padding-inline: 0 !important;
            padding-bottom: 0 !important;
        }
        form[data-composer-placement="home"] { margin: 0 var(--quick-chat-inset) var(--quick-chat-inset) !important; }
        [data-thread-scroll-footer] { --thread-composer-bottom-inset: var(--quick-chat-inset) !important; }
        [data-thread-scroll-footer] > [data-pip-obstacle] { padding-inline: var(--quick-chat-inset) !important; }

        /* Messages end at the composer's top edge, so no text shows beside, below, or through it.
           ChatGPT keeps the composer area's height in --thread-scroll-padding-bottom (plus 1rem).
           The composer floats outside the shortened scroll area, so it is not clipped. */
        [data-app-action-timeline-scroll] {
            --quick-chat-composer-area: calc(var(--thread-scroll-padding-bottom, 0px) - 1rem);
            height: calc(100% - var(--quick-chat-composer-area)) !important;
            flex: none !important;
            container-type: size;
            scroll-timeline: --quick-chat-thread block;
        }
        /* The page's spacer kept the last message clear of the composer; now it only clears the fade. */
        [data-app-action-timeline-scroll] > :first-child > [aria-hidden="true"]:last-child { height: var(--quick-chat-fade) !important; }
        /* Messages stop at the bottom edge of the title bar and fade out above the composer. A mask
           on the scroll area would also hide the composer, so the mask is on the content and a
           scroll timeline keeps it aligned with the visible area. A short conversation cannot
           scroll, so its timeline is inactive; the mask position then stays at the start value. */
        @keyframes quick-chat-follow-scroll {
            from { mask-position: 0 calc(0px - var(--quick-chat-top)); }
            to { mask-position: 0 100%; }
        }
        [data-app-action-timeline-scroll] > :first-child {
            --quick-chat-top: var(--thread-content-top-inset, 0px);
            --quick-chat-title-bar: min(var(--app-shell-titlebar-height, 52px), var(--quick-chat-top));
            mask-image: linear-gradient(to bottom,
                transparent var(--quick-chat-title-bar),
                black var(--quick-chat-title-bar),
                black calc(100% - var(--quick-chat-fade)),
                transparent);
            mask-size: 100% calc(100cqh + var(--quick-chat-top));
            mask-position: 0 calc(0px - var(--quick-chat-top));
            mask-repeat: no-repeat;
            animation: quick-chat-follow-scroll linear both;
            animation-timeline: --quick-chat-thread;
        }

        /* Text looks like native text: the system's font smoothing, and 15-point message text like
           ChatGPT's own companion window. Table text keeps its smaller size. */
        * { -webkit-font-smoothing: auto !important; }
        [data-app-action-timeline-scroll] :not(th, td, th *, td *) { --font-text-md-size: 15px !important; }

        /* No scroll bars or scroll bar gutters, and no elastic stretch at the ends of a scroll. */
        * { overscroll-behavior: none !important; }
        *, *::before, *::after { scrollbar-width: none !important; scrollbar-gutter: auto !important; }
        ::-webkit-scrollbar { display: none !important; width: 0 !important; height: 0 !important; }
        """#

    /// Adds the style and a small bridge to the panel: window dragging from the empty title bar
    /// area, and the page state that the panel's own buttons need. It runs at document start,
    /// because ChatGPT shows its page while the HTML continues to load.
    static let script = #"""
        (() => {
            const host = location.hostname.toLowerCase();
            if (host !== "chatgpt.com" && !host.endsWith(".chatgpt.com")) return;
            // An adopted style sheet comes after the page's own style sheets, and it is not in the
            // DOM, so the page cannot remove it when it renders the document again.
            const style = new CSSStyleSheet();
            style.replaceSync(\#(javaScriptString(css)));
            document.adoptedStyleSheets = [...document.adoptedStyleSheets, style];

            const post = message => window.webkit?.messageHandlers?.quickChat?.postMessage(message);
            const controls = 'a, button, input, textarea, select, label, summary, [contenteditable="true"], [role="button"], [role="link"], [role="menuitem"], [role="option"], [role="tab"], [role="switch"], [role="slider"]';
            const titleBarBottom = () => document.querySelector("header")?.getBoundingClientRect().bottom || 52;

            // A press on empty title bar space (not a control, not an overlay such as the sidebar or
            // a dialog) moves the window; a double press zooms it, like a native title bar.
            document.addEventListener("mousedown", event => {
                if (event.button !== 0 || event.clientY >= titleBarBottom()) return;
                const target = event.target instanceof Element ? event.target : null;
                if (!target || target.closest(controls) || !target.closest("main, header")) return;
                event.preventDefault();
                post({ type: event.detail === 2 ? "zoom" : "drag" });
            }, true);

            // Esc hides the panel. The composer always claims Esc, so the page does not pass it on.
            // While a menu, a dialog, a popup, or the sidebar is open, Esc closes that instead.
            const open = '[role="dialog"], [role="alertdialog"], [role="menu"], [role="listbox"], [data-radix-popper-content-wrapper], [aria-haspopup][aria-expanded="true"], header [aria-expanded="true"]';
            window.addEventListener("keydown", event => {
                if (event.key !== "Escape" || event.isComposing || event.repeat) return;
                if ([...document.querySelectorAll(open)].some(element => element.getClientRects().length > 0)) return;
                post({ type: "escape" });
            }, true);

            // The panel's close button sits at the top left of the page's title bar, and its other
            // buttons at the top right of a chat page's title bar (the signed-in pages with a
            // composer). Each hides while something covers its corner (the sidebar, a menu, a
            // dialog). Other pages have their own buttons at the top right. The buttons follow the
            // page's light or dark theme.
            const covered = (x, y) => {
                const element = document.elementFromPoint(x, y);
                return !!element && element !== document.documentElement && element !== document.body &&
                    !element.closest("main, header[data-app-shell-titlebar]");
            };
            let previous = "";
            let pending = false;
            let loadedAWhileAgo = false;
            const report = () => {
                pending = false;
                // Until the page's own style loads, it has no color scheme; the panel then keeps its theme.
                const scheme = getComputedStyle(document.documentElement).colorScheme;
                const titleBar = !!document.querySelector("header[data-app-shell-titlebar]");
                const state = {
                    type: "state",
                    // While the HTML loads, the page shows a placeholder with a different composer.
                    // The page is ready when it has its real composer, or a moment after it loads.
                    ready: document.readyState === "complete" && (loadedAWhileAgo ||
                        !!document.querySelector("form[data-chatgpt-composer]") || !document.querySelector("[data-composer-body]")),
                    close: titleBar && !covered(26, 26),
                    buttons: titleBar && !!document.querySelector('[data-app-shell-active-page="true"] form[data-chatgpt-composer]') &&
                        !covered(innerWidth - 26, 26) && !covered(innerWidth - 70, 26),
                    dark: scheme === "normal" ? null : scheme.includes("dark")
                };
                const current = JSON.stringify(state);
                if (current !== previous) { previous = current; post(state); }
            };
            // A hidden page (the panel loads before it first shows) gets no animation frames.
            const schedule = () => {
                if (pending) return;
                pending = true;
                if (document.hidden) setTimeout(report, 100); else requestAnimationFrame(report);
            };
            new MutationObserver(schedule).observe(document.documentElement, {
                childList: true, subtree: true, attributes: true,
                attributeFilter: ["class", "style", "hidden", "open", "aria-expanded", "aria-hidden", "data-state", "data-theme"]
            });
            for (const name of ["transitionend", "animationend", "resize"]) window.addEventListener(name, schedule, true);
            document.addEventListener("readystatechange", schedule);
            window.addEventListener("load", () => setTimeout(() => { loadedAWhileAgo = true; schedule(); }, 1000));
            report();
        })();
        """#

    /// `value` as a JavaScript string literal.
    private static func javaScriptString(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}
