<p align="center"><img src="assets/logo.svg" width="128" alt="cardXchange logo"></p>
<p align="center"><img src="assets/wordmark.svg" width="360" alt="cardXchange"></p>

# cardXchange

**Remember not just who people are, but when, where and how you met them.**

cardXchange (<https://cardxchange.me>) is a personal contact manager for Mac, iPhone and iPad. It enriches the contacts you already have with the history of your interactions: meetings, calls, events and photos.

> **Status: early development.** The shared core, the `cx` command line, a Mac app and a first iPhone / iPad app exist and work on a local store; connections and (if you switch it on) the meeting history are written to your contacts, Mac only, and both apps sync their data through your private iCloud. The design, the decisions taken so far and the results of the technical spikes are in [SPEC.md](docs/SPEC.md).

## The idea

cardXchange has two faces:

```
┌──────────────────────────┐         ┌──────────────────────────┐
│  Apple Contacts app      │         │  cardXchange app         │
│                          │         │                          │
│  Anna Example            │ ──────▶ │  Anna Example            │
│  mobile  +49 …           │  cx     │  How we met · Notes      │
│  cardxchange  cx://pers… │  link   │  Tags · Connections      │
│  Notes                   │         │  History                 │
│   ── cardxchange ──      │ ◀────── │   12 Nov  Dinner, Köln   │
│   Met 7× · last 12 Nov   │ history │   03 Oct  Web call       │
│   12 Nov  Dinner, Köln   │         │  Photos                  │
│   ── /cardxchange ──     │         │                          │
└──────────────────────────┘         └──────────────────────────┘
```

- **In the Contacts app** you keep working as usual and simply see more: every contact gets a link into cardXchange and a short history of when you last met.
- **In the cardXchange app** you find everything Contacts can't hold. It looks like the Contacts app, with pink highlights so you know where you are.

## Planned features

| | |
|---|---|
| **History per person** | Every event you shared with someone, newest first |
| **Events** | Live meetings, web calls, phone calls, larger gatherings, written exchanges, with place, participants, topics and follow-ups |
| **Photos** | Hand cardXchange a photo: it reads time and place, recognises the people in it and attaches it to the right event |
| **Contacts sync** | History and links are written into your address book and stay up to date |
| **LinkedIn capture** | Share a profile to cardXchange at a conference and the person lands in cardXchange and in Contacts |
| **Calendar import** | Meetings with people you know become event proposals |
| **Quick log** | "I just talked to …" in two taps |
| **Keep in touch** | Smart lists and reminders for people you haven't seen in a while |
| **Ask** | "Who did I meet in Frankfurt last week?" |
| **Command line** | A `cx` CLI on the Mac, so scripts and AI agents can read, write and search |
| **Exchange cards** | Show a QR code, and the other person gets your card in their cardXchange; later changes reach them as updates you both see |

## Command line

Build and try it (macOS with full Xcode):

```sh
swift build -c release
ln -s "$(swift build -c release --show-bin-path)/cx" ~/.local/bin/cx   # any folder on your PATH

cx people anna                                     # your contacts plus cardXchange-only persons
cx log "Anna Example" --format phone-call --title "Catch-up" --at yesterday
cx log "Ben New" --create --title "Fair" --format gathering --at 2026-10-03 --end 2026-10-05 --place Frankfurt
cx person "Anna Example"                           # contact details, notes, tags and history
cx person open "Anna Example"                      # show the card in the Contacts app
cx people --near Köln --within 50km                # people with an address near Köln, nearest first (50, 50 km, 800m also work)
cx locate                                          # locate outstanding addresses (see below); --status shows the progress
cx events --since 2026-11-01 --place frankfurt
cx followup add <event-id> "send the book title"
cx person connect "Anna Example" "manager of" "Ben New"       # Ben's card in Contacts gets "manager: Anna Example"
cx contacts history on                             # write the meeting history into each contact's note
cx contacts journal                                # every change cardXchange made to your address book
cx person rhythm "Anna Example" 3m                 # keep in touch every 3 months
cx due                                             # who is overdue
cx capture profile.png --picture face.png          # read a profile screenshot: name, job, company, LinkedIn link, picture
cx person photo add "Anna Example" anna.jpg        # keep the face in it as a reference photo (--face 2 when several faces are found)
cx person photo list "Anna Example"                # also: photo remove <person> <id>, photo export <person> <id> <file>
cx person delete "Anna Example"                    # the contact leaves Contacts now; cardXchange keeps a copy for 30 days
cx people --deleted                                # recently deleted people and when they are deleted for good
cx person restore "Anna Example"                   # back again, with a new contact made from the copy (without the note)
cx person purge "Anna Example"                     # delete for good now; purge --expired does it for everyone whose 30 days are over
cx --help
```

- People are found by name, nickname, part of either, or ID. An unknown or ambiguous name stops the command with exit code 2 and lists the candidates.
- Every command takes `--json` for scripts and AI agents. Dates are ISO 8601 in UTC; fields without a value (`end`, `lastMet`, `id` of a contact cardXchange knows nothing about yet) are left out.
- A date without a time means the whole day for `--end` and `--until`.
- The store is `~/Library/Application Support/cardxchange/cardxchange.store`; set `CX_STORE` or pass `--store` to use another file.
- Contacts are read for names and details (macOS asks for access on first use). cardXchange writes three things into them: a `cardxchange` link row that opens the person in the app, connections as "related name" rows, and — only after `cx contacts history on` — a history block in the note, between `── cardxchange ──` and `── /cardxchange ──`; your own note text around it is never changed. `cx contacts sync` brings everything up to date, `person disconnect` and `contacts history off` remove what cardXchange added. `--no-contacts` neither reads nor writes the address book.
- `--near` needs the addresses of your contacts located first: `cx locate` sends them to Apple's geocoder, at most 300 per clock hour and one per second, and when the hour's budget is spent it says when it can continue (ten minutes into the next hour) and stops. The coordinates are part of the cardXchange data and sync through iCloud, so every device locates an address only once; each device counts its own 300 per hour (in `geocache.json` next to the default store, shared by the app and the command line). The cards are taken in random order, so that devices working at the same time rarely pick the same one. `people --near` tells you how many addresses are not located yet.
- Event formats: `live-meeting`, `web-call`, `phone-call`, `gathering`, `written`.
- Events can carry links (`--link`, repeatable), e.g. to a calendar entry or a document.

Run the tests with `swift test`.

## Apps

The Mac app shows your people and each person's card, laid out like Contacts with pink highlights; next to a birthday it shows the age. You can browse and search people and events; log an event in a few seconds (the New Event button above the list, or + on a person's card): type two letters to pick one or several people — those you met most recently are offered right away — while time and the format you used last are already filled in; someone who is not in your contacts yet is added by typing the name and choosing "New person"; such a person lives in cardXchange only until you press "Add to Contacts" on their card, which creates the contact (name and `cardxchange` link) and opens it so you can enter phone, mail and the rest; edit their tags, notes, how you met and keep-in-touch rhythm (the pencil) — when tagging, the tags you already use are offered, and typing a new name creates one; add and remove relationships (related names that are only on the contact card are listed with them, marked "in Contacts"); add an event right in a person's History ("Add event"); edit and delete events, and add or remove their people ("Add people" in the event); and add and tick off follow-ups. Changes made with the CLI appear when the app comes to the front. You can also edit the contact itself and create contacts without leaving cardXchange: the pencil on a person's card turns the card into an editor (Cancel or Done brings the card back), laid out like the edit view of Contacts — a label, the value, a button to remove the row, and an empty row of each kind to add one — with two labelled groups: "Contact card" (first and last name, nickname, company, job title, phones, mail addresses, web addresses, social profiles, postal addresses, birthday — typed as a date such as "2. September 1963", "2.9.1963" or, without a year, "2. September"; the contact's note is shown greyed out, as cardXchange cannot change it) and "cardXchange" (tags, how you met, notes, keep-in-touch rhythm). The New Contact button above the list opens the contact fields empty, in a sheet. cardXchange writes only what you changed, leaves everything else (including the note, the `cardxchange` link and related names) alone, and refuses to save, writing nothing, if the contact was changed in Contacts in the meantime. On the Mac a contact that has a note cannot be saved directly without Apple's notes entitlement; cardXchange then makes the same changes through the Contacts app.

**Deleting a person:** the trash button on a person's card deletes the person after a confirmation. A contact is deleted from Apple Contacts at once (on the Mac through the Contacts app when the contact has a note). cardXchange keeps a copy of the contact's fields and the person's events, notes, tags and photos for 30 days under "Recently Deleted", at the top of the people list. There you can restore the person, which creates the contact again with the same `cardxchange` link, or delete them for good. The copy does not hold the note, so a restored contact has no note (cardXchange may not read notes yet); it also has no picture. After 30 days the app deletes the person for good; their events stay without them.

**Photos of a person:** the "Photos" row on a person's card keeps pictures of their face, to recognise them in new photos later. Add them with + (photo library on iPhone / iPad, files or the clipboard on the Mac — "Paste Photo", because ⌘V stays "capture a profile") or drag pictures onto the row. cardXchange detects the face on the device and keeps only a crop around it, as a copy in its own store, so every device has it through your private iCloud. If a picture shows several faces you pick the right one; a picture without a face is refused. Tap a photo to delete it or, for a person with a contact, to use it as the contact's picture ("Use as contact picture", which replaces the picture in Contacts; on the Mac cardXchange asks the Contacts app when a contact with a note does not accept the save). There is no limit.

**Map:** the third entry next to People and Events shows everyone with a postal address on a map — one pin per address, labelled home / work, nearby pins grouped with a count; open the callout of a pin to get to the person. The search field filters the map like the list. While the app runs it locates your contacts' addresses in the background (the street, postal code, city and country of each address are sent to Apple's geocoding service, at most 300 per hour; the status line at the bottom says how far it is, when it continues and when it is expected to be done; this estimate assumes the device locates the rest alone). When the map shows no pin, a small note above the status line says why: the search finds nobody, or the people it finds have no located address yet. The map shows your own position, and the arrow button on the map moves the map to it; cardXchange asks for location access when you first open the map, and it does not store or send your position. The coordinates sync through iCloud with the rest of your cardXchange data, so your devices share the work: each one picks cards at random and has its own 300 per hour. A store opened with `-store` does not locate in the background. People with only a city appear at the city centre.

