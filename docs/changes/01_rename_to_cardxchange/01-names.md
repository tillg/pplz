# Names: old to new

The names follow the decisions in `README.md` §3. The identifiers at Apple (D1 to D3) and the use of `cx` (D5, D6) are confirmed by the user.

## 1. The table of identifiers

This is the one source for the new names. `<TeamID>` is the team ID from `App/Local.xcconfig`; it is not written into the repository.

| Thing | Old | New |
|---|---|---|
| Name for people (display name, window title, docs) | `pplz` | `cardXchange` |
| Website | none | `https://cardxchange.me` |
| Command | `pplz` | `cx` |
| Bundle ID, Mac app and iOS app (the two share one ID) | `com.tillg.pplz` | `me.cardxchange.app` |
| Bundle ID, iOS share extension | `com.tillg.pplz.share` | `me.cardxchange.app.share` |
| Bundle ID, Mac share extension | `com.tillg.pplz.sharemac` | `me.cardxchange.app.sharemac` |
| Bundle ID, UI tests | `com.tillg.pplz.uitests` | `me.cardxchange.app.uitests` |
| App Group, iOS | `group.com.tillg.pplz` | `group.me.cardxchange.app` |
| App Group, Mac | `<TeamID>.com.tillg.pplz` | `<TeamID>.me.cardxchange.app` |
| iCloud container | `iCloud.com.tillg.pplz` | `iCloud.me.cardxchange.app` |
| URL scheme | `pplz` | `cx`; `pplz` stays registered |
| `CFBundleURLName` | `com.tillg.pplz` | `me.cardxchange.app` |
| Link in a contact | `pplz://person/<uuid>` | `cx://person/<uuid>` |
| Label of the link row in a contact | `pplz` | `cardxchange` |
| Capture URL (share extension to app) | `pplz://capture` | `cx://capture` |
| Markers of the note block | `── pplz ──`, `── /pplz ──` | `── cardxchange ──`, `── /cardxchange ──` |
| Default store | `~/Library/Application Support/pplz/pplz.store` | `~/Library/Application Support/cardxchange/cardxchange.store` |
| Geocoding budget | `…/pplz/geocache.json` | `…/cardxchange/geocache.json` |
| Environment variables | `PPLZ_STORE`, `PPLZ_NO_CONTACTS` | `CX_STORE`, `CX_NO_CONTACTS` |
| Environment variables of the UI tests | `PPLZ_APP_ARGS`, `PPLZ_UI_SCRIPT` | `CX_APP_ARGS`, `CX_UI_SCRIPT` |
| Info.plist key for the Mac App Group | `PplzAppGroup` | `CXAppGroup` |
| Installed Mac app | `/Applications/pplz.app` | `/Applications/cardXchange.app` |
| Simulator used by `scripts/ui.sh` | `pplz iPhone` | `cardxchange iPhone` |
| GitHub repository | `tillg/pplz` | `tillg/cardxchange` |
| Local folder | `~/git/pplz` | `~/git/cardxchange` |

Names that do not change:

- The eight `@Model` classes: `Person`, `Event`, `Tag`, `Connection`, `PersonPhoto`, `Setting`, `FollowUp`, `LocatedAddress`. A new class name breaks the store and the CloudKit record types.
- `contact-writes.jsonl`, `geocache.json`, the `Inbox` folder of the App Group.
- The launch arguments (`-store`, `-noContacts`, `-noSync`, `-forceSync`, `-select`, `-show`, `-mode`, `-capture`).
- The setting key `showHistoryInContacts`.
- The asset names `AppIcon` and `AccentColor`, and the files in `assets/`.
- `Tests/…/Fixtures/before-photos.store`. The file is not opened and not changed.

## 2. Swift package

`Package.swift`:

| Old | New |
|---|---|
| package `pplz` | `cardxchange` |
| library and target `PplzCore` | `CXCore` |
| library and target `PplzUI` | `CXUI` |
| executable and target `pplz` | `cx` |
| test target `PplzCoreTests` | `CXCoreTests` |
| test target `PplzUITests` | `CXUITests` |

Folders and files (use `git mv`, so that the history stays):

| Old | New |
|---|---|
| `Sources/PplzCore/` | `Sources/CXCore/` |
| `Sources/PplzCore/PplzStore.swift` | `Sources/CXCore/CXStore.swift` |
| `Sources/PplzUI/` | `Sources/CXUI/` |
| `Sources/pplz/Pplz.swift` | `Sources/cx/CX.swift` |
| `Tests/PplzCoreTests/` | `Tests/CXCoreTests/` |
| `Tests/PplzUITests/` | `Tests/CXUITests/` |
| `App/Mac/PplzMacApp.swift` | `App/Mac/CardXchangeMacApp.swift` |
| `App/iOS/PplziOSApp.swift` | `App/iOS/CardXchangeiOSApp.swift` |

Imports: about 40 lines `import PplzCore` or `@testable import PplzCore`, 3 lines for `PplzUI`.

## 3. Swift symbols

| Old | New | Uses |
|---|---|---|
| `struct Pplz` (the root command), `commandName: "pplz"` | `struct CX`, `commandName: "cx"` | 4 |
| `PplzStore` | `CXStore` | 50 in 16 files |
| `PplzError` | `CXError` | 68 in 20 files |
| `isPplzOnly` (also the JSON key) | `isCXOnly` | 18 in 9 files |
| `pplzPersonID` | `cxPersonID` | 12 in 5 files |
| `pplzAdded(_:field:)` | `cxAdded(_:field:)` | 10 in 4 files |
| `isPplzLink(_:)` | `isCXLink(_:)` | 4 in 2 files |
| `pplzGroup`, `pplzFields` (private) | `cxGroup`, `cxFields` | 2 each |
| `PplzMacApp`, `PplziOSApp` | `CardXchangeMacApp`, `CardXchangeiOSApp` | 1 each |
| test functions with `Pplz` in the name (7) | the same name with `CX`, for example `createsCXOnlyPerson` | |

