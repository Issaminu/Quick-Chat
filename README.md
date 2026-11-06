<div align="center">

# Quick Chat

**ChatGPT on ⌥Space. A small chat panel that looks and feels like part of your Mac.**

Press ⌥Space in any app, ask a question, read the answer, and go back to your work.
Every message is a regular ChatGPT chat, not an agent task.

This is a fork of [shuaibird/Quick-Chat](https://github.com/shuaibird/Quick-Chat), with many additional UI changes.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)

<img src="docs/demo.gif" width="880" alt="Quick Chat demo: over an article, a reader presses Option-Space, asks what gravitational lensing is, then asks for an interactive diagram. ChatGPT builds it in the panel. The reader expands the panel to a large window, drags the lensing galaxy, changes its mass with a slider, shrinks the panel, and presses Esc to go back to the article.">

*Press ⌥Space, ask, get an interactive diagram, explore it in a large window, and go back to reading.*

</div>

## Highlights

- **Always one key away.** ⌥Space opens the panel over any app, also over full-screen apps. Esc closes it.
- **It does not take the focus from your app.** Like Spotlight, the panel takes your typing, but the app you were in stays active.
- **It looks native.** The panel has the macOS translucent material, rounded corners with a real shadow, and the system font with the system's font smoothing. It follows ChatGPT's light or dark theme.
- **Only the chat.** The empty chat shows only the composer. Greetings, suggestions, notices, the disclaimer and the selection toolbars are hidden.
- **The title bar comes when you need it.** In the small panel, it shows while the pointer is over the panel, and fades out 0.5 seconds after the pointer leaves. Then the messages use its space. In the large window, it always shows.
- **Small or large.** **Expand** (or a double-click on the title bar, or ⌘F) makes the panel a large window with the same chat. **Shrink** makes it small again. The page never shows a half-drawn layout during the change.
- **Temporary chats.** One click starts a chat that does not go into your history. The icon fills while a temporary chat is on.
- **Ready when you are.** ChatGPT loads in the background when the app starts. While a page loads, the panel shows a spinner instead of a half-loaded page.
- **Interactive answers.** The panel is ChatGPT on the web, so it shows ChatGPT's interactive answers: diagrams, simulations, sliders and buttons inside the chat. ChatGPT Classic shows only text and standard formatting.
- **Always up to date.** You get every new ChatGPT web feature on the day it ships, with your own account and your own models.

## Why this exists

ChatGPT Classic for Mac has a chat bar on ⌥Space: you press it in any app, ask a question, and get a normal chat.

The new ChatGPT desktop app (Chat, Work and Codex) works differently:

- **⌥Space opens Mini.** Mini starts Work and Codex agent tasks, not plain chats.
- **The experimental Popout Window** (Settings → Experimental features) also starts agent tasks.
- **Plain chat is only in the app window.** No system-wide shortcut opens it.

This is important because the two kinds of use have different limits. Work and Codex share one usage allowance, with a 5-hour window and a weekly limit. Chat has its own model availability and message limits ([OpenAI: Managing usage in Work and Codex](https://help.openai.com/en/articles/20001516)). A quick question through Mini uses the agent allowance that you may want to keep for real tasks.

ChatGPT Classic is also falling behind:

- **New features skip it.** OpenAI says that new features may come only to the new app ([OpenAI: Moving to the new ChatGPT desktop app](https://help.openai.com/en/articles/20001276)).
- **It cannot show Intelligent UI**, the GPT-6 answers that mix text, visuals and interactive elements. OpenAI tells you to use ChatGPT on the web for them ([OpenAI: GPT-6 and other models in ChatGPT](https://help.openai.com/en/articles/20001354-gpt-6-and-other-models-in-chatgpt)).

Quick Chat shows chatgpt.com in a small floating panel. So you keep the ⌥Space chat bar, and every message is a regular ChatGPT chat with all web features.

Quick Chat works next to the new ChatGPT desktop app, and it can free ⌥Space from the Mini shortcut. It does not need any ChatGPT app: without one, it works alone.

## Install

**With an AI assistant:** tell Claude, ChatGPT or another assistant:
*"Read https://github.com/Issaminu/Quick-Chat/blob/main/INSTALL.md and help me install Quick Chat."*
[INSTALL.md](INSTALL.md) gives the assistant step-by-step instructions for the two options below.

### Download

1. Get `Quick-Chat-<version>.zip` from the [releases](https://github.com/Issaminu/Quick-Chat/releases). It is a universal app (Apple silicon and Intel) for macOS 14 Sonoma or later.
2. Double-click the zip, then drag **Quick Chat.app** into **Applications**. Open it from Applications, not from Downloads.
3. The first time, macOS shows *"Apple could not verify 'Quick Chat' is free of malware…"*. Click **Done**.
4. Open **System Settings → Privacy & Security**, go to **Security**, and click **Open Anyway** next to "Quick Chat was blocked…". Confirm with **Open Anyway** and your login password. The button shows for about one hour after the blocked launch. If you do not see it, open the app again.

   Or, in Terminal, after you move the app to Applications:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/Quick Chat.app"
   ```

Quick Chat then shows in the menu bar. It has no Dock icon.

**Why the warning?** GitHub Actions builds each release from the tagged source. But the release is not signed with an Apple Developer ID and not notarized by Apple, so macOS warns about it. On macOS 15 and later, Control-click → Open does not skip the warning. If you do not want to trust a prebuilt app, [build it yourself](#build-from-source).

**Verify the download** (optional): put the matching `.sha256` file in the same folder, then:

```sh
cd ~/Downloads && shasum -a 256 -c Quick-Chat-<version>.zip.sha256
```

**Update:** quit Quick Chat, put the new app in Applications, and do the Open Anyway step again.

### Build from source

You need macOS 14 or later and Swift 6.0 or later. Xcode 16 or later is recommended. The Command Line Tools alone (`xcode-select --install`) can build for one architecture. If `swift build` fails with "Unknown error parsing property list", install Xcode.

```sh
git clone https://github.com/Issaminu/Quick-Chat.git
cd Quick-Chat
make            # build and sign "build/Quick Chat.app"
make run        # build, quit a running copy, and open the new one
make install    # copy to /Applications (or: make install PREFIX=~/Applications)
make uninstall  # remove it again
make clean      # remove .build and build/
```

macOS does not quarantine apps that you build yourself, so Gatekeeper does not block them.

## Use it

1. Click the menu-bar icon, and make sure **Quick Chat** is on. It turns on by itself at launch.
2. Press **⌥Space**. The panel opens at the bottom center of the screen under the pointer.
3. Sign in to ChatGPT once, inside the panel. Email, Apple or Microsoft sign-in is the most reliable.
4. Ask. Press ⌥Space, Esc or ⌘W to close the panel. The next ⌥Space opens the same conversation again, with your draft.

Each time Quick Chat starts after a normal quit, it starts with empty drafts. After a crash, your drafts stay.

To start Quick Chat at login: **System Settings → General → Login Items → Open at Login → +**, then select Quick Chat.

### Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌥Space | Open or close the panel (change it with **Change Shortcut…** in the menu) |
| Esc or ⌘W | Close the panel. While a menu, a dialog or the sidebar is open, Esc closes that first. |
| ⌘N | New chat, without a page reload |
| ⌘B | Show or hide the sidebar |
| ⌘F | Expand to a large window, or shrink back |
| ⌘O | Reset the panel to its default size (440 × 540) |
| ⌘K | Search your chats (ChatGPT) |
| ⌘U | Attach files (ChatGPT) |
| ⌘/ | Show all of ChatGPT's shortcuts |

The ChatGPT shortcuts come from chatgpt.com. They all work in the panel.

### The title bar

In the small panel, the title bar shows while the pointer is over the panel, and all its buttons fade in and out together. In the large window, it always shows.

| Button | Action |
| --- | --- |
| Close | Closes the panel (same as Esc). |
| Sidebar | Opens ChatGPT's sidebar with your chats and projects. |
| Expand / Shrink | Makes the panel a large window with the same chat, or small again. |
| Temporary Chat | Starts or ends a temporary chat (in an empty chat). |
| New Chat | Starts a new chat (in a conversation, same as ⌘N). |

Drag an empty part of the title bar to move the panel. Drag an edge to resize it. Each time the app starts, the panel first opens at its default place. It keeps its size across launches.

In the large window, ChatGPT docks its row of icons on the left. Point at them to see the sidebar.

## Design details

Quick Chat changes how chatgpt.com looks inside the panel. It changes only the look, not what the page does:

- **One material.** The page background is transparent, so the panel's native translucent material shows through. Menus, the sidebar and floating buttons keep their own backgrounds.
- **Concentric corners.** The window corners have a 20-point radius. The composer sits 8 points from the sides and the bottom, so its corners have a 12-point radius (20 − 8), with the same center.
- **A clear message area.** Messages stop at the top edge of the composer and fade out above it, so no text shows beside, below or through the composer. At the top, messages stop at the bottom edge of the title bar.
- **Native text.** Text uses the system font with the system's font smoothing, and message text is 15 points.
- **Quiet scrolling.** The message list and a long draft in the composer have a thin rounded scroll bar inside the right edge. They do not stretch at the ends. A code block scrolls its code first, then the conversation.
- **The cursor stays in view.** In a long draft, the composer scrolls with the text cursor while you type, paste or move the cursor.
- **No jumps when the size changes.** During Expand or Shrink, a cover with the panel's material fades in, the window changes its size, and the cover fades out when the page is drawn at the new size.

The style uses only ChatGPT's own semantic attributes (`data-app-shell-*`, `data-composer-*`, `data-thread-*`) and design tokens, never text or generated class names. When ChatGPT changes its page, a part of the style that loses its hook falls back to ChatGPT's own look. The page does not break.

## Free ⌥Space from ChatGPT's Mini

The new ChatGPT app also uses ⌥Space, for Show Mini. **Disable Show Mini Shortcut** in the menu removes that shortcut. Mini itself still works from inside the app.

The new ChatGPT app reads its shortcuts from `~/.codex/keybindings.json` (or `$CODEX_HOME/keybindings.json`). To free ⌥Space, Quick Chat adds one entry there:

```json
{"command": "openAvatarOverlay", "key": null}
```

The ChatGPT app writes the same "unbound" entry itself when it finds a shortcut clash.

- **Automatic on a clash.** If Quick Chat's shortcut is the same as Show Mini's, Quick Chat removes Show Mini's shortcut while Quick Chat is on, also when Disable Show Mini Shortcut is off.
- **Restart needed.** ChatGPT reads this file only at launch. Quick Chat offers **Restart ChatGPT to Apply**. It never restarts ChatGPT by itself.
- **Restored on quit.** When you turn the features off or quit Quick Chat, it puts your previous entry back. A backup in `~/Library/Application Support/ChatGPTCompanion/` restores it at the next launch if Quick Chat crashed.
- If the file is not valid JSON, Quick Chat does not change it.

## Permissions

Quick Chat needs no Accessibility or Automation access. macOS asks for the **microphone** the first time you use voice, and for the **camera** when you take a photo or share video.

Release builds, and local builds without an Apple Development certificate, are signed ad-hoc. macOS then identifies the app by the hash of its code, so after each update it can ask again. To clear old entries:

```sh
tccutil reset Microphone dev.shuaibird.quickchat
tccutil reset Camera dev.shuaibird.quickchat
```

If you build from source with a free Apple Development certificate (Xcode → Settings → Accounts), macOS keeps the grants across rebuilds. The build script finds the certificate by itself.

## Privacy

- Quick Chat has no servers, no analytics and no telemetry. The panel connects only to chatgpt.com and to the sign-in provider that you select. Other links open in your default browser.
- Your sign-in session stays on your Mac, in the app's web data. **Sign Out of Quick Chat** deletes it.
- Quick Chat changes nothing in the ChatGPT app bundle. The only file that it changes is the ChatGPT app's `keybindings.json`, and it restores that file when you turn the features off or quit.

## Limitations

- **It is a web view.** It shows chatgpt.com, not a native ChatGPT client. You sign in separately from any ChatGPT app. Your chats are regular ChatGPT conversations in your history (except temporary chats).
- **Google sign-in can stop working.** It works because the panel identifies itself as Safari. Google blocks sign-in from embedded web views and can detect this at any time. Email, Apple and Microsoft sign-in do not have this risk.
- **chatgpt.com can change.** When it changes, a part of the panel's style can fall back to ChatGPT's own look until Quick Chat is updated.
- **Downloads and dialogs.** Downloads go to ~/Downloads and show in Finder. Some cases can fail, such as the right-click "Download Image" item. `alert()` and `confirm()` dialogs from the site do not show.
- **It depends on ChatGPT app internals.** The Show Mini command name (`openAvatarOverlay`) is not documented. A ChatGPT update can rename it.
- **The usage benefit may not last.** If Chat and Work get one shared allowance, Quick Chat is still a fast chat panel, but it saves no agent allowance.

## Development

The checks run on macOS:

```sh
python3 scripts/check-panel.py
swiftc -swift-version 6 Sources/QuickChat/Features/QuickChat/QuickChatPageStyle.swift scripts/check-page-style.swift -o /tmp/quickchat-page-style-check
/tmp/quickchat-page-style-check
```

- `check-panel.py` builds the real panel in an isolated test app with a local page that has the same hooks as chatgpt.com. It checks the buttons, the shortcuts, the title bar, the size changes and the position.
- `check-page-style.swift` checks the style on a local page: transparency, insets, corners, the message cut and fade, the hidden toolbars and the scroll bar.
- `check-live.py` checks the style on the real chatgpt.com, with your Quick Chat session. It sends no messages. Run it when ChatGPT changes its page, to see which part lost its hook. Quit Quick Chat first.

  ```sh
  python3 scripts/check-live.py
  ```

Build options (environment variables for `make` or `scripts/build-app.sh`):

| Variable | Default | Effect |
| --- | --- | --- |
| `CODESIGN_IDENTITY` | first "Apple Development" identity, else ad-hoc | signing identity; `-` forces ad-hoc |
| `UNIVERSAL=1` | off | build for arm64 and x86_64 |
| `VERSION` | latest `v*` git tag, else `0.0.0-dev` | `CFBundleShortVersionString` |
| `BUNDLE_ID` | `dev.shuaibird.quickchat` | bundle identifier |

### Releasing

The tag is the version. `git tag -a v0.3.0 -m "Quick Chat 0.3.0" && git push origin v0.3.0` starts `.github/workflows/release.yml`. The workflow builds a universal, ad-hoc-signed app, checks it, and attaches `Quick-Chat-0.3.0.zip` and its `.sha256` to a GitHub release. A tag with a `-` (for example `v0.4.0-beta.1`) makes a prerelease. To test without a release, run the workflow by hand (`gh workflow run release.yml -f version=0.3.0-test`). It then uploads the zip as a workflow artifact.

## Credits

Quick Chat started as [shuaibird/Quick-Chat](https://github.com/shuaibird/Quick-Chat), which brought the ⌥Space chat bar to the new ChatGPT app. This fork redesigns the panel: the native look, the title bar, the Expand and Shrink transition, temporary chats, and the background loading.

## Not affiliated with OpenAI

Quick Chat is an independent open-source project. It is not affiliated with, endorsed by or sponsored by OpenAI. ChatGPT is a trademark of OpenAI, used here only to tell what the app works with.

## License

[MIT](LICENSE)
