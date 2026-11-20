# Data migration

The old name is written into data in five places. A search-and-replace in the code breaks each of them.

| Place | Old form | Risk if only the code changes |
|---|---|---|
| Store folder on the Mac | `~/Library/Application Support/pplz/` | the app starts with an empty store |
| Link row in each linked contact | label `pplz`, value `pplz://person/<uuid>` | the person is not matched; a second link is added |
| History block in the contact notes | `── pplz ──` … `── /pplz ──` | a second block is added; "off" does not remove the old block |
| Contact journal | entries with `"label":"pplz"` | none, if the rules in §3 and §5 are kept |
| iCloud container, App Group, app container on iOS | old identifiers | no data in the new ones |

All new names are in `01-names.md` §1. File and line references are to the code before the rename.

## 1. Rules for the work

- Do each step first on a copy, with `--store <temp file> --no-contacts` on the command itself.
- Export the address book before the first contact sync with the new build.
- Do not open the real store with a build that is between two phases.
- No test opens the address book. The logic for Contacts is tested through the pure planning functions.
- From phase 5 on, no old build exists on a device: not the old app, not the old `pplz` command. See §10.

## 2. Store folder on the Mac

### 2.1 What is in the folder

| Item | Old name | New name |
|---|---|---|
| Folder | `pplz/` | `cardxchange/` |
| Store, with its SQLite side files | `pplz.store`, `pplz.store-wal`, `pplz.store-shm` | a new `cardxchange.store` that receives a copy of each record (§2.5) |
| Photo data (external storage) | `.pplz_SUPPORT/` | the new store writes its own `.cardxchange_SUPPORT/` |
| CloudKit asset cache | `pplz_ckAssets/` | not copied; it is a cache |
| Contact journal | `contact-writes.jsonl` | the same name, new folder |
| Geocoding budget | `geocache.json`, `.lock`, `.broken` | `geocache.json` only, new folder |
| Backups made by hand | `backup-…/` | stay in the old folder |

Core Data derives the name of the photo folder and of the asset cache from the name of the store file. Thus the temporary copy of the old store keeps the name `pplz.store`, so that Core Data finds `.pplz_SUPPORT` next to it.

### 2.2 Open points

- **M1, [S] 2026-11-20: no test before the migration.** It is not proven that a store with photos opens correctly after the store file and `.pplz_SUPPORT` have new names. The user accepts this. The checks are the counts in §2.3 step 6 and the look at the photos in §10 step 7. The old folder stays complete as a backup.
- **M2, [S] 2026-11-20: best effort.** The store holds sync data for the old iCloud container. It is not proven that the new app uploads all records to the new container from this store. A failure does not stop the rename. Try it in phase 4: start the new Mac app with the migrated copy from M1 and `-store <copy> -forceSync YES -noContacts YES`. Then compare the record counts in CloudKit Console, or in the new iOS app in the simulator. After the test, reset the Development environment of the new container (**Reset Environment**), so that phase 5 starts with an empty container.
- Step 11 in §10 does the same check again on the real data.
- **Result of M1 and M2, 2026-11-20, with a copy of the real store.** The renamed store opened with the same counts, and the photo opened (M1 passes). M2 failed. The new app started with sync to `iCloud.me.cardxchange.app`, and Core Data deleted all local data of the store. The log said "CKIdentity record has changed" (reset reason 3). CloudKit gives each container its own user record ID, so a new container looks like a different iCloud account to Core Data. The renamed old store can therefore not be used with the new container.
- **[S] 2026-11-20: copy the records into a new store (the fallback).** The user chose this over keeping the old container. See §2.5. The new store has no sync data of the old container, so the first start of the app uploads all records.

### 2.3 Procedure (script `scripts/migrate-from-pplz.sh`, D9)

The script takes the old folder and the new folder as arguments. The defaults are the real folders.

