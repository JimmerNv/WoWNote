# WowNote

WowNote is a World of Warcraft 3.3.5a addon for account-wide Markdown-style notes, item links, and a built-in talent planner.

This repository is prepared for a GitHub upload. The current build intentionally hides the note-sharing UI because addon/channel based sharing is unreliable on the tested private server environment.

## Features

- Account-wide saved notes through `WowNoteDB`
- In-game note editor
- Markdown-style lightweight note formatting
- Item link handling in note content
- Talent planner for Wrath of the Lich King / client interface `30300`
- Titan Panel integration via optional dependency
- Share transport code is still present internally for experimentation, but the visible Share menu entry has been removed

## Installation

1. Download or clone this repository.
2. Make sure the addon folder is named exactly:

   ```text
   WowNote
   ```

3. Copy the folder into:

   ```text
   Interface/AddOns/WowNote
   ```

4. Restart WoW completely.
5. Enable `WowNote` in the character selection AddOns menu.
## Screenshoots
<img width="844" height="544" alt="wowNote4" src="https://github.com/user-attachments/assets/3367bfa2-932b-4134-93a6-e879d86ee6de" />
<img width="1135" height="675" alt="wowNote1" src="https://github.com/user-attachments/assets/06b3fb60-9bb8-4ba9-a727-e8ec626579ce" />
<img width="1865" height="1014" alt="wownote2" src="https://github.com/user-attachments/assets/48cb69f9-abf9-4627-ad7a-283b65071822" />
<img width="1101" height="874" alt="wowNote3" src="https://github.com/user-attachments/assets/033f1ee5-81b4-4559-892e-dceefb0253a1" />


## Slash commands

```text
/wn
/wownote
```

Opens or toggles the main WowNote window.

```text
/wn new
/wn talents
/wn talents load
/wn items
```

Additional development/debug commands may still exist in the source, but server-side chat/addon throttling can make sharing unreliable. The visible Share menu has therefore been removed from this build.

## Compatibility

Target client:

```text
World of Warcraft 3.3.5a
Interface: 30300
```

Tested in a private-server environment. Behavior can differ between private servers, especially for addon messages, chat channels, and server-side spam/mute protection.

## Development notes

The addon is intentionally distributed as a classic single-file WoW addon:

```text
WowNote.toc
WowNote.lua
```

A packaging script is included under `scripts/package.sh`. It creates an installable addon zip under `dist/`.

## Repository structure

```text
.
├── WowNote.toc
├── WowNote.lua
├── README.md
├── CHANGELOG.md
├── LICENSE.md
├── docs/
│   └── DEVELOPMENT.md
└── scripts/
    └── package.sh
```

## License

No open-source license has been selected yet. See `LICENSE.md`.
