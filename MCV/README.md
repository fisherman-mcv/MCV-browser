# MCV Browser (Swift + WKWebView)

Technical README for the release-ready non-experimental package.

## Stack

- SwiftUI + AppKit UI
- WKWebView (WebKit) browser engine
- C++ command helper (`helper.cpp`)
- zsh build script (`build.cpp`)

This project is not based on Qt WebEngine.

## Main files

- `main.swift`
- `helper.cpp`
- `build.cpp`

## Runtime architecture

- `BrowserStore` in `main.swift` is the main runtime state and behavior layer.
- `BrowserRootView` renders window UI, chrome, overlays, panels, and routes keyboard/pointer events.
- `BrowserTab` wraps each `WKWebView` plus metadata and observers.
- `CommandHelperClient` executes `mcv_command_helper` and maps JSON actions to Swift handlers.
- `MiniMCVPanelController` and `MiniMCVPanelModel` implement the `Opt+Space` mini window.
- `WebExtensionManager` + bridge classes implement unpacked/Web Store extension install and runtime injection.
- `SecurityProfileRuntime` provides profile isolation per security mode.
- `PerformanceMonitorModel` drives the terminal-style performance window.

## Keyboard shortcuts

### Global shortcut

- `Opt+Space`: toggle Mini MCV panel (Carbon global hotkey).

### Core window shortcuts

- `Cmd+E`: command overlay (mixed mode: command or search/address).
- `Ctrl+E`: disabled (consumed, no action).
- `Cmd+L`: focus smart bar.
- `Cmd+U`: focus current page content (removes focus from text inputs/overlays).
- `Cmd+F`: open find overlay.
- `Cmd+I`: open devtools.
- `Cmd+J`: open devtools console.
- `Cmd+D`: toggle browser chrome visibility.
- `Cmd+R`: reload.
- `Opt+R`: hard reload.
- `Cmd+[` and `Cmd+]`: back/forward.
- `Cmd+T`: new tab (or open main window from music window).
- `Cmd+W`: close current tab, and hide window if only one tab remains.
- `Cmd+Shift+T`: restore most recently closed tab.
- `Cmd+Shift+D`: duplicate tab.
- `Cmd+Shift+B`: add current page to bookmarks.
- `Cmd+Y`: toggle history panel.
- `Cmd+B`: toggle bookmarks panel.
- `Cmd+S`: toggle Saved navigator overlay.
- `Cmd+G`: open tab wheel.
- `Cmd+O`: open music wheel.
- `Cmd+1..9`, `Cmd+0`: switch regular tabs by index.
- `Cmd+Left/Right` and `Cmd+Up/Down`: cycle regular tabs.
- `Cmd+,`: open Settings (standard macOS settings shortcut).

### Option-only shortcuts

- `Opt+F`: copy current page URL.
- `Opt+1..9`, `Opt+0`: open bookmark by default index.
- `Opt+Left/Right` and `Opt+Up/Down`: cycle bookmark tabs.
- `Opt+<alnum>` custom bookmark shortcuts:
- Input accepts one alphanumeric symbol.
- Trigger works only with exact `Option` modifier.

### Temporary/system shortcuts

- `Ctrl+Q`: traffic light tuner overlay.
- `Ctrl+R`: open performance window.
- `Ctrl+W`: reset browser to first-launch state.

### Escape behavior

- If link hint mode active: close hint mode.
- If mini panel active: close mini panel.
- If command overlay active: close overlay.
- If tab wheel active: cancel wheel selection.
- If music wheel active: cancel wheel selection.
- If no overlay/panel active: start Vimium-style link hints.

## Overlay and panel keyboard control

### Command overlay

- `Up` / `Down`: move suggestion selection.
- `Enter`: run selected suggestion or typed input.
- `Tab`: toggle command-armed state in mixed mode.

### Find overlay (`Cmd+F`)

- `Up` / `Down`: move match suggestion.
- `Enter`: activate selected suggestion.
- `Esc`: close and clear highlights.

### Saved navigator (`Cmd+S`)

- `Up` / `Down`: selection.
- `Right` or `Enter`: open folder/link.
- `Left` or `Backspace`: go to parent folder.
- `Delete` / `Forward Delete` / `Cmd+Delete`: remove selected entry.
- `Mouse wheel`: moves selection.
- Supports drag and drop of saved links between folders and root.

### Bookmarks panel

- `Up` / `Down`: selection.
- `Enter`: open selected bookmark.
- Hover syncs current keyboard selection.
- Header shows current bookmark position as `Current: X/N` when active tab is bookmarked.

### Tab wheel (`Cmd+G`)

- Opens around cursor.
- `Scroll` or `Arrow keys`: cycle tab target.
- `Enter`, mouse release, or releasing `Cmd`: accept selection.
- `Esc`: cancel.

### Music wheel (`Cmd+O`)

- Opens around cursor.
- Mouse direction selects action sector.
- `Scroll` adjusts volume delta.
- Mouse release or releasing `Cmd`: execute selection.
- `Esc`: cancel.
- Center node shows current title/subtitle/progress/artwork and mood state.

## Command runtime

Command execution path:

- `Cmd+E` and smart bar command mode call `applyBridge(...)`.
- Local handlers run first for:
- `ext ...` (extension local command set).
- `alias ...` (local alias CRUD and command chaining).
- Alias expansion supports `/cmd1/cmd2/...` chain parsing.
- Remaining commands go to C++ helper (`mcv_command_helper`) which returns JSON actions.
- Swift side executes action handlers (`navigate`, `reload_page`, `open_settings`, `set_theme`, and others).

### Command groups

Navigation:

- `open <url>`
- `reload`
- `back`
- `forward`
- `home`
- `new | newtab | t`
- `private`
- `close | closetab | w`
- `reset | resettabs | tabsreset`

