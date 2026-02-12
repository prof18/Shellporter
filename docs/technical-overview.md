# Shellporter Technical Overview

Shellporter is a menu bar-only macOS application that detects the project directory of the active IDE window and opens a terminal at that location with a single hotkey press.

## At a Glance

- **Language:** Swift 6.2 (strict concurrency)
- **UI framework:** AppKit + SwiftUI (preferences/onboarding only)
- **Build system:** SwiftPM (no Xcode project)
- **External dependencies:** None
- **Minimum target:** macOS 14
- **Activation policy:** `.accessory` (menu bar only, no dock icon)

## Project Layout

```
Sources/Shellporter/
  main.swift                              App entry point
  App/
    AppDelegate.swift                     Status bar, lifecycle, lazy deps
    AppDelegate+Accessibility.swift       Permission polling + onboarding
    AppDelegate+Menu.swift                Dynamic menu rebuild
    AppDelegate+Terminal.swift            Hotkey callbacks, resolve-then-launch flow
    AppDelegate+Windows.swift             Window controller helpers
  Resolver/
    FocusedProjectResolver.swift          Orchestrator: strategy chain per IDE family
    AXWindowInspector.swift               macOS Accessibility API (AXUIElement)
    PathHeuristics.swift                  Title parsing, path normalization, project root detection
    JetBrainsRecentProjectsResolver.swift recentProjects.xml parser + tiered scoring
    EditorRecentsResolver.swift           VS Code / Cursor / Antigravity storage.json parser
    ResolutionCacheStore.swift            LRU cache (200 entries, JSON-persisted)
    ResolverModels.swift                  IDEFamily enum, ResolvedProjectContext, ResolverAttempt
  Terminal/
    TerminalLauncher.swift                Per-terminal launch logic (5 terminal types)
  Config/
    AppConfig.swift                       Settings model + TerminalChoice enum
    ConfigStore.swift                     JSON persistence, auto-detect, fallback
    SystemTerminalDetector.swift          Reads default terminal from macOS URL scheme handler
  Hotkey/
    HotKeyManager.swift                   Carbon Events global hotkey registration
    HotKeyShortcut.swift                  Key code display helpers
  Diagnostics/
    Logger.swift                          File logger with 2 MB rotation
  Localization/
    AppStrings.swift                      Localized string accessors
  UI/
    SettingsView.swift                    SwiftUI preferences
    SettingsViewModel.swift               Debounced config updates via Combine
    AboutView.swift                       SwiftUI about window
    AccessibilityOnboardingView.swift     First-run permission prompt
  Resources/
    Localization/en.lproj/Localizable.strings
    (icon assets)

Tests/ShellporterTests/                   Unit tests for resolvers, config, heuristics
Scripts/
  compile_and_run.sh                      Kill + package + relaunch dev loop
  package_app.sh                          .app bundle assembly + signing
  setup_dev_signing.sh                    Create stable local codesign identity
  sign-and-notarize.sh                    Notarization (scaffolded)
  make_appcast.sh                         Sparkle appcast generation (scaffolded)
  build_icon.sh                           Icon.icon -> Icon.icns conversion
```

## Entry Point

`main.swift` manually creates `NSApplication`, sets an `AppDelegate`, sets `.accessory` activation policy (no dock icon), and calls `app.run()`. No storyboards, no `@main`.

