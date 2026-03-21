# MCV Browser (Qt WebEngine)

MCV is a macOS-focused browser shell built with Qt Widgets + Qt WebEngine, with a command-first workflow (`Cmd+E`), floating tab UI, security modes, and a global Spotlight-like overlay.

## Current Build Targets

This repository currently has two qmake project files:

- `SpotlightBrowser_experimental.pro` -> builds `MCVExperimental`
- `SpotlightBrowser.pro` -> builds `MCV`

Important: **both `.pro` files currently compile `SpotlightBrowser_experimental.cpp`**.

## Key Features

- Command overlay (`Cmd+E`) with history/autocomplete/aliases.
- Floating tabs panel + circular tab wheel.
- Favorites (pinned domains), saved links, per-session tab restore.
- Security modes: `classic`, `safe`, `secure`.
- Global system overlay on macOS (`Option+Space`).
- Built-in tools: calc, translate, perf diagnostics, focus mode, keychain autofill.
- UI controls: tint/theme/font/opacity/logo presets.

## Repository Layout

- `SpotlightBrowser_experimental.cpp` - main implementation used by current builds.
- `SpotlightBrowser.cpp` - older/base variant source kept in repo.
- `SpotlightBrowser_experimental.pro` - target `MCVExperimental`.
- `SpotlightBrowser.pro` - target `MCV` (currently same source as experimental).
- `SpotlightBrowser_experimental.qrc` - embedded assets for logos/resources.
- `logos/` - custom logo PNG presets.
- `AppIcon.icns` - app icon bundle asset.

## Requirements

- macOS
- Xcode Command Line Tools
- Qt 6 with WebEngine modules

Typical install:

```bash
brew install qt qt-webengine qt-positioning
export PATH="/opt/homebrew/opt/qt/bin:$PATH"
```

## Build and Run

Build experimental:

```bash
qmake SpotlightBrowser_experimental.pro
make -j"$(sysctl -n hw.ncpu)"
./MCVExperimental
```

Build MCV target:

```bash
qmake SpotlightBrowser.pro
make -j"$(sysctl -n hw.ncpu)"
./MCV
```

## Update `.app` Bundle (macOS)

If wrapper app already exists, replace inner executable and re-sign:

```bash
cp -f MCVExperimental "MCV Experimental.app/Contents/MacOS/MCVExperimental"
codesign --force --deep --sign - "MCV Experimental.app"
```

For `MCV` target:

```bash
cp -f MCV "MCV.app/Contents/MacOS/MCV"
codesign --force --deep --sign - "MCV.app"
```

## Keyboard Shortcuts (Current)

### Core

- `Cmd+E` - open/close command overlay
- `Cmd+S` - DevTools panel
- `Cmd+F` - copy current URL
- `Cmd+G` - tab wheel
- `Cmd+T` - new empty tab
- `Cmd+W` - close tab
- `Cmd+N` - new window
- `Cmd+R` - reload
- `Cmd+[` / `Cmd+]` - back / forward
- `Cmd+Shift+[` / `Cmd+Shift+]` - previous / next tab
- `Cmd+Q` - hard exit process

### Option shortcuts

- `Opt+R` - hard reload (bypass cache)
- `Opt+I` - DevTools
- `Opt+J` - Console (DevTools Console panel)
- `Opt+F` - find in page
- `Opt+T` - run `restore` (restore saved session tabs)
- `Opt+Up` / `Opt+Down` - previous / next tab
- `Opt+1..9`, `Opt+0` - jump to regular tab 1..10
- `Opt+Tab` / `Opt+Shift+Tab` - open tabs panel
- `Opt+Space` - toggle system overlay (global hotkey on macOS)

### Favorites / Tab switch

- `Cmd+1..9`, `Cmd+0` - open favorite by key
- `Cmd+\\`, `Cmd+\``, `Cmd+Ї`, `Cmd+Ё` - tabs panel fallback by layout

### Tab wheel controls

- `Cmd+G` - open/close wheel
- arrows / `Tab` - move selection
- mouse wheel - rotate selection
- `Enter` or `Space` - activate
- `Esc` - close

## Command Reference (Experimental)

Run `help` inside MCV for full in-app help. Main commands:

### Navigation

- `open <url>`
- `reload`
- `back`
- `forward`
- `home`
- `new`
- `close`
- `tabs`
- `restore`

### Search / Sites

- `g <query>`
- `ddg <query>`
- `yt <query>`
- `tw <user>`
- `x <user>`
- `gh <user>`
- `ghr <owner/repo>`
- `c [prompt]`
- `gmail`
- `classroom`
- `tv <symbol> [tf]`
- `bn btc|eth`
- `coinglass`
- `cmc btc|eth`
- `fear`
- `json <url>`

### Tools