**Capture a profile:** the Capture Profile button above the list takes a screenshot of someone's profile (e.g. LinkedIn) — a file on the Mac, a photo on iPhone / iPad. Quicker: share the screenshot or the profile link to cardXchange from the share menu (iPhone, iPad and Mac), or on the Mac paste it into cardXchange (⌘V, or Edit → Paste Screenshot or Business Card) or drag it onto the window. cardXchange reads it on the device: Vision recognises the text and crops the profile picture, Apple's on-device language model sorts the text into name, job title, company and place (iOS 26 / macOS 26 or later with Apple Intelligence; otherwise you fill in the fields yourself). A LinkedIn address visible in the screenshot is picked up too. You check the fields, say who it is — cardXchange proposes people with the same LinkedIn profile or name, or "New person", and "Search people" finds anyone else — and cardXchange creates or completes the person and the contact; it only fills fields that are still empty. Then it asks which event you met at: a recent cardXchange event, an entry of your calendar, or a new event.

**Business cards** go the same way: on iPhone / iPad "Capture Profile → Scan Business Card" opens the camera, which crops and straightens the card (the first page is read); on the Mac paste, drop or share a photo of the card. Mail address, phone and mobile number, website and postal address are found by rule — also on a device without Apple Intelligence — and name, title, role and company by the language model. In an existing contact, a mail address, number or website is added unless the contact already has that very one.

