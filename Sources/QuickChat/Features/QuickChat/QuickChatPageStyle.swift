/// Visual changes are limited to ChatGPT; account-provider pages keep their own styling.
enum QuickChatPageStyle {
    static let windowCornerRadius = 20
    static let composerInset = 8
    static let composerSelector = "#prompt-textarea, #mobile-composer-prompt, [data-composer-markdown][contenteditable], [role=\"textbox\"][contenteditable]"
    static let script = """
        (() => {
            const host = location.hostname.toLowerCase();
            if (host !== "chatgpt.com" && !host.endsWith(".chatgpt.com")) return;
            const style = document.createElement("style");
            style.id = "quick-chat-page-style";
            style.textContent = `
                :root {
                    --quick-chat-window-radius: \(windowCornerRadius)px;
                    --quick-chat-composer-inset: \(composerInset)px;
                    --quick-chat-composer-radius: calc(var(--quick-chat-window-radius) - var(--quick-chat-composer-inset));
                    --app-color-background-surface: transparent !important;
                    --app-color-background-surface-under: transparent !important;
                    --main-surface-primary: transparent !important;
                    --main-surface-background: transparent !important;
                    --bg-primary: transparent !important;
                }
                html, body, #root, main, #thread, #thread-bottom-container,
                :where(div:has(form :is(\(composerSelector)))) {
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
                [data-quick-chat-titlebar] {
                    pointer-events: none !important;
                    display: flex !important;
                    padding: 8px !important;
                    align-items: flex-start !important;
                    justify-content: flex-start !important;
                    box-sizing: border-box !important;
                }
                [data-quick-chat-titlebar] *:not([data-quick-chat-temporary-branch]):not([data-quick-chat-temporary-button] *) {
                    display: none !important;
                }
                [data-quick-chat-temporary-branch]:not([data-quick-chat-temporary-button]) {
                    display: contents !important;
                    contain: none !important;
                    transform: none !important;
                }
                [data-quick-chat-temporary-button] {
                    pointer-events: auto !important;
                    display: flex !important;
                    visibility: visible !important;
                    position: static !important;
                    width: 28px !important;
                    min-width: 28px !important;
                    height: 28px !important;
                    margin: 0 !important;
                    padding: 4px !important;
                    background: transparent !important;
                }
                [data-quick-chat-mode-switcher], [data-quick-chat-disclaimer] { display: none !important; }
                [data-quick-chat-welcome], [data-quick-chat-welcome] * {
                    visibility: hidden !important;
                    pointer-events: none !important;
                }
                [data-quick-chat-composer-layer] { background: transparent !important; }
                [data-composer-body], [data-quick-chat-composer-surface] {
                    background: color-mix(in srgb, CanvasText 6%, transparent) !important;
                    border: 1px solid color-mix(in srgb, CanvasText 12%, transparent) !important;
                    border-radius: var(--quick-chat-composer-radius) !important;
                    box-sizing: border-box !important;
                    -webkit-backdrop-filter: blur(12px);
                    backdrop-filter: blur(12px);
                }
                [data-quick-chat-composer-dock] {
                    padding: 0 var(--quick-chat-composer-inset) var(--quick-chat-composer-inset) !important;
                    margin: 0 !important;
                    width: 100% !important;
                    max-width: none !important;
                    box-sizing: border-box !important;
                }
                [data-quick-chat-composer-wrapper] {
                    padding-inline: 0 !important;
                    padding-bottom: 0 !important;
                    margin-inline: 0 !important;
                    margin-bottom: 0 !important;
                    max-width: none !important;
                }
                [data-quick-chat-composer-dock-self] {
                    margin: 0 var(--quick-chat-composer-inset) var(--quick-chat-composer-inset) !important;
                    width: calc(100% - var(--quick-chat-composer-inset) * 2) !important;
                }
                [data-composer-body] button.bg-composer-primary,
                form button[data-testid="send-button"], form button[data-testid="voice-mode-button"] {
                    background: #fff !important;
                    color: #000 !important;
                }
                [data-composer-body] button.bg-composer-primary svg,
                [data-composer-body] button.bg-composer-primary svg *,
                form button[data-testid="send-button"] svg, form button[data-testid="voice-mode-button"] svg {
                    color: #000 !important;
                }
                *, *::before, *::after {
                    scrollbar-width: none !important;
                    scrollbar-gutter: auto !important;
                }
                ::-webkit-scrollbar {
                    display: none !important;
                    width: 0 !important;
                    height: 0 !important;
                }
                form:has(:is(\(composerSelector))) {
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

            const promptSelector = '\(composerSelector)';
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
            const styleComposer = () => {
                const prompt = document.querySelector(promptSelector);
                const form = prompt?.closest('form');
                if (!form) return;
                let surface = prompt.closest('[data-composer-body]') || form;
                for (let element = prompt.parentElement; element && form.contains(element); element = element.parentElement) {
                    if (parseFloat(getComputedStyle(element).borderTopLeftRadius) >= 12) surface = element;
                }
                for (let element = prompt.parentElement; element && form.contains(element); element = element.parentElement) {
                    element.toggleAttribute('data-quick-chat-composer-layer', element !== surface);
                    element.toggleAttribute('data-quick-chat-composer-surface', element === surface);
                }
                let dock = form.closest('#thread-bottom-container');
                if (!dock) {
                    dock = form;
                    for (let parent = form.parentElement; parent && !parent.matches('main, #thread, #root, body'); parent = parent.parentElement) {
                        if (parent.getBoundingClientRect().height > form.getBoundingClientRect().height + 80 ||
                            parent.querySelector('article, [data-message-author-role], h1, h2')) break;
                        dock = parent;
                    }
                }
                dock.toggleAttribute('data-quick-chat-composer-dock', dock !== form);
                dock.toggleAttribute('data-quick-chat-composer-dock-self', dock === form);
                for (let parent = form.parentElement; parent && parent !== dock && dock.contains(parent); parent = parent.parentElement) {
                    parent.toggleAttribute('data-quick-chat-composer-wrapper', true);
                }
            };
            const trimPageChrome = () => {
                for (const titlebar of document.querySelectorAll('[data-app-shell-titlebar]')) {
                    const hasSignIn = [...titlebar.querySelectorAll('button, a')]
                        .some(element => /^(log in|sign up)$/i.test(label(element)));
                    if (!hasSignIn) titlebar.toggleAttribute('data-quick-chat-titlebar', true);
                }
                const temporary = [...document.querySelectorAll('button[aria-label="Temporary chat"], button[data-testid="temporary-chat-button"]')]
                    .find(element => !element.closest('[role="dialog"], [role="menu"]'));
                const header = temporary?.closest('[data-app-shell-titlebar], header, #page-header');
                if (header) {
                    header.toggleAttribute('data-quick-chat-titlebar', true);
                    for (let element = temporary; element && element !== header; element = element.parentElement) {
                        element.toggleAttribute('data-quick-chat-temporary-branch', true);
                    }
                    temporary.toggleAttribute('data-quick-chat-temporary-button', true);
                }
                const prompt = document.querySelector(promptSelector);
                const form = prompt?.closest('form');
                const home = form?.matches('[data-composer-placement="home"]')
                    ? form.closest('[class~="group/home-composer-layout"]') : null;
                for (const heading of document.querySelectorAll('main h1, main h2, main .heading-xl, main [role="heading"], #thread h1, #thread h2')) {
                    if (prompt && !heading.closest('article, [data-message-author-role], [data-message-id], .markdown, aside, [role="dialog"], [role="alert"]')) {
                        let region = heading;
                        while (home && region.parentElement && region.parentElement !== home &&
                               !region.parentElement.contains(form) && !region.parentElement.querySelector('article, [data-message-author-role]')) {
                            region = region.parentElement;
                        }
                        region.toggleAttribute('data-quick-chat-welcome', true);
                    }
                }
                if (document.querySelector('[data-quick-chat-disclaimer]')) return;
                for (const element of document.querySelectorAll('div, p, small, span')) {
                    if (element.closest('article, [data-message-author-role], .markdown, form, aside, header, #page-header, [data-quick-chat-titlebar], [role="dialog"]') ||
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
                styleComposer();
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
