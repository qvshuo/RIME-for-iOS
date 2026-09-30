# AGENTS.md — Quill (iOS RIME input method)

This file is the **single authoritative technical document** for the repo. The
README is intentionally minimal; every architectural fact, convention, and
pitfall below is meant to be read by both humans and AI agents before touching
the code. Read the whole thing before making changes.

## What this repo is

**Quill (Quill 输入法)** — a minimal iOS RIME input method.

- Xcode project `Quill.xcodeproj` is **generated from `project.yml`** by `xcodegen`. Edit `project.yml`, then run `xcodegen generate --project .`.
- Two app targets: `Quill` (main settings app) and `QuillKeyboard` (keyboard extension, `UIInputViewController`).
- `librime` is vendored as **prebuilt xcframeworks** in `Frameworks/` (built by `scripts/build-librime.sh`); the binaries are committed, so a plain clone builds without the RIME toolchain.
- RIME data lives in `Resources/SharedSupport/` with **prebuilt** `build/*.bin` — the keyboard works with **no deploy at runtime**.
- Minimum iOS **26.0**, iPhone only (`TARGETED_DEVICE_FAMILY = 1`).
- Keyboard UI is 100% self-built SwiftUI (KeyboardKit was removed). No closed-source UI dependency.

## Repository layout

```
App/                               # main app: QuillApp.swift (entry), SettingsView.swift, icons, entitlements
QuillKeyboard/                     # keyboard extension: InputController.swift (thin), entitlements
QuillKeyboardUITests/              # unit tests (swift-testing), hostless bundle
Packages/
  RimeEngine/                      # Swift-direct librime bridge + RimeContext (@Observable)
  Models/                          # shared domain models (Candidate / KeyAction / KeyboardLayout / SyncToast)
  KeyboardUI/                      # self-built SwiftUI keyboard + JSON layouts
  Sync/                            # backend-agnostic WebDAV sync (WebDAVClient / WebDAVCredentialStore / WebDAVSyncOperation)
Frameworks/                        # 9 prebuilt xcframeworks : librime libglog libleveldb libmarisa libopencc libyaml-cpp boost_{filesystem,regex,atomic}
Resources/SharedSupport/           # RIME data (schemas, dicts, opencc, lua, lm_sc.gram) + generated build/*.bin
scripts/build-librime.sh           # cross-compile librime + deps → Frameworks/*.xcframework
scripts/build-prebuilt-data.sh     # macOS-native librime generates Resources/SharedSupport/build/*.bin
project.yml                        # xcodegen source of truth (re-generate Quill.xcodeproj after edits)
README.md                          # intentionally minimal (style rules below)
AGENTS.md                          # you are here
THIRD-PARTY-NOTICES.md             # licenses of bundled binaries & RIME data
```

## Build & run

```sh
xcodegen generate --project .      # create Quill.xcodeproj from project.yml
```

Unsigned simulator build:

```sh
xcodebuild -project Quill.xcodeproj -scheme Quill -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64
```

Simulator build that embeds App Group / keyboard entitlements:

```sh
xcodebuild -project Quill.xcodeproj -scheme Quill -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM=<TEAM_ID> ENTITLEMENTS_ALLOWED=YES
```

`ENTITLEMENTS_ALLOWED=YES` is required so the App Group entitlement is embedded and `containerURL(forSecurityApplicationGroupIdentifier:)` succeeds in the Simulator.

Unsigned device ipa (self-sign on iPhone):

```sh
xcodebuild -project Quill.xcodeproj -scheme Quill -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/dd build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
mkdir -p /tmp/ipa_stage/Payload
cp -R build/dd/Build/Products/Release-iphoneos/Quill.app /tmp/ipa_stage/Payload/
cd /tmp/ipa_stage && zip -r -y -X Quill-unsigned.ipa Payload
```