**My Card:** in the settings (cardXchange → Settings… on the Mac, the gear button above the list on iPhone / iPad) you choose who you are and which of your fields you pass on to others. "Me" is a person from the list; until you choose, the Mac uses the card that Contacts marks as "My Card". The name is always on the card. Company, job title and picture are switches, and so is each phone number, mail address, web address, social profile and postal address. At first the card has your name, company, job title, one mobile number, the first mail address and your LinkedIn profile. "Show My Card" shows exactly what is passed on. The choice stays on the device and does not sync. The QR code that passes the card on comes in a later step.

The iPhone / iPad app uses the same screens. It is at an early stage: it syncs with the Mac through iCloud (changes from another device appear within seconds while the app is open), and writes the `cardxchange` link into a contact when you first record something about that person; relationships and the history block are written by the Mac only. Edit and New Contact work as on the Mac (saving directly, also for contacts with a note); the contact's note itself cannot be read there, and the Edit screen says so. The "Contact card" button shows the system's contact card inside cardXchange, where you can edit the contact, call or message (iOS has no way to jump to a person in the Contacts app).

Both are built from the Xcode project in `App/`, which is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
cp App/Local.xcconfig.example App/Local.xcconfig    # then enter your Apple developer team ID
scripts/build-app.sh mac                             # builds cardXchange.app and installs it in /Applications
scripts/build-app.sh iphone "My iPhone"              # builds and installs on a connected, unlocked device
scripts/build-app.sh simulator                       # builds for the iOS simulator
```

To click through the iOS app from the command line (useful for coding agents), `scripts/ui.sh` runs a list of steps in a simulator and saves screenshots and the accessibility tree to `tmp/ui/`:

```sh
scripts/ui.sh "-select|Anna Example" "tap:Log Event;screenshot:sheet;tree:sheet"
```

## Working on cardXchange with Claude Code

The repository brings its own guidance (`CLAUDE.md`) and skills (`.claude/skills/`), so that everyone works the same way. Plain `claude` uses these skills together with your personal skills; the repository switches off five plugins that do the same job. `scripts/claude.sh` starts a session with the configuration of the repository only, without the plugins, skills and settings of your own `~/.claude`. In both cases your personal `~/.claude/CLAUDE.md` and the memory of the project are still read.

## Coming from pplz

cardXchange was called pplz before 2026-11-20. The command is now `cx`, and the store folder is `~/Library/Application Support/cardxchange/`. `scripts/migrate-from-pplz.sh` copies every record of the old store into a new store, one time. It keeps the old folder as `pplz.migrated-<date>`. Until then, `cx` and the app refuse to start with the default store. `cx` stops if `PPLZ_STORE` or `PPLZ_NO_CONTACTS` is set: use `CX_STORE` and `CX_NO_CONTACTS`. Old links (`pplz://person/<id>`, label `pplz`) and old history blocks (`── pplz ──`) are still read, and `cx contacts sync` replaces them with the new form. The steps are in `docs/changes/01_rename_to_cardxchange/`.