1. Stop if the new **store file** exists. A new folder that holds only `geocache.json` is not a reason to stop: `cx locate` with a temporary store creates it.
2. Stop if the app, a `pplz` process or a `cx` process runs.
3. Stop if the old folder holds an item that the table in §2.1 does not name. Print the item.
4. Copy the three old store files and `.pplz_SUPPORT` into a temporary folder. Copy `contact-writes.jsonl` into the new folder. Copy `geocache.json` over a file that is possibly there. The script does not write to the old folder.
5. Copy each record from the temporary copy into a new store `cardxchange.store` (§2.5). The tool for this is `cx copy-store`.
6. Read eleven counts with `sqlite3`: persons, events, tags, connections, photos, follow-ups, settings, located addresses, participants, event tags and person tags. Read the counts of the temporary copy before step 5 opens it, and the counts of the new store after step 5. Stop with an error if they are different, and delete the new store files.
7. Rename the old folder to `pplz.migrated-<date>`. This folder is the backup. An old build that is still somewhere finds no store there and cannot write into old data.

Step 7 is the only change to old data, and one `mv` undoes it.

### 2.4 Code (phase 3)

- `CXStore.defaultURL`: the new path; `CX_STORE` in place of `PPLZ_STORE`.
- `Geocoding.swift`: `cardxchange/geocache.json`. `isDefaultPair` follows `defaultURL`.
- Guard 1: `cx` stops with an error if `PPLZ_STORE` or `PPLZ_NO_CONTACTS` is set (D8). The check does not depend on the new variables. Reason: an ignored `PPLZ_NO_CONTACTS=1` lets `cx` write to the real address book.
- Guard 2: if the new default store does not exist and the old folder `pplz/` exists, `cx` and the app stop with an error that names the migration script. They do not create an empty store next to data that is not migrated. The guard applies only to the default store, not to `--store` / `-store`.
- Tests first: one test for each guard, with the environment and the folder given as parameters (as `defaultURL(environment:)` does today).

### 2.5 Copy into a new store (decided 2026-11-20)

- `cx copy-store <old store> <new store>` opens the old store and a new store, both without iCloud. It copies every record of the eight model classes. The command is not shown in the help; only the script uses it.
- It stops if the new store exists. It opens the old store only through the temporary copy of step 4, because opening a store can change it.
- Each record keeps its ID (`uuid`) and every value, also the dates (`createdAt`) and the photo data. Relationships point to the copies: participants, tags, connections, photos and follow-ups. Settings and located addresses are copied by their keys.
- The ID matters most: the link in each contact holds the person ID (§3).
- The new store holds no sync data. When the new app starts it with iCloud, it uploads all records to the new container.
- **M2 repeated, 2026-11-20, with a copy of the real store: passes.** The copy kept all counts (21 persons, 1655 located addresses, 13 participants, 8 person tags). The app uploaded all 1682 records, and the local data stayed complete. A second, empty store with `-forceSync YES` received the same counts.
- CloudKit record names are made by each store, not taken from `uuid`. Records that a test uploaded would therefore come back as duplicates of the real records. **Reset the Development environment of the new container before phase 5**, and keep the new app closed on the iPhone and the iPad until then.
- Test first: a store with each kind of record and each relationship is copied, and the copy gives the same snapshots as the original.

## 3. Link row in Contacts (`PersonLink`)

### 3.1 How it works today

- `PersonLink` writes the label `pplz` and the value `pplz://person/<uuid>` (`PersonLink.swift:6-9`). `personID(from:)` accepts only the scheme `pplz` (`:13`).
- Each filter for the link goes through `PersonLink.personID`. The one other scheme check is in `PeopleModel.open(_:)` (`PeopleModel.swift:654`).
- `ContactsSync.linkPlan` reads only the store and gives one row for each person (`ContactsSync.swift:31-38`). It does not see the rows of the contact.
- `SystemContacts.fetchAll` keeps the first person ID of a contact, not the rows (`SystemContacts.swift:24`).
- `applyLinks` adds a row and writes a journal entry. If the row is already there, it writes no entry (`ContactsSync.swift:46-50`).
- No function removes one URL row. On the Mac, the general `ContactsApp.apply` can remove or update a URL row. On iOS, removal exists only in the edit path, and that path refuses the link row.
- A journal entry holds the contact identifier, which is different on each device. The journal on iOS is in the app container.

