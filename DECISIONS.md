---
title: "Decisions"
created: 2026-11-19
edited: 2026-11-19
---

**Contents**

- [2026-11-19 11:54 — Profile capture from a screenshot, built while the user is at lunch](#run-2026-11-19-1154)
  - [11:56 — Commit and push to main without asking each time](#run-2026-11-19-1154-1)
  - [11:58 — Build order: everything that does not need the model first](#run-2026-11-19-1154-2)

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