- `calc <expr>`
- `tran <text>`
- `tran <from> <to> <text>`
- `translate ...` (alias)
- `speed x1.25`
- `scroll x0.5`
- `perf status|gpu|fps [sec]`
- `downloads [clear]`
- `history [sites|cmds|clear|del N]`
- `focus 30m|42m|2h`
- `focus off`
- `focus set <folder[,folder]>`
- `clear`
- `dev`
- `scream` / `egg`

### UI / Appearance

- `dark`
- `theme dark|light|off`
- `opacity <0.05-1.0>`
- `tabopacity <0.05-1.0>`
- `tint <color>|system|off`
- `tint img on|off`
- `font <name>|off`
- `logo <preset>`
- `logo list`
- `blur on|off`
- `suggest on|off`
- `spot`
- `float`
- `minimal`
- `bar`

### Customization

- `alias <key> <expansion>`
- `alias`
- `fav`
- `fav list`
- `fav open <key>`
- `profile trade|dev|minimal`

### Security

- `mode classic|safe|secure`
- `js on|off` (secure mode)
- `clearonexit add|del <host>`
- `clearonexit list`
- `wipe`
- `ua mobile|desktop`
- `proxy on|off`

### Passwords (Keychain)

- `pass`
- `pass save [host]`
- `pass set <host> <user> <pass>`
- `pass fill [host]`
- `pass del <host>`
- `pass list`
- `pass auto on|off`
- `pass ignore add|del <host>`
- `pass ignore list`

## Security Modes

### classic

- Standard profile behavior.
- Persistent cookies/cache/history/downloads.

### safe

- Dedicated `SafeProfile`.
- Disk persistence enabled.
- Additional filtering + `clearonexit` support.

### secure

- Dedicated `SecureProfile`.
- No persistent cookies.
- No disk cache.
- Stricter request/resource blocking and memory-only permissions.

Switching mode opens a new browser window in the selected mode.

## Translation Behavior

`tran` uses Google Translate HTTP endpoint (`translate.googleapis.com`).

Output format is:

```text
Translate (ru → en)

<translated text>
```

Auto direction:

- Cyrillic detected -> `ru -> en`
- otherwise -> `en -> ru`

Language short codes:

- `e` English (`en`)
- `f` French (`fr`)
- `r` Russian (`ru`)
- `u` Ukrainian (`uk`)
- `s` Spanish (`es`)
- `c` Chinese (`zh-CN`)
- `a` Arabic (`ar`)
- `i` Italian (`it`)

## First-Launch Page

First run intro/start page is embedded in `SpotlightBrowser_experimental.cpp` as `kStartPageHtml`.

After first run, key `ui/firstLaunchIntroShown` is persisted in app settings.

To force first-run page again:

```bash
defaults delete com.local.MCV "ui/firstLaunchIntroShown" 2>/dev/null
defaults delete com.Local.MCV "ui/firstLaunchIntroShown" 2>/dev/null
```

## Persistence

Stored via `QSettings` (organization `Local`, app name `MCV`).

Examples:

- UI prefs (theme/opacity/tint/font/logo)
- sessions (`session/tabs`, `session/current`)
- aliases (`terminal_aliases`)
- favorites (`terminal_favorites`)
- download/search history
- mode-specific settings (`safe/*`, `secure/*`)

## Favorites Format and Reserved Keys

Format:

```text
1 - https://chatgpt.com
2 - https://youtube.com
a - https://x.com
```

Rules:

- key is one char (`0-9` or `A-Z`)
- separators: `-`, `:`, `=`
- duplicate key overwrites previous (warning shown)

Reserved keys are blocked:

- `e`, `t`, `w`, `n`, `r`, `s`

## Troubleshooting

### App won’t open

Re-sign bundle:

```bash
codesign --force --deep --sign - "MCV Experimental.app"
```

### `permission denied` when launching `.app`

`.app` is a directory bundle. Run the inner executable:

```bash
"MCV Experimental.app/Contents/MacOS/MCVExperimental"
```

### Global `Opt+Space` does not trigger

Likely macOS input-source shortcut conflict. Rebind system shortcut or change hotkey in code.

### Restore did nothing

- Check there is a saved session (`session/tabs` exists).
- Use `restore` command (or `Opt+T`) after tabs were saved.

## Open Source Checklist

Recommended to publish:

- `README.md`
- `SpotlightBrowser_experimental.cpp`
- `SpotlightBrowser.cpp`
- `SpotlightBrowser_experimental.pro`
- `SpotlightBrowser.pro`
- `SpotlightBrowser_experimental.qrc`
- `logos/`
- `AppIcon.icns`
- `LICENSE`

Do not publish:

- binaries (`MCV`, `MCVExperimental`, etc.)
- `*.o`, `moc_*`, `qrc_*`, `Makefile`
- `*.app`, `*.dmg`
- local env files, secrets, tokens

---

If behavior changes in code, update this README in the same commit.
