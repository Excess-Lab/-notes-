<div align="center">

<img src="%3Cnotes%3E/Icon/icon-dark.png" width="128" alt="<notes> app icon">

# &lt;notes&gt;

**Plain Markdown notes for macOS, with git history, on-device dictation and tasks in your calendar.**

[![Release](https://img.shields.io/github/v/release/Excess-Lab/-notes-?style=flat-square&color=000000&label=release)](https://github.com/Excess-Lab/-notes-/releases/latest)
![macOS 27+](https://img.shields.io/badge/macOS-27%2B-000000?style=flat-square&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-000000?style=flat-square&logo=swift&logoColor=white)
[![License: MIT](https://img.shields.io/badge/license-MIT-000000?style=flat-square)](LICENSE)

[Download](https://github.com/Excess-Lab/-notes-/releases/latest) · [Changelog](CHANGELOG.md) · [Build from source](#build-from-source)

</div>

---

## Why

Your notes are files, not rows in someone else's database. `<notes>` keeps everything as ordinary
`.md` files in a folder you choose. That folder is a git repository: every edit is versioned, and the
history can go to your own private GitHub repo. No accounts, no servers of ours. Open the same
folder in any other editor and nothing breaks.

## Features

|  |  |
|---|---|
| **Notes** | Markdown in a regular folder. Tabs, folders, drag and drop, pin, duplicate, templates, a daily note. ⌘Z for everything. |
| **Sync** | The folder is a git repo with automatic commits. Optional GitHub sign-in by device code, no password. Conflicts keep both versions. |
| **Search** | One search (⌘K) across notes, tasks, events, videos and transcript text. |
| **Dictation** | Hold a hotkey anywhere in macOS, speak, release: text lands on the clipboard or in the focused field. Recognition runs on your Mac. |
| **Tasks & calendar** | `- [ ] task 📅 date` lines become tasks and show up in Apple Calendar. Day, week and month views with drag to create, move and resize. |
| **Video & audio** | Drop a file to transcribe it on-device, with speakers. Save as a note or export to `.srt`. |
| **Apple Intelligence** | Optional note summaries and tasks from a transcript, on-device. |
| **Privacy** | PIN code and Touch ID. Tokens live in the Keychain. The network is used only for GitHub and one-time model downloads. |

Light and dark themes · English, Russian and Serbian (Latin)

## Install

1. Download `notes.dmg` from the [latest release](https://github.com/Excess-Lab/-notes-/releases/latest).
2. Open it and drag `<notes>` into **Applications**.
3. The build is not notarized yet. On first launch open **System Settings → Privacy & Security**,
   scroll down and click **Open Anyway**.

Requires macOS 27 or later.

## Your vault

```
my-notes/                 ← any folder, also a git repo
├── Входящие.md           ← inbox for quick tasks
├── projects/
│   └── app.md            - [ ] ship 1.0 📅 2026-11-01 15:00
├── шаблоны/              ← templates: {{дата}} {{время}} {{название}}
│   └── день.md
└── расшифровки/          ← transcripts
```

- Notes are plain `.md`. The app writes nothing of its own into the vault.
- Search index, caches and speech models live outside it, in Application Support, and are rebuilt
  from the files.
- Speech models (GigaAM for Russian, Whisper for 99 languages, speaker detection) are downloaded on
  demand, only the ones you turn on.

## Build from source

```bash
git clone https://github.com/Excess-Lab/-notes-.git notes && cd notes
./Scripts/fetch-sherpa-onnx.sh      # speech runtime, ~100 MB, checksums verified
open "<notes>.xcodeproj"            # scheme <notes>, destination My Mac, ⌘R
```

Run the tests:

```bash
cd NotesCore && swift test
```

Build the installer (`build/notes.dmg`):

```bash
Scripts/make-dmg.sh
```

## Built with

[SwiftUI](https://developer.apple.com/xcode/swiftui/) ·
[libgit2](https://libgit2.org) ·
[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) with GigaAM ·
[WhisperKit](https://github.com/argmaxinc/WhisperKit) ·
Foundation Models · EventKit · Metal ·
[Martian Grotesk](https://github.com/evilmartians/grotesk)

## License

[MIT](LICENSE) © 2026 Makar K. Martian Grotesk is licensed under the SIL Open Font License 1.1.
