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

    /// The panel's buttons press the page's own controls. Each script runs in its own function
    /// scope: every call runs in the page's global scope, where a second top-level `const` with
    /// the same name fails. The daily page check (scripts/check-page-hooks.swift) runs them too.
    ///
    /// New Chat (⌘N): the page's New chat button (next to its sidebar button), else its Home
    /// link, else ChatGPT's own shortcut (⇧⌘O). True when the page took the action.
    static let newChatScript = """
        (() => {
            const page = document.querySelector('[data-app-shell-active-page="true"]') || document;
            const button = page.querySelector('[data-app-shell-header-slot="start"] > :not([aria-hidden="true"]) button:not([aria-controls])')
                || page.querySelector('a[href="/"]') || document.querySelector('a[href="/"]');
            if (button) { button.click(); return true; }
            const event = new KeyboardEvent('keydown', {
                key: 'O', code: 'KeyO', keyCode: 79, which: 79,
                metaKey: true, shiftKey: true, bubbles: true, cancelable: true
            });
            return !(document.activeElement || document.body).dispatchEvent(event);
        })();
        """
    /// Sidebar (⌘B): the small layout has a sidebar button in the page's title bar. The wide
    /// layout has none (its sidebar is a docked row of icons), so the page then gets its own
    /// sidebar shortcut, ⌘⇧S.
    static let toggleSidebarScript = """
        (() => {
            const toggle = [...document.querySelectorAll('header[data-app-shell-titlebar] button[aria-controls]')]
                .find(element => element.getClientRects().length > 0);
            if (toggle) toggle.click();
            else for (const type of ['keydown', 'keyup']) document.dispatchEvent(new KeyboardEvent(type, { key: 'S', code: 'KeyS', keyCode: 83, metaKey: true, shiftKey: true, bubbles: true, cancelable: true }));
            setTimeout(() => { if (document.activeElement?.matches('button, [role="button"]')) document.activeElement.blur(); }, 60);
            return !!toggle;
        })();
        """
    /// Temporary Chat: the page's temporary chat button, found by its icon or its label. False
    /// when the page has none (the panel then loads the temporary chat address).
    static let temporaryChatScript = """
        (() => {
            const button = [...document.querySelectorAll(\(temporaryChatButtons))]
                .find(element => element.getClientRects().length > 0);
            if (!button) return false;
            button.click();
            return true;
        })();
        """
    static let temporaryChatButtons = #"'header button:has(use[href*="chat-bubble"][href*="dashed"]), header button[aria-label*="temporary chat" i], button[data-testid="temporary-chat-button"]'"#

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
        /* Interactive answers: the sandbox frame shows the panel's material too (see sandboxFrameScript). */
        iframe[src*=".web-sandbox.oaiusercontent.com"] { background-color: transparent !important; }

        /* Chat pages' title bar: only the sidebar button. The panel adds its own buttons on the right.
           The rest stays in the layout (hidden), because the page measures it to place the
           conversation. Other pages (such as plugins or scheduled tasks) keep their title bar. */
        [data-app-shell-active-page="true"]:has(form[data-chatgpt-composer]) {
            & header[data-app-shell-titlebar] > :not([data-app-shell-header-slot="start"]) {
                visibility: hidden !important;
                pointer-events: none !important;
            }
            & [data-app-shell-header-slot="start"] [data-app-shell-header-slot-content] > :not(:has([aria-controls])) { display: none !important; }
            /* The title bar is on top: it takes the pointer, so text and links under it get no
               text pointer and no presses. The page script sends the scroll wheel through. */
            & header[data-app-shell-titlebar] { pointer-events: auto !important; cursor: default !important; }
        }
        header[data-app-shell-titlebar] .bg-surface { background-color: transparent !important; }
        /* The title bar shows only while the pointer is over the panel (the panel sets
           data-quick-chat-pointer). It shows at once. It hides with a fade, together with the
           panel's buttons (same duration and curve): other pages' title bars fade with it, and
           messages fade in under it. The transition of the new state applies, so only the hide
           has one. The value is set only on the elements that use it, and it does not inherit: a
           value on the root makes the page compute the style of each element again, which takes
           a busy page about 70 ms. */
        @property --quick-chat-title-bar-shown { syntax: "<number>"; inherits: false; initial-value: 1; }
        html[data-quick-chat-pointer="outside"] :is(header[data-app-shell-titlebar], [data-app-action-timeline-scroll] > :first-child) {
            --quick-chat-title-bar-shown: 0;
            transition: --quick-chat-title-bar-shown 0.2s ease-in-out !important;
        }
        header[data-app-shell-titlebar] { opacity: var(--quick-chat-title-bar-shown) !important; }
        /* The panel draws its own sidebar button, so that one fade shows and hides every button
           of the title bar. The page's sidebar button stays in place under the panel's one (it is
           what the panel's button clicks), without being drawn. */
        header[data-app-shell-titlebar] [data-app-shell-header-slot="start"] button[aria-controls] { visibility: hidden !important; }

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
            /* The primary button is white with a black icon in dark mode, black with a white icon in light mode. */
            --color-background-composer-primary: light-dark(#000, #fff) !important;
            --color-text-composer-primary: light-dark(#fff, #000) !important;
        }
        form[data-chatgpt-composer] [data-composer-body] { border-radius: var(--quick-chat-composer-radius) !important; }
        /* While the composer's text overflows, space below the last line lets it scroll above the
           text area's bottom fade. */
        form[data-chatgpt-composer] [data-rich-text-layout][data-overflowing] > [contenteditable="true"] { padding-bottom: 16px !important; }
        /* The composer's own Expand control: it does not fit in the panel (the panel has Expand).
           The text no longer keeps space free for it. */
        form[data-chatgpt-composer] [data-composer-expansion-control] { display: none !important; }
        form[data-chatgpt-composer] [data-rich-text-layout="multiline"] { padding-right: 0 !important; }
        /* The scroll bar of a long draft sits in the right margin, so the text keeps equal margins. */
        form[data-chatgpt-composer] [data-rich-text-layout][data-overflowing] { margin-right: -10px !important; }

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
        }
        /* The page's spacer kept the last message clear of the composer; now it only clears the fade. */
        [data-app-action-timeline-scroll] > :first-child > [aria-hidden="true"]:last-child { height: var(--quick-chat-fade) !important; }
        /* Messages stop at the bottom edge of the title bar (they fade in under it while it is
           hidden) and fade out above the composer. A mask on the scroll area would also hide the
           composer, so the mask is on the content. The page script moves the mask with the visible
           area (alignMask). It does not use a scroll timeline: WebKit can keep a scroll timeline's
           old progress after the conversation grows, until the next scroll, and the mask then
           hides the top of the visible messages. These values apply until the script runs. */
        [data-app-action-timeline-scroll] > :first-child {
            --quick-chat-top: var(--thread-content-top-inset, 0px);
            --quick-chat-title-bar: min(var(--app-shell-titlebar-height, 52px), var(--quick-chat-top));
            mask-image: linear-gradient(to bottom,
                rgb(0 0 0 / calc(1 - var(--quick-chat-title-bar-shown))) var(--quick-chat-title-bar),
                black var(--quick-chat-title-bar),
                black calc(100% - var(--quick-chat-fade)),
                transparent);
            mask-size: 100% calc(100cqh + var(--quick-chat-top));
            mask-position: 0 calc(0px - var(--quick-chat-top));
            mask-repeat: no-repeat;
        }

        /* Text looks like native text: the system's font smoothing, and 15-point message text like
           ChatGPT's own companion window. Table text keeps its smaller size. */
        * { -webkit-font-smoothing: auto !important; }
        [data-app-action-timeline-scroll] :not(th, td, th *, td *) { --font-text-md-size: 15px !important; }

        /* Like a native app: only text in the message list, the composer and form fields can be
           selected. Buttons, labels, the title bar, the sidebar and menus cannot, also with ⌘A. */
        body { -webkit-user-select: none !important; user-select: none !important; }
        [data-app-action-timeline-scroll] * { -webkit-user-select: text !important; user-select: text !important; }
        [data-app-action-timeline-scroll] :is(button, [role="button"], [role="menuitem"], [role="tab"]),
        [data-app-action-timeline-scroll] :is(button, [role="button"], [role="menuitem"], [role="tab"]) * {
            -webkit-user-select: none !important;
            user-select: none !important;
        }
        :is([contenteditable="true"], [contenteditable="plaintext-only"], input, textarea),
        :is([contenteditable="true"], [contenteditable="plaintext-only"]) * {
            -webkit-user-select: text !important;
            user-select: text !important;
        }

        /* Like a native app, focus rings show only while you move the focus with the keyboard
           (after Tab; the page script sets data-quick-chat-keyboard). A click, a button of the
           panel that presses a page button, or a menu that gives the focus back to its button
           (after Esc) shows none. The page draws rings as outlines, and as box shadows through
           Tailwind's ring variables; the element's other shadows stay. */
        html:not([data-quick-chat-keyboard]) :is(:focus-visible, :focus-visible::before, :focus-visible::after,
            :is(button, a, summary, select, [role="button"], [role="link"], [role="tab"], [role="switch"], [role="checkbox"], [role="radio"], [role="combobox"], [role="menuitem"], [role="option"]):focus) {
            outline: none !important;
            --tw-ring-shadow: 0 0 #0000 !important;
            --tw-ring-offset-shadow: 0 0 #0000 !important;
            --tw-inset-ring-shadow: 0 0 #0000 !important;
        }

        /* No toolbars on selected text: "Ask ChatGPT" on a message, and text formatting in the
           composer. Both are floating boxes whose content is a toolbar of buttons
           (role="presentation"); menus and other popovers have other content. */
        [data-radix-popper-content-wrapper]:has(> [role="dialog"] > [role="presentation"]),
        body > * > [style*="translateY(-100%)"]:has(> [role="presentation"] > button) { display: none !important; }

        /* No elastic stretch at the ends of the page, the message list and the composer's text.
           Inner scroll areas (such as code blocks) pass a scroll on to the message list at their
           ends, so they keep the default. */
        html, body, [data-app-action-timeline-scroll], form[data-chatgpt-composer] [data-rich-text-layout] {
            overscroll-behavior: none !important;
        }
        /* Only the message list and the composer's text have a scroll bar: a thin rounded thumb at
           the right edge, like a floating macOS scroll bar. WebKit draws it only while the area
           can scroll. The page styles every scroll bar, which in WebKit gives a fixed one that
           takes more width, so the two areas go back to the default first. */
        :not([data-app-action-timeline-scroll], [data-rich-text-layout]), *::before, *::after { scrollbar-width: none !important; scrollbar-gutter: auto !important; }
        :not([data-app-action-timeline-scroll], [data-rich-text-layout])::-webkit-scrollbar { display: none !important; width: 0 !important; height: 0 !important; }
        :is([data-app-action-timeline-scroll], [data-rich-text-layout]) { scrollbar-width: auto !important; scrollbar-color: auto !important; scrollbar-gutter: auto !important; }
        :is([data-app-action-timeline-scroll], [data-rich-text-layout])::-webkit-scrollbar { width: 10px; height: 0; background: transparent; }
        :is([data-app-action-timeline-scroll], [data-rich-text-layout])::-webkit-scrollbar-track { background: transparent; margin-block: 4px; }
        [data-app-action-timeline-scroll]::-webkit-scrollbar-track { margin-top: var(--app-shell-titlebar-height, 52px); }
        :is([data-app-action-timeline-scroll], [data-rich-text-layout])::-webkit-scrollbar-thumb {
            border: 2px solid transparent;
            border-right-width: 3px;
            border-radius: 5px;
            /* A long conversation keeps a thumb that is easy to see and to grab. */
            min-height: 40px;
            background-clip: padding-box;
            background-color: color-mix(in srgb, CanvasText 45%, transparent);
        }
        [data-rich-text-layout]::-webkit-scrollbar-thumb { min-height: 24px; }
        :is([data-app-action-timeline-scroll], [data-rich-text-layout])::-webkit-scrollbar-thumb:hover { background-color: color-mix(in srgb, CanvasText 60%, transparent); }
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

            // A press on the panel's background moves the window, like ChatGPT's own companion
            // window: on empty title bar space, and on empty space in the page (between and beside
            // messages, in the composer around its field, in the sidebar). Controls, text, the
            // messages and answers, media, code blocks and scroll bars keep the press, and so do
            // overlays such as menus and dialogs. A double press on the title bar zooms the window,
            // like a native title bar.
            const content = '[data-user-message-bubble], [data-markdown-text-style], [data-dil-response], [data-client-defined-widget], pre, table, img, picture, video, canvas, svg, iframe, math';
            const hasOwnText = element => [...element.childNodes].some(node => node.nodeType === Node.TEXT_NODE && node.textContent.trim());
            const onScrollBar = (element, x, y) => {
                const r = element.getBoundingClientRect();
                return (element.scrollHeight > element.clientHeight && x >= r.left + element.clientLeft + element.clientWidth) ||
                    (element.scrollWidth > element.clientWidth && y >= r.top + element.clientTop + element.clientHeight);
            };
            const editing = () => !!document.activeElement?.closest?.('[contenteditable="true"], input, textarea');
            document.addEventListener("mousedown", event => {
                if (event.button !== 0 || event.ctrlKey) return;
                const target = event.target instanceof Element ? event.target : null;
                if (!target || target.closest(controls) || !target.closest("main, header, nav")) return;
                const inTitleBar = event.clientY < titleBarBottom();
                if (!inTitleBar && (target.closest(content) || hasOwnText(target) || onScrollBar(target, event.clientX, event.clientY))) return;
                // No text selection starts, and the composer keeps the focus. A press on the
                // background still ends a selection in the messages, as a press on text does.
                event.preventDefault();
                if (!inTitleBar && !editing()) getSelection()?.removeAllRanges();
                post({ type: inTitleBar && event.detail === 2 ? "zoom" : "drag" });
            }, true);

            // The title bar takes the pointer (see the style), so the scroll wheel scrolls the
            // area under it here: the nearest element that can scroll.
            document.addEventListener("wheel", event => {
                const header = event.target instanceof Element ? event.target.closest("header[data-app-shell-titlebar]") : null;
                if (!header || event.ctrlKey) return;
                const below = document.elementsFromPoint(event.clientX, event.clientY).find(element => !header.contains(element));
                for (let element = below; element; element = element.parentElement) {
                    const style = getComputedStyle(element);
                    const scrolls = (overflow, size, client) => /auto|scroll/.test(overflow) && size > client;
                    if (!scrolls(style.overflowY, element.scrollHeight, element.clientHeight) &&
                        !scrolls(style.overflowX, element.scrollWidth, element.clientWidth)) continue;
                    const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? element.clientHeight : 1;
                    element.scrollBy({ left: event.deltaX * unit, top: event.deltaY * unit, behavior: "instant" });
                    event.preventDefault();
                    return;
                }
            }, { capture: true, passive: false });

            // The composer keeps the text cursor in view: after typing, a paste or a cursor move,
            // its text area scrolls the shortest way that shows the cursor above the area's
            // bottom fade. The page does not do this after a paste or at a new line.
            // Where the cursor is: the character before it, or the element next to it (after a
            // paste the cursor sits between paragraphs).
            const caretRect = (node, offset) => {
                if (node.nodeType === Node.TEXT_NODE) {
                    const range = document.createRange();
                    if (offset > 0) {
                        range.setStart(node, offset - 1);
                        range.setEnd(node, offset);
                        const rects = range.getClientRects();
                        if (rects.length) return rects[rects.length - 1];
                    }
                    range.setStart(node, offset);
                    range.collapse(true);
                    return range.getClientRects()[0] ?? node.parentElement.getBoundingClientRect();
                }
                const before = node.childNodes[offset - 1], after = node.childNodes[offset];
                const next = before ?? after;
                if (!next) return node.getBoundingClientRect();
                if (next.nodeType === Node.TEXT_NODE) return caretRect(next, before ? next.length : 0);
                if (next.nodeType !== Node.ELEMENT_NODE) return node.getBoundingClientRect();
                const rects = next.getClientRects();
                return (before ? rects[rects.length - 1] : rects[0]) ?? next.getBoundingClientRect();
            };
            const caretInView = () => {
                const selection = getSelection();
                if (!selection.rangeCount || !selection.focusNode) return;
                const node = selection.focusNode;
                const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
                const area = element?.closest('form[data-chatgpt-composer] [data-rich-text-layout]');
                if (!area || area.scrollHeight <= area.clientHeight) return;
                const rect = caretRect(node, selection.focusOffset);
                const box = area.getBoundingClientRect();
                const bottom = box.bottom - 20, top = box.top + 4;
                if (rect.bottom > bottom) area.scrollTop += rect.bottom - bottom;
                else if (rect.top < top) area.scrollTop -= top - rect.top;
            };
            const caretSoon = () => requestAnimationFrame(caretInView);
            for (const name of ["input", "paste", "keyup"]) document.addEventListener(name, caretSoon, true);
            document.addEventListener("selectionchange", caretSoon);

            // Focus rings: on with Tab, off with the next press of the mouse or the trackpad.
            const root = document.documentElement;

            // Safe mode. ChatGPT changes its page from time to time, and this style keys on the
            // page's structure. If the style hides the composer, or most of a conversation's text,
            // it turns itself off for this page: the page then shows ChatGPT's own look, which
            // still works, and the panel shows none of its own buttons over it. The test turns the
            // style off and on again in one task, so nothing is drawn in between. It runs a moment
            // after the page loads and after each move to another page.
            let safeMode = null;
            const editorShows = () => [...document.querySelectorAll('form [contenteditable="true"], form textarea')]
                .some(e => e.checkVisibility({ opacityProperty: true, visibilityProperty: true }) && e.getBoundingClientRect().width > 8);
            const conversationText = () => location.pathname.startsWith("/c/") ? (document.querySelector("main")?.innerText.length ?? 0) : 0;
            const harm = () => {
                const styled = { editor: editorShows(), text: conversationText() };
                style.disabled = true;
                const plain = { editor: editorShows(), text: conversationText() };
                style.disabled = false;
                if (plain.editor && !styled.editor) return "composer";
                if (plain.text > 200 && styled.text < plain.text / 2) return "messages";
                return null;
            };
            const checkSafety = () => {
                if (safeMode || document.readyState !== "complete") return;
                const reason = harm();
                if (!reason) return;
                safeMode = reason;
                style.disabled = true;
                root.dataset.quickChatSafeMode = reason;
                post({ type: "safeMode", reason });
                schedule();
            };
            let checkedPage = "";
            const checkSafetySoon = () => {
                if (location.href === checkedPage) return;
                checkedPage = location.href;
                for (const delay of [1500, 5000]) setTimeout(checkSafety, delay);
            };
            window.addEventListener("keydown", event => { if (event.key === "Tab") root.dataset.quickChatKeyboard = ""; }, true);
            window.addEventListener("pointerdown", () => { delete root.dataset.quickChatKeyboard; }, true);

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
            // The message mask covers the visible area of the message list: its top edge is at the
            // top of the scroll area, and its height is the scroll area's height. The values are
            // set on the content element only when they change.
            const scrollerSelector = "[data-app-action-timeline-scroll]";
            const masks = new WeakMap();
            let scroller = null;
            // False also when the page changed the element's inline style.
            const maskIsSet = content => {
                const mask = masks.get(content);
                return !!mask && content.style.maskPosition === mask.position && content.style.maskSize === mask.size;
            };
            const alignMask = target => {
                const content = target?.firstElementChild;
                if (!content) return;
                const y = target.getBoundingClientRect().top + target.clientTop - content.getBoundingClientRect().top;
                const wanted = `0 ${Math.round(y * 100) / 100}px|100% ${target.clientHeight}px`;
                if (maskIsSet(content) && masks.get(content).wanted === wanted) return;
                [content.style.maskPosition, content.style.maskSize] = wanted.split("|");
                masks.set(content, { wanted, position: content.style.maskPosition, size: content.style.maskSize });
            };
            document.addEventListener("scroll", event => {
                if (event.target instanceof Element && event.target.matches(scrollerSelector)) {
                    scroller = event.target;
                    alignMask(scroller);
                }
            }, { capture: true, passive: true });
            let previous = "";
            let pending = false;
            let loadedAWhileAgo = false;
            const report = () => {
                pending = false;
                const rendered = [...document.querySelectorAll(scrollerSelector)].find(e => e.getClientRects().length);
                if (rendered) { scroller = rendered; alignMask(rendered); }
                // Until the page's own style loads, it has no color scheme; the panel then keeps its theme.
                const scheme = getComputedStyle(document.documentElement).colorScheme;
                // In safe mode the page shows its own title bar, without the panel's buttons.
                const titleBar = !safeMode && !!document.querySelector("header[data-app-shell-titlebar]");
                if (document.readyState === "complete") checkSafetySoon();
                // In a wide window the page docks its sidebar (or its row of icons) on the left;
                // the main area then starts to its right.
                const main = [...document.querySelectorAll("main[data-app-shell-main-surface]")].find(e => e.getClientRects().length);
                const left = Math.max(0, Math.round(main?.getBoundingClientRect().left ?? 0));
                const state = {
                    type: "state",
                    // While the HTML loads, the page shows a placeholder with a different composer.
                    // The page is ready when it has its real composer, or a moment after it loads.
                    ready: document.readyState === "complete" && (loadedAWhileAgo ||
                        !!document.querySelector("form[data-chatgpt-composer]") || !document.querySelector("[data-composer-body]")),
                    // The left corner holds the panel's Sidebar and Temporary Chat (or New Chat)
                    // buttons; they show on chat pages, the pages with a composer.
                    close: titleBar && !covered(left + 26, 26) && !covered(left + 70, 26),
                    chat: titleBar && !!document.querySelector('[data-app-shell-active-page="true"] form[data-chatgpt-composer]'),
                    left,
                    // A docked row of icons shows the sidebar on hover; the page then has no toggle.
                    sidebar: [...document.querySelectorAll("header[data-app-shell-titlebar] button[aria-controls]")].some(e => e.getClientRects().length),
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
            new MutationObserver(records => {
                // The mask's own changes need no report.
                if (records.every(r => r.type === "attributes" && r.attributeName === "style" && maskIsSet(r.target))) return;
                // New content (the page renders the message list again) gets its mask at once.
                if (scroller?.isConnected && scroller.firstElementChild && !maskIsSet(scroller.firstElementChild)) alignMask(scroller);
                schedule();
            }).observe(document.documentElement, {
                childList: true, subtree: true, attributes: true,
                attributeFilter: ["class", "style", "hidden", "open", "aria-expanded", "aria-hidden", "data-state", "data-theme"]
            });
            for (const name of ["transitionend", "animationend", "resize"]) window.addEventListener(name, schedule, true);
            document.addEventListener("readystatechange", schedule);
            window.addEventListener("load", () => setTimeout(() => { loadedAWhileAgo = true; schedule(); }, 1000));
            report();
        })();
        """#

    /// ChatGPT shows interactive answers (diagrams, simulations) in sandbox frames from another
    /// site, which the page style cannot reach. Their page background is black, so in these frames
    /// (and the frames inside them) the background becomes transparent, like the panel's page.
    /// The answer's own panels keep their colors. Other embedded frames do not change.
    static let sandboxFrameScript = #"""
        (() => {
            if (window === window.top) return;
            const sandbox = origin => /\.web-sandbox\.oaiusercontent\.com$/i.test(new URL(origin).hostname);
            const origins = [location.origin, ...(location.ancestorOrigins ?? [])].filter(o => o && o !== "null");
            if (!origins.some(o => { try { return sandbox(o); } catch { return false; } })) return;
            const style = new CSSStyleSheet();
            style.replaceSync("html, body { background: transparent !important; }");
            document.adoptedStyleSheets = [...document.adoptedStyleSheets, style];
        })();
        """#

    /// Removes ChatGPT's saved drafts (of a new chat and of each conversation), once per web view
    /// session, before the page reads them. ChatGPT saves them in its persisted page state in
    /// IndexedDB, and older versions in local storage. The script never creates the database:
    /// if the page has not made it yet, there is nothing to remove.
    static let clearDraftsScript = #"""
        (() => {
            const host = location.hostname.toLowerCase();
            if (host !== "chatgpt.com" && !host.endsWith(".chatgpt.com")) return;
            if (sessionStorage.getItem("quick-chat-drafts-cleared")) return;
            sessionStorage.setItem("quick-chat-drafts-cleared", "1");
            for (const key of Object.keys(localStorage)) {
                if (/^oai\/apps\/.*draft/i.test(key)) localStorage.removeItem(key);
            }
            const request = indexedDB.open("codex-browser-host");
            request.onupgradeneeded = () => request.transaction.abort();
            request.onerror = event => event.preventDefault();
            request.onsuccess = () => {
                const db = request.result;
                db.onversionchange = () => db.close();
                if (!db.objectStoreNames.contains("records")) return db.close();
                const transaction = db.transaction("records", "readwrite");
                transaction.oncomplete = transaction.onabort = () => db.close();
                const store = transaction.objectStore("records");
                const key = "codex.browser.persistedAtomState";
                const read = store.get(key);
                read.onsuccess = () => {
                    const state = read.result;
                    if (!state || typeof state !== "object") return;
                    const drafts = Object.keys(state).filter(name => /prompt-drafts/i.test(name));
                    if (!drafts.length) return;
                    for (const name of drafts) delete state[name];
                    if (store.keyPath === null) store.put(state, key); else store.put(state);
                };
            };
        })();
        """#

    /// `value` as a JavaScript string literal.
    private static func javaScriptString(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}