```swift
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

## Core Flow: Hotkey -> Terminal

When the user presses the hotkey (default `Ctrl+Opt+Cmd+T`):

```
1. HotKeyManager (Carbon Events) fires onPress callback
2. AppDelegate.resolveAndOpenTerminal(using:)
3.   Check accessibility permission; show onboarding if missing
4.   FocusedProjectResolver.resolve(targetApp:)
5.     Determine target app (frontmost, or cached "last external app")
6.     Identify IDE family from bundle ID
7.     Take AX window snapshot (title + document)
8.     Run strategy chain (IDE-specific order)
9.     On success: cache result, return path
10.    On failure: try cache lookup, then return nil
11.  If path found: TerminalLauncher.launch(at:choice:config:)
12.  If path nil: show NSOpenPanel for manual folder pick
```

A second hotkey (`Ctrl+Opt+Cmd+C`) copies a `cd` command to the pasteboard instead and focuses the terminal.

## Resolver Architecture

### IDE Detection

`IDEFamily.from(bundleIdentifier:)` classifies the frontmost app:

| Family | Bundle ID patterns |
|---|---|
| `jetBrains` | `com.jetbrains.*`, `org.jetbrains.*`, `com.intellij.*`, `com.google.android.studio*` |
| `vscode` | `com.microsoft.vscode`, `com.microsoft.vscodeinsiders`, `com.vscodium` |
| `cursor` | `*cursor*`, `com.todesktop.230313mzl4w4u92` |
| `antigravity` | `com.google.antigravity` |
| `xcode` | `com.apple.dt.xcode` |
| `unknown` | Everything else |

### Strategy Chains

Each IDE family runs strategies in a specific order. The first successful strategy wins.

| Family | Strategy order |
|---|---|
| JetBrains | `TitlePaths` -> `JetBrainsRecentProjects` -> `AXDocument` -> `Cache` |
| VS Code / Cursor / Antigravity | `AXDocument` -> `TitlePaths` -> `EditorRecents` -> `Cache` |
| Xcode | `AXDocument` -> `TitlePaths` -> `Cache` |
| Unknown | `AXDocument` -> `TitlePaths` -> `Cache` |

**Why different orders?** JetBrains IDEs expose the project name reliably in the window title, but their AXDocument often points to a single file deep in the tree. VS Code exposes the workspace URI directly via AXDocument, making it the fastest source. Xcode's AXDocument is unreliable for workspace-level paths.

### Strategies in Detail

#### AXDocument

Reads `kAXDocumentAttribute` from the focused AX window element. If it's a `file://` URI or absolute path, normalize it (strip file name, find project root). Fastest when available.

#### TitlePaths (AXTitle)

Parses the window title for path-like tokens:
1. Split on common separators (` -- `, ` - `, ` - `)
2. Scan for tokens starting with `/` or `~`
3. Regex scan for embedded paths: `(~|/)[A-Za-z0-9._/\-]+`
4. For each candidate, check existence on disk and normalize

#### JetBrainsRecentProjects

Parses `recentProjects.xml` files from `~/Library/Application Support/JetBrains/*/options/` and `~/Library/Application Support/Google/*/options/` (Android Studio).

Files are sorted by modification date (newest first). The XML parsing extracts `<entry key="...">` elements with `RecentProjectMetaInfo` metadata including frame title, opened status, and timestamps.

**Tiered scoring** prevents false positives when multiple similar projects exist:

| Tier | Condition | Rationale |
|---|---|---|
| 0 | Frame title matches current window title AND mentions candidate path | Strongest: live window match |
| 1 | Folder name exactly matches a title hint (literal or canonical) | Current title is source of truth |
| 2 | Frame title contains the candidate's full path | Stale but useful when no exact name match |
| 3 | Partial/substring folder name overlap | Weakest: catches `feed-flow` matching `feed-flow-2` |

Within a tier, candidates are further ordered by: `isOpened` > `isLastOpened` > `activationTimestamp` > `projectOpenTimestamp` > `sourceRank` > `depth` > path string.

**Path normalization** handles JetBrains tokens like `$USER_HOME$` and `&#36;USER_HOME&#36;`.

#### EditorRecents

Parses VS Code's `storage.json` from the editor's `globalStorage` directory. Uses two extraction methods:

1. **JSON traversal**: Recursively searches for `history.recentlyOpenedPathsList.entries`, then extracts paths from keys like `folderUri`, `workspaceUri`, `fileUri`, `folder`, `workspace`, `path`, `fsPath`.
2. **Regex fallback**: Scans raw text for `file:///...` URIs and absolute paths.

Both methods handle URI encoding (`\u002F`, `\/`, `file://` prefix stripping).

Matching uses project name hints from the window title: exact match first, partial match second, most recent entry as last resort.

#### CachedResolution

Last-resort strategy: looks up a previously successful resolution from the on-disk LRU cache. Handled on the main actor (not the resolver queue) because `ResolutionCacheStore` is `@MainActor`-isolated.

Two cache keys per resolution:

- **Exact**: `<bundleID>|title|<normalized window title>` -- precise recall for the same window, handles multi-project setups (e.g. two IntelliJ windows with different projects).
- **Last**: `<bundleID>|last` -- fallback when the title has changed or is empty, covers the common single-project-per-editor case.

Lookup tries exact key first (higher confidence), then last key. Both require the cached path to still exist on disk.

### Path Normalization

`PathHeuristics.normalizeProjectPath(from:)`:
1. Standardize the URL
2. If it's a file (not directory), go to parent
3. If it ends in `.xcodeproj` or `.xcworkspace`, go to parent
4. Walk up the directory tree looking for project root markers

