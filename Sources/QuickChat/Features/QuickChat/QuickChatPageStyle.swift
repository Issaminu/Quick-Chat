/// Visual changes are limited to ChatGPT; account-provider pages keep their own styling.
enum QuickChatPageStyle {
    static let script = """
        (() => {
            const host = location.hostname.toLowerCase();
            if (host !== "chatgpt.com" && !host.endsWith(".chatgpt.com")) return;
            const style = document.createElement("style");
            style.id = "quick-chat-page-style";
            style.textContent = `
                main, #thread {
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
                    background-color: Canvas !important;
                }
                [data-quick-chat-mode-switcher] { display: none !important; }
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
            let pending = false;
            let previous = '';
            const refresh = () => {
                pending = false;
                hideModeSwitch();
                const rectangles = [...document.querySelectorAll(controls)]
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