Search and sites:

- `g <query>`
- `ddg <query>` or `search <query>`
- `yt <query>` or `youtube <query>`
- `wiki <query>`
- `wiki <lang> <query>` with language aliases `e r u i f s c`
- `tw <user>`
- `x <user>`
- `gh <user>` or `github <user>`
- `ghr <user/repo>`
- `tv <symbol> [1m|5m|15m|1h|4h|1d]`
- `bn <symbol>`
- `coinglass`
- `cmc btc|eth`
- `fear`
- `json <url>`
- `c [prompt]` (open ChatGPT, optionally with query)

Tools and browser actions:

- `book | bookmark | pin`
- `bookmarks | bm`
- `history [sites|cmds|clear|del N]`
- `downloads [clear]`
- `clear`
- `dev`
- `console`
- `settings`
- `copy | copylink`
- `tab <number>`
- `speed x1.5`
- `scroll x0.5`
- `notify <text>` or `notify <title>|<message>`

Interface:

- `dark`
- `theme dark|light|off`
- `colors | color`
- `spot`
- `float`
- `minimal`

Security:

- `mode classic|safe|secure`
- `js on|off` (secure mode only)
- `clearonexit add <host>`
- `clearonexit del <host>`
- `clearonexit list` (safe mode only)
- `wipe` and `pass ...` currently return preview status

Pro settings:

- `pro`
- `pro opacity <0.05-1.0>`
- `pro blur on|off`
- `pro blur mini on|off` (status-only placeholder response)
- `pro suggest on|off`
- `pro smart on|off`
- `pro radius <int>`
- `pro cuts [edit|path|reload|reset]`
- `pro reset`

Music:

- `music`
- `music stop|pause|toggle|next|prev`
- `music favorite`
- `music playlist|radio`
- `music find|search [query]`
- `music focus [coding|trading|night|resonance]`
- `music play <query>`

Ollama and AI:

- `ollama on|off|status|test|chat <message>`
- Helper supports `ai <prompt>`, but `Cmd+E` blocks direct `ai` and shows a message.
- Intended path for `ai` is Mini MCV.

Extensions:

- `ext list|ls|panel`
- `ext install <folder|url|id>`
- `ext webstore <url|id>`
- `ext enable <id>`
- `ext disable <id>`
- `ext remove <id>`
- `ext popup <id>`
- `ext options <id>`
- `ext window <id>` (opens popup/options in separate app window)
- `ext grant <id> <permission>`
- `ext revoke <id> <permission>`
- `ext reload`
- `ext logs`

Aliases:

- `alias` shows summary
- `alias <name> <expression>` saves alias
- `alias del <name>` (also `remove`, `rm`, `delete`)
- `alias clear`
- Chain format supported, for example `alias tv /new/open https://tradingview.com/`
- Alias recursion depth limit is `8`.

Help:

- `help`
- `help <cmd>`
- `help ext`
- Help opens a native help tab rendered by app UI, not a web page.

## Mini MCV (`Opt+Space`)

- Supports instant calculator:
- `calc <expr>`
- `=<expr>`
- raw arithmetic like `2+2`
- Supports instant translation:
- `tran <text>`
- `tran <from> <to> <text>`
- aliases: `e f r u s c a i`
- default direction:
- Cyrillic text defaults to `ru -> en`
- Latin text defaults to `en -> ru`
- Supports local AI:
- `ai <prompt>`
- uses selected Ollama model from Settings.
- Can open web preview when input resolves to URL/search.

## Security modes

`classic`:

- default profile and storage behavior
- persistent cookies/cache/history/downloads
- no extra request filtering

`safe`:

- separate profile datastore (`SafeProfile` identifier on supported macOS)
- persistent storage
- download confirmation dialog on download attempts
- `clearonexit` host list available and applied on app termination

`secure`:

- non-persistent datastore (`WKWebsiteDataStore.nonPersistent()`)
- separate process pool
- blocks top-level `http` and `ws` navigations
- injects secure shield script that blocks or restricts:
- insecure or cross-origin `fetch`
- insecure or cross-origin `XMLHttpRequest`
- insecure or cross-origin `WebSocket`
- insecure or cross-origin `Worker` and `SharedWorker`
- insecure `sendBeacon`
- `Notification.requestPermission` forced to denied
- `serviceWorker.register` rejected
- `PushManager.subscribe` rejected
- insecure or cross-origin script `src` nodes removed via mutation observer
- per-host JavaScript policy controlled by `js on|off`

Mode switch persists in settings and opens a new browser window to apply config.

## WebExtensions implementation

- Installs unpacked folder extensions and Web Store CRX sources.
- Web Store install path:
- parse extension id from URL/id input
- download CRX from Google update endpoint
- extract ZIP payload
- unpack and install into app support
- Uses compatibility tiers:
- tier `A`: content-script-focused manifests
- tier `B`: background/action/browser_action present
- tier `C`: high-risk APIs like `webRequestBlocking`, `debugger`, `nativeMessaging`
- Runtime bridge includes:
- content script injection through `WKUserScript`
- JS bridge shim for selected `chrome.*` APIs
- background runtime using JavaScriptCore
- permission gate with grant/revoke overrides
- Extensions panel supports:
- install by id/url/path
- rename
- copy id
- open popup/options/window
- enable/disable
- remove
- install progress bar and status text

## First-run and hints

- Hint lifecycle uses launch counter and auto-hides hints after `3` launches by default.
- Hints can be forced back on in settings.

## Build

```bash
./build.cpp
```

## Package build output

- `MCV` binary
- `MCV.app`
- `mcv_command_helper`
- `MCV_installer.dmg`
