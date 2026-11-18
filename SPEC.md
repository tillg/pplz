# pplz — Specification

Status: **draft v0.3** · 2026-11-18 · all open questions walked through with Till

Legend used throughout:

- **[S]** stated by you
- **[A]** my assumption — correct me if wrong
- **[?]** open, see [Open questions](#9-open-questions)

---

## 1. Vision

pplz is a personal contact manager that remembers not only *who* people are but *when, where and how I met them*. **[S]**

It has two faces:

1. **The system Contacts app** (Mac, iPhone, iPad) — pplz enriches the contacts already there and keeps them in sync with pplz data. I keep using Contacts as usual and simply see more. **[S]**
2. **The pplz app** — holds the additional information per person (events, photos, history) and offers the functionality Contacts can't. **[S]**

### Platforms

- macOS, iOS, iPadOS **[S]**
- One native codebase (Swift / SwiftUI, multiplatform target) **[A]**
- Single user, my own data; no multi-user, no sharing, no pplz user accounts **[A]**
- No own application backend. Exceptions: the cloud services pplz calls while it is "cloud first" — face recognition (§7) and the language model (§4.5) — each with its own credentials. **[A]**

### Non-goals (for now) **[A]**

- Not a team CRM, no sales pipeline
- No Android / web / Windows
- No messaging or calling from within pplz

---

## 2. Domain model

```
Person ──< Participation >── Event ──< Photo
   │                           │
   └──── Face (enrolled)       └── Place
Photo ──< FaceObservation >── Person
```

### 2.1 Person

A person I know. Normally linked 1:1 to a contact in the system address book **[S]**; pplz-only persons without a contact are allowed (see below).

| Field | Notes |
|---|---|
| pplz ID | pplz's own UUID per person; it is the `<id>` in `pplz://person/<id>` |
| Link to system contact | contact IDs are device-local (R3). Slice 1 stores the local contact ID as a temporary link; slice 2 replaces it with the `pplz` link field in the contact. A person record is created only when pplz has something to store — contacts are never bulk-imported. The record keeps the contact's name as last seen (shown in event participant lists and when the contact is unavailable); it is refreshed when the person is next used and can be stale after a rename in Contacts. |
| Core contact data (name, phone, mail, …) | owned by Contacts and not duplicated in pplz while a contact is linked; pplz-only persons carry their own minimal core data **[A]** |
| How we met | where / when / through whom **[S]** decided 2026-11-18 |
| Notes | free text, things to remember **[S]** |
| Tags / groups | my own labels ("client", "sailing club") to filter and group **[S]** |
| Connections | links between persons: "introduced by", "colleague of", "partner of" **[S]**. Stored as a directed sentence "A — kind — B" with free-text kind; shown on both persons **[A]** |
| Keep-in-touch rhythm | desired interval per person (e.g. every 3 months); pplz lists people I haven't met for too long **[S]**. Stored in days (a month counts as 30); people with a rhythm but no event yet count as overdue **[A]** |
| | Connections are mirrored into Contacts as related names (§3.2) **[S]** 2026-11-18. Tags and the rhythm live in pplz only **[A]** |
| History | derived: all events this person participated in, newest first **[S]** |
| Photos | derived: all photos this person was recognized in **[S]** |
| Face reference data | for recognition, see §5 |

**Persons without a contact** **[S]** decided 2026-11-18: allowed — a name is enough. "Add to Contacts" creates the system contact on demand, so my address book stays free of one-off acquaintances. pplz-only persons then need their own minimal core data (name, optional photo) **[A]**.

**Deleted contacts** **[S]**: if I delete a contact in Contacts, the person stays in pplz marked "contact deleted". pplz asks me once: keep as pplz-only, restore the contact, or delete everything.

### 2.2 Event

Anything where I could meet people. **[S]**

| Field | Notes |
|---|---|
| Date / time | start, plus an **optional end** (also multi-day); quick logs leave the end empty **[S]** decided 2026-11-18 |
| Place | name + coordinates; empty for calls **[S]** |
| Format | built-in: `web call` · `phone call` · `live meeting` · `larger gathering` (conference, party, meetup) · `written exchange` (notable chat / mail, logged by hand); plus **custom formats** I define in settings **[S]** decided 2026-11-18 |
| Participants | 0..n Persons **[A]** |
| Title | e.g. "Dinner at Luigi's" **[A]** |
| Notes | free text **[A]** |
| Topics / follow-ups | what was discussed, and open follow-ups that can be ticked off **[S]** |
| Tags | same tag system as for persons **[S]** |
| Links / attachments | calendar entry, meeting link, documents **[S]**. Links are built; file attachments are not yet **[A]** |
| Photos | 0..n **[S]** |

### 2.3 Photo

A picture from an event, or just taken when I met someone (incl. selfies). **[S]**

| Field | Notes |
|---|---|
| Image reference | reference to the Photos-library asset + pplz's own small thumbnail **[S]**. If the original is deleted in Photos, the thumbnail remains. Images that are not in the Photos library (dragged-in files) are kept as pplz's own copy **[A]** |
| EXIF | capture time, GPS, camera **[S]** |
| Recognized people | 0..n, each with face region + confidence + confirmed-by-me flag **[A]** |
| Event | the event this photo is attributed to **[S]** |

### 2.4 History

Not stored separately — it is the per-person view over events (and their photos). **[A]**

---

## 3. Contacts integration

### 3.1 Principles

- The system address book stays the **source of truth for core contact data** of linked persons. pplz reads it live; it doesn't keep its own copy of names / numbers. **[A]**
- pplz is the **source of truth for everything else** (events, photos, history). **[A]**
- "Always in sync" **[S]** means:
  - a change to a contact in Contacts shows up in pplz immediately / on next launch
  - a change in pplz that affects the enrichment (new event, changed participants) updates the contact
  - new / deleted contacts are picked up; for deleted contacts see §2.1

### 3.2 What pplz writes into a contact

| Enrichment | Where in the contact | Status |
|---|---|---|
| Contact history (events I met the person at) | Notes ("comment") field, see §3.3 | **[S]** built for the Mac CLI 2026-11-18 |
| Deep link back to the person in pplz | URL field with custom label `pplz` → `pplz://person/<id>`; Contacts shows it as a tappable row that opens the person in pplz. Also serves as the cross-device identity link (R3). **Built 2026-11-18 (Mac):** written for every person pplz has a record of, the first time something is stored about them and by `pplz contacts sync`; the Mac app opens the person when the link is clicked. Contacts pplz has stored nothing about get no link yet. | **[S]** decided 2026-11-18 |
| Contact photo | contact image — for contacts without a picture pplz offers the best recognised face crop (or the LinkedIn picture, §4.4); set only after I confirm | **[S]** decided 2026-11-18 |
| LinkedIn / other social-media links | the contact's social-profile fields; kept in sync both ways: a profile added in Contacts shows in pplz, one added in pplz is written to the contact | **[S]** decided 2026-11-18 |
| Connections between people | the contact's **related names** (the field that holds e.g. "spouse"), as plain text `label: name`. The app offers **the same relationships as Contacts** (mother, father, parent, son, daughter, brother, sister, child, friend, spouse, partner, assistant, manager, other, plus colleague and a custom one) **[S]** 2026-11-18, phrased the same way: on Anna's card, "manager: Ben" means Ben is Anna's manager. Rows are written with Apple's own labels, so Contacts shows and translates them like its built-in ones. The matching row goes on the other card where it is unambiguous (friend ↔ friend, mother ↔ child, sister ↔ sibling, assistant ↔ manager); "manager" and "other" get none. Free-text kinds without "… of" ("introduced by", CLI only) go on the first person's card. pplz only removes rows it added itself: every write is recorded in a journal (`contact-writes.jsonl` next to the store, `pplz contacts journal`). Built 2026-11-18 on the Mac via Contacts scripting (§8.1 S6) until the notes entitlement arrives. | **[S]** 2026-11-18; the both-cards rule is **[A]** |
| Not written | "last met" date field, tags as Contacts groups — offered but not selected on 2026-11-18, so left out for now | **[A]** |

All my contacts live in **iCloud** — no Exchange / Google accounts to support. **[S]**

### 3.3 History in the notes field

pplz owns **one clearly delimited block** inside the note; everything outside it is mine and never touched. **[A]**

```
<my own notes stay here, untouched>

── pplz ──
Met 7× · last 2026-11-12
2026-11-12  Live meeting · Dinner at Luigi's, Köln
2026-10-03  Web call · Project kickoff
2026-08-21  Phone call
…
── /pplz ──
```

- Direction is **one-way** pplz → Contacts for this block. Manual edits inside the block are overwritten on next sync. **[S]** decided 2026-11-18
- Length: summary line + the 10 most recent events; full history lives in pplz. **[S]**
- Language: follows the device language. **[S]** To stop two devices with different languages from rewriting each other's block, the language is fixed by the first device and kept as a synced setting that I can change. **[A]**
- Line format as in the example above. **[S]** Only date, format, title and place are written, never event notes. **[A]**
- **Built 2026-11-18 for the Mac CLI** (`pplz contacts history on|off|status`), off by default. Written through Contacts scripting (§8.1 S6) until the notes entitlement arrives; a note is only replaced if it still reads as it did when pplz read it, and every write is in the journal. The block text is English only for now; the device-language rule is not built yet.
- Writing to Contacts is an explicit setting ("Show history in Contacts"), and only confirmed events are written — as declared to Apple, §8.4. **[S]**

---

## 4. The pplz app

### 4.1 People

- List / search of all persons: contacts plus pplz-only persons (visibly marked) **[A]**
- Person detail: core contact data (read from Contacts), pplz-only data, **history timeline**, photos **[S]**
- Contacts → pplz: via the `pplz` link row in the contact (§3.2) **[S]**
- pplz → contact: a button on the person detail **[S]**
  - macOS: opens the contact in Contacts.app. How is open: the `addressbook://` URL did not select the contact in one test (§8.1 S7); scripting the selection worked but needs Automation permission (store-readiness unclear); the in-app contact card (`CNContactViewController`, as on iOS) is the safe alternative. **[?]** spike
  - iOS / iPadOS: no public way to open the Contacts app at a specific contact; pplz shows the system contact card in-app instead (`CNContactViewController`, view + edit) **[A]**

### 4.2 Events

- Chronological list, filter by format / person / place **[A]**
- Create & edit manually: date, place, format, participants, notes **[S]**
- Created automatically from photos (§5) **[S]**
- **From the calendar** **[S]** decided 2026-11-18: calendar entries with attendees who are contacts become event *proposals* (date, place, participants; format guessed: video link → web call, location → live meeting). I confirm or dismiss them. **[A]** for the details
- **Quick log** **[S]**: a fast "I just talked to …" action — button on the person card, widget, Siri / Shortcuts action — to log a call or meeting in two taps
- Not planned: mail / messages as event source; phone call log (not available to apps, §8 R4)

### 4.3 Photos

- Photo sources **[S]** decided 2026-11-18:
  - manual: share sheet, drag & drop, photo picker
  - one dedicated Photos album (e.g. "pplz") that pplz watches; new photos in it are processed automatically
  - no scan of the whole Photos library
- Review queue: "pplz thinks this is Anna and Ben at Luigi's on 12 Nov — correct?" → confirm / fix **[A]**
- Browse by person / by event **[A]**

### 4.4 LinkedIn capture **[S]** added 2026-11-18

**Use case:** I meet someone at a conference or fair, we connect on LinkedIn — and I want that new person to end up in pplz *and* Contacts, including their LinkedIn picture, with very little effort.

Flow (decided 2026-11-18):

1. On the person's LinkedIn profile (app or browser) → Share → **pplz**, or scan their LinkedIn QR code in pplz. This delivers the profile link and, if the share provides it, the name; otherwise I type the name. **[A]** until the device spike
2. **Picture** **[S]**: I share the profile picture or a screenshot of the profile to pplz; pplz crops the face automatically and attaches it. pplz never fetches pictures from LinkedIn itself (R7).
3. pplz proposes "how we met" from the current event (time + place, e.g. the conference I'm at) and adds the person as a participant of that event. **[A]**
4. **The system contact is created automatically** with name, LinkedIn link and picture. **[S]**

Also: attaching a LinkedIn profile to an *existing* person must be equally easy (share → pick person, or paste link). **[A]**

Possible later addition: bulk import of existing connections from LinkedIn's official data export (R7). **[A]**

### 4.5 Smart features **[S]** decided 2026-11-18

- **Smart lists** — rule-based, no AI: "not met in 6 months", "met this year", "new since the fair", by tag / place / format. Also drives the keep-in-touch reminders (§2.1).
- **Natural-language search** — "who did I meet in Berlin last spring?", "the sailing guy from the fair" → people / events.
- **Relationship summary** — a short AI-written briefing per person from history, notes and follow-ups ("last met in October, talked about X, you owe him Y"); handy before a meeting.
- Language model **[S]** decided 2026-11-18: **cloud model first, behind an interface, switchable to an on-device model later** — same principle as face recognition, same caveat: my notes about other people go to the provider until switched. 
- Provider **[S]** decided 2026-11-18: **a model accessed through OpenRouter**, configured by `.env` variables (API key, model name) — may change later. Which model, and how the key reaches the iPhone / iPad app (a `.env` file only works for the Mac CLI / development) are open. **[A]**

### 4.6 Command-line interface (Mac) **[S]** added 2026-11-18

pplz ships with a `pplz` CLI on the Mac **from the start**, so that tools like Claude Code can access it.

- Works on the same data as the app (same local store, same iCloud sync). **[A]**
- The CLI only changes pplz data. Writing the result into contacts (notes block, link) is done by the app — a bare command-line binary probably cannot hold the notes entitlement (§8.1 S5). So after a CLI write, the contact is updated when the Mac app next runs or syncs; whether a background helper should do it immediately is open. **[A]**
- **Read, write and search** **[S]** decided 2026-11-18: list / show people with history; list / create / edit events; add notes, follow-ups, tags; log a quick interaction.
- **Search includes natural language** **[S]**: `pplz ask "Who did I meet in Frankfurt last week?"` (command name **[A]**). So the natural-language search of §4.5 lives in the shared core, not in the app UI, and is built in slice 1 together with the CLI.
- Whether the CLI may also create / change system contacts: not decided; assumed no for the first version. **[A]**
- Machine-readable output (`--json`) plus human-readable default. **[A]**
- Architecture consequence: all domain logic lives in a shared Swift package used by the Mac app, the iOS app and the CLI — no logic in the UI layer. **[A]**
- To verify in a spike: a command-line tool sharing the app's sandboxed store + CloudKit sync, and its Contacts permission.

### 4.7 Look & feel

- pplz looks **very similar to the native Contacts app** on each platform, so I feel at home immediately. **[S]**
- **Pink highlights** make it obvious that I'm *not* in the original Contacts app. **[S]**
- Concretely **[A]**:
  - same structure as Contacts: list of people with search and alphabetical sections → contact card (Mac / iPad: sidebar + detail, iPhone: navigation stack)
  - person card laid out like the Contacts card: a large header with the contact's picture (or initials on pink), the **nickname as the big title** when there is one with full name · job · company below it **[S]** 2026-11-18, quick-action buttons (message, call, video, mail), then one rounded group per kind of field with an action icon on each row; pplz content (connections, history, photos) appears as additional sections in the same visual language. Apple's full-height contact *posters* are not available to other apps (unverified); pplz uses the contact picture.
  - standard system components, fonts, light / dark mode — no custom design system
  - pink as the app's accent / tint colour (buttons, links, selection, pplz-specific sections, app icon) instead of system blue
  - the pink is Apple's **system pink** (adapts to light / dark mode and accessibility settings) **[S]** decided 2026-11-18

---

## 5. Photo pipeline

```
ingest → read EXIF → detect faces → match faces to persons → attribute to event → update history → sync contact notes
```

1. **Ingest** — a photo enters pplz, handed over manually or via the watched album (§4.3).
2. **EXIF** — capture time and GPS; reverse-geocode GPS to a place name. **[S]**
3. **Face detection & recognition** — find faces, match against known persons. **[S]**
   - Unknown face → ask me who it is; my answer enrolls / improves that person's reference data. **[A]**
   - Low-confidence match → goes to the review queue, never silently applied. **[A]**
4. **Event attribution** **[S]**
   - An existing event matches (time window, and place if both have one) → attach photo, add recognized people as participants.
   - No match → propose a new event (`live meeting`, date + place from EXIF, participants = recognized people). **[A]**
   - Match rule **[S]** decided 2026-11-18: the photo was taken between the event's start and end (or, without an end, on the same day) with a margin of about 3 hours, and — if both have a location — within about 500 m. The result always goes through the review queue for confirmation.
5. **History** — the event appears in the history of every recognized person. **[S]**
6. **Contacts** — affected contacts' notes blocks are regenerated (§3.3). **[S]**

Edge cases the first version handles **[S]** decided 2026-11-18:

- **No EXIF** (messenger-forwarded photos, screenshots): pplz asks me for the date or lets me pick the event.
- **Unknown people**: I can name a face (creates a pplz-only person) or mark it "ignore", so strangers in the background aren't asked about again.
- **Web-call screenshots**: attributed to a web-call event; faces in the tiles are recognised like in photos.
- **Merge / split**: merge two events that are really one; move photos to another event.

---

## 6. Storage & device sync

- Data lives locally on each device and syncs between my Mac, iPhone and iPad. **[A]**
- SwiftData / Core Data + CloudKit **private** database — no own storage backend, no pplz account, data stays in my iCloud. **[S]** decided 2026-11-18
- Photo references use `PHCloudIdentifier` (asset IDs are device-local); where it can't be resolved, the thumbnail remains. **[A]** see §8.3
- App and CLI share one local store; only the app syncs with CloudKit (§8.3). **[A]**
- Model must respect the CloudKit schema rules from day one (no unique constraints, optional relationships with inverses, additive schema changes only — see §8.2). **[A]**
- Contacts themselves sync via iCloud Contacts as today; pplz writes the notes block on one device and iCloud distributes it. Needs care to avoid two devices writing the same block concurrently. **[A]**
- Works offline; syncs when online. **[A]**

---

## 7. Privacy

- pplz stores **biometric data of third parties** (face reference data). Under GDPR this is special-category data; for purely personal use the household exemption should apply to *me*; sending such data to a cloud provider is a grey area I accept for the personal build, and it is not acceptable as-is for a distributed app. **[A]** — not legal advice
- Face recognition **starts with a cloud service**, built behind an interface so it can be **switched to an on-device model later**. **[S]** decided 2026-11-18
  - pplz talks to a `FaceRecognizer` abstraction (detect → identify against my enrolled persons); cloud provider is one implementation, an on-device Core ML model a later one. No provider-specific data in the domain model. **[A]**
  - Consequence: while the cloud provider is in use, face images / face data of third parties leave my devices. Acceptable for the personal build; **must be switched to on-device (or get explicit consent + privacy policy) before any App Store release**. **[A]**
  - Cloud service: **Amazon Rekognition** **[S]** decided 2026-11-18. Conditions **[A]**: EU region (availability to confirm), opt-out from AWS using the content to improve its services, credentials not embedded in the app (small proxy or temporary credentials — see R8).
- Face reference data deletable per person, including at the cloud provider. **[A]**
- **Contact note text never leaves my devices**: pplz reads the note only to preserve my own text around its block; that text is not sent to the language model or any other service. (This is also what the notes-entitlement request to Apple states.) **[A]**
- **Language model**: natural-language search and relationship summaries send my notes and history about other people to the model provider (via OpenRouter) while "cloud first" applies. Same rule: fine for the personal build, to be switched to on-device or covered by consent + privacy policy before a store release. **[A]**

---

## 8. Feasibility risks

Platform constraints that can reshape the concept. Checked against Apple's developer docs on 2026-11-18; "unverified" = not confirmed by a primary source.

| # | Finding | Impact on pplz |
|---|---|---|
| R1 | Reading/writing the contact **note** field requires the entitlement `com.apple.developer.contacts.notes` on iOS, iPadOS **and** macOS (13+). Apple must approve it on request; no public distribution without it. Without it, fetching the note fails (`CNError.unauthorizedKeys`). On macOS, saving *any* change to a contact that has a note also fails without it (confirmed, §8.1 S4). Unverified: whether a development provisioning profile can carry the entitlement before approval; approval time (forum reports: weeks, or no reply). | The whole Contacts integration depends on Apple's approval — custom-labelled fields are **not** a fallback (§8.1). Request first thing. |
| R2 | Vision only *detects* faces (rectangles, landmarks, quality) — no identification, no face-embedding API found. No public PhotoKit API found for the Photos app's named "People". (Absence of an API, not an explicit statement by Apple.) | Recognition cannot come from Apple. pplz starts with a cloud service (R8) and later switches to its own on-device face-embedding model (Core ML); either way it needs an enrollment and confirmation flow. |
| R3 | `CNContact.identifier` is only unique **on the current device**. Apple documents no cross-device linking recipe. | pplz needs its own stable link Person ↔ contact, e.g. a pplz ID stored in a contact field that syncs via iCloud (candidate: the `pplz://person/<id>` URL from §3.2), with matching by name / mail / phone as fallback. Unverified practice — spike it. |
| R4 | CallKit exposes only *active* calls; no call-log / FaceTime-history API found on iOS (absence of an API, not an explicit statement by Apple). `CXCallObserver` is not listed for macOS; a macOS call-history API could not be verified either way. | Assume phone-call events cannot be captured automatically. Manual entry, or derive from calendar (Q6). |
| R5 | With iOS "limited access" the app sees only the contacts the user picked (plus ones it created). | pplz needs **full** contacts access; onboarding must ask for it and handle the limited case. |
| R6 | Labelled contact fields (URLs, dates, related names, social profiles, …) accept custom label strings; wholly new field types are not possible. Custom-labelled URL and date fields were written successfully (§8.1 S1, S2). Unverified: how the custom label is displayed. | Used for the `pplz` link. Not a fallback for R1: writing them fails too on contacts that have a note (§8.1 S4). |

**R7 — LinkedIn data access (researched 2026-11-18).**

- LinkedIn's open API products only cover the *signed-in member* (name, picture, e-mail) and posting. Connections and other members' profiles need partner-programme approval. (LinkedIn developer docs)
- LinkedIn's User Agreement prohibits scraping / automated copying of profiles; robots.txt forbids automated access. A plain fetch of a public profile showed a "join to view" wall. → **pplz must not fetch profile pages or pictures automatically**; it would also endanger an App Store release.
- Not verified, needs a device spike: what the iOS share sheet hands over when sharing a profile (probably the URL, perhaps a title, probably no image); what the LinkedIn QR code encodes (probably the profile URL).
- LinkedIn's official data export contains a connections list (believed: name, profile URL, company, position, connected-on date; e-mail only if the connection allows; no pictures) — usable for a bulk import.
- An EU-only "Member Data Portability" API exists (found via secondary source only); scope and availability to individuals unverified — worth a follow-up.
- **Consequence for §4.4:** link and name can come from share sheet / QR; the **LinkedIn picture cannot be pulled automatically** by legitimate means. Options: I share / save the picture or a profile screenshot and pplz crops the face; or a photo taken on the spot.

**R8 — Cloud face recognition (researched 2026-11-18).**

| Service | Identifies people | Open to individuals | Notes |
|---|---|---|---|
| Amazon Rekognition | yes (face collections) | yes | By default AWS may use content to improve its services; opt-out via an AWS Organizations policy (free to set up). About $0.001 per image, free tier at low volume. EU region availability not verified. |
| Azure AI Face | yes | effectively no | Identification is "Limited Access", only for customers managed by Microsoft. |
| Google Cloud Vision | no | – | Detection only. |
| CompreFace (self-hosted, Apache 2.0) | yes | yes | No third party, but needs a server I host (x86 / Docker). |

Credentials must not be embedded in the app → a small proxy (or temporary credentials) is needed, which is the one piece of backend in an otherwise backend-free design.

### 8.1 Mac spike results (2026-11-18, macOS 27.2.1, unsigned Swift command-line tool, one throw-away test contact)

| # | Test | Result |
|---|---|---|
| S1 | Create contact with URL field, custom label `pplz`, value `pplz://person/…` | ✅ works; label and custom-scheme value stored unchanged |
| S2 | Add a date field with custom label `last met` | ✅ works |
| S3 | Read / write the note without the entitlement | ❌ note key is silently not fetched; accessing or setting it crashes (`CNPropertyNotFetchedException`) |
| S4 | Update **only non-note fields** on a contact that **has a note**, without the entitlement | ❌ save fails with Cocoa error 134092. Confirms the forum reports. Deleting such a contact works. |
| S5 | Add the entitlement to an ad-hoc signed binary (no provisioning profile) | ❌ process is killed at launch — the entitlement must be authorised by a provisioning profile |
| S6 | Write URL field / note through Contacts.app scripting (AppleScript) | ✅ works even with a note present, no entitlement needed (needs the user's Automation permission; macOS only) |
| S7 | `addressbook://<id>` while Contacts.app is already running | ⚠️ in one run the contact was not selected (selection read back by script, not checked visually). Scripting `set selection to {person id "<id>"}` did select it. |
| S8 | Test contact created on the Mac syncs to the iPhone via iCloud | ✅ seen in Contacts on the iPhone (observed by Till; link row not explicitly checked) |

**Consequences**

- **The notes entitlement is a prerequisite for the whole Contacts integration, not only for the history block.** Without it pplz cannot even write its link field into contacts that have a note (S4). Whether a development build can use it before Apple approves is unverified — S5 only shows it cannot be self-signed; check in the developer portal whether the capability can be added to a development profile. → Request it from Apple as the very first step (needs Apple Developer Program membership).
- **Mac-only bridge while waiting for Apple (personal build):** the Mac app writes link + history through Contacts.app scripting (S6); iCloud carries the result to iPhone / iPad. Not a store-ready path — interim only. **[A]**
- **pplz → Contacts button on Mac:** not settled — see §4.1; needs a visual re-test of `addressbook://` and a decision between scripting and the in-app contact card.
- Not testable on this Mac: whether tapping the `pplz://` row in Contacts opens pplz (needs a built app registering the scheme), and everything iOS (needs Xcode + device).

### 8.4 Notes entitlement request (submitted 2026-11-18)

Requested from Apple for bundle ID `com.tillg.pplz`; answer comes by email. Status: **pending**.

What was declared to Apple, and therefore binds the product:

- pplz is a **personal CRM**; use-case category "writes app-specific information to Contact Notes field".
- pplz writes only its own delimited block (summary + up to 10 recent events); text outside the block is read solely to preserve it.
- **No note text that pplz did not write is shared off the device with third parties** (§7).
- **Writing is triggered by explicit user action:** I turn on "Show history in Contacts" in setup; afterwards a contact's block is updated only when I create, edit or confirm an event involving that contact. Unconfirmed proposals (photos, calendar) are never written.
- Permission prompt text: "pplz shows your contacts and adds a history of your meetings and calls to each contact's notes. Your own notes stay unchanged, and pplz does not share them with anyone."

### 8.2 Further doc findings (2026-11-18)

- **In-app contact card:** `CNContactViewController` exists for iOS / iPadOS and macOS, with editing. No public way to open the iOS Contacts app at a specific contact (absence of an API).
- **Photos "People":** Apple forum answers say there is no API to access it.
- **Face-embedding models:** licence matters for store-readiness. InsightFace / ArcFace pretrained models are non-commercial research only; FaceNet code is MIT but weights' training-data licences are unclear; AuraFace (Apache 2.0) is named as a permissive option (secondary source). Core ML conversion not verified for any of them — spike needed.
- **CloudKit sync (SwiftData / Core Data):** private database only; no unique constraints, all relationships optional with inverses, no "deny" delete rule, production schema changes additive only. Handling of large binaries (photos) not verified.
- **Entitlement approval time:** Apple staff say it "varies wildly"; no recent data.

### 8.3 Storage spike: one store for app + CLI (2026-11-18)

Tested locally (throw-away SwiftData package, Xcode 27.2 toolchain):

| # | Test | Result |
|---|---|---|
| T1 | Build a SwiftData model with `swift build` using only the Command Line Tools | ❌ SwiftData's macro plugin is missing there. With full Xcode selected: ✅ builds, and `swift test` runs. → **Full Xcode is required**, also for the core package and CLI. |
| T2 | Two-entity model (Person ↔ Event, optional to-many both ways, CloudKit-compatible shape) in a store at a custom path | ✅ |
| T3 | Three processes writing to the same store file at the same time | ✅ all writes present, no errors |
| T4 | A long-running process sees what other processes wrote | ✅ a new fetch returns the new rows (already-loaded objects were not tested) |
| T5 | Change history recorded in the store | ✅ history tables are written by default — the precondition for the syncing process to pick up CLI writes |

From Apple's documentation:

- A bare command-line binary **cannot hold CloudKit entitlements** (no place for a provisioning profile). Apple's documented way is an app-like bundle around the tool.
- Sharing one SwiftData store between processes is supported (Apple's app + widget sample). Changes from another process are not announced automatically; the reader uses SwiftData's history API.
- SwiftData and Core Data can work on the same store file (Apple sample), so the choice is reversible.
- macOS 15+ protects app group containers: a process accesses them without a prompt only if signed by the same team with a team-ID-prefixed group ID (or equivalent).
- **Not documented, not testable without a signed app:** that the app's CloudKit sync exports rows written by another process. Inferred from how history-based export works; needs a spike with a signed build.
- Photos: asset identifiers are device-local; `PHCloudIdentifier` is Apple's cross-device reference (can fail or be ambiguous → thumbnail remains the fallback).

**Design consequences** **[A]**

- **SwiftData** for the store, model shaped for CloudKit from day one.
- **Only the app talks to CloudKit.** The CLI is a plain local reader / writer of the same store; the Mac app (running, or at next launch) syncs its changes. Same split as for contacts (§4.6).
- The CLI ships **inside the Mac app bundle**, signed by the same team, with `pplz` on the PATH as a link — this gives it access to the app's group container. For development, a store path override (`PPLZ_STORE`) lets CLI and tests run against any file.
- Photos are referenced by cloud identifier + own thumbnail.

Sources:
[notes entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.contacts.notes) ·
[accessing the contact store](https://developer.apple.com/documentation/contacts/accessing-the-contact-store) ·
[CNContact.identifier](https://developer.apple.com/documentation/contacts/cncontact/identifier) ·
[Vision](https://developer.apple.com/documentation/vision) ·
[PHAssetCollectionSubtype](https://developer.apple.com/documentation/photos/phassetcollectionsubtype) ·
[CXCallObserver](https://developer.apple.com/documentation/callkit/cxcallobserver) ·
[CNLabeledValue](https://developer.apple.com/documentation/contacts/cnlabeledvalue) ·
[entitlement request form](https://developer.apple.com/contact/request/contact-note-field) ·
[CNContactViewController](https://developer.apple.com/documentation/contactsui/cncontactviewcontroller) ·
forum reports on saving contacts with notes: [847426](https://developer.apple.com/forums/thread/847426), [723695](https://developer.apple.com/forums/thread/723695) ·
[approval time](https://developer.apple.com/forums/thread/728716) ·
[Core Data model for CloudKit](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit) ·
[SwiftData sync](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) ·
[LinkedIn API access](https://learn.microsoft.com/en-us/linkedin/shared/authentication/getting-access) ·
[LinkedIn User Agreement](https://www.linkedin.com/legal/user-agreement) ·
[LinkedIn data export](https://www.linkedin.com/help/linkedin/answer/a566336) ·
[Rekognition pricing](https://aws.amazon.com/rekognition/pricing/) · [Rekognition FAQ](https://aws.amazon.com/rekognition/faqs/) ·
[Azure Face limited access](https://learn.microsoft.com/en-us/legal/cognitive-services/computer-vision/limited-access-identity) ·
[Google Vision face detection](https://docs.cloud.google.com/vision/docs/detecting-faces) ·
[CompreFace](https://github.com/exadel-inc/CompreFace)

---

## 9. Open questions

All questions from the first draft were answered on 2026-11-18.

### Still open

- **Model via OpenRouter** — which model; how the key is provided on iPhone / iPad (§4.5).
- **pplz → Contacts button on the Mac** — scripting, URL scheme or in-app contact card (§4.1).
- **CLI and contacts** — may the CLI create / change system contacts; should a background helper update contacts right after a CLI write (§4.6).
- **Spikes** — see slice 0 in §10.

### Decided

1. **Distribution** — personal build first, but store-ready: no choices that would block an App Store release later. The two "cloud first" decisions (2, 17) are deliberate exceptions that must be resolved before a release.
2. **Face recognition** — start with a cloud service (Amazon Rekognition), built so it can be switched to a local model later (§7, R8).
3. **Notes block** — pplz owns a delimited block (one-way), summary + last 10 events, device language (§3.3).
4. **Storage** — iCloud / CloudKit private database, no own storage backend (§6).
5. **Photo source** — manual hand-over + one watched album; reference to the Photos asset plus own thumbnail (§4.3, §2.3).
6. **Automatic events** — calendar import (as proposals) and a quick-log action; no mail / messages (§4.2).
7. **pplz-only person data** — how we met + notes, tags / groups, connections between people, keep-in-touch reminders (§2.1).
8. **Persons without contact** — allowed; contact is created on demand (§2.1).
9. **Event details** — formats: + larger gathering, written exchange, custom; fields: + optional end, topics / follow-ups, tags, links / attachments (§2.2).
10. **Deleted contacts** — person is kept; pplz asks what to do (§2.1).
11. **Other enrichment** — contact photo (on confirmation) and LinkedIn / social-media links kept in sync (§3.2).
12. **Photo matching & edge cases** — §5.
13. **"Smart"** — smart lists, natural-language search, AI relationship summary (§4.5).
14. **Contact accounts** — all contacts are in iCloud.
15. **Pink** — system pink (§4.7).
16. **LinkedIn capture** — link + name via share sheet / QR, picture via shared image or screenshot (auto-cropped), contact created automatically (§4.4).
17. **Language model** — cloud first, switchable; accessed through OpenRouter, configured by `.env` variables (§4.5).
18. **CLI** — on the Mac from the start; read, write and search, including natural-language search (§4.6).

---

## 10. Proposed slicing (proposal, not decided) **[A]**

| Slice | Content | Proves |
|---|---|---|
| 0 | Notes entitlement requested from Apple on 2026-11-18 (pending, §8.4). Remaining spikes: tap on `pplz://` row opens the app (Mac + iPhone); can a development profile carry the notes entitlement before approval; link field survives iCloud sync as cross-device ID; does the app's CloudKit sync export CLI-written rows (signed build); what the LinkedIn share sheet / QR code delivers; `addressbook://` re-test. Mac Contacts spikes done, see §8.1. Storage spike done, see §8.3. | R1, R3, R7 |
| 1 | *(in progress — core + CLI done 2026-11-18 for people, contact details, events with links, tags, follow-ups, history, connections, keep-in-touch (`pplz due`), open card in Contacts; first Mac app (people list with search, person card, log an event, edit pplz fields and connections from the card, events list by month with event detail, event editing / deleting and follow-ups, open in Contacts, `pplz://person/<id>` links) built with SwiftPM + `scripts/make-app.sh`; open: `ask`, custom formats, file attachments, changing an event's participants and adding pplz-only persons in the app, Xcode project, iOS / iPadOS app)* Shared core package + **Mac CLI** + Mac / iOS app in Contacts look with pink: people list from Contacts, pplz-only person data, manual events + quick log, history timeline (local only); CLI incl. natural-language search via OpenRouter | domain model, CLI |
| 2 | Contacts integration: `pplz` link, history block in notes, social links, both-way navigation (Mac scripting bridge until the entitlement arrives) | Contacts integration |
| 3 | Device sync via CloudKit | storage |
| 4 | LinkedIn capture | §4.4 |
| 5 | Calendar import, smart lists, keep-in-touch reminders | |
| 6 | Photos: manual + album, EXIF, event attribution (people assigned by hand), merge / split | pipeline without ML |
| 7 | Face recognition (cloud, switchable) + review queue; contact photo proposal | |
| 8 | Natural-language search in the app UI + relationship summary | |
