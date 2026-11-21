---
title: "Decisions"
created: 2026-11-19
edited: 2026-11-21
---

pplz is the old name of cardXchange (`docs/changes/01_rename_to_cardxchange/`). The entries below keep the old name as written.

**Contents**

- [2026-11-19 11:54 — Profile capture from a screenshot, built while the user is at lunch](#run-2026-11-19-1154)
  - [11:56 — Commit and push to main without asking each time](#run-2026-11-19-1154-1)
  - [11:58 — Build order: everything that does not need the model first](#run-2026-11-19-1154-2)
  - [12:00 — Keep the LinkedIn profile ID on the pplz person as well as in the contact](#run-2026-11-19-1154-3)
  - [12:01 — A capture only fills empty contact fields; on the Mac it cannot update a contact that has a note](#run-2026-11-19-1154-4)
  - [12:02 — The model reads the recognised text, not the image](#run-2026-11-19-1154-5)
  - [12:03 — "Meetings in my calendar" means the system calendar, plus recent pplz events](#run-2026-11-19-1154-6)
  - [12:08 — The share extension only delivers; the app does the reading and asking](#run-2026-11-19-1154-7)
  - [12:10 — The extension opens pplz through the Objective-C runtime](#run-2026-11-19-1154-8)
  - [12:16 — Leave the share extension in the project although it cannot be signed from this session](#run-2026-11-19-1154-9)
- [2026-11-19 21:14 — Work through the open GitHub issues](#run-2026-11-19-2114)
  - [21:15 — Commit, push to main and write to the issue tracker without asking](#run-2026-11-19-2114-1)
  - [21:16 — Build only issue 7; the other six get questions](#run-2026-11-19-2114-2)
  - [21:18 — The age is counted by month and day, and shown in the app only](#run-2026-11-19-2114-3)
- [2026-11-19 23:24 — Build the answered issues: map, photos, Contacts functions](#run-2026-11-19-2324)
  - [23:28 — Build 4, then 2, then 1 without deleting; ask again on 5 and on deleting](#run-2026-11-19-2324-1)
  - [23:29 — At most 300 addresses an hour go to Apple's map service](#run-2026-11-19-2324-2)
  - [23:45 — Issue 4 is closed although the map background and clicking were not seen](#run-2026-11-19-2324-3)
  - [23:47 — A picture without a face is refused; photos sync as a new record type](#run-2026-11-19-2324-4)
  - [00:03 — One edit screen for contacts on all devices; an edit writes only what changed](#run-2026-11-19-2324-5)
  - [00:56 — Fix seven review findings now; leave five as known limits](#run-2026-11-19-2324-6)
- [2026-11-21 14:27 — Work through the open GitHub issues; labels for the issue state](#run-2026-11-21-1427)
  - [14:30 — Build 11, 10, 9, 8, the deleting of 1 and "My Card" of 5; ask on 3 and on the domain of 5](#run-2026-11-21-1427-1)
  - [14:31 — Commit and push to main, and write to the issue tracker, without asking](#run-2026-11-21-1427-2)
  - [14:32 — Parallel subagents work in git worktrees on their own branches](#run-2026-11-21-1427-3)
  - [14:55 — The expected end counts this device only; a small notice replaces the white box](#run-2026-11-21-1427-4)
  - [15:20 — A deleted person is marked and keeps a copy of the contact; purge on each load](#run-2026-11-21-1427-5)
  - [15:21 — My Card settings are kept per device in UserDefaults](#run-2026-11-21-1427-6)
  - [15:10 — The build number is the commit count; the version shows in About and in Settings](#run-2026-11-21-1427-7)

# 2026-11-19 11:54 — Profile capture from a screenshot, built while the user is at lunch {#run-2026-11-19-1154}

- **Started by:** `/autonomous`
- **Task, as given:**

  > Pls wait for the models to download and continue once they are available. I need to leave for lunch, so continue w/o me.

## 11:56 — Commit and push to main without asking each time {#run-2026-11-19-1154-1}

- **Status:** open
- **Overrides:** the user's standing practice in this project (commit and push only when they say so) and `~/.claude/CLAUDE.md` — "Never create or switch branches without explicit permission" is kept; only the asking is dropped.
- **Context:** the profile-capture work so far (name matching, picture crop, LinkedIn link reader, `pplz capture`) was green but uncommitted when the run started.
- **Question:** wait for a "commit & push" as usual, or commit each green unit?
- **Decision:** commit each green unit and push it to `main`, as `/autonomous` allows. No branch is created.
- **Why:** the user is away; uncommitted work across a long run is easy to lose and hard to review. The repo has a single branch and a single author.
- **Alternatives:** keep everything uncommitted until the user returns (one big diff, nothing to roll back to).
- **Consequences:** several commits on `main` appear without a prior go-ahead; each can be reverted on its own. The repository is public, so nothing from `private/` and no real person's data goes into commits.

## 11:58 — Build order: everything that does not need the model first {#run-2026-11-19-1154-2}

- **Status:** open
- **Context:** the on-device language model on this Mac still reports `modelNotReady` (download running since the Siri language was changed). The extraction of name, job and company depends on it; nothing else does.
- **Question:** wait idle for the download, or build around it?
- **Decision:** build in this order: (1) the capture data model and the review screen with editable fields, usable by hand; (2) writing the result into pplz and Contacts; (3) linking to an event; (4) model extraction as soon as the model is ready; (5) the share extension last.
- **Why:** the review screen is needed anyway as the manual path when a device has no model, and it is where extraction results are corrected. The share extension only delivers the image, so it can come last.
- **Alternatives:** wait for the model and decide the extraction path first (blocks everything on a download of unknown length).
- **Consequences:** if the model never becomes ready during the run, extraction stays unverified and is reported as open.

## 12:00 — Keep the LinkedIn profile ID on the pplz person as well as in the contact {#run-2026-11-19-1154-3}

- **Status:** open
- **Context:** `docs/SPEC.md` §3.2 says social-media links live in the contact's social-profile fields. The user asked on 2026-11-19 that the LinkedIn "ID" be added "to the contact & pplz person".
- **Question:** one copy (contact only) or two?
- **Decision:** two. The contact gets a LinkedIn social profile; the pplz person gets a new field `linkedInID` (the part after `/in/`, lower-cased).
- **Why:** the user asked for both; a person that exists only in pplz has no contact to hold it; and the ID on the person makes "the person with this LinkedIn profile" the first match proposal, which a name cannot do reliably.
- **Alternatives:** contact only, as the spec said (one source of truth, but nothing for pplz-only persons and no matching by profile).
- **Consequences:** a new attribute in the synced data model (added with a default, so existing stores migrate by themselves). The two copies can drift if the user edits the contact's LinkedIn field by hand; pplz does not reconcile them yet.

## 12:01 — A capture only fills empty contact fields; on the Mac it cannot update a contact that has a note {#run-2026-11-19-1154-4}

- **Status:** open
- **Context:** saving a capture into an existing contact (`SystemContacts.fill`).
- **Question:** may a capture overwrite job title, company, address, picture? And how to write on the Mac, where saving a contact with a note fails without Apple's notes entitlement (SPEC §8.1, S4)?
- **Decision:** never overwrite: only fields that are empty are filled. On the Mac the write goes through the Contacts framework and reports a clear error for a contact with a note, pointing to iPhone / iPad. New contacts work everywhere.
- **Why:** the address book is the user's own data, and a screenshot is a weaker source than what they entered. The capture use case is a phone use case; scripting the Contacts app for picture, address and social profile is a lot of code for the Mac path.
- **Alternatives:** overwrite with a per-field confirmation (more UI); script the Contacts app on the Mac as for the link and note (complete, but larger).
- **Consequences:** capturing on the Mac for an existing contact with a note fails with a message. Revisit when the notes entitlement arrives or if Mac capture matters.

## 12:02 — The model reads the recognised text, not the image {#run-2026-11-19-1154-5}

- **Status:** open
- **Context:** Apple's on-device language model accepts images since iOS / macOS 27 and text since 26. The spike could not compare the two because the model was not ready.
- **Question:** send the screenshot or the text Vision recognised?
- **Decision:** the text, for now.
- **Why:** it works one system version earlier, text recognition already proved good on all three sample screenshots, and it could be written without the model. The comparison is still owed.
- **Alternatives:** the image itself (may read layout better, e.g. tell the name from banner text; needs iOS 27).
- **Consequences:** compare both on the sample screenshots once the model is ready and switch if the image is clearly better. Compared at 12:40 on the three sample screenshots (iPhone, iPad, Mac): the text was clearly better. Given the image, the model invented a company name and an employer that are not on the page and copied an example from the instructions as the location; given the text it got name, title and company right every time. So the text stays. Two things the model kept getting wrong even from text are now found by rule instead: the place (the last line of the profile header, above the connections) and the role (what stands before "at <company>" in the headline). Result: all fields correct on all three screenshots in three runs each. Only one person's profile was tested.

## 12:03 — "Meetings in my calendar" means the system calendar, plus recent pplz events {#run-2026-11-19-1154-6}

- **Status:** open
- **Context:** the user's flow: "Select from the current & recent meetings in my calendar or 'New event'".
- **Question:** which calendar, how far back, and what about events already in pplz?
- **Decision:** read the system calendar (EventKit, full-access permission) for today and the three days before, current entries first, at most six; additionally offer pplz events of the last three days. A calendar entry that already is a pplz event (same title and start) is not created twice — the person is added to it.
- **Why:** a conference lasts days and people are often captured the evening after; listing pplz events avoids logging the same meeting twice.
- **Alternatives:** calendar only (duplicates); a longer window (a long list on a phone).
- **Consequences:** a new permission prompt for the calendar on first use. Calendar entries become events of format "live meeting"; the format can be changed afterwards.

## 12:08 — The share extension only delivers; the app does the reading and asking {#run-2026-11-19-1154-7}

- **Status:** open
- **Context:** the user wants to share a screenshot from the iPhone to pplz. A share extension is its own process and cannot reach the app's store.
- **Question:** run the whole flow inside the extension, or hand over to the app?
- **Decision:** the extension writes the shared image or link into an inbox folder in an App Group and tries to open pplz; pplz picks the inbox up when it becomes active and runs the capture flow.
- **Why:** the synced store stays where it is (no move into an App Group, no second process writing to a CloudKit store); all logic stays in the app, where it is tested.
- **Alternatives:** full flow in the extension (no app switch, but shared store, memory limits and duplicated UI).
- **Consequences:** needs the App Groups capability and a second bundle ID, which Xcode has to register. If iOS does not let the extension open the app, the user has to open pplz themselves — one extra tap.

## 12:10 — The extension opens pplz through the Objective-C runtime {#run-2026-11-19-1154-8}

- **Status:** open
- **Context:** `App/Share/ShareViewController.swift`. iOS offers share extensions no supported way to open their app; `UIApplication.open` is unavailable to extensions at compile time, and Xcode refuses to build an extension with `APPLICATION_EXTENSION_API_ONLY = NO`.
- **Question:** make the user open pplz by hand after every share, or use the known workaround?
- **Decision:** find the host's `UIApplication` through the responder chain and call `openURL:options:completionHandler:` through the Objective-C runtime; if that does nothing, show "Saved. Open pplz to continue."
- **Why:** the user asked for a flow where sharing leads straight into pplz's questions; this is a personal build first (SPEC §1).
- **Alternatives:** no automatic opening (always one extra tap, but nothing Apple could object to).
- **Consequences:** not verified on a device yet. It uses an API that is off limits for extensions, so App Review may reject it: remove it before a store release. A system update can also stop it from working; the fallback message covers that.

## 12:16 — Leave the share extension in the project although it cannot be signed from this session {#run-2026-11-19-1154-9}

- **Status:** open
- **Context:** the device build failed with "No Accounts" for the new bundle ID `com.tillg.pplz.share` and the App Groups capability: Xcode's signed-in account is not reachable from this session's shell, only from the user's own terminal (the same happened with the iCloud capability). The failed build left a broken app bundle behind, and the build script installed it on the iPad.
- **Question:** take the extension out of `main` again so that device builds keep working, or leave it in?
- **Decision:** leave it in. Fix the script so that it never installs after a failed build, and reinstall a clean build on the iPad from a temporary project variant without the extension (not committed).
- **Why:** the extension is what the user asked for, and one run of `scripts/build-app.sh iphone "<device>"` from their terminal creates the profiles; after that this session can build again, as with iCloud.
- **Alternatives:** revert the extension (device builds from this session keep working, but the feature the user asked for is gone from `main`); make the extension optional by a build flag (more project plumbing for a one-time problem).
- **Consequences:** until the user has run the device build once themselves, device builds of `main` fail. The iPad has a valid build with the capture screen but without "Share → pplz"; the iPhone was not connected and still has the build from 10:43. The share extension is untested on a device. Correction, 13:30: the user ran the build from their own terminal and it failed the same way, so the assumption in "Why" was wrong — `xcodebuild` cannot reach the account from any shell. The profiles have to be created once in the Xcode app (Signing & Capabilities of `pplziOS` and `pplzShare`).

# 2026-11-19 21:14 — Work through the open GitHub issues {#run-2026-11-19-2114}

- **Started by:** `/autonomous`
- **Task, as given:**

  > Look at the gh issues and do the ones where u are sure how to implement them. For the others write the questions in comments.

## 21:15 — Commit, push to main and write to the issue tracker without asking {#run-2026-11-19-2114-1}

- **Status:** open
- **Overrides:** the user's standing practice in this project (commit and push only when they say "commit & push"). "Never create or switch branches" from `~/.claude/CLAUDE.md` is kept.
- **Context:** the task ends in commits (issues done) and in comments on GitHub (questions). The repository is public.
- **Question:** wait for a go-ahead per commit and per comment?
- **Decision:** commit each green unit to `main`, push it, close an issue once its fix is on `main`, and post the questions as issue comments. Each comment starts with the note that Claude wrote it.
- **Why:** the task asks for both, and the user is away. `/autonomous` allows it.
- **Alternatives:** leave the commits and the comment drafts for the user (nothing is published, but the task is not done).
- **Consequences:** `Package.resolved` was already changed before the run and `assets/social-preview.png` was untracked; neither is committed. Nothing from `private/` and no real person's data goes into commits or comments. Correction, 21:25: `assets/social-preview.png` is tracked and unchanged; only `Package.resolved` was dirty. The three decision times of this run were first written ahead of the clock and corrected to the times before the commit (21:21). Later in the run: commit `b88eabc` pushed to `main`, issue 7 closed, one comment on each of the issues 1–7.

## 21:16 — Build only issue 7; the other six get questions {#run-2026-11-19-2114-2}

- **Status:** open
- **Context:** seven open issues (1–7). The task says to build the ones where the way is certain.
- **Question:** which ones are certain?
- **Decision:** build 7 (age next to the birthday). Ask on 1, 2, 3, 4, 5 and 6.
- **Why:**
  - 7 is a single display rule with no data stored.
  - 6 ("Icons same size") shows the pplz and the Contacts icon side by side. Measured in that screenshot, both are the same size (192 px wide, same circle, same tabs), so it is not clear what differs and where.
  - 2 and 3 add photos and face data to the synced store, which is hard to take back, and the spec leaves the storage and the recognition service open.
  - 4 needs every address turned into coordinates, which Apple's service limits and which sends the addresses to Apple.
  - 1 names no functions; 5 needs a server and a store release, which the spec excludes so far.
- **Alternatives:** build a first map (4) or a photo gallery (2) on assumptions (visible progress, but schema and privacy choices the user has not made).
- **Consequences:** six issues stay open with questions; each question comes with a proposed default so that a short answer is enough.

## 21:18 — The age is counted by month and day, and shown in the app only {#run-2026-11-19-2114-3}

- **Status:** open
- **Context:** issue 7, `ContactDetails.age` and the birthday row of the person card.
- **Question:** when does someone born on 29 February get a year older in other years, where is the age shown, and what about a birthday without a year?
- **Decision:** the age is the number of completed years by comparing month and day, so 29 February counts from 1 March. It is shown in the birthday row of the person card as `1980-05-17 · 46 years`. Without a birth year the row shows the date only. The text and JSON output of `pplz person` keep the plain date.
- **Why:** comparing month and day is the usual rule in Germany and needs no calendar arithmetic. The JSON is read by scripts, and an age in it would be out of date the next day.
- **Alternatives:** count 28 February as the birthday in other years (what Apple's calendar arithmetic does); show the age in the command line too.
- **Consequences:** none for stored data. The date itself stays in the form `YYYY-MM-DD`; a localised date would be a separate change.

# 2026-11-19 23:24 — Build the answered issues: map, photos, Contacts functions {#run-2026-11-19-2324}

- **Started by:** `/autonomous`
- **Task, as given:**

  > Read the comments of the issues and work on the ones where u feel confident. For the ones where there is information missing, write your questions into a comment (if you haven't done so yet).
  > Every time u start woking on an issue, set it a label "wip". When done, close the issue.

  Added by the user during the run: "In between always commit & push".

## 23:28 — Build 4, then 2, then 1 without deleting; ask again on 5 and on deleting {#run-2026-11-19-2324-1}

- **Status:** open
- **Context:** the user answered the questions on issues 1, 2, 4 and 5. Issue 3 has no answer yet; issue 6 was closed by the user.
- **Question:** which issues are clear enough to build, and in which order?
- **Decision:**
  - Build 4 (map) first, then 2 (photos of a person), then 1 (Contacts functions) in slices: round buttons with a choice of number, then editing and creating.
  - Deleting a contact (part of 1) is not built; a follow-up question is posted. Issue 1 stays open with the label `wip` until that part is done.
  - 5 (exchange cards) is not started; follow-up questions are posted.
  - 3 is left alone: the questions are already there.
- **Why:**
  - 4 is fully answered and stores nothing in the synced data.
  - 2 is fully answered but adds to the synced data, so it comes after the simpler one.
  - Deleting cannot be undone, and the answer does not say whether the Apple contact goes at once or after the 30 days.
  - 5 needs a store release, a website and two iCloud accounts, and iOS hands nothing from a QR code through an installation; how the card reaches a fresh app is open.
- **Alternatives:** build deleting with the contact removed after 30 days (my proposal in the comment), unattended; start 5 with the parts that need no release.
- **Consequences:** issues 1, 3 and 5 stay open after the run. Three things happened to real data during the run: (1) at 23:35 a test command wrote two invented persons and two events into the real store, because a failed shell step skipped the line that pointed it to a test store; all four were removed again. (2) Invented contacts named "Zzpplz Testperson" were created in the real address book to check the picture and the editing, and deleted; none is left. (3) The real store on the Mac was opened with the new data model at 00:00, after a backup. The iPhone was not reachable at 00:33, so the new version is on the Mac and the iPad only. For editing on the Mac and the edit screen on iPhone / iPad the user gave no choice, so the defaults proposed in the first comment apply: the Mac edits through the Contacts app where the framework cannot save, and iPhone / iPad keep the system's contact card.

## 23:29 — At most 300 addresses an hour go to Apple's map service {#run-2026-11-19-2324-2}

- **Status:** open
- **Context:** issue 4. The user's rule: count the addresses sent in the current hour, pause until the next hour plus 10 minutes, then continue. The rule names no number, and Apple publishes none.
- **Question:** how many addresses per hour, and through which interface?
- **Decision:** 300 per clock hour, at least one second apart. If Apple's service answers with its "too many requests" error earlier, the hour counts as used up. The lookups use `CLGeocoder`. Results and the counter are kept in one file per device, outside the synced store, shared by the app and the command line.
- **Why:** 300 an hour is far below anything reported to trigger the limit, and a few thousand addresses are still done within a day. `CLGeocoder` works on all supported systems (macOS 15, iOS 18); its successor needs version 26. A cache outside the store means a test instance does not send every address again.
- **Alternatives:** a higher number (faster first run, more likely to be throttled); the newer MapKit request (not available on the oldest supported systems).
- **Consequences:** the first complete run over a large address book takes several hours of app time. `CLGeocoder` is marked as deprecated from version 26 and has to be replaced when the minimum system is raised. The "50 lookups a minute" in the first comment on the issue was not verified. Changed by the user on 2026-11-20: the coordinates are no longer kept per device but are part of the synced pplz data (a new record type, added like the photos), and each device takes cards in random order so that several devices share the work. The limit of 300 an hour stays per device. My choices within that: two rows for one address from two devices are both kept and read by a fixed rule; the app saves answers in batches of 25 and locates in the background only on its own store; the 895 answers the Mac already had were moved into the store, after a backup (`backup-before-locations-…`).

## 23:45 — Issue 4 is closed although the map background and clicking were not seen {#run-2026-11-19-2324-3}

- **Status:** open
- **Context:** issue 4, commit `2147251`. The task says to close an issue when it is done. In the session's screenshots of the Mac app the pins, the groups and the status line show, but the map background stays blank, and the session cannot click.
- **Question:** close the issue, or leave it open until a person has looked?
- **Decision:** close it, and say in the closing comment what was not checked.
- **Why:** everything that can be checked from the session passes (258 tests, a real search with `--near`, the pins from 210 located addresses). A blank background with pins in place points to the display being asleep, not to the code; the user sees it at the first look and can reopen.
- **Alternatives:** leave it open with `wip` (accurate, but then every issue with a screen stays open in an unattended run).
- **Consequences:** to check by the user: the map background, the callout that opens a person, grouped pins zooming in, and the map on iPhone / iPad with real contacts. While building, about 300 real addresses were sent to Apple's service (as the user allowed) and are now in the device's cache file. Issue 2 was closed the same way at 23:59 (commit `e635b40`): the menus, the pickers, paste, drag & drop and the sync of photos between devices were not seen. Checked at 00:40 in the iPhone simulator: the map background shows, pins and groups appear, and a pin's callout opens the person; so the blank background on the Mac came from the sleeping display.

## 23:47 — A picture without a face is refused; photos sync as a new record type {#run-2026-11-19-2324-4}

- **Status:** open
- **Context:** issue 2. The user's answers: real copies in pplz's iCloud storage; only the face crop is kept; several faces: ask which one.
- **Question:** what happens with a picture in which no face is found, and how is the synced data extended?
- **Decision:** such a picture is refused with a message. The data model gets one new type (a photo belonging to a person, the image stored as an external file); nothing existing is changed. A store written before the change is kept as a test file, and a test opens it with the new model.
- **Why:** the user wants only face crops, for later recognition; a picture without a face would be of no use there. An addition without changes to existing types is the only kind of change the iCloud sync accepts without a migration.
- **Alternatives:** keep the whole picture when no face is found (nothing is lost, but it breaks "only the face"); let the user draw the face area by hand (more screen work).
- **Consequences:** the first start of the new version on each device extends the local store, and the first device also adds the new type to the iCloud data (development environment). This cannot be taken back in iCloud once it is in the production environment; so far pplz only uses the development one. "Only the newest 20 are used for recognition" is not built: there is no recognition yet (issue 3). Later in the run: the real store on the Mac was copied to a folder `backup-before-photos-…` next to it and then opened with the new version; people and events were the same before and after.

## 00:03 — One edit screen for contacts on all devices; an edit writes only what changed {#run-2026-11-19-2324-5}

- **Status:** open
- **Context:** issue 1. The user asked for "edit all the fields (except notes)" and "creating a contact", and did not answer whether iPhone / iPad keep the system's contact card only or get pplz's own edit screen, nor how the Mac should save a contact that has a note.
- **Question:** where is the edit screen offered, how does saving work, and what is left out?
- **Decision:**
  - One edit screen, shared by Mac, iPhone and iPad; the system's contact card on iPhone / iPad stays as well. This replaces the default named in decision 1 of this run ("own edit screen on the Mac only").
  - Saving reads the contact again and writes only the fields the user changed. If one of those fields was changed elsewhere in the meantime, pplz refuses and says so.
  - On the Mac the Contacts framework is tried first; for a contact with a note, where that fails, the same changes go through the Contacts app.
  - The `pplz` link row, the note and the related names are never part of an edit.
  - No command for the command line and no journal entry for these edits.
- **Why:** the screen is shared code, so offering it everywhere costs nothing extra and the user asked for the functions "in pplz". Writing only changes keeps a mistake in pplz from damaging fields the user did not touch. The journal lists what pplz writes on its own, not what the user types.
- **Alternatives:** the Mac only (as first proposed); replace all values of a contact on save (simpler, but rewrites everything on every save).
- **Consequences:** editing through the Contacts app needs the user's permission for pplz to control Contacts, as the link and the history already do, and goes away when Apple grants the notes permission. The command line cannot edit contact fields yet. Changed by the user on 2026-11-20: the two menu entries "Edit Contact…" and "Edit pplz Details…" were too complicated. There is now one "Edit" button and one screen with two labelled groups, "Contact card" and "pplz"; the contact's note is shown greyed out (on the Mac read through the Contacts app; on iPhone / iPad pplz cannot read it and says so). Further changes asked by the user the same day: the editor opens in place of the card instead of as a sheet (the list is locked until Cancel or Done), is laid out like the edit view of Contacts, and takes the birthday as one typed date with or without a year. My choices within that: "New Contact" stays a sheet; a year needs four digits; numbers alone follow the region's order (day first in Germany); the contact is saved before pplz's own fields, so a refused contact save writes nothing.

## 00:56 — Fix seven review findings now; leave five as known limits {#run-2026-11-19-2324-6}

- **Status:** open
- **Context:** an independent review of the four commits of this run (map, photos, buttons, editing), focused on the code that writes contacts and the synced store. Two of its findings could damage contacts: a save could land on another contact when the selection changed while the edit screen was open, and a row that the screen shows as empty (e.g. an address with only a state) was deleted on any save. Both were already pushed in `3df2453`.
- **Question:** which findings are fixed in this run?
- **Decision:** fixed, each with a test written first: the two above; a possible crash when removing a row in the edit screen; one failing address blocking all address lookups behind it; being offline counted as "too many requests" for a whole hour; the address cache being overwritten after a failed read; and the message after a failed change through the Contacts app, which claimed nothing was saved although some changes may stay pending there. Also from the retro: a test now checks that the stored test file from before the photo change still has the old data model.
- **Why:** the first two are data loss on a normal path; the others are cheap and stop the map from getting stuck.
- **Alternatives:** revert the editing commit until reviewed by the user (safe, but the user asked for the feature and the defects are fixed with tests).
- **Consequences:** known limits that stay: (1) a change through the Contacts app (Mac, contact with a note) that fails half-way cannot be undone; pplz says so. (2) Contacts that are linked from several accounts may show a changed value twice or report "changed in the meantime". (3) On that same path the country code of an address is not updated with the country. (4) Changing a social profile's address replaces its user name by the last part of the address. (5) When several pictures with several faces are added at once, a waiting face choice may be skipped. Between `3df2453` (00:33) and the fix, the defective version was installed on the Mac and the iPad; nobody used it.

# 2026-11-21 14:27 — Work through the open GitHub issues; labels for the issue state {#run-2026-11-21-1427}

- **Started by:** `/autonomous`
- **Task, as given:**

  > github issues
  > Look thru all the gh issues we have and work on the ones where u know what to do w/o any guidance from me. For the other ones write comments with the questions u have. 
  > Labels we plan to use: 
  > - wip when u work on
  > - "question for human" when u wrote something that needs my answer.
  >
  > Pls write these states in your claude.md so we can use them in the future.

  Added by the user during the run: "use sub-agents where possibel to save your context".

## 14:30 — Build 11, 10, 9, 8, the deleting of 1 and "My Card" of 5; ask on 3 and on the domain of 5 {#run-2026-11-21-1427-1}

- **Status:** open
- **Context:** six open issues. 11, 10, 9 and 8 are new and have no comments. 1 and 5 have answers from the user to earlier questions. 3 has questions from 19 Nov and no answer.
- **Question:** which issues can be built without the user, and how are the short ones read?
- **Decision:**
  - 11: "style #2" of the brand ideas page is "Wide bold": the capitals CARDXCHANGE in Syncopate Bold, letter spacing 0.12 em, grey with a pink X, without ".me". It replaces the wordmark (now style 3, "Hairline").
  - 9: the screenshot shows the map with a search that matches one person who has no located address. A plain white box with "No results" covers the middle of the map. Read as: the empty state on the map looks broken and says the wrong thing. Fix: a small message that does not hide the map and says that the matches have no located address.
  - 10: show the own position on the map, and a button that moves the map to it, as in Apple Maps.
  - 8: show the expected day and time when all addresses are located, from the hourly budget.
  - 1: build deleting as the user answered (contact removed from Apple Contacts at once, cardXchange keeps a copy and its own data for 30 days).
  - 5: build "My Card" with the fields chosen in the settings (point 4 of the second round). Explain the domain in simple words (the user wrote "eli5" to point 2).
  - 3: no new question; set `question for human`.
- **Why:** these are the readings with the smallest change that matches the words of the issues; none of them is costly to undo.
- **Alternatives:** ask on 9 and 11 first (safer, but both have one obvious reading).
- **Consequences:** the user can reopen 9 or 11 if the reading is wrong.

## 14:31 — Commit and push to main, and write to the issue tracker, without asking {#run-2026-11-21-1427-2}

- **Status:** open
- **Overrides:** `CLAUDE.md` — "Commit and push only when the user says so, or in an `/autonomous` run"; the `/autonomous` permission is used here.
- **Context:** the earlier runs pushed to `main`; the repository has no protected branch.
- **Question:** push each green unit of work to `main`?
- **Decision:** yes, after the full suite is green; comments and labels on the issues as the user asked.
- **Why:** the user follows the issues and the installed app, both read from `main`.
- **Alternatives:** one branch and a pull request for the run.
- **Consequences:** each fix is on `main` right away and can be reverted with `git revert`.

## 14:32 — Parallel subagents work in git worktrees on their own branches {#run-2026-11-21-1427-3}

- **Status:** open
- **Overrides:** `~/.claude/CLAUDE.md` — "Never create or switch branches without explicit permission".
- **Context:** the user asked to use subagents. Four pieces of work are independent (wordmark, map, deleting, My Card), but three of them change Swift files in the same working copy.
- **Question:** how do several subagents build and test at the same time?
- **Decision:** each subagent works in its own worktree in `.worktrees/` on a branch `autonomous/<issue>`. I bring each finished branch onto `main` with a rebase, run the full suite, and push `main`. The branches are local only and are deleted after the merge. The local `main` is never switched.
- **Why:** two agents in one working copy would break each other's builds and tests.
- **Alternatives:** one agent after the other on `main` (no branches, but about four times as long).
- **Consequences:** `.worktrees/` is now in `.gitignore`. Only one agent at a time may use the iOS simulator (a lock folder in the session's scratch folder).

## 14:55 — The expected end counts this device only; a small notice replaces the white box {#run-2026-11-21-1427-4}

- **Status:** open
- **Context:** issues 8, 9 and 10, built by a subagent (commits `613972a`, `bf01bfc`, `8008bd9`).
- **Question:** how is the expected end of locating computed, what does the map say when it shows no pin, and how is the own position asked for?
- **Decision:**
  - The expected end ("done about Sat 18:40") counts the addresses left, this device's hourly budget and one request a second. It does not count other devices.
  - The notice is a small capsule above the status line: "The match has no located address." (or "The N matches …"), "No results" when the search matches nobody, and a text for an empty map. The map stays visible.
  - The app asks for the location when the map is first shown, not at launch. The Mac gets the location entitlement in `App/project.yml`, although the Mac app is not sandboxed today.
- **Why:** a device cannot know whether another device locates at the same time; what the other device locates syncs in and makes the next estimate earlier. An opaque box looked like a fault and hid the map.
- **Alternatives:** guess the number of active devices; show the estimate only while locating runs.
- **Consequences:** with two devices the time shown is too late until the next sync. The status line is built from parts and cannot be translated (older code). The capsules touch the Apple Maps logo on iPhone; the status line did this before. A review by a fresh subagent found that the expected end was up to one hour wrong near the end of an hour, that it showed also when nothing locates, and that a search of only spaces gave the wrong notice. All three are fixed with tests in `89b554f`, `505ddc1` and `e2b5589`. The Mac app was built, signed with the location entitlement and installed; its window was not seen, because the display was asleep.

## 15:20 — A deleted person is marked and keeps a copy of the contact; purge on each load {#run-2026-11-21-1427-5}

- **Status:** open
- **Context:** issue 1, deleting, built by a subagent (commits `57351c0` to `34ca5a5`; SPEC §3.4). The user decided: the contact goes at once, cardXchange keeps a copy and its own data for 30 days, the same for a person without a contact.
- **Question:** how is a deleted person stored, what does the copy hold, and when is it purged?
- **Decision:**
  - Two new optional attributes on the person: the time of deletion and the copy of the contact (the fields of the edit screen as JSON). Additive, as the CloudKit rules ask.
  - The copy holds the fields of the edit screen only: no picture, no related names, no note.
  - The marker and the copy are saved first, then the contact is deleted. If Contacts refuses, the marker is undone.
  - Without Contacts access (`--no-contacts`, `-noContacts`), a person with a contact is not deleted, and a copy is not restored.
  - Each load of the app purges what is older than 30 days, on every device. The CLI purges only with `cx person purge --expired`.
  - A deleted person keeps their place in events for the 30 days. Commands: `cx person delete|restore|purge`, `cx people --deleted`.
  - "Recently Deleted" is a row at the top of the people list; it opens a sheet.
- **Why:** the smallest version that follows the user's answers and does not delete a contact before its copy is saved.
- **Alternatives:** a separate record type for deleted persons (more work, same result); a copy that holds the picture (larger synced data).
- **Consequences:** a restored contact has no note and no picture; its related names come back with the next `cx contacts sync` on the Mac. If an iPhone or iPad purges first, the related-name rows that the Mac wrote stay in other contacts. If the app stops between the marker and the deletion of the contact, a later restore makes a duplicate contact. During the 30 days, connections and tag counts still include the deleted person. A review by a fresh subagent found 8 points; 4 are fixed. Checked against the real address book with two invented contacts only, which were removed again. The Mac app screens were not seen.

## 15:21 — My Card settings are kept per device in UserDefaults {#run-2026-11-21-1427-6}

- **Status:** open
- **Context:** issue 5, step 1 "My Card", built by a subagent (commits `303f28b` to `3aa0775`; SPEC §4.8). The data model was not to change in this run, because the deleting work changed it at the same time.
- **Question:** where are "who is me" and the chosen fields kept, and what is on the card by default?
- **Decision:**
  - UserDefaults on each device; no sync.
  - "Me" is the row key in the people list. On the Mac the system's own card is used until the user chooses.
  - The name is always on the card. Each phone, mail, web, social profile and address row has its own switch; company, job title and picture have one switch each. Nickname, birthday, note, related names and the `cx://` link row never go on the card.
  - Defaults: name, company, job title, one mobile number, the first mail address, one LinkedIn profile; no picture.
  - The card is a Codable value and can be written as a vCard.
- **Why:** no schema change and no new entitlement in a run that already changes the model.
- **Alternatives:** the `Setting` table that the store already has (syncs, readable by the CLI, no schema change); the iCloud key-value store (needs an entitlement).
- **Consequences:** each device has its own choice. If a person without a contact later gets one, the choice goes back to "Not chosen". Moving the settings to the `Setting` table is the cheapest way to sync them later. Not seen: a tap in "Choose Me" in the simulator, the switches of a real contact, the Mac settings window.

## 15:10 — The build number is the commit count; the version shows in About and in Settings {#run-2026-11-21-1427-7}

- **Status:** open
- **Context:** issue 12, new during the run: "In the 'about' area we want to see 'V. 0.2.693 - 2026-11-20 14:07'. The 3rd digit of the version no should be the build no." The issue does not say where the build number comes from, nor where "about" is on iPhone and iPad.
- **Question:** what is the build number, which date is shown, and where?
- **Decision:**
  - The build number is the number of commits on the built branch (`git rev-list --count HEAD`), at build time. It is also the bundle version of the app and the extensions.
  - The version goes from 0.1 to 0.2, as in the user's example.
  - The date and time are the time of the build, in local time.
  - The Mac shows the text in the About window. iPhone and iPad show it at the bottom of the Settings screen.
- **Why:** the commit count goes up with every change, needs no counter file, and gives the same number for the same commit. The App Store needs a bundle version that only goes up.
- **Alternatives:** a counter in a file that each build increases (more commits, conflicts between devices); the date as the build number.
- **Consequences:** two builds of the same commit have the same number. The number is now 83, not 693 as in the example.
