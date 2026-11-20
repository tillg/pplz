# Change 01: rename pplz to cardXchange

Status: approved 2026-11-20. Phases 2 and 3 are done by Claude; the phases of the user follow.

Marks, as in `docs/SPEC.md`: **[S]** stated by the user, **[A]** assumption with a recommendation, **[?]** open.

## 1. Goal

The app, the command line, the Apple identifiers, the GitHub repository and the local folder get the new name.
The user's data stays complete: the store, the photos, the links in Contacts and the history blocks in the contact notes.

- **[S]** The new name is cardxchange.
- **[S]** The short name is `cx`.
- **[S]** The website is `cardxchange.me`.
- **[S]** The change includes the GitHub repository and the local folder.
- **[S]** One deliverable is a step-by-step guide for the work at Apple.

## 2. Documents

| File | Content |
|---|---|
| `README.md` | this file: decisions, phases, acceptance checks |
| `01-names.md` | the map from each old name to the new name, with the files |
| `02-data-migration.md` | what happens to data that is on disk, in Contacts and in iCloud |
| `03-apple-guide.md` | the steps that the user does at Apple and on the devices |
| `04-repository-and-folder.md` | the GitHub repository, the local folder, the tools around them |

`01-names.md` §1 is the one table of new identifiers. The other documents refer to it. If a decision changes, change that table first.

## 3. Decisions

The user confirmed D1, D2, D3, D5, D6, D11 and D13 on 2026-11-20, and the other items with the recommended answers on the same day.
Items D1 to D3 are permanent at Apple: an identifier cannot be renamed after it is registered.

| # | Decision | Answer or recommendation | Why | Mark |
|---|---|---|---|---|
| D1 | Bundle ID: new or keep `com.tillg.pplz` | New: `me.cardxchange.app` | A change is not possible after a release. The reverse of the website domain is the usual form. Cost of "new": a new request for the notes entitlement (the wait starts again), new permission prompts, a new app container on iOS (data comes back through iCloud). "Keep" has none of these costs, but the old name stays in the identifier for all time. | [S] 2026-11-20 |
| D2 | iCloud container: new or keep | New: `iCloud.me.cardxchange.app` | Sync uses only the CloudKit Development environment. Apple documents no way to delete a container, so the old one stays as an unused entry. A container name is not tied to the bundle ID; "keep" is possible with a new bundle ID. | [S] 2026-11-20 |
| D3 | App Group: new or keep | New, same pattern as today | The inbox holds items for a short time only. | [S] 2026-11-20 |
| D4 | Written form of the name | `cardXchange` where people read it, `cardxchange` in identifiers, paths and URLs | The logo files already use `cardXchange`. | [S] 2026-11-20 |
| D5 | Where `cx` applies | The command line tool `cx`, the URL scheme `cx://`, environment variables `CX_*`, module and type prefix `CX` | `cx` is short to type. No `cx` command is on the PATH of the development Mac. Known points: a different app can register the same two-letter scheme, and iOS then opens one of the two. Apple's CallKit uses the prefix `CX` and has a type `CXError`; pplz does not import CallKit. | [S] 2026-11-20 |
| D6 | Where the long name applies | Label of the link row in Contacts, markers of the note block, store folder and store file | These names are visible to the user in Contacts and in Finder. | [S] 2026-11-20 |
| D7 | Old link rows and old note blocks | The new build reads the old and the new form and writes only the new form | Without this, each contact gets a second link and a second block. See `02-data-migration.md`. | [S] 2026-11-20 |
| D8 | Old names in the CLI | No alias. `cx` stops with an error when a variable `PPLZ_STORE` or `PPLZ_NO_CONTACTS` is set. The JSON key `isPplzOnly` becomes `isCXOnly`. | The owner is the only user. An old variable that is silently ignored makes `cx` use the real store or the real address book. | [S] 2026-11-20 |
| D9 | Store migration | One script, run one time. It copies each record into a new store with the hidden command `cx copy-store`. | There is one real store. A store that synced with the old container cannot sync with the new one (M2). See `02-data-migration.md` §2. | [S] 2026-11-20 |
| D10 | The owner is the only person with real data | Yes | The repository is public, but no release exists. | [S] 2026-11-20 |
| D11 | Pending request for the notes entitlement | Send a new request for the new bundle ID that refers to the old request | The request names the old bundle ID. See `03-apple-guide.md` A6. | [S] 2026-11-20 |
| D12 | `docs/DECISIONS.md` | Keep the old entries as written. Add one line at the top that pplz is the old name. | The file is a record of past runs. | [S] 2026-11-20 |
| D13 | Who owns an old link row | A URL row with the label `pplz` and a value `pplz://person/<uuid>` is always a row that pplz wrote. The new build replaces it without a journal entry as proof. | The journal cannot prove it: it is different on each device, and the journal on iOS goes away with the old app. No person writes such a row by hand. | [S] 2026-11-20 |

D13 is an exception to the rule "pplz owns only what it wrote and recorded". The user agreed to it.