**Project root markers:** `.git`, `.hg`, `.svn`, `.xcworkspace`, `.xcodeproj`, `.code-workspace`.

### Window Selection

`AXWindowInspector.snapshot(pid:)` collects candidate windows in priority order:
1. **Focused window** (`kAXFocusedWindowAttribute`) -- preferred
2. **Main window** (`kAXMainWindowAttribute`)
3. **All windows** (`kAXWindowsAttribute`)

Focused window is always preferred to avoid reading a stale title from a background project window.

### Target App Selection

When the hotkey fires, Shellporter may already be frontmost (the menu was clicked). `preferredTargetApp()` handles this:

1. If the frontmost app is not Shellporter, use it
2. Otherwise, use `lastKnownExternalApp` (tracked via `NSWorkspace.didActivateApplicationNotification`)
3. If that's terminated, fall back to frontmost

## Terminal Launcher

Each terminal type has distinct launch mechanics:

### Terminal.app
AppleScript via `osascript`. If Terminal is already running, opens a new tab (`do script "cd ..."`). If not, waits up to 2 seconds for the window to appear, then runs the command.

### iTerm2
AppleScript with **session reuse**. Sessions are named with a marker (`shellporter:<path>`). On subsequent invocations for the same path, Shellporter scans all iTerm2 windows/tabs/sessions for a matching marker and selects it instead of creating a new tab.

### Kitty
CLI-based single-instance launch: `kitty --single-instance --directory=<path>`. Searches for the binary in `/Applications/kitty.app/Contents/MacOS/kitty`, `/opt/homebrew/bin/kitty`, `/usr/local/bin/kitty`, `/usr/bin/kitty`. Falls back to `open -a kitty` if the binary isn't found.

### Ghostty
Two modes controlled by `ghosttyOpenNewWindow` config:
- **Single instance** (default): Tries `ghostty +new-window --working-directory=<path>` (Kitty-style CLI, one dock icon). Falls back to `open -a Ghostty <path>` (new tab in existing instance).
- **New window**: Uses `open -na Ghostty --args --working-directory=<path>` (separate process, may show extra dock icon).

Note: Ghostty's macOS CLI support for `+new-window` / `--working-directory` is not fully stable yet (ghostty-org/ghostty#2353).

### Custom Command
User provides a template string. `{path}` is replaced with the shell-escaped project path. Executed via `/bin/zsh -lc "<command>"`.

### Shell Escaping
Two escaping functions on `String`:
- `shellEscapedForBash()`: Single-quote wrapping with `'` -> `'"'"'` replacement
- `appleScriptEscaped()`: Backslash-escapes `\`, `"`, `\n`, `\r`, `\t`

## Hotkey System

Uses the **Carbon Events API** (`RegisterEventHotKey` / `InstallEventHandler`), not the modern `CGEvent` tap, because Carbon hotkeys work reliably as a background/accessory app without requiring the "Input Monitoring" permission.

Each `HotKeyManager` instance:
1. Installs an event handler for `kEventClassKeyboard` / `kEventHotKeyPressed`
2. Registers the hotkey with a unique 4-char signature + numeric ID
3. Uses `Unmanaged.passUnretained(self)` as the event handler's `userData`
4. Has an `isInvalidated` flag checked in the callback as a safety net against stale pointers

Two independent managers: `"SHPO"` (open terminal) and `"SHPC"` (copy cd command).

## Configuration

### Storage

`~/Library/Application Support/Shellporter/config.json`:

```json
{
  "customCommandTemplate": "open -a Terminal {path}",
  "defaultTerminal": "terminal",
  "ghosttyOpenNewWindow": false,
  "hotkeyKeyCode": 17,
  "hotkeyModifiers": 2816,
  "copyCommandHotkeyKeyCode": 8,
  "copyCommandHotkeyModifiers": 2816
}
```

- `hotkeyKeyCode` 17 = `T`, `copyCommandHotkeyKeyCode` 8 = `C`
- `hotkeyModifiers` 2816 = `controlKey | optionKey | cmdKey`

### First Launch

On first launch (no config file), `ConfigStore`:
1. Uses `SystemTerminalDetector` to query the macOS default handler for `x-man-page://` URL scheme
2. Maps the handler's bundle ID to a `TerminalChoice`
3. Creates config with the detected terminal as default

### Terminal Availability Fallback

When loading an existing config, if the configured terminal is no longer installed, `ConfigStore` auto-detects a replacement and updates the config.

### Settings UI