### 3.2 Behaviour of the new build

- `PersonLink.label` is `cardxchange`. `PersonLink.url` writes `cx://person/<uuid>`.
- `PersonLink.personID(from:)` accepts the scheme `cx` and the scheme `pplz`. The person ID is the same in the two forms. A contact with an old link is matched to its person as before.
- A new pure function decides what to do with the link rows of one contact. Input: the URL rows of the contact and the person ID. Output: rows to add, rows to remove.

| URL rows of the contact for this person | Result |
|---|---|
| none | add the new row |
| one new row | nothing |
| a row with the new value and a label that is not `cardxchange` | nothing; the value decides, as today |
| one old row | add the new row, remove the old row |
| one old row and one new row | remove the old row |
| two or more identical new rows | remove all but one |
| a row that is not a link for this person | never touched |

- An old row is removed on the strength of its form (D13): label `pplz` and a value that `personID(from:)` reads as the old scheme. No journal entry is necessary as proof.
- Each added and each removed row gets a journal entry. Old journal entries are not changed; the journal is append-only.
- The app registers the URL schemes `cx` and `pplz`. `PeopleModel.open(_:)` accepts the two schemes for `person` and for `capture`.
- The share extensions send `cx://capture`.

### 3.3 New code

- The reading of contacts gives the link rows of each contact to the planning function, not only the first person ID. Built 2026-11-20: `ContactsSync.applyLinks` reads the URL rows of the contact just before it writes, and `PersonLink.changes` plans them.
- A function that removes one URL row, on the Mac (through the Contacts app) and on iOS (through `CNContactStore`). An update of the row in place is permitted in place of "add and remove", if it is simpler on a platform. The result in the address book is the same.
- **[S] 2026-11-20, L2:** The Mac and iOS both write link rows today; this stays.
- **[S] 2026-11-20, L3:** The old scheme and the old parser branch stay in the code without an end date. An old backup of the address book can bring old rows back, and the table in §3.2 repairs them.

### 3.4 Tests first (phase 2)

Write these before the code. They must fail for the expected reason.

- an old-scheme URL gives the same person ID as the new-scheme URL
- the URL that is written has the new scheme and the new label
- one test for each line of the table in §3.2
- an old link is never part of an edit diff, and the editor shows neither form

### 3.5 Existing tests that change

The rename changes what the app writes. These existing assertions change with it. The user agreed on 2026-11-20, because the rule is that a test is not changed to make it pass:

- link form and label: `PersonLinkTests.swift`, `ContactEditTests.swift:156-162`, `CardPresentationTests.swift:56`, `PeopleModelTests.swift:145`
- markers: `NotesBlockTests.swift`
- JSON key `isPplzOnly`: `RegressionTests.swift:58`
- message texts with the name: `PeopleModelTests.swift`, `PhotoTests.swift:80`

Each such change is a replacement of a name in an expected value. No assertion is removed or made weaker.

## 4. History block in the notes (`NotesBlock`)

### 4.1 How it works today

- `blockRange` finds the last end marker, then the nearest start marker before it (`NotesBlock.swift:47-51`). A start marker without an end marker is not a block.
- `merge` replaces that range, or appends the block, or removes it when the block is nil.
- `ContactsSync.apply` reads the note, calls `merge`, and writes only if the text is different (`ContactsSync.swift:71-73`).
- `historyPlan` covers only persons with a stored contact identifier, and gives nothing when the setting is off.
- Only the Mac writes blocks.

### 4.2 Behaviour of the new build

- `render` writes the new markers.
- `blockRange` finds a block with the new markers. If there is none, it finds a block with the old markers.
- `merge` replaces the block that was found with the new block, in the same position. The text before and after the block does not change.
- If a note has a new block and an old block, `merge` updates the new block and removes the old block.
- "Off" (block is nil) removes the two forms.
- Result: the first `cx contacts sync` on the Mac rewrites each old block, because the merged text is different from the note.
- A contact whose person has no stored contact identifier on this Mac keeps its old block until that person is adopted. The block is then replaced, not doubled.