Temporary names change too (`pplz-script-`, `pplz-picture-`, and the `pplz-…` prefixes in the tests) to `cx-…`. They hold no data.

## 4. Text that the user reads

Replace `pplz` with `cardXchange` in text for people, and with `cx` where the text names the command.

- CLI help and messages in `Sources/pplz/Pplz.swift` (about 50 lines). Examples: ``see `cx locate` ``, `(cardXchange only)`, `cx log "Anna Example" …`. The help of `--store` names `$CX_STORE` and the new path.
- Messages of the contact sync, for example `Contacts: added the cardXchange link`.
- Messages in `Sources/PplzCore/FacePhoto.swift` and `Sources/PplzCore/SystemContacts.swift`.
- UI strings in `Sources/PplzUI`: `PeopleView.swift` (title, alert title, badge, help), `PersonCardView.swift`, `PersonEditor.swift`, `CaptureSheet.swift`, `LogEventSheet.swift`, `PhotosGroup.swift`, `PeopleModel.swift`.
- `App/Mac/PplzMacApp.swift`: `Window("cardXchange", id: "main")`.
- Share extensions: `Sending to cardXchange…`, `Opening cardXchange…`, `Saved. Open cardXchange to continue.`, and the text for an item that is not accepted.
- The error text in `SystemCalendar.swift`.
- There is no string catalog. All strings are English literals in the code.

The term "pplz-only person" becomes "cardXchange-only person". This phrase and `isCXOnly` are candidates for a glossary term in a later grilling session; this change keeps the meaning and changes only the name.

## 5. `App/project.yml` and the generated files

- `name: cardxchange`. The generated project is `App/cardxchange.xcodeproj`.
- Package reference `cardxchange` (`path: ..`); the dependency is `package: cardxchange`, `product: CXUI`.
- `PRODUCT_BUNDLE_IDENTIFIER`: the four values from §1.
- `PRODUCT_NAME: cardXchange` for the two apps. `CFBundleDisplayName: cardXchange` in all four Info.plists.
- Targets: `cardxchangeMac`, `cardxchangeiOS`, `cardxchangeShare`, `cardxchangeShareMac`, `cardxchangeUITests`. `PRODUCT_NAME` of the last three is the target name. `TEST_TARGET_NAME: cardxchangeiOS`.
- Schemes: `cardxchangeMac`, `cardxchangeiOS`.
- Entitlement files: `Mac/cardxchange.entitlements`, `iOS/cardxchange.entitlements`, `Share/cardxchangeShare.entitlements`, `ShareMac/cardxchangeShareMac.entitlements`.
- Entitlement values: the iCloud container and the App Groups from §1.
- Info.plist key `CXAppGroup` in the Mac app and the Mac share extension. `CaptureInbox.swift` reads the same key and has the new iOS group as its constant.
- `CFBundleURLTypes`: `CFBundleURLName: me.cardxchange.app`, `CFBundleURLSchemes: [cx, pplz]`, in the Mac app and the iOS app.
- The usage descriptions (four keys, six lines): replace each `pplz` in the texts with `cardXchange`. The text for Contacts is also the text in the notes entitlement request; keep the two the same.
- The comments that name pplz.

Constants in the code that must be the same string as a value in `project.yml`:

- `PplzStore.iCloudContainer` (`Sources/PplzCore/PplzStore.swift:11`): `iCloud.me.cardxchange.app`
- `CaptureInbox.appGroup` (`Sources/PplzCore/CaptureInbox.swift:6`): `group.me.cardxchange.app`

A replacement of `pplz` with `cardxchange` gives a wrong value for these two and for each bundle ID. Take the values from §1.

`.gitignore` names generated files literally. Change `App/pplz.xcodeproj/` and the entitlement lines. Delete the old generated files from the working folder after the first `xcodegen generate`.

## 6. Scripts

- `scripts/build-app.sh`: the project file, the two schemes, `tell application id "me.cardxchange.app" to quit`, the three paths `…/cardXchange.app`, `/Applications/cardXchange.app`, the comments.
- The script does not touch `/Applications/pplz.app`. The user deletes the old app in phase 5 (`02-data-migration.md` §10 step 4).
- New: `scripts/migrate-from-pplz.sh` (`02-data-migration.md` §2.3).
- `scripts/ui.sh`: `TEST_RUNNER_CX_APP_ARGS`, `TEST_RUNNER_CX_UI_SCRIPT`, the project, the scheme, the default simulator name.
- `App/UITests/ScriptRunnerTests.swift`: `CX_APP_ARGS`, `CX_UI_SCRIPT`.
- `scripts/claude.sh`: no change.

## 7. Documents

| File | Change |
|---|---|
| `README.md` | title, all commands (`cx …`), the symlink line, the store path, `CX_STORE`, the link and the markers in the diagram, the build paths. Add the website. |
| `docs/SPEC.md` | all 138 places. §2.1, §3.2, §3.3, §6, §8.1, §8.3 name identifiers from §1. §8.4 gets the new bundle ID and the state of the request. Add one **[S]** line with the date for the rename. |
| `CLAUDE.md` | the product sentence, the commands, the paths, the module names, the type names, the skills table text. Add: the old name is pplz, and old data forms are still read. |
| `docs/DECISIONS.md` | one line at the top; the old entries stay (D12) |
| `.claude/skills/README.md` | line 18 |
| `docs/agents/domain.md` | no occurrence today; check again |
| `App/Local.xcconfig.example` | check the comment text |

`docs/GLOSSARY.md` does not exist. This change does not create it.
