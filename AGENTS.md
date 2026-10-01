# AGENTS.md — RIME for iOS

Read this file before modifying the project. It is the authoritative architecture and contributor guide; the README stays concise.

## Identity and layout

Display name: **RIME for iOS**. Project/product: `RIMEForiOS`. Keyboard target: `RIMEKeyboard`. Hostless Swift Testing target: `RIMECoreTests`.

```
App/                         RIMEApp, SetupView, assets, App.entitlements
KeyboardExtension/           KeyboardInputController, Keyboard.entitlements
Packages/
  KeyboardModels/            Candidate, KeyAction, KeyboardLayout, panel and toast states
  RimeEngine/                librime bridge, RimeContext, RimePaths, bounded engine logs
  RimeSync/                  WebDAV transport, credential storage and file orchestration
  KeyboardUI/                SwiftUI panels, input model, geometry and JSON layouts
Tests/
  Input/                     Shift, routing, real librime and host marked text
  Layout/                    Row/grid geometry and theme contrast
  Sync/                      Paths/XML, credentials, failures and cancellation
  Diagnostics/               Bounded writes, UTF-8 tails and session ownership
  Rendering/                 Panel intrinsic sizes
Frameworks/                  Committed binary xcframeworks
Resources/SharedSupport/     Bundled RIME sources and precompiled build/*.bin
scripts/                     Optional engine/data rebuilding
screenshots/                 Keyboard appearance
project.yml                  XcodeGen source of truth
RIMEForiOS.xcodeproj/         Generated project and shared schemes
README.md                    Installation and privacy
REVIEW.md                    Latest review and validation
THIRD-PARTY-NOTICES.md        Bundled component licenses
docs/                       Upstream comparison, tests and change history
```

Bundle IDs: `art.anjing.rimeios`, `art.anjing.rimeios.keyboard`; App Group: `group.art.anjing.rimeios`. These identify a new installation. Old private containers are inaccessible to the new app. Existing users must sync the old keyboard first, then configure and sync the new keyboard, using a distinct device installation ID if necessary. No old-identifier migration layer is retained.

## Build, test and package

Minimum iOS 26, iPhone only. Xcode 27 / Swift 6.4 compiler, Swift 6 language mode; SwiftPM tools 6.4. Edit `project.yml`, then regenerate:

```sh
xcodegen generate --project .
xcodebuild test -project RIMEForiOS.xcodeproj -scheme RIMEForiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -derivedDataPath build/Debug CODE_SIGNING_ALLOWED=NO ARCHS=arm64
xcodebuild -project RIMEForiOS.xcodeproj -scheme RIMEForiOS -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/Release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
./scripts/package-ipa.sh
```

Binary simulator slices are arm64. Swift Testing results follow an initial XCTest report of zero tests. For development App Group access, use valid signing and `ENTITLEMENTS_ALLOWED=YES`; unsigned/self-signed installations normally use private containers.

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` are the sole version source. Both plists reference them. The SharedSupport copy phase removes its destination first and declares output paths; otherwise incremental builds nest directories or fail script sandboxing. Release CI uses the `xcode-27` runner and explicitly selects Xcode 27.0; `macos-latest` can still ship an older Swift compiler. Tag pushes trigger `.github/workflows/release.yml`; do not publish or push without authorization.

## Dependency boundaries

```
RIMEForiOS embeds RIMEKeyboard
RIMEKeyboard → KeyboardUI → RimeSync → RimeEngine → KeyboardModels
                         → RimeEngine
                         → KeyboardModels