The user agreed to the change of expected values in existing tests (`02-data-migration.md` §3.5) on 2026-11-20.

Not part of this change:

- The content of the website `cardxchange.me`, and universal links (`https://cardxchange.me/...`) in place of the custom URL scheme.
- A release in the App Store.
- New artwork. The logo, the wordmark and the app icon are already new.

## 4. Size of the change

The name occurs about 900 times in about 80 files (case ignored): `Sources/` 295, `Tests/` 167, `docs/SPEC.md` 138, `App/` 94, `README.md` 84, `docs/DECISIONS.md` 46, `CLAUDE.md` 29, `scripts/` 20, `Package.swift` 16.

Most of these are a mechanical rename. Three groups are not mechanical:

1. Names in data that exists: the link rows and note blocks in Contacts, the journal, the store folder. See `02-data-migration.md`.
2. Names registered at Apple. See `03-apple-guide.md`.
3. Names outside the repository: GitHub, the local folder, the symlink of the command. See `04-repository-and-folder.md`.

The new identifiers do not follow from a replacement of `pplz` with `cardxchange`: `com.tillg.pplz` becomes `me.cardxchange.app`. Take each identifier from `01-names.md` §1.

## 5. Phases

Each phase ends with a check. Do not start a phase before the check of the phase before it passes.

| # | Phase | Who | Check |
|---|---|---|---|
| 0 | Confirm the decisions in §3 | user | the table in `01-names.md` §1 is final |
| 1 | Register the new identifiers at Apple and send the entitlement request (`03-apple-guide.md` part A) | user | the identifiers are visible in the developer account |
| 2 | Contacts: read the old and the new form, write the new form (`02-data-migration.md` §3, §4). Test first, with the old module names. | Claude | `swift test` passes, with the new tests |
| 3 | Rename (`01-names.md`), the new default paths and the guards (`02-data-migration.md` §2.4), the migration script (§2.3) | Claude | `swift build` and `swift test` pass. The fixture test passes. The search in §6 finds only allowed lines. |
| 4 | Build the apps with the new identifiers (`03-apple-guide.md` part B). Build the release binary and link `cx` on the PATH. Remove `PPLZ_*` variables from the shell profile. Try M2 with a copy of the store. | user and Claude | the Mac app and the iOS app start with a temporary store. `cx --help` works. The result of M2 is written down; it does not stop the phase. |
| 5 | Mac: last sync with the old apps, remove the old apps and the old command, migrate the store, sync contacts (`02-data-migration.md` §10 steps 1 to 8) | user | the counts are the same before and after. One contact has one link row and one history block. |
| 6 | iPhone and iPad: install the new app, give the permissions, sync (`02-data-migration.md` §10 steps 9 to 11, `03-apple-guide.md` C2) | user | the data is on each device |
| 7 | GitHub repository and local folder (`04-repository-and-folder.md`) | user | `git fetch` works in the new folder. `cx --help` works from the new folder. |
| 8 | Clean up at Apple and on the Mac (`03-apple-guide.md` part D) | user | the old identifiers are removed where Apple permits it |

Rules for the order:

- Phase 3 changes no behaviour except the names in `01-names.md`, the guards and the script.
- Between phase 4 and phase 5, start the new app and `cx` only with a temporary store (`-store`, `--store`). The guards in `02-data-migration.md` §2.4 stop a start without it.
- From phase 5 on, no old build runs on a device. An old build does not know the new link and adds an old link again.

## 6. Acceptance checks

1. `swift build`, `swift build -c release` and `swift test` pass.
2. `git grep -i pplz` finds lines only in these places:
   - the code that reads the old link, the old markers and the old URL scheme, and the tests for it
   - `CFBundleURLSchemes` in `App/project.yml`
   - the guards for the old variables and the old store folder
   - the migration script
   - the sentences in `docs/SPEC.md`, `CLAUDE.md` and `README.md` that say what the old name was and what is still read
   - `docs/DECISIONS.md` and this folder
   - the binary fixture `before-photos.store`
3. `SchemaMigrationTests` passes without a change to the test or to the fixture. No `@Model` class has a new name.
4. `cx --store <temp file> --no-contacts people` works. `cx --help` shows no old name.
5. With `PPLZ_STORE` or `PPLZ_NO_CONTACTS` set, `cx` stops with an error that names the new variable.
6. The Mac app starts as `cardXchange` with `-store <temp file> -noContacts YES`. The iOS app passes one `scripts/ui.sh` run in the simulator.
7. After the migration of the real store: the same number of persons, events, tags, connections and photos as before, and each photo opens.
8. After the first sync of contacts with the new build, for a contact that had an old link and an old block:
   - one link row, with the label `cardxchange` and the same person ID as before
   - no row with the label `pplz`
   - one history block, with the new markers
   - the text around the block is unchanged
9. A `pplz://person/<id>` URL still opens the person in the new app.
10. A screenshot shared from an iPhone and from the Mac arrives in the app.
11. iCloud sync: a new event on the Mac appears on the iPhone.
12. A fresh subagent has compared this folder with the result (`two-axis-review`).
