# WowNote

WowNote is a World of Warcraft 3.3.5a addon for account-wide notes, talent builds, raid planning, and loot roll convenience.

It provides an in-game note editor, a talent planner, a raid planner with reusable presets, roster assignments, import/export support, and an optional auto loot roller for Greed/Disenchant rules.

## Features

- **Cursor Effects** – animated configurable cursor trails and particles, available under Quality of Life.

### Notes

- Account-wide saved notes through `WowNoteDB`
- In-game note editor
- Markdown-style lightweight note formatting
- Item link handling in note content
- Import/export support for sharing notes as text

### Talent Planner

- Built-in talent planner for Wrath of the Lich King
- Save and load talent builds
- Export/import talent builds for sharing
- Designed for client interface `30300`

### Raid Planner

- Create and preview LFM messages directly in-game
- Raid size selection: `10`, `25`, or custom
- Editable raid name
- Role requirements for Tanks, Healers, DPS, mDPS, and rDPS
- Automatic missing-role calculation
- Optional roster assignments by role
- Automatic role counting based on assigned players
- Automatic removal of tracked group/raid members when they leave
- Configurable posting channel, such as `/2`, `/5`, `/y`, `/g`, `/p`, or `/raid`
- Custom message templates with placeholders
- Additional info field
- Contact field, for example `/w me` or `/w CharacterName`
- Internal note field that is saved but not posted

### Raid Planner Presets

- Save reusable raid planner presets
- Load, update, and delete saved presets
- Import/export presets as text
- Share complete raid setups with other players
- Presets include role setup, roster assignments, channel, template, additional info, contact text, and internal notes

### Auto Loot Roller

- Optional auto roll system for loot windows
- Automatically rolls Disenchant if available, otherwise Greed
- Configurable maximum item rarity
- Optional maximum item level filter
- Level protection for level 80+ characters
- Queue-based handling for multiple simultaneous loot rolls
- Automatic confirmation handling for Disenchant rolls

Safety exclusions:

- Epic Bind-on-Equip items are always excluded
- Primordial Saronite is always excluded
- Need rolls are never performed automatically


### Integrated Mail Tools

WoWNote includes an embedded Postal-derived mail module under the internal name `WowNotePostal`.

Included mailbox functions:

- Open all eligible mailbox attachments and gold with configurable delay
- Select multiple inbox mails and batch open or return them
- Shift-click shortcuts for taking mail contents
- Ctrl-click shortcut for returning mail
- Alt-click inventory items into outgoing mail
- Mouse wheel inbox scrolling
- Automatic outgoing mail subject based on sent money
- Contact, alt, friend, guild, and recent-recipient dropdown near the recipient field
- Trade blocking while the mailbox is open
- Session summary for collected gold
- Visual delete/return helper for expiring mail

The embedded module is renamed internally so it can coexist with a separately installed Postal addon without using the same AceAddon name or saved-variable table. Use `/wnpostal` while a mailbox is open to show the integrated module menu.

### UI Integration

- Main WowNote window
- Raid Planner window
- Auto Loot Roller settings window
- Minimap button
- Titan Panel integration via optional dependency

Minimap controls:

- Left-click: open WowNote
- Right-click: open Raid Planner
- Middle-click: open Auto Loot Roller
- Drag: move the minimap icon

## Screenshots

### Notes

<img width="844" height="544" alt="WowNote Notes" src="https://github.com/user-attachments/assets/3367bfa2-932b-4134-93a6-e879d86ee6de" />

### Talent Planner

<img width="1135" height="675" alt="WowNote Talent Planner" src="https://github.com/user-attachments/assets/06b3fb60-9bb8-4ba9-a727-e8ec626579ce" />

### Raid Planner

<img width="1865" height="1014" alt="WowNote Raid Planner" src="https://github.com/user-attachments/assets/48cb69f9-abf9-4627-ad7a-283b65071822" />

### Auto Loot Roller

<img width="1101" height="874" alt="WowNote Auto Loot Roller" src="https://github.com/user-attachments/assets/033f1ee5-81b4-4559-892e-dceefb0253a1" />

## Installation

1. Download the latest release ZIP from the [Releases](https://github.com/JimmerNv/WoWNote/releases) page.
2. Extract the ZIP.
3. Make sure the addon folder is named exactly:

   ```text
   WowNote

### PallyPower integration

WoWNote includes an integrated PallyPower-compatible assignment module using the original `PLPWR` addon protocol. It announces `SELF`, `ASELF`, `SYMCOUNT`, and `FREEASSIGN`, accepts native assignment updates, mirrors the standard PallyPower assignment tables internally, and provides a WoWNote-styled assignment GUI with icon columns, a `Free On/Off` toggle, a hideable buff frame, and an `All` button for fast mass assignment.

The `All` button is a WoWNote improvement: left-click fills empty class slots, Shift-left-click overwrites all class slots, and right-click clears all class blessings.
