/// Visual changes are limited to ChatGPT; account-provider pages keep their own styling.
enum QuickChatPageStyle {
    static let script = """
        (() => {
            const host = location.hostname.toLowerCase();
            if (host !== "chatgpt.com" && !host.endsWith(".chatgpt.com")) return;
            const style = document.createElement("style");
            style.id = "quick-chat-page-style";
            style.textContent = `
                :root {
                    --app-color-background-surface: transparent !important;
                    --app-color-background-surface-under: transparent !important;
                    --main-surface-primary: transparent !important;
                    --main-surface-background: transparent !important;
                    --bg-primary: transparent !important;
                }
                html, body, #root, main, #thread, #thread-bottom-container,
                :where(div:has(form #prompt-textarea), div:has(form #mobile-composer-prompt)) {
                    background: transparent !important;
                }
                aside, [role="dialog"], [role="menu"], [role="listbox"], #stage-slideover-sidebar {
                    --app-color-background-surface: Canvas !important;
                    --app-color-background-surface-under: Canvas !important;
                    --main-surface-primary: Canvas !important;
                    --main-surface-background: Canvas !important;
                    --bg-primary: Canvas !important;
                    background-color: Canvas !important;
                }
                [data-testid="open-sidebar-button"], [data-testid="create-new-chat-button"],
                [aria-label="Open sidebar"], [aria-label="Close sidebar"], [aria-label="New chat"] {
                    background: transparent !important;
                }
                [data-quick-chat-header] { visibility: hidden !important; }
                [data-quick-chat-sidebar], [data-quick-chat-new-chat] {
                    visibility: visible !important;
                    position: fixed !important;
                    top: 8px !important;
                    width: 28px !important;
                    height: 28px !important;
                    margin: 0 !important;
                    padding: 4px !important;
                    background: transparent !important;
                }
                [data-quick-chat-sidebar] { left: 40px !important; right: auto !important; }
                [data-quick-chat-new-chat] { right: 10px !important; left: auto !important; }
                [data-quick-chat-mode-switcher], [data-quick-chat-disclaimer] { display: none !important; }
                *, *::before, *::after {
                    scrollbar-width: none !important;
                    scrollbar-gutter: auto !important;
                }
                ::-webkit-scrollbar {
                    display: none !important;
                    width: 0 !important;
                    height: 0 !important;
                }
                form:has(#prompt-textarea), form:has(#mobile-composer-prompt) {
                    --bg-primary: color-mix(in srgb, Canvas 35%, transparent) !important;
                    --bg-secondary: color-mix(in srgb, Canvas 35%, transparent) !important;
                    --main-surface-secondary: color-mix(in srgb, Canvas 35%, transparent) !important;
                    --app-color-background-surface: color-mix(in srgb, Canvas 35%, transparent) !important;
                }
                form:has(#mobile-composer-prompt) {
                    background: color-mix(in srgb, Canvas 35%, transparent) !important;
                }
            `;
            document.documentElement.appendChild(style);

            const controls = 'button, a, input, select, textarea, [role="button"], [role="tab"], [role="switch"], [role="radio"], [contenteditable="true"]';
            const label = element => (element.getAttribute('aria-label') || element.textContent || '').trim();
            const hideModeSwitch = () => {
                for (const control of document.querySelectorAll(controls)) {
                    if (label(control) !== 'Chat') continue;
                    let group = control.parentElement;
                    for (let depth = 0; group && depth < 4; depth++, group = group.parentElement) {
                        const options = [...group.querySelectorAll(controls)];
                        if (options.length > 2) break;
                        if (options.length === 2 && options.some(option => label(option) === 'Work')) {
                            group.toggleAttribute('data-quick-chat-mode-switcher', true);
                            break;
                        }
                    }
                }
            };
            const trimPageChrome = () => {
                const topControl = selector => [...document.querySelectorAll(selector)].find(element => {
                    const rect = element.getBoundingClientRect();
                    return rect.top < 64 && rect.bottom > 0 && rect.width > 0 &&
                        !element.closest('aside, [role="dialog"], #stage-slideover-sidebar');
                });
                const sidebar = topControl('[data-testid="open-sidebar-button"], [data-testid="close-sidebar-button"], [aria-label="Open sidebar"], [aria-label="Close sidebar"]');
                const newChat = topControl('[data-testid="create-new-chat-button"], [data-testid="new-chat-button"], [aria-label="New chat"]');
                let header = (sidebar || newChat)?.closest('#page-header, header');
                if (!header) {
                    for (let parent = (sidebar || newChat)?.parentElement; parent; parent = parent.parentElement) {
                        const rect = parent.getBoundingClientRect();
                        if (rect.height > 72) break;
                        if (rect.width >= innerWidth / 2) header = parent;
                    }
                }
                const hasSignIn = header && [...header.querySelectorAll('button, a')]
                    .some(element => /^(log in|sign up)$/i.test(label(element)));
                if (header && !hasSignIn) {
                    // Keep the site's handlers and layout, exposing just its two icon buttons.
                    header.toggleAttribute('data-quick-chat-header', true);
                    sidebar?.toggleAttribute('data-quick-chat-sidebar', true);
                    newChat?.toggleAttribute('data-quick-chat-new-chat', true);
                }
                for (const control of document.querySelectorAll('[data-testid="open-sidebar-button"], [data-testid="close-sidebar-button"], [aria-label="Open sidebar"], [aria-label="Close sidebar"]')) {
                    const rect = control.getBoundingClientRect();
                    if (rect.top < 64 && rect.bottom > 0) control.toggleAttribute('data-quick-chat-sidebar', true);
                }
                if (document.querySelector('[data-quick-chat-disclaimer]')) return;
                for (const element of document.querySelectorAll('div, p, small, span')) {
                    if (element.closest('article, [data-message-author-role], .markdown, form, aside, header, #page-header, [data-quick-chat-header], [role="dialog"]') ||
                        element.querySelector('form, textarea, [contenteditable]')) continue;
                    const text = element.textContent.trim();
                    if (text.length > 350 || !text.startsWith('ChatGPT can make mistakes.')) continue;
                    let disclaimer = element;
                    while (disclaimer.parentElement?.textContent.trim() === text &&
                           !disclaimer.parentElement.querySelector('form, textarea, [contenteditable]')) {
                        disclaimer = disclaimer.parentElement;
                    }
                    disclaimer.toggleAttribute('data-quick-chat-disclaimer', true);
                    break;
                }
            };
            let pending = false;
            let previous = '';
            const refresh = () => {
                pending = false;
                hideModeSwitch();
                trimPageChrome();
                const rectangles = [...document.querySelectorAll(controls)]
                    .filter(element => getComputedStyle(element).visibility !== 'hidden')
                    .map(element => element.getBoundingClientRect())
                    .filter(rect => rect.top < 44 && rect.bottom > 0 && rect.width > 0 && rect.height > 0)
                    .map(rect => [rect.left, rect.top, rect.width, rect.height]);
                const current = JSON.stringify(rectangles);
                if (current !== previous) {
                    window.webkit?.messageHandlers?.quickChatHeaderControls?.postMessage(rectangles);
                    previous = current;
                }
            };
            const schedule = () => {
                if (!pending) { pending = true; requestAnimationFrame(refresh); }
            };
            new MutationObserver(records => {
                if (records.some(record => record.type === 'attributes' ||
                    [...record.addedNodes, ...record.removedNodes].some(node => node.nodeType === Node.ELEMENT_NODE))) schedule();
            }).observe(document.documentElement, {
                childList: true, subtree: true, attributes: true,
                attributeFilter: ['class', 'style', 'aria-hidden', 'aria-expanded', 'data-state']
            });
            document.addEventListener('transitionend', schedule, true);
            document.addEventListener('animationend', schedule, true);
            window.addEventListener('resize', schedule);
            window.addEventListener('scroll', schedule, true);
            refresh();
        })();
        """
}