- The `Copy SharedSupport` build phase (`rm -rf` + `cp -R Resources/SharedSupport` → `.app/SharedSupport`) declares its destination in `outputPaths`, so the script sandbox (default `YES`) allows the write. Do not revert to a bare `cp -R` onto the existing directory — it nests `SharedSupport/SharedSupport` on every incremental build.
- **Releases are automated**: pushing a `v*` tag (`.github/workflows/release.yml`, macOS runner + `actions/checkout@v7`) builds the same unsigned device ipa and publishes a GitHub Release with auto-generated notes via `gh release create`. Release steps: bump `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `project.yml` (the single version source — both plists reference `$(MARKETING_VERSION)`), commit, then `git tag vX.Y.Z && git push origin vX.Y.Z`. Note the runner image names Xcode bundles with a `.app` suffix (`Xcode_26.6.0.app`) — don't append another one when selecting.
- Rebuilding librime from source is optional (Frameworks are committed): `scripts/build-librime.sh` expects a `librime/` clone (containing its `deps/`) at the repo's **parent directory** (`$ROOT/../librime`).
- Enabling the keyboard in the Simulator requires **Settings › General › Keyboard** (editing the `com.apple.keyboard.preferences` plist alone is not enough). Grant Full Access so the extension can read the App Group container.

## Package graph (dependency direction)

```
Quill → embeds QuillKeyboard
QuillKeyboard → KeyboardUI → Sync → RimeEngine → Models
              → RimeEngine
              → Models