```

The main app only displays setup status and version; it neither links KeyboardUI nor starts librime. Backend/network details stay in RimeSync; RimeEngine remains independent of WebDAV. Keep names tied to responsibilities rather than the product brand. Comments explain constraints and reasons, not obvious code or abandoned implementations.

State ownership:

- `RimeContext`: process engine, candidates, preedit and one-shot commit. Internal mutable state is ObservationIgnored and protected by NSRecursiveLock; UI publication runs on the main thread.
- `InputState`: controller-local host state and current panel.
- `KeyboardSyncState.shared`: process-wide maintenance gate and transient result.
- `SyncSettingsModel`: credential draft and connectivity testing. Its separate KeyboardInputModel never changes host language or writes draft text to the host.
- `KeyboardInputModel`: layout, language and Shift. Cached rows only depend on these low-frequency values; candidate/preedit observation stays in child views.

## Engine and data invariants

- Initialize data_size on RimeTraits, RimeContext and RimeCommit. Zero values silently disable optional fields/context results.
- Setup happens once per process; a second glog initialization can crash. Initialize in the background, create/publish the session on the main thread, and serialize all API access under the recursive lock.
- Read get_commit exactly once and retain it until pollCommit consumes it. Never infer a commit merely from process_key returning true.
- RimeEngineC explicitly retains Lua and octagram registration objects. Static linking alone can discard them. levers must be registered by deployer_initialize for user dictionary synchronization.
- Runtime full deployment is absent. Read bundled precompiled data; initialization and session creation are allowed. Keyboard extension memory limits vary by device/OS; do not treat a historical ~77 MiB observation as a universal guarantee.
- Select luna_pinyin, with the first available schema as fallback. There is no runtime schema picker.
- App Group user data is `Rime/`; private data is `Application Support/RIMEForiOS/Rime/`. Credentials are stored under the corresponding group/private support directory. Main app and extension private containers are separate.
- Never unlink LevelDB LOCK files. Kernel lock lifetime protects the existing inode.
- Maintenance runs on one serial queue, including deferred session cleanup. Owner tokens prevent an old controller from destroying a replacement controller's session. Recreate only after checking native composition, literal composition and pending commit under the lock.

Bundled data is managed upstream, not hand-edited. Enhanced files track qvshuo/luna-pinyin-enhanced `6bd91c9` (2026-09-27); Japanese files track gkovacs/rime-japanese `4c1e651`. Preset pinyin/schema/dictionary files track rime/rime-luna-pinyin `56b934b`; essay/symbols come from librime's minimal data. default.yaml only changes schema_list to existing luna_pinyin/luna_pinyin_simp and page_size to 9. The enhanced custom patch also references Japanese. Desktop frontend custom files remain verbatim and inert on iOS. OpenCC data comes from ver.1.1.9; lm_sc.gram is upstream's committed grammar. List patches require @N or /+/ /= operators.

Reference Squirrel is the latest stable **1.1.2**, commit `876adeb`; its librime pin is **1.16.0**, `a251145d`. The build clone uses the same pin. Update binaries/data only deliberately with a stable release and validate both platforms. Latest frontend code does not imply a need to upgrade librime.

Optional scripts default to `../librime`; use RIME_ROOT for an isolated clone at the commits in Frameworks/versions.json. build-librime.sh rejects mismatched source pins. verify-dependencies.sh --binaries checks committed slices without upstream sources. build-librime.sh enables merged plugins, iOS-compatible Lua and disables cross-compiled tools. Preserve OpenCC's BUILD_OPENCC_DATA/TOOLS guards when updating its sources. build-prebuilt-data.sh deploys a source-only staging copy and replaces SharedSupport/build only after validating output; failed deployment preserves old data. Do not regenerate dictionary assets for a naming-only change. OpenCC remains 1.1.9; both slices were rebuilt with the release dependency baseline. SHARE_INSTALL_PREFIX=SharedSupport keeps future fallback paths independent of the machine.

## Input and appearance

- Manual single/double Shift begins literal composition on the next character, including numbers/fullwidth punctuation. Letters, digits and symbols stay in one candidate until Space, Return or candidate selection commits once. Space confirms without appending a space; without composition it inserts a literal space. English automatic initial uppercase does not start literal composition. Backspace removes a complete Unicode character.
- MarkedTextWriter clears marked text, unmarks, then inserts one combined result. Bare unmark can commit the last letter; multiple proxy insertions can reorder a composition and following symbols in some hosts.
- Backspace with no preedit goes directly to the proxy. Do not add extra context re-reads to the repeat path. Double-space punctuation only follows two literal spaces within 0.35 s; candidate commits and keyboard activation reset it.
- Default requests Chinese; asciiCapable requests English. Other host types fall back to Chinese. Number/symbol pages remain manual layout choices. Return uses the host label without preedit, otherwise ⏎; highlight only when host text exists without preedit.
- SwiftUI colorScheme follows the host. No controller heuristic or pinned override style. Solid keycaps and an opaque preview bubble; dark key overlays assume a #2B2B2B system backdrop. Theme blend tests check this assumption.
- Host document identity changes discard old composition before processing new input; read the public documentIdentifier through Objective-C because UIKit can temporarily return nil. Hidden controllers reject input and stop log polling while retaining credential drafts. Background context snapshots carry a publication revision and cannot overwrite newer snapshots.
- Input height is 266 pt, sync/log/export 480 pt, inline editing 580 pt. UIInputView.allowsSelfSizing plus hosting intrinsicContentSize drives system sizing. Mount hosting in viewWillAppear to avoid a loading layout shift. Log export keeps the log page height.
- Key height 45, row gap 11, horizontal padding 7. RowLayoutMath keeps geometry pure: fixed function keys, elastic space, return-label borrowing, aligned z/s and m/k. Widths/gaps determine actual frames; don't replace them with arbitrary weights.
- Candidate scroll views hide scroll edge blur. Collapsed candidates use natural widths and LazyHStack; expanded candidates use a lazy grid and a stable snapshot. The initial native page has 9 candidates; expansion fetches up to 77. First-row alignment uses the actual selected/unselected cell height. No candidate comments are rendered.
- All menu buttons align to q and offer only the other two panels. Credential editing stays in a vertical title/value list with one Done button, a visible password and active-row Paste/Clear. Server, username and password carry red required markers; path and installation ID use defaults when empty. Avoid native text fields that summon another keyboard inside the extension.

## Synchronization and diagnostics

Credentials require HTTPS without embedded auth/query/fragment, safe relative paths and a one-component device ID. Defaults: Rime_Sync and iPhone. Save tests connectivity before atomically persisting JSON with mode 0600, iOS file protection and backup exclusion. This is system-protected storage, not application-level encryption.

Manual sync uses a process gate, unique staging directory and at most two parallel device downloads. Listing/download failure aborts before applying files. Only *.userdb.txt/custom_phrase.txt are transferred; foreign phrases overwrite deterministically in sorted device order. Blocking engine maintenance merges dictionaries, restores installation.yaml and recreates the session before input resumes. Upload/read failures are reported. Timeout cancels network work but waits for noninterruptible maintenance, so completion can exceed the deadline. Always clean staging. No background sync, local mirror or forced deploy.

Engine logs: Logs/engine.log. Keyboard logs: Logs/Keyboard/keyboard.log. BoundedLogFile serializes writes; each has one current and one previous file at 256 KiB each, including oversized legacy truncation. Native logging starts at warning and avoids independent unbounded glog files. Never record keystrokes/passwords. PID/session markers indicate incomplete cleanup, not proof of a crash.

The log view reads the latest 8 KiB per source once per second in a view-scoped task and stops when absent or the controller is hidden. Only changed tails are published. No manual refresh/clear APIs. Export snapshots four files (roughly 1 MiB), then presents a native UIKit activity popover at the log page height, without an extra navigation wrapper or custom Close button. Sharing does not resize the keyboard container. Keyboard extensions cannot present outside their system-owned region; confirmationDialog/text selection menus can invoke unavailable extension features. Deletion confirmation stays inline.

## Verification and scope

See docs/testing.md for core coverage and docs/input-method-comparison.md for the current upstream evaluation. Validate geometry, input commits, sync failures/cancellation and bounded logging; do not multiply tests of trivial aliases, literal UI text or cosmetic timing. Liquid Glass needs a running UIKit host for visual checks, not ImageRenderer. Do not claim simulator observations are device memory measurements or that mocked transport tests establish real WebDAV interoperability.

README edits correct facts or remove clutter; no expanded marketing, gesture tables or usage sections. Source is MIT; bundled binaries/data retain their licenses in THIRD-PARTY-NOTICES.md. Evaluating GPL upstream code does not authorize copying it into MIT source.
