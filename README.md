# pplz

**Remember not just who people are, but when, where and how you met them.**

pplz is a personal contact manager for Mac, iPhone and iPad. It enriches the contacts you already have with the history of your interactions: meetings, calls, events and photos.

> **Status: specification phase.** There is no app yet. The design, the decisions taken so far and the results of the first technical spikes are in [SPEC.md](SPEC.md).

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
