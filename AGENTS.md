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
  Sync/                            # backend-agnostic WebDAV sync (WebDAVClient / WebDAVKeychainStore / WebDAVSync)
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
  CODE_SIGNING_ALLOWED=NO
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
Quill ─┬→ RimeEngine (→ binary xcframeworks)
       ├→ Models
       └→ Sync ─→ RimeEngine      (WebDAV sync; app & keyboard both link it)

QuillKeyboard ─┬→ RimeEngine
               ├→ Models
               ├→ KeyboardUI ─┬→ RimeEngine
               │               └→ Models
               └→ Sync ─→ RimeEngine
```

The main **app does NOT depend on KeyboardUI** (the settings icon uses system colors instead).

> `RimeContext` is split across `RimeContext.swift` (declaration + internal state + notification callback) and `RimeContext+{Lifecycle,Input,Directories,Logging}.swift` extension files.

## Architecture

### State is split by domain

- `RimeContext` (`@Observable`, `RimeEngine`) holds **engine state only**: `candidates`, `preedit`, `highlightedCandidateIndex`, `commitText`.
- `InputState` (`@MainActor`, `KeyboardUI`, **owned by `InputController`**) holds **host/sync UI state**: `hasInputText`, `toast`.

Never pass `hasInputText` or `preedit` as `KeyboardView` init params — replacing `UIHostingController.rootView` with a same-typed view preserves `@State`, so init values are ignored on later rebuilds. Scope the reads instead (see Return key below).
- **No retained context refs in `KeyboardViewModel`** — `consume(_:rimeContext:)` takes the context explicitly per call (default `nil`, tests pass nothing). Do not reintroduce weak vars on the model: `@State` persists the first instance across rootView replacements, so stored refs silently go stale.

### RimeContext essentials

- **`RimeTraits.data_size` must be set** to `sizeof(RimeTraits)` or optional fields (`log_dir`, …) are ignored.
- **`RimeContext` / `RimeCommit` are initialized with `RIME_STRUCT(Type, var)`** so `data_size` is nonzero; otherwise `RimeGetContext`/`RimeGetCommit` return `False` and the keyboard shows no preedit/candidates even though keys are "handled".
- **Commit text must be captured immediately**: `RimeGetCommit` returns the commit only once per composition; `refreshContext()` consumes it into internal storage. Read it via `pollCommit()` only.
- **`setup()` runs once per process** (`isSetup` flag + lock). Calling `InitGoogleLogging()` twice crashes inside glog.
- Session is **lazily created on the keypress thread** (`createSessionIfNeeded()`) — never create/use a session across threads. `start()` pre-creates one so the first keypress is cheap.
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

- The space key is **not** repeatable. Tap inserts a space; double-tap within 0.35 s converts to `。` (zh) / `.` (en). **Double-tap conversion only applies when both taps land as literal spaces (no RIME preedit)** — during a composition the space commits the candidate and the tracker is **reset** (`InputController.resetDoubleSpaceState()`), so a quick second tap is a plain space: double-tap during preedit = 选词 + 空格 (`你好 `), never `。`. **Long-press 3 s triggers the manual WebDAV sync** (`Theme.spaceSyncHoldDuration`; `Key.spaceKeyBody` runs a 0.05 s-step repeating `Timer`). After a 0.5 s preview delay (`Theme.spaceSyncPreviewDelay`) the hold writes progress into `InputState.syncHoldProgress`, which shows a top-center hint capsule (mini ring + 「继续按住同步」，same visual language as the toast); at full the capsule hands over to the sync toast and fires `action(.startSync)`; releasing before 3 s is a normal space. A RIME preedit aborts it (`startManualSync()` guards `preedit.isEmpty`).
- Sync feedback = transient top-center **toast** (`SyncToastView`, piped by `InputState.toast` of type `SyncToast` in `Models`): `started` persists until the sync finishes (`SyncToast` carries no duration), then the controller swaps in `同步完成` / `同步失败，请检查设置` and dismisses after 2.5 s / 4.0 s (`InputController.scheduleToastDismissal`). The hold-hint capsule and the toast share one position and one visual language (capsule, `keyBackground` fill + `floatingShadow()`, mutually exclusive via `SyncToastOverlay.phase`), `allowsHitTesting(false)`, floats at keyboard top center.
- **While the toast is visible all keys are swallowed**: `KeyboardView.handleKey` starts with `guard inputState.toast == nil else { return }` (`.startSync` passes because the toast is nil before it's set).
- Sync is bounded by a **60 s timeout** (`WebDAVSync.syncWithTimeout(.seconds(60))`); on timeout it reports failure (`false`). The timeout **races** the sync and never cancels it — the loser keeps running in the background (a 2026-08-23 incident showed "files uploaded but 同步失败" when a slow WebDAV endpoint blew past 15 s; measured: Koofr primary mount ~1.5 s per 1.1 MB GET, Koofr's OneDrive-backed mount 3-5× slower). 60 s was chosen to cover the slow mount; if an endpoint can't finish in time, use a faster one. The `recreateSession()` call itself is owned by `InputController.startManualSync()` and runs whenever `preedit.isEmpty` **regardless of sync result** — a failed/timeout sync may still have applied foreign `custom_phrase.txt` (step 3.5), which needs a session reload to take effect.
- **No-App-Group is the supported baseline, not a defect**: the app is designed around self-signed installs (user uses Feather); the main app and keyboard are expected to run with independent sandboxes, user data, and logs. Each process logs an `AppGroup shared/per-app` marker at startup so you know where its log lands; keyboard-side sync logs land in the extension's private `Documents/Logs` and never appear in the main app's 导出日志 — that is normal, do not "fix" it or warn about it in the UI. Accordingly there is **no「允许完全访问」status row or warning**: Full Access only gates the extension's own networking (sync), the main app has no channel to observe it in per-app mode (the old shared-defaults flag was removed as dead code), and an ungranted state surfaces naturally as a failed sync whose toast says 检查设置.

### Shift & language

- **English starts uppercase-once.** Switching to `.english` (via `.asciiCapable` keyboard type or the language toggle) sets `shiftState = .uppercaseOnce`; the first letter produces uppercase then reverts to lowercase. Space/backspace do **not** consume it; switching to numbers/symbols **does**.
- 单击临时大写; double-tap within 0.35 s locks caps; locked-tap unlocks (ShiftTap state machine, unit-tested).
- Tapping 中/英 flips `inputLanguage` and writes `ascii_mode` back to RIME (`setAsciiMode`) after the key returns; commits pending composition first.

### Symbols page auto-return

`KeyboardViewModel.autoReturnSymbols` holds sentence-ending chars (（ ） @ “ ” 。 ， 、 ？ ！ 【 】 ｛ ｝ # % ^ * + = _ \ | ｜ 《 》 & ·) — tapping one inserts the char and returns to the letter page (iOS quick-type behavior). Other symbol keys stay on the page.

### Keyboard types

Only `.default` and `.asciiCapable` are honored (fcitx5-ios ignores `UIKeyboardType`; iOS itself substitutes the system keyboard for number/URL/etc.). `.default` → Chinese mode (`ascii_mode=false`); `.asciiCapable` → English (`ascii_mode=true`); everything else falls back to `.default`. No numeric layout pages; the pure-number JSONs and `.numeric` cases were removed. Manual number/symbol pages (`numbers-zh/en`, `symbols-zh/en`) remain via the "123" / "#+=" keys. `InputController` observes `keyboardType`/`returnKeyType` in `textDidChange`/`viewWillAppear` and rebuilds the root only on change.

## Settings UI conventions

- `SettingsView` is a `NavigationStack` + `List` (internally a `Form` with `.formStyle(.grouped)`, functionally equivalent) with `.navigationTitle("Quill 输入法")`, `.navigationBarTitleDisplayMode(.large)` (home page = system large title, no custom icon).
- **Buttons need an explicit non-`.automatic` `.buttonStyle` (`.borderless`, `.plain`, or `.borderedProminent`)** — on iOS 26 the List row's gesture swallows single taps on `.automatic` buttons (they only fire on long press). The List has **no** tap-to-dismiss gesture; keyboard dismissal relies on `.scrollDismissesKeyboard(.immediately)` + the keyboard-toolbar 完成 button.
- The WebDAV settings are **one 同步 section**: 服务器地址/用户名/密码/同步目录/安装 ID each get a footnote label above via `LabelledField`, then 保存/测试连接; the footer shows the 长按空格 3 秒 hint. 删除凭据 sits in its **own destructive Section** below (keychain survives uninstall, so deletion must be explicit) with its `confirmationDialog` **attached to the destructive Button itself** — iOS 26 anchors the dialog to whatever view carries the modifier, so a Form-level attachment floats it to the top of the screen while a button-level one keeps it next to 删除凭据. Input fields use the `clearableField` modifier (gray X, `.tint(.secondary)`, shown only when focused & non-empty); the info `info.circle` is `.tint(.primary)` (a `.foregroundStyle` on the image is overridden by the button tint).
- 保存/测试连接 are `.disabled` when `allCredentialsEmpty` (the 3 credential fields 服务器地址/用户名/密码 all empty; 同步目录 and 安装 ID both have defaults and don't count).
- The 同步 section header and the 同步目录/安装 ID field titles each carry an `info.circle` 弹窗说明; **all popups share the single `syncAlert` alert state**.
- `最近同步于 …` was removed along with its keychain timestamp (`saveLastSyncDate`/`loadLastSyncDate`) and the Darwin completion notification — do not reintroduce without a cross-process channel rationale.

## Sync: WebDAV (Koofr) — keyboard is the single sync authority

No App Group / iCloud needed for sync; the app and keyboard share credentials via a **shared Keychain** (`keychain-access-groups: $(AppIdentifierPrefix)art.anjing.quill.shared`, both target entitlements) → `WebDAVKeychainStore`.

Flow (`WebDAVSync.sync()`, Squirrel semantics):

1. **In-flight guard**: a process-wide `Mutex` marks a sync in progress. A concurrent trigger (including a zombie sync still finishing after the 60 s timeout lost the race) is skipped and returns `false`. Never run two syncs in parallel — they would wipe/read/write the same staging dir and user dict.
2. Wipe the temp staging dir (`tmp/RimeSyncStage`).
3. `PROPFIND` the sync root on the WebDAV root — default `Rime_Sync`, editable via the settings 同步目录 field (`WebDAVSync.syncRootPath` reads it from saved credentials). If it (or this device's subdir) is missing, `MKCOL` it first — the first sync bootstraps from an empty server; without the parent `MKCOL` a missing root returns 409 and fails the upload.
4. Download every device subdir's `luna_pinyin_extended.userdb.txt` and `custom_phrase.txt` into staging (only these two files are ever synced — `WebDAVSync.relevantFile`).
5. Copy `custom_phrase.txt` from foreign device dirs into the user dir (librime only merges `*.userdb.txt`; the `.txt` must be applied manually so StableDb reads it on the next session).
6. `RimeContext.setStagingDirectory(stagingDir:)` (engine is backend-agnostic; called by `Sync`) rewrites `installation.yaml` `sync_dir` to the staging dir.
7. `syncUserData()` (librime `RimeSyncUserData`) exports this device's userdb to `staging/<installationID>/` (default `Quill`, editable via 安装 ID) and merges all device dirs; **it requires a staging override** (no local fallback) and always runs inside `defer { clearStagingDirectory() }`.
8. Upload `staging/<installationID>/` back to `<root>/<installationID>/`.
9. Done — no completion notification, no last-sync timestamp (both removed: the only cross-process channel is the keychain, and the timestamp feature wasn't worth a keychain entry).

There is **no persistent local `Rime_sync/` mirror** — the staging dir is wiped each sync. The keyboard extension needs Full Access + `com.apple.security.network.client` to reach Koofr over HTTPS. No folder picker: the sync root is fixed at `<WebDAV root>/Rime_Sync/` (no bookmarks, no security-scoped URLs).

### Session reload after sync — no full redeploy

librime reads `custom_phrase.txt` (`db_class: stabledb` → `StableDb` reads the `.txt` at runtime), `*.custom.yaml` (merged by the Customizer on config load), and userdb only **when a RIME session/engine is created**. The extension may keep a cached session, so `InputController.startManualSync()` (aborted when a RIME preedit exists) runs sync then calls `RimeContext.recreateSession()` — destroy + immediate recreate — **only when `preedit.isEmpty`**. Destroying mid-composition wipes the live composition (marked preedit stays but RIME's session is gone → the next backspace removes all marked text; keystrokes before a reset are lost; backspace gets off-by-one). The recreate is dispatched through `WebDAVSync.runAfterSync` (the sync's serial queue), never on the main thread — a timed-out zombie sync may still hold the engine lock running `syncUserData`, and calling `recreateSession()` from `MainActor` would block the keyboard until that lock frees. A full `RimeDeploy`/`startMaintenance` is never needed and is banned by the Jetsam limit.

### levers must be loaded for sync

`RimeInitialize` only loads `kDefaultModules` (core/dict/gears), so the deployer tasks behind `RimeSyncUserData` (`installation_update`/`backup_config_files`/`user_dict_sync`) are **not registered** and it returns `false` (「同步失败」). `setupOnce()` therefore calls `rimeAPI.deployer_initialize!(&traits)` right after `initialize!` to load `kDeployerModules` (levers) — module loading is idempotent.

## Logs & logging

- `RimeContext.redirectStderrToLogFile()` (`fopen("a")` + `dup2(fileno(file), STDERR_FILENO)`, fcitx5-ios pattern) runs at the top of `start()` so RIME/glog output lands in `Logs/quill.log`. `pruneGlogFiles` trims stale glog artifacts.
- Logs are **not shown in the app UI**; the settings page keeps only an 导出日志 `ShareLink` on `exportLogURL()`.
- Log location (`Paths.logDirectory`): with an App Group both processes write to the **same** `group.art.anjing.quill/Logs/quill.log` — the main app's 导出日志 export therefore also contains keyboard lines. Without an App Group (self-signed) each falls back to its own `Documents/Logs/quill.log`.

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
- **Never touch a session from another thread**; `createSessionIfNeeded()` runs on the keypress thread.
- **Never unlink LevelDB LOCK files**: locks are released by the kernel when a process exits; deleting a lock file can let another process lock a new inode while the database is still in use.
- **`reduce_english_filter` runs but is a no-op with the current data (investigated, kept)**: it only scans the first `idx` candidates and English short words never rank high here — for input `rug`, Chinese candidates (quality ≈ 1.87 = `exp(normalized_weight)` + `initial_quality` 1.2 + length term) beat melt_eng's `rug` (quality = `initial_quality` 1.1 ≈ rank #44), outside the scan window. The rime-ice doc behavior assumes English ranks #1. Net effect: short English words are always at the bottom anyway; the config is harmless. Verified with a macOS-host librime repro against the same prebuilt data.

## Testing

```sh
xcodebuild test -project Quill.xcodeproj -scheme Quill -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' CODE_SIGNING_ALLOWED=NO
```

- Scheme test target = `QuillKeyboardUITests` (swift-testing; the hostless bundle links `KeyboardUI` + `RimeEngine` + `Models` + the binary xcframeworks).
- Cover `RowLayoutMath`, `CandidateGridLayout`, `ShiftTap`, `LayoutAction`, `SyncToast` messaging, and `ThemeFillColor` (incl. the dark blend assertions). Layout/grid math must live as **pure functions** in the library so the test bundle and the app share one implementation.
- Note: `All tests` may first appear to run from XCTest (`Executed 0 tests`) before the swift-testing suites are listed.
- Sync toast *timing* is deliberately not unit-tested (it lives in the keyboard controller); only the message mapping is.

## Conventions for agents

- **README style (user-curated — subtract, never fatten)**: the user manually trimmed the README (removed marketing copy like「开箱即用」and the gesture/操作 table). When touching the README, only correct facts or remove; **do not** reintroduce feature showcases, usage/gesture tables, or a「使用」section. Installation wording stays as-is: unsigned ipa + self-sign via AltStore/Feather. Any interaction numbers quoted in docs (e.g. 长按空格 3 秒) must track `Theme.spaceSyncHoldDuration`.
- **Do not** reintroduce removed behaviors: deploy path, schema switcher, numeric keyboard types, iCloud/local `Rime_sync` mirror, HTTP log upload, `activeSyncExportDirectory`, `importAllDeviceData`, `setOption` (only `setAsciiMode` exists), the `.return` dead branch (a long-gone `KeyAction.return` path that produced no proxy output — the current `.return` case is alive and emits a newline / commits), or an auto-sync scheduler. The settings UI offers only WebDAV credential storage + connectivity test + credential deletion (keychain survives uninstall, so an explicit delete entry is required).
- **Do not** hand-edit qvshuo-sourced RIME data files.
- Keep `RimeContext` backend-agnostic: URL/session/WebDAV specifics live in `Sync`, field/IME UI state in `InputState` (KeyboardUI), engine state in `RimeContext` (RimeEngine).
- Keep layout/grid math pure and unit-tested; avoid hard-coded widths.
- Keyboard code runs inside the extension's tight memory budget: no full deploys, no heavy caches, no reading every candidate on the keyboard root's body.
- No code comments unless they record a non-obvious why (the AGENTS gotchas above are the home for architecture-level explanations).

## License

App source: MIT (see `LICENSE`). Bundled binaries and RIME data carry their own licenses — see `THIRD-PARTY-NOTICES.md`.