## How cardXchange recognises a contact on every device

Apple Contacts has no identifier that is the same on your Mac, iPhone and iPad: each device gives the same contact a different one. cardXchange therefore brings its own.

- **The ID is the `cardxchange` link in the contact**, a URL row such as `cx://person/7ffa0cd8-…`. It travels with the contact through iCloud, survives renames, and opens the person in cardXchange when you click it.
- **It is written when you first record something** about a person (a tag, a note, an event, a relationship), by the device you do it on. Contacts you never use in cardXchange stay untouched; they still appear in cardXchange, read live from your address book.
- **Names never decide a match.** A name is content and can change.
- **A short delay is normal:** cardXchange data and contacts sync through separate iCloud channels, so a person recorded on one device can appear as a separate entry on another until the contact with its link has arrived.
- **If you delete the `cardxchange` row**, cardXchange treats the contact as unlinked until a device writes the row again.
- **Known gap:** if two devices record something about the same new contact before they have synced, each creates its own ID and the person appears twice. Nothing merges these yet.

## How it is built

- Native Swift and SwiftUI for macOS, iOS and iPadOS
- One shared core package used by the apps and the CLI
- Local-first storage with SwiftData, synced between your devices through your private iCloud
- No cardXchange account and no cardXchange server

Face recognition and natural-language search start with cloud services behind an interface, so they can be replaced by on-device models later. The trade-offs are described in the [privacy section of the spec](docs/SPEC.md#7-privacy).

## Roadmap

1. Core package, Mac CLI and a first app: people, events, quick log, history
2. Contacts integration: link, history block, social links
3. Sync between devices
4. LinkedIn capture
5. Calendar import, smart lists, keep-in-touch reminders
6. Photos with EXIF and event attribution
7. Face recognition
8. Natural-language search and relationship summaries in the app

Details and open points: [SPEC.md](docs/SPEC.md#10-proposed-slicing-proposal-not-decided-a).

## Requirements

- macOS with full Xcode 27 or later (the Command Line Tools alone cannot build SwiftData models)
- An Apple Developer Program membership for the Contacts notes entitlement and iCloud sync