```

The main app only displays keyboard setup status and version. It does not initialize librime or link KeyboardUI.

## Architecture

### State is split by domain

- `RimeContext`: engine state (candidates, preedit, highlighted candidate, one-shot commit). Internal engine fields are ObservationIgnored and protected by the engine lock.
- `InputState`: per-controller host text state and panel mode.
- `KeyboardSyncState.shared`: process-wide sync gate and toast. A replacement controller sees an existing sync immediately.
- `SyncSettingsModel`: keyboard-local credential draft, selected field and connection-test state. The model persists across panel switches; it loads saved credentials once.
- `KeyboardViewModel`: input layout/language/shift. Credential editing uses a separate instance so it does not change the host input language.

Credential fields are buttons, not native TextField/SecureField controls. Selecting one replaces the candidate bar with an editor toolbar and routes the existing key grid into the draft. Those keys never reach UITextDocumentProxy or librime. The toolbar supports explicit paste, clear, password visibility and Done; Return moves to the next field. Passwords and keystrokes are never logged.

Keep candidates/preedit reads in child views so typing does not invalidate the keyboard root. Pass the engine explicitly to `KeyboardViewModel.consume`; do not retain a context in the model.

### RimeContext essentials

- **`RimeTraits.data_size` must be initialized** with `rimeStructInit` (`sizeof(RimeTraits) - sizeof(data_size)`) or optional fields (`log_dir`, …) are ignored.
- **`RimeContext` / `RimeCommit` are initialized with `RIME_STRUCT(Type, var)`** so `data_size` is nonzero; otherwise `RimeGetContext`/`RimeGetCommit` return `False` and the keyboard shows no preedit/candidates even though keys are "handled".
- **Commit text must be captured immediately**: `RimeGetCommit` returns the commit only once per composition; `refreshContext()` consumes it into internal storage. Read it via `pollCommit()` only.
- **`setup()` runs once per process** (`isSetup` flag + lock). Calling `InitGoogleLogging()` twice crashes inside glog.
- Session is **lazily created under the engine lock** (`createSessionIfNeeded()`). `start()` pre-creates one on the main thread so the first keypress is cheap; synchronization and reload run on the serial maintenance queue.
- After creating a session the bridge selects **`luna_pinyin`** (fallback: first available schema) and sets `ascii_mode=false`. `RimeContext` no longer persists a preferred schema; there is **no schema switcher UI**.
- All RIME access is serialized with `NSRecursiveLock`.

### Data model — no deploy path

`deploy()` / `startMaintenance` is **removed**. `start()` is just `setup → initialize` (a full deploy exceeds the keyboard extension's ~77MB memory limit and gets it killed by Jetsam — the keyboard appears then exits ~2s later).

- Both targets read prebuilt data from `SharedSupport/build/` (`prebuilt_data_dir`, default `shared_data_dir/build`).
- Writable user data goes to **App Group/Rime** when available; without an App Group (e.g. self-signed ad-hoc) the app and the keyboard each fall back to their own private `Application Support/Quill/Rime` —**these are NOT synced** with each other (no cross-process mechanism without an App Group).
- librime resolves `user/build` (staging) → `prebuilt` (Bundle), so candidates work without deploying.

## UI: theme & key caps

- **Key caps are pure solid color; press = single pressed tone.** `Theme.keyBackground` applies a single `RoundedRectangle` fill — no shadow, stroke, or gradient. The confirm key is a **single constant** `#007AFF` (fcitx5-ios `highlightBackground`), shared across light/dark.
- Press feedback is a **uniform pressed fill** via `Theme.fillColor(style:isPressed:)` — every key style (`normal`/`special`/`confirm`) presses to the single `Theme.pressedKeyBackground`: light `#F0F1F3` (dims, near-white), dark ≈ `#6B6B6B` (brightens). The confirm key's foreground swaps to `keyForeground` on press so the label stays visible on the light pressed tone. The press fill animates with an explicit `0.05 s` ease-out (`Key.swift`), overriding SwiftUI's system default button press animation (~0.2 s) that felt laggy.
- **Preview bubble background is the opaque `Theme.previewBubbleBackground`** (light `#FFFFFF`, dark `#585858` = the dark `keyBackground` mixed over the `#2B2B2B` backdrop). It must **not** reuse `keyBackground` — a semi-transparent bubble floating over key seams reads as "transparent" in dark mode.
- **Theme follows SwiftUI `@Environment(\.colorScheme)`** (fcitx5-ios's simplest approach). `KeyboardView` picks `Theme.dark`/`Theme.light` itself; the environment follows the **host app's** appearance, so a light app typing under a dark system stays light (fcitx5-ios behavior). `InputController` never resolves dark/light itself and rebuilds the root view only for `keyboardType`/`returnKeyType` changes. Do not reintroduce a `resolvedIsDark()` host heuristic (`keyboardAppearance` → trait → `UIScreen.main`) or any `overrideUserInterfaceStyle` pin — it was removed on purpose (below).
- **The keyboard follows the host app's appearance directly, no pin**: a transient `overrideUserInterfaceStyle = UIScreen.main.traitCollection.userInterfaceStyle` (system) pin was added to hide a one-frame flash on appearance toggles, but it forces the **system** theme over a per-app override and is only cleared when the controller's own trait *changes* — so a persistently light app under a dark system stays dark forever. Removed to match fcitx5-ios; expect a possible one-frame flash when the host style differs from the system's.
- **Light theme is opaque** (`keyBackground` and `specialKeyBackground` both `#FFFFFF`; light function keys stay white). **Dark theme is fcitx5-ios-style semi-transparent overlays** blended over the system dark backdrop (`#2B2B2B`). The alphas are **derived, not hand-picked**: `Theme.overlay(base:target:)` solves the alpha that makes a neutral-grey base (white or `#858585`) hit the target opaque grey over `darkBackdrop` — key →`#585858`, special →`#3A3A3A`, pressed →`#6B6B6B`, candidate selection →`#5A5A5A`. `darkBackdrop` is the single assumption point; if iOS ever changes the keyboard backdrop color, re-tune it and re-run the blend assertions in `ThemeTests.swift`.
- **The keyboard panel background is transparent** — `Color.black.opacity(0.001).ignoresSafeArea()` in `KeyboardView` — the system keyboard container draws the background. The hosting controller's view is transparent too.
- **Keyboard slides up smoothly via `viewWillAppear` hosting**: the `UIHostingController` is created in `viewDidLoad` but added as a child + constraints activated in `viewWillAppear` (mounting in `viewDidLoad` causes a huge layout shift). Height = intrinsic size `.frame(height: theme.totalHeight)` — no `preferredContentSize`, no manual safe-area math.

## UI: keyboard dimensions & key widths

### Dimensions are literal integers (no runtime scaling)

`keyHeight: 45`, `rowSpacing: 11`, `candidateBarHeight: 40`, top/bottom padding `8/5`, left/right padding `7` → `totalHeight` **266 pt**. The keyboard is bottom-anchored (system places the view bottom-flush), so `keyboardPadding.bottom` fixes the keys' bottom edge; changing `keyHeight`/`rowSpacing` shifts only the top.

### Key widths are a grid model, not weights (`RowLayoutMath`)

A global letter cell `L = (gridWidth − 9×6)/10` derives from the 10-key rows, then row composition decides:

1. **Bottom rows** (contain a space key): `123/ABC` and 中/英 are `fixed` 67.5 / 45 pt; the return key is `max(67.5, labelWidth)` and **steals from the space key** when the label is long (space floors at `2×keyHeight`).
2. **Letter row 3** (⇧/⌫): both square 45 pt; the 7 middle letters are `L`, flush left/right; the two gaps are `g = 1.5L − 36`, which makes **z align with s and m with k exactly**.
3. **Numbers/symbols row 3** (#+=/123 + ⌫ both fixed 45): middle keys flex-share the remainder.
4. **Pure-letter rows**: 10 keys flush at `L`; 9 keys centered with `(L+6)/2` side padding.
5. Anything else falls back to weight-based sharing.

`RowLayout` carries per-key `widths` and per-pair `gaps`; `KeyboardRowView` renders with `HStack(spacing: 0)` + `Spacer` frames so the ⇧/⌫ alignment gaps aren't doubled. `KeyDescriptor.fixedWidth` comes from the JSON `"fixed"` field and survives `localizedDescriptor`/`effectiveDescriptor` rebuilds.

### Candidate bar & expanded grid

- Collapsed: horizontal `ScrollView` + `LazyHStack` of **all** candidates, natural widths (never forced to fill the row); scrollable past the viewport. Right chevron in a fixed 34 pt column, above the fold of the scroll.
- Expanded: a **grid replaces the entire keyboard** (no residual collapsed bar, avoiding duplicated first-row candidates); background stays transparent. Line-breaking measures text widths (`CandidateGridLayout`, pure functions, unit-tested) — never scales fonts or stuffs cells.
- **Grid aligns with the collapsed bar**: horizontal padding = `theme.keyboardPadding.leading` (7 pt); the first row's **center** is pinned to `barHeight / 2` → top inset `barHeight / 2 − firstRowHeight / 2`, where `firstRowHeight` is the row 0 **actual** height — `candidateSelectionHeight` (34) when the highlighted candidate is in row 0, else `candidateCellHeight` (32). Do **not** compute from the fixed 32 pt cell — when candidate 0 is the highlighted pill the row is 34 pt and centering on 32 pt drops the first word ~1 pt.
- Selected candidate = pill (height 34 / h-padding 6 / corner radius 9) shared verbatim between bar and grid; unselected cells 32 pt tall with 10 pt h-padding. Chevrons use fixed grey `0x4D5650` (not `.secondary`).
- Tapping a candidate commits and auto-collapses; an empty composition also auto-collapses. Comments are not rendered; the bar keeps its fixed height even when empty.

## Input behavior

### Return key (dynamic label & primary highlight)

Always acts as a return key. With a RIME preedit: shows `⏎`, **no** highlight. Otherwise shows host-driven `returnKeyLabel` (go→前往, search→搜索, send→发送, next→下一步, done→完成, emergencyCall→紧急呼叫, …) and is blue when `inputState.hasInputText` and there is no preedit.

- The dynamic label/highlight lives in `KeyboardRowView` (private child of `KeyboardView`) in its own `body` — **only** rows containing a return key read `rimeContext.preedit`/`inputState.hasInputText` (short-circuited ternaries), so typing re-renders just the bottom row. `currentRows` is cached by (layout, language, shift) and never flows through that cache. `ReturnLabelWidth` memoizes label measurement per process.
- `InputController` maintains `hasInputText` in `textDidChange` (and on focus in `viewWillAppear`) via `UIKeyInput.hasText`, with a `documentContextBefore/After`+`selectedText` fallback (`hasText(in:)`) because some fields report an unreliable `hasText`; it also sets it `true` eagerly on committed-text insertion so the highlight updates before the next `textDidChange`.
- The candidate bar / expanded grid / key rows are separate private subviews so `candidates`/`highlightedCandidateIndex` reads stay out of the keyboard root's body.
- `UIReturnKeyType` is the Swift name (not `UIKeyboardReturnKeyType`).

### Backspace

Keep it simple: if `rimeContext.preedit` is empty → `textDocumentProxy.deleteBackward()` directly (no RIME round-trip); otherwise let RIME delete the composition, falling back to `deleteBackward()` only when RIME reports unhandled. **Do not** add proxy re-reads or preedit-change heuristics into the backspace path — that regresses rapid backspace deletion. `syncText()` clears marked text when the composition becomes empty via `setMarkedText("")` + `unmarkText()` (a bare `unmarkText()` would *finalize* the last marked letter, needing two backspaces). Commit paths never hit that branch.

### Space bar & manual sync trigger

- Space is a normal non-repeating key. Double tap within 0.35 seconds inserts `。` / `.` only after a literal space; committing a candidate resets the tracker. Showing the keyboard resets the tracker too.
- With no composition, the candidate bar menu opens Sync or Log; the same menu returns to the input keyboard. Candidate changes return to input without a polling task.
- Sync starts only from the Sync button, without preedit. No space hold timer or progress hint remains.
- Input is gated only while `KeyboardSyncState.isSyncing`. Result toasts dismiss after 2.5 seconds (success) or 4 seconds (failure) and do not block typing.
- No App Group is the supported self-sign baseline. Full Access gates extension networking; do not show an unreliable main-app permission status row.

### Shift & language

- **English starts uppercase-once.** Switching to `.english` (via `.asciiCapable` keyboard type or the language toggle) sets `shiftState = .uppercaseOnce`; the first letter produces uppercase then reverts to lowercase. Space/backspace do **not** consume it; switching to numbers/symbols **does**.
- 单击临时大写; double-tap within 0.35 s locks caps; locked-tap unlocks (ShiftTap state machine, unit-tested).
- Tapping 中/英 flips `inputLanguage` and writes `ascii_mode` back to RIME (`setAsciiMode`) after the key returns; commits pending composition first.

### Symbols page auto-return

`KeyboardViewModel.autoReturnSymbols` holds sentence-ending chars (（ ） @ “ ” 。 ， 、 ？ ！ 【 】 ｛ ｝ # % ^ * + = _ \ | ｜ 《 》 & ·) — tapping one inserts the char and returns to the letter page (iOS quick-type behavior). Other symbol keys stay on the page.

### Keyboard types

Only `.default` and `.asciiCapable` are honored (fcitx5-ios ignores `UIKeyboardType`; iOS itself substitutes the system keyboard for number/URL/etc.). `.default` → Chinese mode (`ascii_mode=false`); `.asciiCapable` → English (`ascii_mode=true`); everything else falls back to `.default`. No numeric layout pages; the pure-number JSONs and `.numeric` cases were removed. Manual number/symbol pages (`numbers-zh/en`, `symbols-zh/en`) remain via the "123" / "#+=" keys. `InputController` observes `keyboardType`/`returnKeyType` in `textDidChange`/`viewWillAppear` and rebuilds the root only on change.

## Settings and sync panels

The main app is a minimal Form with enablement status, a system settings link and version. Use explicit button styles in Form/List, since automatic style can consume taps on iOS 26.

The keyboard Sync panel offers server URL, username, password, sync directory and installation ID, plus Save, Delete and Sync. Save validates, tests connectivity, then writes an immutable snapshot; failure preserves both the previous saved configuration and the draft. Controls are disabled during testing/sync; deletion needs confirmation. Defaults are `Rime_Sync` and `Quill`. Multiple devices must use distinct installation IDs.

`WebDAVCredentialStore` uses JSON in App Group or private Application Support/Quill. It serializes file access, writes atomically with iOS complete-until-first-authentication protection, sets mode 0600, and excludes the file from backup. This is OS-protected file storage, not application-level encryption. Base64 is not used. Keychain entitlements and APIs are removed; existing Keychain credentials are not migrated, so upgrades require reconfiguration.

## Sync: WebDAV

`WebDAVSync` owns the atomic process-wide in-flight gate and a dedicated serial engine queue. `WebDAVSyncOperation` owns file orchestration, independent of the engine and credential store:

1. Snapshot and validate credentials once. Only HTTPS with no embedded credentials/query/fragment is allowed; relative paths cannot contain empty/dot segments, backslashes or control characters. Installation ID must be one directory component.
2. Create a unique staging directory, removed on all exits.
3. List foreign device directories; 404 at the root means a first sync. Download at most two devices concurrently, retaining only userdb and custom_phrase.txt. Any listing/download error aborts before applying files.
4. Atomically apply foreign custom_phrase.txt in sorted device order (existing overwrite semantics, deterministic result). librime performs the userdb merge.
5. On the engine queue, set staging and installation ID, run blocking maintenance, restore installation.yaml's normal sync directory, and recreate the session before resuming the caller. Session recreation checks the real composition and pending commit under the engine lock.
6. Create remote parent directories in order, then upload only the two relevant files. Any upload/read error fails the operation.

`syncWithTimeout` uses structured concurrency with a 60-second deadline. On timeout, cancel network work but await the noninterruptible engine step before releasing the UI gate. There are no detached zombie syncs. The exact return can exceed the deadline if librime is still completing its blocking maintenance. Controller destruction is queued behind engine maintenance and guarded by a session owner token, so an old controller cannot destroy a replacement controller’s session.

No periodic sync, local mirror, full deploy or runtime schema switcher. `deployer_initialize` still loads levers after initialize so user_dict_sync tasks are registered.

## Logs & diagnostics

- Engine stderr/glog: `Paths.logDirectory/quill.log`, rotated at process initialization above 1MiB. Startup prunes only named glog level files, never unrelated directories or diagnostics.
- Keyboard lifecycle/panel/sync events: `Logs/Keyboard/keyboard.log`, serialized writes, 1MiB rotation and one previous file. No signal or uncaught-exception handlers.
- A PID/session ownership marker records whether the previous process completed cleanup. Only log an unfinished previous session if its PID is gone; OS reclamation can cause this, so it is not a confirmed crash. An old controller cannot delete a newer controller's marker, and clearing logs leaves the marker intact.
- The Log panel shows the latest 8KB, with explicit refresh. Export creates a bounded snapshot of keyboard + engine current/previous logs, suitable for sharing. Clear truncates the active engine log inode so stderr continues writing to the visible file.

## RIME data conventions

- `Resources/SharedSupport/` mirrors **`github.com/qvshuo/luna-pinyin-enhanced`** (formerly `qvshuo/squirrel`; not rime-ice). The qvshuo-sourced files (everything except the preset files listed below and the generated `build/`) must track the upstream clone (currently master `7c47d6d`, synced 2026-08-19) and are **never hand-edited**. Its `japanese.*` files are synced verbatim from `gkovacs/rime-japanese` (master `4c1e651`).
- **Preset data sources are per-file**: `pinyin.yaml`, `luna_pinyin.schema.yaml`, `luna_pinyin.dict.yaml`, `luna_pinyin_simp.schema.yaml` track **`rime/rime-luna-pinyin`** (master `56b934b`); `essay.txt` and `symbols.yaml` are **librime's bundled `data/minimal` copies** — exactly what squirrel 1.1.2 ships through its librime 1.16.0 pin (do **not** "update" them to rime-essay/rime-prelude master); `default.yaml` is librime's `data/minimal/default.yaml` with two deliberate edits (below); `opencc/` is generated from **opencc `ver.1.1.9`** (16 `.ocd2` + 14 `.json`; older than 1.4.x so no `hk2sp`/`s2hkp`/`opencc_config.schema.json`); `lm_sc.gram` is **qvshuo's committed grammar**.
- **`default.yaml` must reference only existing schemas** (a missing schema fails `workspace_update` / deploy). It is librime `data/minimal/default.yaml` with exactly two edits: `schema_list` = `luna_pinyin` + `luna_pinyin_simp` (replaces `cangjie5`), and `menu.page_size` = 9 (vs 5). `default.custom.yaml` lists `luna_pinyin` + `japanese`; only `luna_pinyin` is ever selected by Quill.
- **Patching list items needs `@N` refs or `/+`/`/=` operators** — a bare `switches/options` key fails with `copy on write failed; incompatible node type` and breaks the schema build. `luna_pinyin.custom.yaml` therefore avoids `switches/options`.
- `luna_pinyin.custom.yaml` mounts `melt_eng` as a secondary English translator and `luna_pinyin_extended.dict.yaml` as the translator dictionary, plus `lua_filter@*reduce_english_filter` and the `lm_sc.gram` grammar. `melt_eng` needs the merged plugins build (below).
- Desktop-only custom files (`squirrel.custom.yaml`, `weasel.custom.yaml`, `ibus_rime.custom.yaml`) are inert on iOS and kept verbatim for parity.

### Version alignment — squirrel / librime

- **Both clones sit at released versions, never master** (tracking latest commits is deliberately avoided — unstable): the reference clone `$ROOT/../squirrel` (**`rime/squirrel`**) is at release tag **1.1.2** (`876adeb`, detached HEAD) with submodules at their 1.1.2 pins (librime `a251145d` = **1.16.0**, plum `4c28f11`, Sparkle `41847a5`), and the build clone `$ROOT/../librime` is pinned to that same `a251145d` (1.16.0).
- **Upgrades are manual and follow squirrel releases** (squirrel upgrades once → we upgrade once): on each rime/squirrel release, `git fetch origin tag <tag> && git checkout <tag>` in `../squirrel`, `git submodule update --init --recursive`, pin `$ROOT/../librime` to the librime version that release ships, then rebuild both `Frameworks/` and `SharedSupport/build/` (scripts below).
- librime's `deps/*` submodules keep their own pins; **opencc** is at librime 1.16.0's pin **`ver.1.1.9`** (`556ed224`), aligning with squirrel 1.1.2 (it was briefly at head `ver.1.4.0`; reverted by decision 2026-08-19). The opencc checkout carries a local patch — `BUILD_OPENCC_DATA`/`BUILD_OPENCC_TOOLS` CMake guards on `add_subdirectory(data)`/`add_subdirectory(tools)` — that must be **re-applied after any opencc source change** (e.g. `git checkout`), else the build scripts' `-DBUILD_OPENCC_DATA=OFF` is silently ignored and the iOS cross-compile tries to build data/tools.

## librime build (prebuilt Frameworks)

- **`BUILD_MERGED_PLUGINS=ON` is required** — the default `OFF` produces a `librime.a` without `levers` linked, so `RimeStartMaintenance`/`RimeDeploy` return `false` and no `.bin` files are generated. `scripts/build-librime.sh` sets it.
- `librime-lua` is patched to compile the in-tree Lua 5.4.8 with `LUA_USE_IOS` (`system()` is unavailable on iOS; without the guard `loslib.c` fails). This powers `lua_filter@*reduce_english_filter`.
- `librime-octagram` is built with `BUILD_TOOLS=OFF` so its `build_grammar` host tool isn't cross-compiled for iOS. This powers `lm_sc.gram`. (The aggregate `-DBUILD_TOOLS=OFF` propagates to the plugin: cmake `option()` never overrides an existing cache variable, so octagram's `add_subdirectory(tools)` is skipped in iOS builds — the macOS-native host build intentionally leaves it ON to generate `lm_sc.gram`.)
- `boost_system` is header-only since Boost 1.82 — no separate library.

### Prebuilt data regeneration

Run `scripts/build-prebuilt-data.sh` (macOS-native librime + `rime_deployer`) after changing schema/dictionary files to regenerate `Resources/SharedSupport/build/*.bin`. The script `rm -rf`s `SharedSupport/build/` **before** `rime_deployer --build` — it must not delete afterwards, or the incremental logic (which treats `shared_data_dir/build` as prebuilt and skips up-to-date artifacts) would wipe the skipped `.bin` files.

## Engine pitfalls (will the keyboard appear "broken")

- **glog double-setup crash**: `InitGoogleLogging()` allows one call per process. Keep the `isSetup` flag + lock guard.
- **Extension memory ceiling ~77MB**: full deploy gets the extension killed by Jetsam (keyboard appears then exits ~2s later) — the usual "keyboard闪退" root cause. Data must remain prebuilt.
- **`data_size` trinity**: `RimeTraits` / `RimeContext` / `RimeCommit` all need nonzero `data_size` or you get "keys handled but no preedit/candidates/commit".
- **Commit is one-shot**: consume through `pollCommit()`; a second `RimeGetContext`/`RimeGetCommit` call sees nothing.
- **Never access a session concurrently**: input uses the main thread, maintenance/reload uses its serial queue, and all engine operations hold the recursive engine lock.
- **Never unlink LevelDB LOCK files**: locks are released by the kernel when a process exits; deleting a lock file can let another process lock a new inode while the database is still in use.
- **`reduce_english_filter` runs but is a no-op with the current data (investigated, kept)**: it only scans the first `idx` candidates and English short words never rank high here — for input `rug`, Chinese candidates (quality ≈ 1.87 = `exp(normalized_weight)` + `initial_quality` 1.2 + length term) beat melt_eng's `rug` (quality = `initial_quality` 1.1 ≈ rank #44), outside the scan window. The rime-ice doc behavior assumes English ranks #1. Net effect: short English words are always at the bottom anyway; the config is harmless. Verified with a macOS-host librime repro against the same prebuilt data.

## Testing

```sh
xcodebuild test -project Quill.xcodeproj -scheme Quill -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' CODE_SIGNING_ALLOWED=NO ARCHS=arm64
```

- Scheme test target = `QuillKeyboardUITests` (swift-testing; the hostless bundle links `KeyboardUI` + `RimeEngine` + `Models` + the binary xcframeworks).
- Cover `RowLayoutMath`, `CandidateGridLayout`, `ShiftTap`, `LayoutAction`, `SyncToast` messaging, and `ThemeFillColor` (incl. the dark blend assertions). Layout/grid math must live as **pure functions** in the library so the test bundle and the app share one implementation.
- Note: `All tests` may first appear to run from XCTest (`Executed 0 tests`) before the swift-testing suites are listed.
- Regression suites cover WebDAV paths/XML, credential validation/storage, draft editing, failed saves, file orchestration failures/cleanup, log UTF-8 tails/rotation/session ownership, and deep/light panel rendering. Test orchestration through an injected transport/engine runner, without networking or deploying RIME.
- Toast timing lives in the process-wide sync state. Do not add wall-clock tests for cosmetic dismissal delays.

## Conventions for agents

- **README style (user-curated — subtract, never fatten)**: the user manually trimmed the README (removed marketing copy like「开箱即用」and the gesture/操作 table). When touching the README, only correct facts or remove; **do not** reintroduce feature showcases, usage/gesture tables, or a「使用」section. Installation wording stays as-is: unsigned ipa + self-sign via AltStore/Feather. Keep interaction descriptions aligned with the keyboard panels.
- **Do not** reintroduce removed behaviors: deploy path, schema switcher, numeric keyboard types, iCloud/local `Rime_sync` mirror, HTTP log upload, `activeSyncExportDirectory`, `importAllDeviceData`, `setOption` (only `setAsciiMode` exists), the `.return` dead branch (a long-gone `KeyAction.return` path that produced no proxy output — the current `.return` case is alive and emits a newline / commits), or an auto-sync scheduler. The keyboard owns WebDAV configuration, connectivity testing, credential deletion and manual sync.
- **Do not** hand-edit qvshuo-sourced RIME data files.
- Keep `RimeContext` backend-agnostic: URL/session/WebDAV specifics live in `Sync`, field/IME UI state in `InputState` (KeyboardUI), engine state in `RimeContext` (RimeEngine).
- Keep layout/grid math pure and unit-tested; avoid hard-coded widths.
- Keyboard code runs inside the extension's tight memory budget: no full deploys, no heavy caches, no reading every candidate on the keyboard root's body.
- No code comments unless they record a non-obvious why (the AGENTS gotchas above are the home for architecture-level explanations).

## License

App source: MIT (see `LICENSE`). Bundled binaries and RIME data carry their own licenses — see `THIRD-PARTY-NOTICES.md`.