### 4.3 Tests first (phase 2)

In `NotesBlockTests`:

- a note with an old block gets one new block in the same position, and the text around it is unchanged
- a note with an old block and "off" has no block afterwards
- a note with the two blocks has one new block afterwards
- an old start marker without an end marker is not a block

## 5. Contact journal

- The file moves with the store folder. Its name and format do not change.
- Old entries keep `"label":"pplz"`. They stay as a record.
- `cxAdded` keeps its meaning for related-name rows. For link rows, ownership follows from the form (D13).
- `cx contacts journal --json` prints old and new entries.

## 6. iCloud

- The new container starts empty. In the Development environment the schema is created when the first records are saved.
- The record types come from the class names (`CD_Person`, …). They do not change, because no `@Model` class changes.
- `CXStore.iCloudContainer` holds the container name as a constant (`PplzStore.swift:11`). It must be the same string as the entitlement in `App/project.yml`.
- The Mac is the source: after the store migration, the Mac app uploads to the new container. See M2 in §2.2.
- The old container stays in the account and is not used. Apple documents no way to delete it.

## 7. iOS and iPadOS

- A new bundle ID is a new app for the system. The new app has a new container and an empty store.
- The data arrives through iCloud from the Mac (§6).
- When the old app is deleted, its store and its journal go with it. Thus the last sync with the old apps (§10 step 1) comes first.
- The permissions for Contacts, Calendar and Camera are asked again.

## 8. App Group inbox

- The inbox holds a shared item only until the app reads it.
- Open each old app one time before it is removed (§10 step 1), so that the inbox is empty.
- The old group container on the Mac (`~/Library/Group Containers/<TeamID>.com.tillg.pplz/`) can be deleted in phase 8.

## 9. Settings of the app

- `UserDefaults` of the old bundle ID holds only window positions. Nothing is migrated.
- The synced setting `showHistoryInContacts` is in the store and moves with it.

## 10. Order on the real data

This is the one order for phases 5 and 6. `03-apple-guide.md` part C gives the Apple side of the same steps.

Phase 5, Mac:

0. Reset the Development environment of the new container `iCloud.me.cardxchange.app` in CloudKit Console (**Reset Environment**). It holds the records of the M2 test. Then Claude starts the new Mac app with an empty temporary store and `-forceSync YES -noContacts YES`: after one minute, all counts must be 0. Until then, do not open the new app on the iPhone or the iPad.
1. Last sync with the old apps. Open pplz on each device and wait. Make one test event on the iPhone and see it on the Mac. Compare the number of persons that the iPhone and the Mac show. If they are different, stop.
2. Write down the counts on the Mac: `pplz people --json` and the number of events of three persons.
3. Delete the old app from iPhone and iPad.
4. On the Mac: quit pplz, delete `/Applications/pplz.app`, delete the symlink `~/.local/bin/pplz`. From now on no old build exists. Check that `cx --help` works (linked in phase 4) and that `env | grep PPLZ_` finds nothing.
5. Export the address book (Contacts app: File, Export, Contacts Archive).
6. Run the migration script. It checks the counts and renames the old folder.
7. Start the new Mac app. Give the permissions (`03-apple-guide.md` C1). Check persons, events and photos against step 2.
8. Run `cx contacts sync`. Check three contacts by hand in the Contacts app: one link row with the new label, one block with the new markers, own note text unchanged.

Phase 6, iPhone and iPad:

9. Wait until iCloud Contacts has carried the result of step 8 to the device. Check one of the three contacts in the Contacts app on the iPhone: it shows the new link row. Do not install the new app before this, or the two devices each add a row.
10. Install the new app. Give the permissions.
11. Wait for the iCloud sync. Compare the number of persons with step 2, and check the same three persons with their events and photos (M2).

Phase 8, one week later: delete `pplz.migrated-<date>` and the old group container.