`SettingsViewModel` wraps `ConfigStore` with Combine publishers. Updates are debounced (300ms) before persisting. Hotkey changes unregister/re-register the Carbon event handlers immediately.

## Accessibility

The app requires macOS Accessibility permission to read window titles and document attributes via `AXUIElement`.

### Permission Flow
1. `applicationDidFinishLaunching`: check `AXIsProcessTrusted()`
2. If not trusted, show onboarding window + start 1.5s polling timer
3. Timer calls `AXIsProcessTrustedWithOptions` (without prompt) each tick
4. On grant: stop timer, dismiss onboarding, rebuild menu
5. Manual grant: "Grant Permission" menu item calls `AXIsProcessTrustedWithOptions(prompt: true)` which opens System Settings

### Code Signing and TCC

Ad-hoc signed builds lose Accessibility permission on every rebuild (macOS TCC keyed on code signature). The `setup_dev_signing.sh` script creates a self-signed "Shellporter Development" certificate in the login keychain for a stable identity that persists across rebuilds.

## Diagnostics

### Logger

File-based logging to `~/Library/Logs/Shellporter/app.log`:
- ISO 8601 timestamps
- 2 MB rotation (current -> `app.1.log` backup, then overwrite)
- Non-blocking writes via `DispatchQueue(qos: .utility)`
- Resolver logs every attempt with strategy name, success/fail, path, and details

### Resolution Diagnostics

`ResolvedProjectContext.diagnosticsSummary` produces a structured text block (app name, bundle ID, IDE family, resolved path, all attempts). The "Copy Last Resolution Info" menu item puts this on the pasteboard for bug reports.

## Resolution Cache

`~/Library/Application Support/Shellporter/resolution-cache.json`

### Why the cache exists

Live resolution strategies (AX APIs, title parsing, XML/JSON metadata files) are the preferred data source because they reflect current state, but they can all fail transiently:

- **AX attributes return nil during app transitions.** When an IDE is launching, switching windows, or entering/exiting full screen, the Accessibility API often reports no title or document for a brief period. The window exists, but its attributes aren't populated yet.
- **Window titles change when switching tabs.** VS Code and Cursor replace the workspace name in the title with the active file name. Once the title no longer contains a path or project name, title-based strategies lose their signal.
- **IDE metadata files aren't continuously updated.** JetBrains `recentProjects.xml` and VS Code `storage.json` are written on project open/close, not on every focus change. If the user opened a project but the file hasn't been flushed yet, parsing finds nothing.
- **Unknown IDEs have limited strategies.** Apps the resolver doesn't recognize (`IDEFamily.unknown`) only have AXDocument and title parsing. If neither works, there is no deeper metadata to fall back on -- without a cache, the resolution simply fails.

The cache turns every successful resolution into a durable fallback. Once Shellporter resolves a path for an app/window, the answer is remembered and can be returned instantly even if every live strategy fails on the next hotkey press. This also avoids re-parsing XML/JSON on every invocation when the user is working in the same project for hours.

### How it works

