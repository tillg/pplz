<p align="center"><img src="assets/logo.svg" width="128" alt="pplz logo"></p>

# pplz

**Remember not just who people are, but when, where and how you met them.**

pplz is a personal contact manager for Mac, iPhone and iPad. It enriches the contacts you already have with the history of your interactions: meetings, calls, events and photos.

> **Status: early development.** The shared core, the `pplz` command line, a Mac app and a first iPhone / iPad app exist and work on a local store; connections and (if you switch it on) the meeting history are written to your contacts, Mac only, and both apps sync their data through your private iCloud. The design, the decisions taken so far and the results of the technical spikes are in [SPEC.md](SPEC.md).

## The idea

pplz has two faces:

```
┌──────────────────────────┐         ┌──────────────────────────┐
│  Apple Contacts app      │         │  pplz app                │
│                          │         │                          │
│  Anna Example            │ ──────▶ │  Anna Example            │
│  mobile  +49 …           │  pplz   │  How we met · Notes      │
│  pplz    pplz://person/… │  link   │  Tags · Connections      │
│  Notes                   │         │  History                 │
│   ── pplz ──             │ ◀────── │   12 Nov  Dinner, Köln   │
│   Met 7× · last 12 Nov   │ history │   03 Oct  Web call       │
│   12 Nov  Dinner, Köln   │         │  Photos                  │
│   ── /pplz ──            │         │                          │
└──────────────────────────┘         └──────────────────────────┘
```

- **In the Contacts app** you keep working as usual and simply see more: every contact gets a link into pplz and a short history of when you last met.
- **In the pplz app** you find everything Contacts can't hold. It looks like the Contacts app, with pink highlights so you know where you are.

## Planned features

| | |
|---|---|
| **History per person** | Every event you shared with someone, newest first |
| **Events** | Live meetings, web calls, phone calls, larger gatherings, written exchanges, with place, participants, topics and follow-ups |
| **Photos** | Hand pplz a photo: it reads time and place, recognises the people in it and attaches it to the right event |
| **Contacts sync** | History and links are written into your address book and stay up to date |
| **LinkedIn capture** | Share a profile to pplz at a conference and the person lands in pplz and in Contacts |
| **Calendar import** | Meetings with people you know become event proposals |
| **Quick log** | "I just talked to …" in two taps |
| **Keep in touch** | Smart lists and reminders for people you haven't seen in a while |
| **Ask** | "Who did I meet in Frankfurt last week?" |
| **Command line** | A `pplz` CLI on the Mac, so scripts and AI agents can read, write and search |

## Command line

Build and try it (macOS with full Xcode):

```sh
swift build -c release
ln -s "$(swift build -c release --show-bin-path)/pplz" ~/.local/bin/pplz   # any folder on your PATH

pplz people anna                                   # your contacts plus pplz-only persons
pplz log "Anna Example" --format phone-call --title "Catch-up" --at yesterday
pplz log "Ben New" --create --title "Fair" --format gathering --at 2026-10-03 --end 2026-10-05 --place Frankfurt
pplz person "Anna Example"                         # contact details, notes, tags and history
pplz person open "Anna Example"                    # show the card in the Contacts app
pplz events --since 2026-11-01 --place frankfurt
pplz followup add <event-id> "send the book title"
pplz person connect "Anna Example" "manager of" "Ben New"     # Ben's card in Contacts gets "manager: Anna Example"
pplz contacts history on                           # write the meeting history into each contact's note
pplz contacts journal                              # every change pplz made to your address book
pplz person rhythm "Anna Example" 3m               # keep in touch every 3 months
pplz due                                           # who is overdue
pplz --help
```

- People are found by name, nickname, part of either, or ID. An unknown or ambiguous name stops the command with exit code 2 and lists the candidates.
- Every command takes `--json` for scripts and AI agents. Dates are ISO 8601 in UTC; fields without a value (`end`, `lastMet`, `id` of a contact pplz knows nothing about yet) are left out.
- A date without a time means the whole day for `--end` and `--until`.
- The store is `~/Library/Application Support/pplz/pplz.store`; set `PPLZ_STORE` or pass `--store` to use another file.
- Contacts are read for names and details (macOS asks for access on first use). pplz writes three things into them: a `pplz` link row that opens the person in the app, connections as "related name" rows, and — only after `pplz contacts history on` — a history block in the note, between `── pplz ──` and `── /pplz ──`; your own note text around it is never changed. `pplz contacts sync` brings everything up to date, `person disconnect` and `contacts history off` remove what pplz added. `--no-contacts` neither reads nor writes the address book.
- Event formats: `live-meeting`, `web-call`, `phone-call`, `gathering`, `written`.
- Events can carry links (`--link`, repeatable), e.g. to a calendar entry or a document.

Run the tests with `swift test`.

## Apps

The Mac app shows your people and each person's card, laid out like Contacts with pink highlights. You can browse and search people and events; log an event with a person (+ on their card); edit their tags, notes, how you met and keep-in-touch rhythm (the pencil) — when tagging, the tags you already use are offered, and typing a new name creates one; add and remove relationships; edit and delete events; and add and tick off follow-ups. Changes made with the CLI appear when the app comes to the front.

The iPhone / iPad app uses the same screens. It is at an early stage: it syncs with the Mac through iCloud (changes from another device appear when the app starts), but it does not write into Contacts.

Both are built from the Xcode project in `App/`, which is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
cp App/Local.xcconfig.example App/Local.xcconfig    # then enter your Apple developer team ID
scripts/build-app.sh mac                             # builds pplz.app and installs it in /Applications
scripts/build-app.sh iphone "My iPhone"              # builds and installs on a connected, unlocked device
scripts/build-app.sh simulator                       # builds for the iOS simulator
```

To click through the iOS app from the command line (useful for coding agents), `scripts/ui.sh` runs a list of steps in a simulator and saves screenshots and the accessibility tree to `tmp/ui/`:

```sh
scripts/ui.sh "-select|Anna Example" "tap:Log Event;screenshot:sheet;tree:sheet"
```

## How it is built

- Native Swift and SwiftUI for macOS, iOS and iPadOS
- One shared core package used by the apps and the CLI
- Local-first storage with SwiftData, synced between your devices through your private iCloud
- No pplz account and no pplz server

Face recognition and natural-language search start with cloud services behind an interface, so they can be replaced by on-device models later. The trade-offs are described in the [privacy section of the spec](SPEC.md#7-privacy).

## Roadmap

1. Core package, Mac CLI and a first app: people, events, quick log, history
2. Contacts integration: link, history block, social links
3. Sync between devices
4. LinkedIn capture
5. Calendar import, smart lists, keep-in-touch reminders
6. Photos with EXIF and event attribution
7. Face recognition
8. Natural-language search and relationship summaries in the app

Details and open points: [SPEC.md](SPEC.md#10-proposed-slicing-proposal-not-decided-a).

## Requirements

- macOS with full Xcode (the Command Line Tools alone cannot build SwiftData models)
- An Apple Developer Program membership for the Contacts notes entitlement and iCloud sync
