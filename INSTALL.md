# Installing Quick Chat: guide for AI assistants

This file is written for an AI assistant (Claude, ChatGPT, Codex, Cursor, …) helping someone
install Quick Chat. If you're a person, the [README](README.md#install) has the same steps.

To use it, tell your assistant:

> Read https://github.com/Issaminu/Quick-Chat/blob/main/INSTALL.md and help me install Quick Chat.

---

## For the assistant

Quick Chat is a macOS menu-bar app (no Dock icon) that shows chatgpt.com in a floating panel
on ⌥Space. Repository: `https://github.com/Issaminu/Quick-Chat`. Bundle id:
`dev.shuaibird.quickchat`. App name on disk: `Quick Chat.app`.

### Ground rules

- **Explain before you act.** Say what each command does before running it, or before asking
  the user to run it if you can't run commands yourself.
- **Never** disable Gatekeeper system-wide (`spctl --master-disable`, `--global-disable`) and
  never use `sudo`. Neither is needed: an app that is built on the user's Mac is not
  quarantined, so Gatekeeper does not block it.
- There is no prebuilt download for this repository. Always build from source.
- Don't edit `~/.codex/keybindings.json` by hand. Quick Chat manages its own entry there.
- If a step fails, show the user the exact error and use [Troubleshooting](#troubleshooting)
  before trying anything else.

### Step 0: check the Mac

```sh
sw_vers -productVersion   # must be 14.0 or later
uname -m                  # arm64 (Apple silicon) or x86_64 (Intel); both are supported
```

If macOS is older than 14, stop: Quick Chat won't run there.

Then build and install Quick Chat from source (steps 1 to 3).

---

### Step 1: check the toolchain

```sh
xcode-select -p
swift --version   # needs Swift 6.0 or later
```

- If `xcode-select -p` fails, the user needs developer tools. Recommend installing **Xcode 16
  or later** from the App Store (most reliable). The Command Line Tools
  (`xcode-select --install`) are smaller and can work, but see the plist error under Troubleshooting.
- If Xcode is installed but `swift --version` reports an older compiler, the active developer
  directory may be wrong; have the user pick the newer Xcode in Xcode → Settings → Locations
  → Command Line Tools.
- The first time Xcode is installed, it may need its license accepted: open Xcode once.

### Step 2: clone and build

```sh
git clone https://github.com/Issaminu/Quick-Chat.git
cd Quick-Chat
make
```

This writes `build/Quick Chat.app`. The first build takes a minute or two.

### Step 3: install and open

```sh
make install                       # copies to /Applications and quits any running copy
open "/Applications/Quick Chat.app"
```

If the user can't write to /Applications, use `make install PREFIX=~/Applications` and open
`~/Applications/Quick Chat.app` instead. Self-built apps aren't quarantined, so there's no
Gatekeeper prompt.

**Optional: keep microphone and camera grants across rebuilds.** If the user signed in to
Xcode with an Apple ID (Xcode → Settings → Accounts), they have a free Apple Development
certificate and the build script uses it automatically. Without one the app is signed ad-hoc,
and macOS may ask for microphone access again after every rebuild.

**Updating later:** `git pull && make install` from the clone.

Then continue with [First run](#first-run).

---

## First run

Tell the user:

1. Quick Chat appears **only in the menu bar** (a speech bubble with sparkles). There's no
   Dock icon or window yet. If the menu bar is crowded, the icon may be hidden behind the
   notch; quitting another menu-bar app or using a menu-bar manager reveals it.
2. Click the icon and check that **Quick Chat** is on. It turns on by itself at launch;
   **Disable Show Mini Shortcut** starts off.
3. Press **⌥Space**. A small panel opens with chatgpt.com, at the bottom center of the screen. Sign in once inside it. Email,
   Apple or Microsoft sign-in are the most reliable; Google sign-in works today but Google may
   block embedded browsers at any time.
4. Press ⌥Space, Esc or ⌘W to hide it. **Change Shortcut…** in the menu picks another key.
5. **If the new ChatGPT desktop app is installed**, it also uses ⌥Space (for Show Mini).
   Quick Chat frees that shortcut automatically while it uses it, and offers
   **Restart ChatGPT to Apply**: ChatGPT only reads shortcut changes at launch. Quick Chat
   never restarts ChatGPT on its own. Quitting Quick Chat restores the original shortcut.
6. The first time the user speaks to ChatGPT, macOS asks for microphone access. Allow it.

To launch it at login: **System Settings → General → Login Items → Open at Login → +**, then
choose Quick Chat.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Nothing visible after opening | It's a menu-bar app; look for the icon, which can be hidden behind the notch. `pgrep -x QuickChat` confirms it's running. |
| ⌥Space does nothing | Turn on **Quick Chat** in the menu. If ChatGPT still grabs ⌥Space, choose **Restart ChatGPT to Apply**. Another app (Raycast, Alfred, input-source switching) may also own ⌥Space; pick a different shortcut with **Change Shortcut…**. |
| `swift build` fails with "Unknown error parsing property list" | Happens with the Command Line Tools alone. Install Xcode and select it (step 1). |
| `UNIVERSAL=1 make` fails | Universal builds need full Xcode, and a normal `make` is fine for one Mac. |
| `swift: command not found` / `xcrun: error: invalid active developer path` | Developer tools are missing; see step 1. |
| Microphone or camera keeps being asked for after an update | Expected for ad-hoc-signed builds (no Apple Development certificate; see step 3). To clear stale entries: `tccutil reset Microphone dev.shuaibird.quickchat` and `tccutil reset Camera dev.shuaibird.quickchat`. |
| Want to remove it | Quit from the menu (this restores ChatGPT's shortcut), then delete `/Applications/Quick Chat.app` (or `make uninstall` in a clone). To also clear settings: `defaults delete dev.shuaibird.quickchat` and `rm -rf ~/Library/Application\ Support/ChatGPTCompanion`. |

For anything else, point the user to the
[issue tracker](https://github.com/Issaminu/Quick-Chat/issues) with the macOS version, the
install path they used, and the exact error.
