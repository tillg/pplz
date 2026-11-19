---
title: "Decisions"
created: 2026-11-19
edited: 2026-11-19
---

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
- **Context:** `SPEC.md` §3.2 says social-media links live in the contact's social-profile fields. The user asked on 2026-11-19 that the LinkedIn "ID" be added "to the contact & pplz person".
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
