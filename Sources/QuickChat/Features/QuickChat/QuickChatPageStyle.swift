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
                div:has(form #prompt-textarea), div:has(form #mobile-composer-prompt) {
                    background: transparent !important;
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
        })();
        """
}