Every successful live resolution writes two cache entries (see [CachedResolution strategy](#cachedresolution) above for key format). The cache is the last strategy in every chain: live data is always tried first.

### Staleness protection

Cached paths are validated against the filesystem before use:
- `lookup()` checks `fileExists` before returning a hit -- a deleted/moved project won't produce a stale result.
- `load()` prunes all entries whose paths no longer exist on disk, keeping the cache file clean across app restarts.

### Mechanics

- LRU eviction at 200 entries (oldest `lastUsed` date evicted first)
- Supports transparent migration from a legacy `[String: String]` format to the current `[String: CacheEntry]` format with timestamps
- ISO 8601 date encoding, pretty-printed JSON for debuggability

## Build and Packaging

### Development

```bash
# Quick build + run
./Scripts/compile_and_run.sh

# With tests
./Scripts/compile_and_run.sh --test

# Universal binary
./Scripts/compile_and_run.sh --release-universal
```

`compile_and_run.sh`:
1. Kills any running Shellporter instances
2. Optionally runs `swift test`
3. Detects a stable signing identity ("Shellporter Development") or falls back to ad-hoc
4. Calls `package_app.sh release`
5. Launches the app and verifies it stays running

### App Bundle Assembly (`package_app.sh`)

1. `swift build -c release --arch <arch>` for each target architecture
2. Create `.app` bundle directory structure
3. Build `Icon.icns` from `Icon.icon` (Icon Composer format) if present
4. Generate `Info.plist` with version, build timestamp, git commit
5. Install binary (or `lipo` for universal)
6. Copy SwiftPM resource bundles to `Contents/Resources/`
7. Embed frameworks to `Contents/Frameworks/` if any
8. Strip extended attributes (`xattr -cr`) to prevent code signing failures
9. Generate empty entitlements file
10. Sign embedded frameworks first, then the app bundle
11. Verify signature with `codesign --verify`

### Version

Read from `version.env` at project root (if present), otherwise defaults to `0.1.0` build `1`.

### Signing Modes

| Mode | When | Identity |
|---|---|---|
| Named identity | `APP_IDENTITY` env var set or local dev cert found | The named certificate |
| Ad-hoc | No identity available | `-` (ad-hoc) |

### Notarization

`sign-and-notarize.sh` and `make_appcast.sh` exist as scaffolding for future distribution via Sparkle, but are not wired into CI.

## Quirks and Non-Obvious Details

1. **No `@main`**: The app uses manual `NSApplication` setup in `main.swift` because SwiftPM executable targets need an explicit entry point. `@main` with `App` protocol would require an Xcode project or workarounds.

2. **Carbon vs CGEvent**: Carbon `RegisterEventHotKey` is used instead of `CGEventTap` because event taps require "Input Monitoring" permission, while Carbon hotkeys work with just the process being alive. This is a deliberate trade-off: Carbon is legacy but requires fewer permissions for a menu bar utility.

3. **`Unmanaged.passUnretained` in HotKeyManager**: The event handler callback needs a pointer to the manager. `passUnretained` avoids a retain cycle but requires careful lifetime management. The `isInvalidated` flag is the safety net.

4. **Resolver queue vs main actor**: Non-cached strategies (file I/O heavy) run on a dedicated `DispatchQueue(qos: .userInitiated)` via `withCheckedContinuation`. Cache lookup stays on `@MainActor` because `ResolutionCacheStore` is `@MainActor`-isolated.

5. **JetBrains title-first strategy**: JetBrains IDEs put the project name in the window title more reliably than in AXDocument. AXDocument typically points to a single file, not the project root. So `TitlePaths` runs before `AXDocument` for JetBrains, opposite to VS Code.

6. **Xcode bundle normalization**: If the resolved path ends in `.xcodeproj` or `.xcworkspace`, the normalizer strips it to the parent directory. Without this, the terminal would open inside the Xcode bundle (which is a directory).

7. **iTerm2 session reuse**: Sessions are tagged with `shellporter:<standardized path>`. On re-invocation, Shellporter iterates all iTerm2 windows/tabs/sessions via AppleScript to find and select the matching session rather than creating a duplicate.

8. **Ghostty dual mode**: The `ghosttyOpenNewWindow` config controls whether Ghostty opens in the same instance (one dock icon, Kitty-style CLI) or spawns a new process (`open -na`, separate dock icon per window). The CLI path is experimental on macOS.

9. **Cache dual-key strategy**: Every successful resolution writes two cache entries: one keyed by window title (for precise recall) and one keyed by `|last` (for when the title changes or is empty). This means the cache can serve both "same project, same window" and "same app, any window" lookups.

10. **`xattr -cr` before signing**: macOS extended attributes (especially `._*` AppleDouble files created by file copies) break code signing. The packaging script strips all xattrs as a preventive measure.

11. **Logger `@unchecked Sendable`**: The logger uses a dispatch queue for serialization, which makes it concurrency-safe but not provably so to the compiler. `@unchecked Sendable` suppresses the warning.

12. **Config migration**: `ResolutionCacheStore` supports transparent migration from an older `[String: String]` cache format to the current `[String: CacheEntry]` format (which includes `lastUsed` dates). This prevents cache loss on upgrade.

## File Locations Summary

| What | Path |
|---|---|
| User config | `~/Library/Application Support/Shellporter/config.json` |
| Resolution cache | `~/Library/Application Support/Shellporter/resolution-cache.json` |
| App log | `~/Library/Logs/Shellporter/app.log` |
| Log backup | `~/Library/Logs/Shellporter/app.1.log` |
| JetBrains recents | `~/Library/Application Support/JetBrains/*/options/recentProjects.xml` |
| Android Studio recents | `~/Library/Application Support/Google/*/options/recentProjects.xml` |
| VS Code recents | `~/Library/Application Support/Code/User/globalStorage/storage.json` |
| Cursor recents | `~/Library/Application Support/Cursor/User/globalStorage/storage.json` |
